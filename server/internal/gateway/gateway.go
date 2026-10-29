// Package gateway is the HTTP surface: routing, auth, and the coordination
// logic that ties the store, matchmaker, and push notifier together
// (plan.v1.md §7, §12).
package gateway

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"strangewords/internal/botplayer"
	"strangewords/internal/config"
	"strangewords/internal/matchmaker"
	"strangewords/internal/metrics"
	"strangewords/internal/moderation"
	"strangewords/internal/push"
	"strangewords/internal/sessions"
	"strangewords/internal/store"
)

type Server struct {
	st      *store.Store
	mm      *matchmaker.Matchmaker
	push    push.Notifier
	mod     moderation.Sink
	log     *slog.Logger
	cfg     config.Config
	now     func() time.Time
	limiter *rateLimiter // nil when rate limiting is disabled (RateRPS <= 0)
}

func New(st *store.Store, mm *matchmaker.Matchmaker, notifier push.Notifier, mod moderation.Sink, log *slog.Logger, cfg config.Config) *Server {
	s := &Server{st: st, mm: mm, push: notifier, mod: mod, log: log, cfg: cfg, now: time.Now}
	if cfg.RateRPS > 0 {
		s.limiter = newRateLimiter(cfg.RateRPS, cfg.RateBurst)
	}
	return s
}

// Routes builds the HTTP handler. Method+path patterns require Go 1.22+.
//
// Middleware order (outermost first): metrics → recover → rate-limit → body
// cap → mux. Metrics is outermost so it records the final status of every
// request, including a 429 or a panic that recover turns into a 500; recover
// sits just inside so a handler panic becomes that counted 500; the body cap is
// innermost, right before the handlers read.
func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.handleHealth)
	mux.Handle("GET /metrics", metrics.Handler())
	mux.HandleFunc("GET /privacy", s.handlePrivacy) // public privacy policy page
	mux.HandleFunc("POST /v1/enter", s.handleEnter)
	mux.HandleFunc("GET /v1/waiting", s.handleWaiting)
	mux.HandleFunc("POST /v1/wait/leave", s.handleWaitLeave)
	mux.HandleFunc("GET /v1/session/{id}", s.handleGetSession)
	mux.HandleFunc("POST /v1/session/{id}/line", s.handleLine)
	mux.HandleFunc("POST /v1/session/{id}/leave", s.handleLeave)
	mux.HandleFunc("POST /v1/session/{id}/dismiss", s.handleDismiss)
	mux.HandleFunc("POST /v1/session/{id}/report", s.handleReport)

	var h http.Handler = limitBody(mux)
	if s.limiter != nil {
		h = s.limiter.middleware(h)
	}
	h = recoverPanic(s.log, h)
	return metrics.HTTPMiddleware(h)
}

// limiterMaxIdle is the idle period after which a per-IP rate-limit bucket is
// forgotten. privacy.html cites it; privacy_test.go pins the wording.
const limiterMaxIdle = 10 * time.Minute

// StartMaintenance launches background upkeep (the rate-limiter idle sweep). It
// runs for the process lifetime; call once after New. No-op when rate limiting
// is disabled.
func (s *Server) StartMaintenance() {
	if s.limiter != nil {
		go s.limiter.runJanitor(time.Minute, limiterMaxIdle)
	}
}

// ---- infra handlers ----

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if err := s.st.Ping(r.Context()); err != nil {
		writeErr(w, http.StatusServiceUnavailable, "redis_down", "redis unreachable")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// ---- enter / waiting ----

type enterRequest struct {
	PushToken string `json:"pushToken"`
	// AllowBot is the caller's own opt-in to the robot poet (D-01). The lenient
	// decode below leaves it false when absent or wrongly typed (fail-closed).
	AllowBot bool `json:"allowBot"`
	Prefs    struct {
		Form string `json:"form"`
	} `json:"prefs"`
}

type enterResponse struct {
	ParticipantToken string         `json:"participantToken,omitempty"`
	State            string         `json:"state"`
	Session          *sessions.View `json:"session,omitempty"`
	WaitID           string         `json:"waitId,omitempty"`
}

func (s *Server) handleEnter(w http.ResponseWriter, r *http.Request) {
	var req enterRequest
	_ = json.NewDecoder(r.Body).Decode(&req) // tolerate empty body

	token := store.NewToken()
	formID := sessions.LookupForm(req.Prefs.Form).ID
	bucket := formID // v1: one bucket per form; only haiku exists

	res, err := s.mm.Enter(r.Context(), token, req.PushToken, bucket, formID, req.AllowBot, s.now())
	if err != nil {
		s.fail(w, err)
		return
	}
	metrics.Entered.Inc()

	if res.Session != nil {
		metrics.Matched.Inc()
		s.maybePush(r.Context(), res.Session, 0, push.MatchReady) // notify the waiter
		v := res.Session.ViewFor(token)
		writeJSON(w, http.StatusOK, enterResponse{ParticipantToken: token, State: "matched", Session: &v})
		return
	}
	metrics.Waiting.Inc()
	writeJSON(w, http.StatusOK, enterResponse{ParticipantToken: token, State: "waiting", WaitID: res.Wait.ID})
}

func (s *Server) handleWaiting(w http.ResponseWriter, r *http.Request) {
	token, ok := bearer(r)
	if !ok {
		writeErr(w, http.StatusUnauthorized, "no_token", "missing bearer token")
		return
	}
	ref, err := s.st.GetRef(r.Context(), token)
	if errors.Is(err, store.ErrNotFound) {
		writeErr(w, http.StatusGone, "session_gone", "your wait has ended")
		return
	}
	if err != nil {
		s.fail(w, err)
		return
	}

	sessID := ref.RefID
	idx := ref.Idx
	if ref.Kind == store.KindWait {
		wfe, err := s.st.GetWait(r.Context(), ref.RefID)
		if errors.Is(err, store.ErrNotFound) {
			writeErr(w, http.StatusGone, "session_gone", "your wait has ended")
			return
		}
		if err != nil {
			s.fail(w, err)
			return
		}
		if wfe.MatchedSessionID == "" {
			// Human first (D-03): only a still-unmatched, opted-in waiter whose
			// window has passed may claim itself for the robot poet. Losing the
			// claim to a human arrival is not an error; the next poll finds the match.
			if wfe.AllowBot && s.cfg.BotWindow > 0 && s.now().UnixMilli()-wfe.EnqueuedAt >= s.cfg.BotWindow.Milliseconds() {
				sess, claimed, err := s.mm.PairWithBot(r.Context(), wfe, sessions.LookupForm(wfe.Bucket).ID, s.cfg.BotThink, s.now())
				if err != nil {
					s.fail(w, err)
					return
				}
				if claimed {
					metrics.BotPaired.Inc()
					writeJSON(w, http.StatusOK, map[string]any{"state": "matched", "session": sess.ViewFor(token)})
					return
				}
			}
			writeJSON(w, http.StatusOK, map[string]string{"state": "waiting"})
			return
		}
		// Matched: migrate the token ref to the session (waiter is index 0).
		sessID = wfe.MatchedSessionID
		idx = 0
		_ = s.st.SetRef(r.Context(), token, store.Ref{Kind: store.KindSession, RefID: sessID, Idx: idx}, store.SessionTTL)
	}

	sess, err := s.loadSession(r.Context(), sessID)
	if err != nil {
		s.fail(w, err)
		return
	}
	sess, err = s.settleBot(r.Context(), sess)
	if err != nil {
		s.fail(w, err)
		return
	}
	s.touchPresence(r.Context(), sess, idx)
	v := sess.ViewFor(token)
	writeJSON(w, http.StatusOK, map[string]any{"state": "matched", "session": v})
}

// handleWaitLeave is the "step back out" path for a participant who has not yet
// seen a match (plan.v1.md §7). It acts only on the ref resolved from the
// caller's own bearer token. If a match landed before the leave arrived, the
// session is dissolved so the partner gets 410 rather than a dead poem.
func (s *Server) handleWaitLeave(w http.ResponseWriter, r *http.Request) {
	token, ok := bearer(r)
	if !ok {
		writeErr(w, http.StatusUnauthorized, "no_token", "missing bearer token")
		return
	}
	ctx := r.Context()
	ref, err := s.st.GetRef(ctx, token)
	if errors.Is(err, store.ErrNotFound) {
		writeErr(w, http.StatusGone, "session_gone", "your wait has ended")
		return
	}
	if err != nil {
		s.fail(w, err)
		return
	}

	var waitID, sessID string
	switch ref.Kind {
	case store.KindWait:
		waitID = ref.RefID
		sessID, err = s.mm.LeaveWait(ctx, token, waitID)
		if err != nil {
			s.fail(w, err)
			return
		}
		if sessID == "" {
			metrics.WaitLeft.Inc()
			writeJSON(w, http.StatusOK, map[string]string{"status": "left"})
			return
		}
	case store.KindSession:
		sessID = ref.RefID
	}

	sess, err := s.loadSession(ctx, sessID)
	if err != nil {
		s.fail(w, err)
		return
	}
	s.dissolve(ctx, sess)
	if waitID != "" {
		_ = s.st.DelWait(ctx, waitID) // best-effort; WaitTTL is the backstop
	}
	metrics.WaitLeft.Inc()
	writeJSON(w, http.StatusOK, map[string]string{"status": "dissolved"})
}

// ---- session actions ----

func (s *Server) handleGetSession(w http.ResponseWriter, r *http.Request) {
	sess, _, idx, ok := s.authSession(w, r)
	if !ok {
		return
	}
	sess, err := s.settleBot(r.Context(), sess)
	if err != nil {
		s.fail(w, err)
		return
	}
	s.touchPresence(r.Context(), sess, idx)
	v := sess.ViewFor(sess.Participants[idx].Token)
	writeJSON(w, http.StatusOK, v)
}

type lineRequest struct {
	Line    int    `json:"line"`
	Text    string `json:"text"`
	IdemKey string `json:"idemKey"`
}

func (s *Server) handleLine(w http.ResponseWriter, r *http.Request) {
	sess, token, idx, ok := s.authSession(w, r)
	if !ok {
		return
	}
	var req lineRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeErr(w, http.StatusBadRequest, "bad_request", "invalid body")
		return
	}

	// Idempotency: replay returns the original response verbatim.
	if req.IdemKey != "" {
		if cached, hit, err := s.st.IdemGet(r.Context(), sess.ID, req.IdemKey); err == nil && hit {
			w.Header().Set("Content-Type", "application/json")
			w.WriteHeader(http.StatusOK)
			_, _ = w.Write(cached)
			return
		}
	}

	if sess.Status != sessions.StatusActive {
		writeErr(w, http.StatusConflict, "not_active", "this poem is not accepting lines")
		return
	}
	if req.Line != sess.CurrentLine {
		writeErr(w, http.StatusConflict, "wrong_turn", "that is not the current line")
		return
	}
	if idx != sess.CurrentAuthor() {
		writeErr(w, http.StatusConflict, "not_your_turn", "it is not your turn")
		return
	}
	clean, err := sessions.CleanLine(req.Text)
	if err != nil {
		if errors.Is(err, sessions.ErrContentRejected) {
			metrics.ContentRejected.Inc()
		}
		writeErr(w, http.StatusUnprocessableEntity, "content_rejected", err.Error())
		return
	}

	// Apply the turn.
	now := s.now()
	sess.Lines = append(sess.Lines, clean)
	sess.CurrentLine++
	sess.Participants[idx].LastSeen = now.UnixMilli()
	metrics.LinesSubmitted.Inc()

	if sess.IsComplete() {
		sess.Status = sessions.StatusComplete
		sess.CompletedAt = now.UnixMilli()
		metrics.PoemsCompleted.Inc()
		if err := s.st.SaveSessionTTL(r.Context(), sess, store.RevealTTL); err != nil {
			s.fail(w, err)
			return
		}
	} else {
		if sess.BotTurn() {
			sess.BotReadyAt = now.Add(s.cfg.BotThink).UnixMilli() // arm the robot poet's think time
		}
		if err := s.st.SaveSession(r.Context(), sess); err != nil {
			s.fail(w, err)
			return
		}
		// Nudge the next author back if they are away.
		s.maybePush(r.Context(), sess, sess.CurrentAuthor(), push.YourTurn)
	}

	v := sess.ViewFor(token)
	body, _ := json.Marshal(v)
	if req.IdemKey != "" {
		_ = s.st.IdemSet(r.Context(), sess.ID, req.IdemKey, body)
		// Track for teardown so the cached response (poem content) is erased
		// when the session dissolves. Re-save to persist the tracking.
		sess.IdemKeys = append(sess.IdemKeys, req.IdemKey)
		if sess.Status == sessions.StatusComplete {
			_ = s.st.SaveSessionTTL(r.Context(), sess, store.RevealTTL)
		} else {
			_ = s.st.SaveSession(r.Context(), sess)
		}
	}
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_, _ = w.Write(body)
}

func (s *Server) handleLeave(w http.ResponseWriter, r *http.Request) {
	sess, _, _, ok := s.authSession(w, r)
	if !ok {
		return
	}
	s.dissolve(r.Context(), sess)
	writeJSON(w, http.StatusOK, map[string]string{"status": "dissolved"})
}

func (s *Server) handleDismiss(w http.ResponseWriter, r *http.Request) {
	sess, token, idx, ok := s.authSession(w, r)
	if !ok {
		return
	}
	sess.Participants[idx].Dismissed = true
	allDismissed := true
	for _, p := range sess.Participants {
		if !p.Dismissed {
			allDismissed = false
			break
		}
	}
	if allDismissed {
		s.dissolve(r.Context(), sess)
		writeJSON(w, http.StatusOK, map[string]string{"status": "dissolved"})
		return
	}
	// Preserve the reveal countdown rather than extending it.
	_ = s.st.SaveSessionTTL(r.Context(), sess, store.RevealTTL)
	v := sess.ViewFor(token)
	writeJSON(w, http.StatusOK, v)
}

// maxReasonLen caps the optional free-text reason on a report.
const maxReasonLen = 280

type reportRequest struct {
	Reason string `json:"reason"`
}

// handleReport captures an abuse report for the caller's session. It is the one
// place a poem's content crosses the ephemerality boundary (brief.final.md §23):
// any member may report while the session is still live (active or in its reveal
// window), and the content is persisted to the moderation sink synchronously,
// before the session's natural erase. No participant or push tokens are
// captured — only the poem, the form, and which session it came from.
func (s *Server) handleReport(w http.ResponseWriter, r *http.Request) {
	sess, _, idx, ok := s.authSession(w, r)
	if !ok {
		return
	}
	var req reportRequest
	_ = json.NewDecoder(r.Body).Decode(&req) // reason is optional
	reason := strings.TrimSpace(req.Reason)
	if n := []rune(reason); len(n) > maxReasonLen {
		reason = string(n[:maxReasonLen])
	}

	if err := s.mod.Capture(r.Context(), moderation.Report{
		SessionID:    sess.ID,
		Form:         sess.FormID,
		Lines:        sess.Lines,
		Participants: len(sess.Participants),
		ReporterIdx:  idx,
		Reason:       reason,
		CompletedAt:  sess.CompletedAt,
		ReportedAt:   s.now().UnixMilli(),
	}); err != nil {
		s.log.Error("report capture failed", "session", sess.ID, "err", err)
		writeErr(w, http.StatusInternalServerError, "internal", "could not file report")
		return
	}
	metrics.Reports.Inc()
	writeJSON(w, http.StatusOK, map[string]string{"status": "reported"})
}

// ---- helpers ----

// authSession resolves the bearer token to a session and the caller's index,
// verifies it matches the {id} in the path, and loads the session. It writes
// the appropriate error and returns ok=false on any failure.
func (s *Server) authSession(w http.ResponseWriter, r *http.Request) (sess *sessions.Session, token string, idx int, ok bool) {
	token, has := bearer(r)
	if !has {
		writeErr(w, http.StatusUnauthorized, "no_token", "missing bearer token")
		return nil, "", 0, false
	}
	ref, err := s.st.GetRef(r.Context(), token)
	if errors.Is(err, store.ErrNotFound) {
		writeErr(w, http.StatusGone, "session_gone", "this session has ended")
		return nil, "", 0, false
	}
	if err != nil {
		s.fail(w, err)
		return nil, "", 0, false
	}
	id := r.PathValue("id")
	if ref.Kind != store.KindSession || ref.RefID != id {
		writeErr(w, http.StatusForbidden, "not_a_member", "not your session")
		return nil, "", 0, false
	}
	sess, err = s.st.GetSession(r.Context(), id)
	if errors.Is(err, store.ErrNotFound) {
		writeErr(w, http.StatusGone, "session_gone", "this session has ended")
		return nil, "", 0, false
	}
	if err != nil {
		s.fail(w, err)
		return nil, "", 0, false
	}
	return sess, token, ref.Idx, true
}

// settleBot lets the robot poet write its current line if it is due, on the
// human's poll. It returns the session the caller should use from then on.
//
// Concurrency contract: the handler's load is only a cheap pre-check. The
// decision to write is re-made on UpdateSession's fresh read and persisted only
// through WATCH/MULTI/EXEC, so racing settles yield exactly one bot line (the
// loser's save aborts), and a human line written between a stale poll's load and
// its settle survives because the transaction aborts on any later write (or
// delete, so a dissolved session is never resurrected). An aborted settle
// persists nothing and returns the latest stored state; a later poll writes the
// line if it is still due. At most one line per call: no loop, retry or lock.
func (s *Server) settleBot(ctx context.Context, sess *sessions.Session) (*sessions.Session, error) {
	now := s.now()
	if !sess.BotTurn() || now.UnixMilli() < sess.BotReadyAt {
		return sess, nil
	}
	var wrote, completed bool
	fresh, err := s.st.UpdateSession(ctx, sess.ID, func(f *sessions.Session) (time.Duration, bool) {
		if !f.BotTurn() || now.UnixMilli() < f.BotReadyAt {
			return 0, false // another poll already settled this line, or the poem moved on
		}
		bot := f.CurrentAuthor()
		line := botplayer.NextLine(f)
		f.Lines = append(f.Lines, line)
		f.CurrentLine++
		f.Participants[bot].LastSeen = now.UnixMilli()
		wrote = true
		if f.IsComplete() {
			f.Status = sessions.StatusComplete
			f.CompletedAt = now.UnixMilli()
			completed = true
			return store.RevealTTL, true
		}
		if f.BotTurn() {
			f.BotReadyAt = now.Add(s.cfg.BotThink).UnixMilli()
		}
		return store.SessionTTL, true
	})
	switch {
	case errors.Is(err, store.ErrConflict):
		return s.loadSession(ctx, sess.ID)
	case errors.Is(err, store.ErrNotFound):
		return nil, errGone
	case err != nil:
		return nil, err
	}
	if wrote {
		metrics.LinesSubmitted.Inc()
		if completed {
			metrics.PoemsCompleted.Inc()
		}
	}
	return fresh, nil
}

func (s *Server) loadSession(ctx context.Context, id string) (*sessions.Session, error) {
	sess, err := s.st.GetSession(ctx, id)
	if errors.Is(err, store.ErrNotFound) {
		return nil, errGone
	}
	return sess, err
}

// touchPresence records that a participant was just seen. Only refreshes the
// outer TTL while active; during the reveal window the countdown is preserved.
func (s *Server) touchPresence(ctx context.Context, sess *sessions.Session, idx int) {
	if idx < 0 || idx >= len(sess.Participants) {
		return
	}
	sess.Participants[idx].LastSeen = s.now().UnixMilli()
	if sess.Status == sessions.StatusActive {
		_ = s.st.SaveSession(ctx, sess)
	}
}

// maybePush notifies participant i if they are not currently present.
func (s *Server) maybePush(ctx context.Context, sess *sessions.Session, i int, kind push.Kind) {
	if i < 0 || i >= len(sess.Participants) {
		return
	}
	p := sess.Participants[i]
	if p.Bot {
		return // the robot poet has no push token; nothing to notify
	}
	last := time.UnixMilli(p.LastSeen)
	if p.LastSeen != 0 && s.now().Sub(last) <= s.cfg.PresenceWindow {
		return // present; no push
	}
	if err := s.push.Notify(ctx, kind, p.PushToken, sess.ID); err != nil {
		s.log.Warn("push failed", "kind", string(kind), "err", err)
	}
}

func (s *Server) dissolve(ctx context.Context, sess *sessions.Session) {
	if err := s.st.DeleteSession(ctx, sess); err != nil {
		s.log.Warn("dissolve failed", "session", sess.ID, "err", err)
		return
	}
	metrics.Dissolved.Inc()
}

var errGone = errors.New("gone")

func (s *Server) fail(w http.ResponseWriter, err error) {
	if errors.Is(err, errGone) {
		writeErr(w, http.StatusGone, "session_gone", "this session has ended")
		return
	}
	s.log.Error("internal error", "err", err)
	writeErr(w, http.StatusInternalServerError, "internal", "something went wrong")
}

func bearer(r *http.Request) (string, bool) {
	h := r.Header.Get("Authorization")
	const p = "Bearer "
	if len(h) > len(p) && strings.EqualFold(h[:len(p)], p) {
		return strings.TrimSpace(h[len(p):]), true
	}
	return "", false
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

type errBody struct {
	Error struct {
		Code    string `json:"code"`
		Message string `json:"message"`
	} `json:"error"`
}

func writeErr(w http.ResponseWriter, status int, code, msg string) {
	var b errBody
	b.Error.Code = code
	b.Error.Message = msg
	writeJSON(w, status, b)
}
