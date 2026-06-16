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

    var isActive: Bool { status == "active" }
    var isComplete: Bool { status == "complete" }

    /// The syllable target for the line currently being written, if any.
    var currentTarget: Int? {
        guard currentLine >= 0, currentLine < form.targets.count else { return nil }
        return form.targets[currentLine]
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
