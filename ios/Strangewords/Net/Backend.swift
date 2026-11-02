import Foundation

/// The network seam the app talks through. `APIClient` reaches the real Go
/// backend over HTTPS; `LocalBackend` fakes a stranger entirely on-device so the
/// whole arc can be exercised on a single simulator with no server, Redis, or
/// robot — ideal for iterating on look & feel.
///
/// Selected in `AppModel.init`: set `SW_LOCAL_MOCK=1` (or run `./run.sh --mock`)
/// to use `LocalBackend`; otherwise the real `APIClient`.
protocol Backend: Sendable {
    /// `allowBot` is the user's opt-in, for this one wait only, to be paired with
    /// the robot poet when no stranger arrives. The server treats it as a
    /// preference of the caller alone; an older server ignores the key and stays
    /// humans-only. There is deliberately no overload that omits it.
    func enter(pushToken: String?, allowBot: Bool) async throws -> EnterResponse
    func waiting(token: String) async throws -> WaitingResponse
    func getSession(id: String, token: String) async throws -> SessionView
    func submitLine(id: String, token: String, line: Int, text: String, idemKey: String) async throws -> SessionView
    func leave(id: String, token: String) async
    /// Step out of the waiting queue before any match (the "step back out"
    /// action). Fire-and-forget like `leave`. The server removes the queue entry,
    /// wait record and token ref, or dissolves the session if a match landed
    /// first. If the call never arrives, the server's liveness rule drops the
    /// waiter within `StaleWaiterAfter`. An older server 404s it, which is ignored.
    func leaveWait(token: String) async
    func dismiss(id: String, token: String) async
    /// Offers, or accepts the partner's offer, to write a second poem after a poem's
    /// reveal (Phase 6 D-02). Returns the updated view: still complete with
    /// `youWantTrade` while the partner considers, or the next poem (status active)
    /// once both have asked. A closed trade throws `APIError.wrongTurn` (the server's
    /// 409 `trade_closed`). The app calls it only when the server's view says
    /// `tradeOpen`, which an older server never sends; an older server would 404 it
    /// (`APIError.http(404)`). There is deliberately no overload that omits arguments.
    func tradeBack(id: String, token: String) async throws -> SessionView
}
