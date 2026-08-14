import SnapshottingTests

/// Discovers and renders every SwiftUI preview linked from the RiskDetected
/// application target. The shared scheme exports deterministic PNG/JSON pairs
/// when `TEST_RUNNER_SNAPSHOTS_EXPORT_DIR` is provided by the caller.
final class RiskDetectedSnapshotTests: SnapshotTest {
    override class func snapshotPreviewModules() -> [String]? {
        ["RiskDetected"]
    }
}
