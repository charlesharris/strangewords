import Foundation
import Testing
@testable import Strangewords

/// Shared test helpers. `makeModel` is the ONLY place a test builds an `AppModel`
/// (Phase 2 D-04, D-06): it always injects a suite-named `TokenStore` and a zero
/// poll interval, so no test writes identity into `UserDefaults.standard` and
/// poll pacing comes entirely from the `FakeBackend` gates.

/// A UUID-named `UserDefaults` container plus the closure that erases it (D-04).
func makeIsolatedDefaults() -> (defaults: UserDefaults, cleanup: () -> Void) {
    let suite = "sw.tests." + UUID().uuidString
    let defaults = UserDefaults(suiteName: suite)!
    return (defaults, { defaults.removePersistentDomain(forName: suite) })
}

/// The only AppModel factory in tests.
@MainActor
func makeModel(backend: any Backend, defaults: UserDefaults) -> AppModel {
    AppModel(backend: backend, tokenStore: TokenStore(defaults: defaults), pollInterval: .zero)
}

/// A haiku-form session view as the server would project it for participant 0.
func haikuView(id: String = "s1", status: String = "active", currentLine: Int = 0,
               yourTurn: Bool = true, lines: [String] = []) -> SessionView {
    SessionView(sessionId: id, you: 0, participantCount: 2, status: status,
                form: FormView(id: "haiku", targets: [5, 7, 5]),
                currentLine: currentLine, currentAuthor: yourTurn ? 0 : 1,
                yourTurn: yourTurn, lines: lines)
}

/// Thrown when the fake's arrival stream ends before a test got the call it expected.
struct ArrivalsEnded: Error {}

/// Walks `fake.arrivals` one call at a time, in the order `AppModel` made them.
/// Deliberately not main-actor isolated: advancing the iterator is a mutating
/// async call, which Swift refuses on actor-isolated storage. Only one test task
/// ever awaits it at a time.
final class Arrivals: @unchecked Sendable {
    private var iterator: AsyncStream<FakeBackend.Pending>.AsyncIterator

    init(_ fake: FakeBackend) {
        iterator = fake.arrivals.makeAsyncIterator()
    }

    func next(sourceLocation: SourceLocation = #_sourceLocation) async throws -> FakeBackend.Pending {
        guard let pending = await iterator.next() else {
            Issue.record("FakeBackend arrivals ended before the expected call", sourceLocation: sourceLocation)
            throw ArrivalsEnded()
        }
        return pending
    }
}

/// Ends every AppModel test: leave, fail any still-open call, let the last action
/// task settle, then erase the suite. Nothing is left parked or persisted.
@MainActor
func finish(_ model: AppModel, _ fake: FakeBackend, _ cleanup: () -> Void) async {
    model.leave()
    await fake.drain()
    await model.actionTask?.value
    cleanup()
}
