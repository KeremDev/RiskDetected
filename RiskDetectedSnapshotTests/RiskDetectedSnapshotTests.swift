import SnapshottingTests

final class RiskDetectedSnapshotTests: SnapshotTest {
    override class func snapshotPreviewModules() -> [String]? {
        ["RiskDetected"]
    }

    override class func snapshotPreviews() -> [String]? {
        [
            "InAppPaywallView",
            "AnalyzingView"
        ]
    }
}
