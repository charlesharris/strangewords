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
        case dissolved(Reason)
    }

    enum Reason: Equatable {
        case completedAndGone   // the poem finished and dissolved
        case partnerLeft        // the other stranger stepped away
        case noOneCame          // the wait ended without a match
        case ended              // generic clean end
    }

    private(set) var phase: Phase = .threshold
    var draft: String = ""
    private(set) var submitError: String?
    private(set) var submitting = false

    private let api: any Backend
    private var pollTask: Task<Void, Never>?
    private let pollInterval: Duration = .seconds(3) // [TUNABLE] plan.v1.md §10

    /// The default backend is the real one, unless `SW_LOCAL_MOCK=1` selects the
    /// on-device `LocalBackend` (see `./run.sh --mock`). Tests/previews can inject.
    init(backend: (any Backend)? = nil) {
        if let backend {
            self.api = backend
        } else if ProcessInfo.processInfo.environment["SW_LOCAL_MOCK"] == "1" {
            self.api = LocalBackend()
        } else {
            self.api = APIClient.shared
        }
    }

    // MARK: - Entry

    /// Cross the threshold: enter the pool and either match or begin waiting.
    func begin() {
        phase = .connecting
        Task {
            do {
                let r = try await api.enter(pushToken: nil)
                if let t = r.participantToken { TokenStore.token = t }
                handleEnter(r)
            } catch {
                submitError = "Couldn't reach the quiet room. Try again."
                phase = .threshold
            }
        }
    }

    /// On cold launch, resume an in-progress engagement if the device holds one.
    func resume() {
        guard let token = TokenStore.token else { phase = .threshold; return }
        Task {
            do {
                if let sid = TokenStore.sessionId {
                    let s = try await api.getSession(id: sid, token: token)
                    apply(s)
                } else {
                    let r = try await api.waiting(token: token)
                    if r.state == "matched", let s = r.session { apply(s) }
                    else { phase = .waiting; pollWaiting() }
                }
            } catch APIError.gone {
                TokenStore.clear(); phase = .threshold
            } catch {
                phase = .threshold
            }
        }
    }

    // MARK: - Actions

    func submit() {
        guard case .composing(let s) = phase, s.yourTurn, let token = TokenStore.token else { return }
        let text = draft
        let line = s.currentLine
        let idem = UUID().uuidString
        submitting = true
        Task {
            defer { submitting = false }
            do {
                let updated = try await api.submitLine(id: s.sessionId, token: token, line: line, text: text, idemKey: idem)
                draft = ""
                submitError = nil
                apply(updated)
            } catch APIError.contentRejected(let m) {
                submitError = m
            } catch APIError.gone {
                dissolve(.partnerLeft)
            } catch APIError.notYourTurn, APIError.wrongTurn {
                // Our view was stale; refetch.
                await refresh(id: s.sessionId, token: token)
            } catch {
                submitError = "Something slipped. Try once more."
            }
        }
    }

    func dismissReveal() {
        guard case .reveal(let s) = phase, let token = TokenStore.token else { return }
        Task { await api.dismiss(id: s.sessionId, token: token) }
        dissolve(.completedAndGone)
    }

    func leave() {
        if let id = TokenStore.sessionId, let token = TokenStore.token {
            Task { await api.leave(id: id, token: token) }
        }
        dissolve(.ended)
    }

    /// Return to the threshold after a dissolution.
    func reset() {
        stopPolling()
        draft = ""
        submitError = nil
        phase = .threshold
    }

    // MARK: - Transitions

    private func handleEnter(_ r: EnterResponse) {
        if r.state == "matched", let s = r.session {
            apply(s)
        } else {
            phase = .waiting
            pollWaiting()
        }
    }

    /// Project a server view onto a phase and arrange polling.
    private func apply(_ s: SessionView) {
        TokenStore.sessionId = s.sessionId
        stopPolling()
        switch s.status {
        case "active":
            phase = .composing(s)
            if !s.yourTurn { pollSession(id: s.sessionId) }
        case "complete":
            phase = .reveal(s)
        default:
            dissolve(.ended)
        }
    }

    private func refresh(id: String, token: String) async {
        if let s = try? await api.getSession(id: id, token: token) { apply(s) }
    }

    private func dissolve(_ reason: Reason) {
        stopPolling()
        TokenStore.clear()
        phase = .dissolved(reason)
    }

    // MARK: - Polling

    private func pollWaiting() {
        stopPolling()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(3))
                guard let self, let token = TokenStore.token else { return }
                do {
                    let r = try await self.api.waiting(token: token)
                    if r.state == "matched", let s = r.session { self.apply(s); return }
                } catch APIError.gone {
                    self.dissolve(.noOneCame); return
                } catch {
                    // transient; keep waiting
                }
            }
        }
    }

    private func pollSession(id: String) {
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: self?.pollInterval ?? .seconds(3))
                guard let self, let token = TokenStore.token else { return }
                do {
                    let s = try await self.api.getSession(id: id, token: token)
                    if s.yourTurn || s.status != "active" {
                        self.apply(s); return
                    }
                    self.phase = .composing(s) // refresh lines while we wait
                } catch APIError.gone {
                    self.dissolve(.partnerLeft); return
                } catch {
                    // transient; keep polling
                }
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }
}
