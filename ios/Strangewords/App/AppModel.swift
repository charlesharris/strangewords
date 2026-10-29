import Foundation
import Observation

/// AppModel is the observable state machine that mirrors the server session
/// lifecycle (plan.v1.md §5, §10). Feature views are pure functions of `phase`.
/// HTTPS + polling drives everything; push is a later re-engagement enhancement.
@MainActor
@Observable
final class AppModel {
    enum Phase: Equatable {
        case threshold
        case connecting
        case waiting
        case composing(SessionView)
        case reveal(SessionView)
        case dissolving(SessionView)   // the dissolution effect is playing, full-screen
        case dissolved(Reason)
    }

    enum Reason: Equatable {
        case completedAndGone   // the poem finished and dissolved
        case partnerLeft        // the other stranger stepped away
        case noOneCame          // the wait ended without a match
        case ended              // generic clean end
    }

    // Small helpers used to detect meaningful phase transitions (e.g. for haptics).
    private var composingSession: SessionView? {
        if case .composing(let s) = phase { return s }
        return nil
    }
    private var isReveal: Bool {
        if case .reveal = phase { return true }
        return false
    }

    private(set) var phase: Phase = .threshold
    var draft: String = ""
    private(set) var submitError: String?
    private(set) var submitting = false
    /// The name this poem coined on its way out — the one thing that survives the
    /// dissolution (see `Naming/PoemNaming.swift`). Set only when a poem completes;
    /// nil for every other ending. Read by `DissolvedView`.
    private(set) var keepsake: CoinedName?

    /// The user's opt-in to write with the robot poet when no stranger arrives
    /// (Phase 5 D-01, D-02). Default OFF; writes through to `SettingsStore`.
    /// Survives `dissolve()` and `reset()`: it is a preference, not identity.
    var allowBot: Bool {
        didSet { settings.allowBot = allowBot }
    }

    /// The user's chosen scenery as a `Themes` id (Settings → scenery). A device
    /// preference, not identity: it survives `dissolve()` and `reset()`, is read by
    /// `RootView`, and is never passed to the `Backend`.
    var themeID: String {
        didSet { settings.themeID = themeID }
    }

    /// How often the poll loops ask the backend for news.
    // nonisolated: referenced from the nonisolated init's default argument; a
    // Duration is immutable/Sendable, so this is safe and keeps Swift 6 happy.
    nonisolated static let defaultPollInterval: Duration = .seconds(3) // [TUNABLE] plan.v1.md §10

    private let api: any Backend
    private let tokenStore: TokenStore
    private let settings: SettingsStore
    let pollInterval: Duration
    @ObservationIgnored private(set) var pollTask: Task<Void, Never>?
    /// The in-flight action task (begin, resume, submit, release, leave). It gives
    /// tests a deterministic sync point (Phase 2 D-07); views never read it.
    @ObservationIgnored private(set) var actionTask: Task<Void, Never>?
    /// A session generation. `begin`, `reset` and `dissolve` bump it; any writer that
    /// captured an older value is stale and must not touch state or identity (D-08).
    /// Compared for equality only, never ordered.
    @ObservationIgnored private var epoch = 0

    /// The default backend is the real one, unless `SW_LOCAL_MOCK=1` selects the
    /// on-device `LocalBackend` (see `./run.sh --mock`). Tests/previews can inject.
    /// `tokenStore` (identity container), `settings` (device preferences) and
    /// `pollInterval` (poll cadence) are defaulted seams: production keeps
    /// `UserDefaults.standard` and 3 seconds.
    init(backend: (any Backend)? = nil,
         tokenStore: TokenStore = TokenStore(),
         settings: SettingsStore = SettingsStore(),
         pollInterval: Duration = AppModel.defaultPollInterval) {
        self.tokenStore = tokenStore
        self.settings = settings
        self.allowBot = settings.allowBot
        // Normalizes an absent or unknown stored id to nature in memory. didSet does
        // not fire during init, so launching never writes the key.
        self.themeID = Themes.with(id: settings.themeID).id
        self.pollInterval = pollInterval
        if let backend {
            self.api = backend
        } else if ProcessInfo.processInfo.environment["SW_LOCAL_MOCK"] == "1" {
            self.api = LocalBackend()
            // Mock sessions are ephemeral (a fresh LocalBackend each launch), so
            // a token persisted from a previous run is meaningless — clear it so
            // we always start at the threshold rather than resuming a ghost.
            tokenStore.clear()
        } else {
            self.api = APIClient.shared
        }
    }

    // MARK: - Entry

    /// Cross the threshold: enter the pool and either match or begin waiting.
    func begin() {
        epoch += 1
        let e = epoch
        let allow = allowBot   // captured now: the opt-in is for this one wait
        Haptics.soft()
        keepsake = nil
        phase = .connecting
        actionTask = Task {
            do {
                let r = try await api.enter(pushToken: nil, allowBot: allow)
                guard !isStale(e) else { return }
                if let t = r.participantToken { tokenStore.token = t }
                handleEnter(r, epoch: e)
            } catch {
                guard !isStale(e) else { return }
                submitError = "Couldn't reach the quiet room. Try again."
                phase = .threshold
            }
        }
    }

    /// On cold launch, resume an in-progress engagement if the device holds one.
    func resume() {
        guard let token = tokenStore.token else { phase = .threshold; return }
        let e = epoch
        actionTask = Task {
            do {
                if let sid = tokenStore.sessionId {
                    let s = try await api.getSession(id: sid, token: token)
                    guard !isStale(e) else { return }
                    apply(s, epoch: e)
                } else {
                    let r = try await api.waiting(token: token)
                    guard !isStale(e) else { return }
                    if r.state == "matched", let s = r.session { apply(s, epoch: e) }
                    else { phase = .waiting; pollWaiting() }
                }
            } catch APIError.gone {
                guard !isStale(e) else { return }
                tokenStore.clear(); phase = .threshold
            } catch {
                guard !isStale(e) else { return }
                phase = .threshold
            }
        }
    }

    // MARK: - Actions

    func submit() {
        guard case .composing(let s) = phase, s.yourTurn, let token = tokenStore.token else { return }
        let text = draft
        let line = s.currentLine
        let idem = UUID().uuidString
        let e = epoch
        Haptics.offer()
        submitting = true
        actionTask = Task {
            defer { submitting = false }
            do {
                let updated = try await api.submitLine(id: s.sessionId, token: token, line: line, text: text, idemKey: idem)
                guard !isStale(e) else { return }
                draft = ""
                submitError = nil
                apply(updated, epoch: e)
            } catch APIError.contentRejected(let m) {
                guard !isStale(e) else { return }
                submitError = m
            } catch APIError.gone {
                guard !isStale(e) else { return }
                dissolve(.partnerLeft)
            } catch APIError.notYourTurn, APIError.wrongTurn {
                // Our view was stale; refetch.
                await refresh(id: s.sessionId, token: token, epoch: e)
            } catch {
                guard !isStale(e) else { return }
                submitError = "Something slipped. Try once more."
            }
        }
    }

    /// Tap "let it go": tell the server we're done and start the (full-screen)
    /// dissolution effect. The effect calls `finishDissolving()` when it ends.
    func release() {
        guard case .reveal(let s) = phase else { return }
        if let token = tokenStore.token {
            actionTask = Task { await api.dismiss(id: s.sessionId, token: token) }
        }
        phase = .dissolving(s)
    }

    /// The dissolution effect finished; let the poem go. As it goes, coin the one
    /// name it leaves behind (while the lines are still in hand).
    func finishDissolving() {
        if case .dissolving(let s) = phase {
            keepsake = PoemNaming.coin(from: s.lines)
        }
        dissolve(.completedAndGone)
    }

    /// Step out. A mid-session exit reports `leave`; a pre-match exit (a token but
    /// no session id yet) reports `leaveWait`, so the server never pairs the next
    /// arriver with a departed waiter (OBS-1). The token is captured before
    /// `dissolve` clears identity.
    func leave() {
        if let token = tokenStore.token {
            if let id = tokenStore.sessionId {
                actionTask = Task { await api.leave(id: id, token: token) }
            } else {
                actionTask = Task { await api.leaveWait(token: token) }
            }
        }
        dissolve(.ended)
    }

    /// Return to the threshold after a dissolution.
    func reset() {
        epoch += 1
        stopPolling()
        draft = ""
        submitError = nil
        keepsake = nil
        phase = .threshold
    }

    // MARK: - Transitions

    private func handleEnter(_ r: EnterResponse, epoch e: Int) {
        if r.state == "matched", let s = r.session {
            apply(s, epoch: e)
        } else {
            phase = .waiting
            pollWaiting()
        }
    }

    /// Project a server view onto a phase and arrange polling. The epoch check
    /// comes first so a stale view never reaches the session-id write (D-08).
    private func apply(_ s: SessionView, epoch e: Int) {
        guard !isStale(e) else { return }
        // Read the outgoing phase before mutating, to detect real transitions.
        let wasComposing = composingSession != nil
        let wasYourTurn = composingSession?.yourTurn ?? false
        let wasReveal = isReveal

        tokenStore.sessionId = s.sessionId
        stopPolling()
        switch s.status {
        case "active":
            phase = .composing(s)
            if !wasComposing {
                Haptics.arrival()                 // matched with a stranger
            } else if !wasYourTurn && s.yourTurn {
                Haptics.arrival()                 // the turn has come back to you
            }
            if !s.yourTurn { pollSession(id: s.sessionId) }
        case "complete":
            phase = .reveal(s)
            if !wasReveal { Haptics.reveal() }
        default:
            dissolve(.ended)
        }
    }

    private func refresh(id: String, token: String, epoch e: Int) async {
        if let s = try? await api.getSession(id: id, token: token) { apply(s, epoch: e) }
    }

    private func dissolve(_ reason: Reason) {
        epoch += 1
        stopPolling()
        tokenStore.clear()
        phase = .dissolved(reason)
    }

    // MARK: - Polling

    private func pollWaiting() {
        stopPolling()
        let e = epoch
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.pollInterval ?? AppModel.defaultPollInterval)
                guard let self, let token = self.tokenStore.token else { return }
                do {
                    let r = try await self.api.waiting(token: token)
                    guard !self.isStale(e) else { return }
                    if r.state == "matched", let s = r.session { self.apply(s, epoch: e); return }
                } catch APIError.gone {
                    guard !self.isStale(e) else { return }
                    self.dissolve(.noOneCame); return
                } catch {
                    // transient; keep waiting
                }
            }
        }
    }

    private func pollSession(id: String) {
        let e = epoch
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.pollInterval ?? AppModel.defaultPollInterval)
                guard let self, let token = self.tokenStore.token else { return }
                do {
                    let s = try await self.api.getSession(id: id, token: token)
                    guard !self.isStale(e) else { return }
                    if s.yourTurn || s.status != "active" {
                        self.apply(s, epoch: e); return
                    }
                    self.phase = .composing(s) // refresh lines while we wait
                } catch APIError.gone {
                    guard !self.isStale(e) else { return }
                    self.dissolve(.partnerLeft); return
                } catch {
                    // transient; keep polling
                }
            }
        }
    }

    /// True once this writer's generation has ended: its task was cancelled, or a
    /// `begin`/`reset`/`dissolve` moved the epoch on since it captured `e`.
    private func isStale(_ e: Int) -> Bool {
        Task.isCancelled || e != epoch
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
