import Foundation

/// The network seam the app talks through. `APIClient` reaches the real Go
/// backend over HTTPS; `LocalBackend` fakes a stranger entirely on-device so the
/// whole arc can be exercised on a single simulator with no server, Redis, or
/// robot — ideal for iterating on look & feel.
///
/// Selected in `AppModel.init`: set `SW_LOCAL_MOCK=1` (or run `./run.sh --mock`)
/// to use `LocalBackend`; otherwise the real `APIClient`.
protocol Backend: Sendable {
    func enter(pushToken: String?) async throws -> EnterResponse
    func waiting(token: String) async throws -> WaitingResponse
    func getSession(id: String, token: String) async throws -> SessionView
    func submitLine(id: String, token: String, line: Int, text: String, idemKey: String) async throws -> SessionView
    func leave(id: String, token: String) async
    func dismiss(id: String, token: String) async
}
