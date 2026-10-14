import Testing
import Foundation

/// Permanent guard for host isolation (Phase 1 D-12). Hosted tests run inside the
/// app process, so `ProcessInfo` here is the same environment `AppModel.init`
/// reads when it picks a backend (the `SW_LOCAL_MOCK` branch in AppModel.swift).
///
/// - `hostRunsInLocalMockMode` checks that the scheme's test action sets
///   `SW_LOCAL_MOCK=1` (on-device `LocalBackend`, leftover token cleared) and a
///   dead `SW_API_BASE`, so no test run can reach the production API.
/// - `testEnvIsNotInheritedFromRunAction` checks that the Run action's `SW_DEV`
///   is absent. Seeing it would mean the test action fell back to inheriting the
///   Run env, which would make isolation hold only by accident.
struct HostIsolationTests {
    @Test func hostRunsInLocalMockMode() {
        let env = ProcessInfo.processInfo.environment
        #expect(env["SW_LOCAL_MOCK"] == "1")
        #expect(env["SW_API_BASE"] == "http://127.0.0.1:9")
    }

    @Test func testEnvIsNotInheritedFromRunAction() {
        #expect(ProcessInfo.processInfo.environment["SW_DEV"] == nil)
    }
}
