import Foundation

/// The client-facing projection of a session (plan.v1.md §7). Speaks
/// participant indices, never A/B, so the UI is participant-count agnostic.
struct SessionView: Codable, Equatable {
    let sessionId: String
    let you: Int
    let participantCount: Int
    let status: String          // "active" | "complete" | "dissolved"
    let form: FormView
    let currentLine: Int
    let currentAuthor: Int
    let yourTurn: Bool
    let lines: [String]
    /// True when the partner is the opt-in robot poet. Declared last with a default
    /// so the memberwise initializer keeps compiling at every existing call site.
    var partnerIsBot: Bool = false

    /// Phase 6 trade back. The server computes these in `Session.ViewFor` and omits
    /// zero or false values (Go `omitempty`); an older server sends none of them, so
    /// the trade never appears (fail-safe). Nothing on the client infers them. Each
    /// is declared with a default so every memberwise call site compiles unchanged.
    /// Which poem of the encounter this is, from 1.
    var poemNumber: Int = 1
    /// A second poem can be asked for right now: this poem is complete and a later one exists.
    var tradeOpen: Bool = false
    /// You have offered (or accepted) and are waiting on the partner.
    var youWantTrade: Bool = false
    /// The partner has offered (or accepted).
    var partnerWantsTrade: Bool = false

    var isActive: Bool { status == "active" }
    var isComplete: Bool { status == "complete" }

    /// The syllable target for the line currently being written, if any.
    var currentTarget: Int? {
        guard currentLine >= 0, currentLine < form.targets.count else { return nil }
        return form.targets[currentLine]
    }
}

extension SessionView {
    /// The wire keys, listed explicitly because `init(from:)` below is hand-written.
    /// Any future field must be added to both `CodingKeys` and `init(from:)`.
    enum CodingKeys: String, CodingKey {
        case sessionId, you, participantCount, status, form
        case currentLine, currentAuthor, yourTurn, lines, partnerIsBot
        case poemNumber, tradeOpen, youWantTrade, partnerWantsTrade
    }

    /// Tolerant decode: the server omits `partnerIsBot` when false (human sessions,
    /// and old servers), which plain synthesized Codable would reject with
    /// keyNotFound. The disclosure is derived only by the server
    /// (`Session.ViewFor`) and is never computed on the client (Phase 5 D-04). The
    /// four trade fields (Phase 6) follow the same rule: absent means 1 or false.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        you = try c.decode(Int.self, forKey: .you)
        participantCount = try c.decode(Int.self, forKey: .participantCount)
        status = try c.decode(String.self, forKey: .status)
        form = try c.decode(FormView.self, forKey: .form)
        currentLine = try c.decode(Int.self, forKey: .currentLine)
        currentAuthor = try c.decode(Int.self, forKey: .currentAuthor)
        yourTurn = try c.decode(Bool.self, forKey: .yourTurn)
        lines = try c.decode([String].self, forKey: .lines)
        partnerIsBot = try c.decodeIfPresent(Bool.self, forKey: .partnerIsBot) ?? false
        poemNumber = try c.decodeIfPresent(Int.self, forKey: .poemNumber) ?? 1
        tradeOpen = try c.decodeIfPresent(Bool.self, forKey: .tradeOpen) ?? false
        youWantTrade = try c.decodeIfPresent(Bool.self, forKey: .youWantTrade) ?? false
        partnerWantsTrade = try c.decodeIfPresent(Bool.self, forKey: .partnerWantsTrade) ?? false
    }
}

/// The form descriptor the client renders structure from. `targets` entries may
/// be null (e.g. free verse) — hence `[Int?]`.
struct FormView: Codable, Equatable {
    let id: String
    let targets: [Int?]
}

struct EnterResponse: Codable {
    let participantToken: String?
    let state: String           // "matched" | "waiting"
    let session: SessionView?
    let waitId: String?
}

struct WaitingResponse: Codable {
    let state: String           // "matched" | "waiting"
    let session: SessionView?
}

struct ServerError: Codable {
    struct Body: Codable { let code: String; let message: String }
    let error: Body
}
