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

	"strangewords/internal/config"
	"strangewords/internal/matchmaker"
	"strangewords/internal/metrics"
	"strangewords/internal/push"
	"strangewords/internal/sessions"
	"strangewords/internal/store"
)

type Server struct {
	st   *store.Store
	mm   *matchmaker.Matchmaker
	push push.Notifier
	log  *slog.Logger
	cfg  config.Config
	now  func() time.Time
}

func New(st *store.Store, mm *matchmaker.Matchmaker, notifier push.Notifier, log *slog.Logger, cfg config.Config) *Server {
	return &Server{st: st, mm: mm, push: notifier, log: log, cfg: cfg, now: time.Now}
}

// Routes builds the HTTP handler. Method+path patterns require Go 1.22+.
func (s *Server) Routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /healthz", s.handleHealth)
	mux.HandleFunc("GET /metrics", s.handleMetrics)
	mux.HandleFunc("POST /v1/enter", s.handleEnter)
	mux.HandleFunc("GET /v1/waiting", s.handleWaiting)
	mux.HandleFunc("GET /v1/session/{id}", s.handleGetSession)
	mux.HandleFunc("POST /v1/session/{id}/line", s.handleLine)
	mux.HandleFunc("POST /v1/session/{id}/leave", s.handleLeave)
	mux.HandleFunc("POST /v1/session/{id}/dismiss", s.handleDismiss)
	return mux
}

// ---- infra handlers ----

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	if err := s.st.Ping(r.Context()); err != nil {
		writeErr(w, http.StatusServiceUnavailable, "redis_down", "redis unreachable")
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) handleMetrics(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/plain; version=0.0.4")
	metrics.WriteText(w)
}

// ---- enter / waiting ----

type enterRequest struct {
	PushToken string `json:"pushToken"`
	Prefs     struct {
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

	res, err := s.mm.Enter(r.Context(), token, req.PushToken, bucket, formID, s.now())
	if err != nil {
		s.fail(w, err)
		return
	}
	metrics.C.Entered.Add(1)

	if res.Session != nil {
		metrics.C.Matched.Add(1)
		s.maybePush(r.Context(), res.Session, 0, push.MatchReady) // notify the waiter
		v := res.Session.ViewFor(token)
		writeJSON(w, http.StatusOK, enterResponse{ParticipantToken: token, State: "matched", Session: &v})
		return
	}
	metrics.C.Waiting.Add(1)
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
	s.touchPresence(r.Context(), sess, idx)
	v := sess.ViewFor(token)
	writeJSON(w, http.StatusOK, map[string]any{"state": "matched", "session": v})
}

// ---- session actions ----

func (s *Server) handleGetSession(w http.ResponseWriter, r *http.Request) {
	sess, _, idx, ok := s.authSession(w, r)
	if !ok {
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
		writeErr(w, http.StatusUnprocessableEntity, "content_rejected", err.Error())
		return
	}

	// Apply the turn.
	now := s.now()
	sess.Lines = append(sess.Lines, clean)
	sess.CurrentLine++
	sess.Participants[idx].LastSeen = now.UnixMilli()
	metrics.C.LinesSubmitted.Add(1)

	if sess.IsComplete() {
		sess.Status = sessions.StatusComplete
		sess.CompletedAt = now.UnixMilli()
		metrics.C.PoemsCompleted.Add(1)
		if err := s.st.SaveSessionTTL(r.Context(), sess, store.RevealTTL); err != nil {
			s.fail(w, err)
			return
		}
	} else {
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
	metrics.C.Dissolved.Add(1)
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
