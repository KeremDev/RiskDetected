import Foundation

/// Binary-level release gate for the Wave 1 global-localization surface.
///
/// Release candidate 1.3.1 (81) compiles this capability into the binary.
/// Public availability still requires server-owned rollout gates; compiling
/// the capability never authorizes a cohort or activates a live-user rollout.
enum RDGlobalLocalizationBuildGate {
    static let compilationCondition = "RD_GLOBAL_LOCALIZATION_WAVE1"

    static var isCompiledIn: Bool {
        #if RD_GLOBAL_LOCALIZATION_WAVE1
        true
        #else
        false
        #endif
    }

    static var isEnabled: Bool {
        if isCompiledIn {
            return true
        }

        #if DEBUG
        return CommandLine.arguments.contains(
            "RD_UI_TEST_GLOBAL_LOCALIZATION_ENABLED"
        ) || ProcessInfo.processInfo.environment[
            "RD_UI_TEST_GLOBAL_LOCALIZATION_ENABLED"
        ] == "1"
        #else
        return false
        #endif
    }
}
