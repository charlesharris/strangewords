import Testing
import Foundation

/// An always-failing test that is switched off unless asked for, so the failing
/// verdict of `scripts/test-ios.sh` can be re-proven on demand.
///
/// In every normal run the canary is disabled and reported as skipped.
/// `TEST_RUNNER_SW_HARNESS_CANARY_FAIL=1 scripts/test-ios.sh` enables it:
/// xcodebuild strips the `TEST_RUNNER_` prefix into the host's environment.
/// When enabled, the runner must exit 1.
struct HarnessCanary {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SW_HARNESS_CANARY_FAIL"] == "1"))
    func failsOnPurpose() {
        #expect(Bool(false), "harness canary")
    }
}
