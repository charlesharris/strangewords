import Foundation

/// Developer affordances that appear only in mock/dev runs — `./run.sh --mock`
/// (which sets `SW_LOCAL_MOCK=1`) or an explicit `SW_DEV=1`. They never appear
/// in a normal build, so the real experience stays clean.
enum Dev {
    static var showControls: Bool {
        let env = ProcessInfo.processInfo.environment
        return env["SW_LOCAL_MOCK"] == "1" || env["SW_DEV"] == "1"
    }

    /// Boot straight into a looping dissolution so the petal animation can be
    /// seen and tuned without playing a whole poem. Set `SW_DEV_DISSOLVE=1`.
    static var previewDissolution: Bool {
        ProcessInfo.processInfo.environment["SW_DEV_DISSOLVE"] == "1"
    }
}
