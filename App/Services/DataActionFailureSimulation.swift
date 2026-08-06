import Foundation

enum DataActionFailureSimulation {
    enum Mode: String {
        case photoDownload = "photo_download"
        case analysisDeleteStorage = "analysis_delete_storage"
        case analysisDeleteMetadata = "analysis_delete_metadata"
        case dataExport = "data_export"
        case bulkReportDelete = "bulk_report_delete"
        case bulkAnalysisDelete = "bulk_analysis_delete"
        case accountDeletionRequest = "account_deletion_request"
        case quotaExceeded = "quota_exceeded"
    }

    static func isEnabled(_ mode: Mode) -> Bool {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard env["RISKDETECTED_ENABLE_DATA_TEST_SIMULATION"] == "true" else {
            return false
        }
        return env["SIMULATE_DATA_ERROR"] == mode.rawValue
        #else
        return false
        #endif
    }

    static func simulatedError(_ mode: Mode) -> NSError {
        NSError(
            domain: "RiskDetected.DataActionFailureSimulation",
            code: -1,
            userInfo: [
                NSLocalizedDescriptionKey: RDLocalization.format("localizable.data.action.failure.simulation.simulated.data.failure.1.ef8df3ff", table: .localizable, fallback: "Simüle edilmiş veri hatası: %1$@", arguments: [String(describing: mode.rawValue)])
            ]
        )
    }
}
