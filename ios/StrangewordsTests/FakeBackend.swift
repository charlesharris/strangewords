import Foundation
import Testing
@testable import Strangewords

/// A gated `Backend` test double (Phase 2 D-05). Every `enter`, `waiting`,
/// `getSession` and `submitLine` call is recorded, then parked on a continuation
/// until the test resolves or fails it, so the test owns exactly when each
/// response lands. `leave` and `dismiss` are recorded and return at once, since
/// `AppModel` fires them and nothing waits on their result.
///
/// Parking every poll is also what keeps `pollInterval: .zero` honest (D-06):
/// the poll loops have no pacing of their own, so a fake that answered at once
/// would spin the main actor. Calls reach the test through `arrivals` in the
/// order they were made.
///
/// The suspension deliberately ignores cancellation of the calling task. It
/// models a response the network has already delivered, which is the window
/// plan 02-02's stale-writer tests reproduce.
actor FakeBackend: Backend {
    enum Kind: Equatable, Sendable {
        case enter, waiting, getSession, submitLine, leave, dismiss
    }

    /// One parked call. Resolve or fail it exactly once; a second attempt records
    /// an `Issue` instead of trapping on a double resume.
    final class Pending: @unchecked Sendable {
        let kind: Kind
        let id: String?
        let token: String?
        let line: Int?
        let text: String?
        let idemKey: String?
        /// The opt-in an `enter` call carried; nil for every other kind.
        let allowBot: Bool?

        private let continuation: CheckedContinuation<Any, Error>
        private let lock = NSLock()
        private var spent = false

        fileprivate init(kind: Kind, id: String?, token: String?, line: Int?, text: String?,
                         idemKey: String?, allowBot: Bool?, continuation: CheckedContinuation<Any, Error>) {
            self.kind = kind
            self.id = id
            self.token = token
            self.line = line
            self.text = text
            self.idemKey = idemKey
            self.allowBot = allowBot
            self.continuation = continuation
        }

        /// True while neither `resolve` nor `fail` has run.
        var isOpen: Bool {
            lock.lock(); defer { lock.unlock() }
            return !spent
        }

        func resolve(_ value: Any) {
            guard claim() else { return }
            continuation.resume(returning: value)
        }

        func fail(_ error: Error) {
            guard claim() else { return }
            continuation.resume(throwing: error)
        }

        private func claim() -> Bool {
            lock.lock(); defer { lock.unlock() }
            if spent {
                Issue.record("FakeBackend.Pending (\(kind)) was resolved more than once")
                return false
            }
            spent = true
            return true
        }

        /// Cleanup path: fail without recording an `Issue` if a test already did.
        fileprivate func failIfOpen(_ error: Error) {
            lock.lock()
            if spent { lock.unlock(); return }
            spent = true
            lock.unlock()
            continuation.resume(throwing: error)
        }
    }

    /// Calls in the order they were made. Safe to read from any task.
    nonisolated let arrivals: AsyncStream<Pending>

    private let sink: AsyncStream<Pending>.Continuation
    private var calls: [Kind] = []
    private var parked: [Pending] = []
    private var drained = false

    init() {
        let (stream, continuation) = AsyncStream<Pending>.makeStream()
        arrivals = stream
        sink = continuation
    }

    // MARK: - Backend

    func enter(pushToken: String?, allowBot: Bool) async throws -> EnterResponse {
        let value = try await park(.enter, allowBot: allowBot)
        return try cast(value, to: EnterResponse.self, for: .enter)
    }

    func waiting(token: String) async throws -> WaitingResponse {
        let value = try await park(.waiting, token: token)
        return try cast(value, to: WaitingResponse.self, for: .waiting)
    }

    func getSession(id: String, token: String) async throws -> SessionView {
        let value = try await park(.getSession, id: id, token: token)
        return try cast(value, to: SessionView.self, for: .getSession)
    }

    func submitLine(id: String, token: String, line: Int, text: String, idemKey: String) async throws -> SessionView {
        let value = try await park(.submitLine, id: id, token: token, line: line, text: text, idemKey: idemKey)
        return try cast(value, to: SessionView.self, for: .submitLine)
    }

    func leave(id: String, token: String) async {
        calls.append(.leave)
    }

    func dismiss(id: String, token: String) async {
        calls.append(.dismiss)
    }

    // MARK: - Test surface

    /// Call kinds in the order `AppModel` made them.
    func recordedCalls() -> [Kind] { calls }

    /// Fails every still-open call with `CancellationError`, and fails any later
    /// call at once. Cleanup relies on this so no task stays parked holding a model.
    func drain() {
        drained = true
        for pending in parked { pending.failIfOpen(CancellationError()) }
        parked.removeAll()
        sink.finish()
    }

    // MARK: - Plumbing

    private func park(_ kind: Kind, id: String? = nil, token: String? = nil, line: Int? = nil,
                      text: String? = nil, idemKey: String? = nil, allowBot: Bool? = nil) async throws -> Any {
        calls.append(kind)
        if drained { throw CancellationError() }
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Any, Error>) in
            let pending = Pending(kind: kind, id: id, token: token, line: line, text: text,
                                  idemKey: idemKey, allowBot: allowBot, continuation: continuation)
            parked.append(pending)
            sink.yield(pending)
        }
    }

    private func cast<T>(_ value: Any, to type: T.Type, for kind: Kind) throws -> T {
        guard let typed = value as? T else {
            Issue.record("FakeBackend \(kind) was resolved with \(Swift.type(of: value)), expected \(T.self)")
            throw APIError.transport
        }
        return typed
    }
}
