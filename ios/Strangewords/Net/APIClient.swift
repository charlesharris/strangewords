import Foundation

/// Typed errors surfaced to the UI so each state transition is intentional.
enum APIError: Error, Equatable {
    case gone                 // 410: the session/wait has ended
    case notYourTurn          // 409 not_your_turn
    case wrongTurn            // 409 wrong_turn / not_active
    case contentRejected(String) // 422
    case http(Int)
    case transport
}

/// APIClient performs the HTTPS calls of the §7 contract. It is an actor so
/// network work stays off the main thread; the token is read from TokenStore.
actor APIClient: Backend {
    static let shared = APIClient()

    /// Base URL of the Go backend.
    ///
    /// Device and Release builds talk to the stable custom hostname, so the
    /// backend can be re-pointed via DNS without an App Store update. The
    /// simulator dev loop overrides it with `SW_API_BASE` (run.sh sets this to
    /// the local server for --solo/--two); the override never ships, since the
    /// environment is only populated by simctl during a dev launch.
    // RED stubs (Phase 2 plan 01 Task 3): inert placeholders so the new tests
    // compile and fail on their assertions. Replaced in the GREEN commit; nothing
    // in production calls them yet.
    static func resolveBase(environment: [String: String]) -> URL { URL(string: "about:blank")! }
    static func makeDefaultSession() -> URLSession { URLSession(configuration: .ephemeral) }
    init(base: URL = APIClient.resolveBase(environment: [:]), session: URLSession = APIClient.makeDefaultSession()) {}

    let base: URL = {
        if let override = ProcessInfo.processInfo.environment["SW_API_BASE"],
           let u = URL(string: override) {
            return u
        }
        return URL(string: "https://api.strangerwords.us")!
    }()
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()

    func enter(pushToken: String?) async throws -> EnterResponse {
        var body: [String: Any] = [:]
        if let pushToken { body["pushToken"] = pushToken }
        let (data, status) = try await send("POST", "/v1/enter", token: nil, json: body)
        guard status == 200 else { throw mapError(status, data) }
        return try decode(EnterResponse.self, data)
    }

    func waiting(token: String) async throws -> WaitingResponse {
        let (data, status) = try await send("GET", "/v1/waiting", token: token, json: nil)
        guard status == 200 else { throw mapError(status, data) }
        return try decode(WaitingResponse.self, data)
    }

    func getSession(id: String, token: String) async throws -> SessionView {
        let (data, status) = try await send("GET", "/v1/session/\(id)", token: token, json: nil)
        guard status == 200 else { throw mapError(status, data) }
        return try decode(SessionView.self, data)
    }

    func submitLine(id: String, token: String, line: Int, text: String, idemKey: String) async throws -> SessionView {
        let body: [String: Any] = ["line": line, "text": text, "idemKey": idemKey]
        let (data, status) = try await send("POST", "/v1/session/\(id)/line", token: token, json: body)
        guard status == 200 else { throw mapError(status, data) }
        return try decode(SessionView.self, data)
    }

    func leave(id: String, token: String) async {
        _ = try? await send("POST", "/v1/session/\(id)/leave", token: token, json: [:])
    }

    func dismiss(id: String, token: String) async {
        _ = try? await send("POST", "/v1/session/\(id)/dismiss", token: token, json: [:])
    }

    // MARK: - plumbing

    private func send(_ method: String, _ path: String, token: String?, json: [String: Any]?) async throws -> (Data, Int) {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let json {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: json)
        }
        do {
            let (data, resp) = try await session.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            return (data, status)
        } catch {
            throw APIError.transport
        }
    }

    private func decode<T: Decodable>(_ type: T.Type, _ data: Data) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw APIError.transport }
    }

    private func mapError(_ status: Int, _ data: Data) -> APIError {
        if status == 410 { return .gone }
        let code = (try? JSONDecoder().decode(ServerError.self, from: data))?.error.code
        switch (status, code) {
        case (409, "not_your_turn"): return .notYourTurn
        case (409, _):               return .wrongTurn
        case (422, _):
            let msg = (try? JSONDecoder().decode(ServerError.self, from: data))?.error.message ?? "rejected"
            return .contentRejected(msg)
        default: return .http(status)
        }
    }
}
