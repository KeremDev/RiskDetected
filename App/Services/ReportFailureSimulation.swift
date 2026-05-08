import Foundation

enum ReportFailureSimulation {
    enum Mode: String {
        case pdfRender = "pdf_render"
        case storageUpload = "storage_upload"
        case metadataInsert = "metadata_insert"
        case download = "download"
        case deleteStorage = "delete_storage"
        case deleteMetadata = "delete_metadata"
    }

    static func isEnabled(_ mode: Mode) -> Bool {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard env["RISKDETECTED_ENABLE_REPORT_TEST_SIMULATION"] == "true" else {
            return false
        }
        return env["SIMULATE_REPORT_ERROR"] == mode.rawValue
        #else
        return false
        #endif
    }

    static func simulatedError(_ mode: Mode) -> NSError {
        NSError(
            domain: "RiskDetected.ReportFailureSimulation",
            code: -1,
            userInfo: [
                NSLocalizedDescriptionKey: "Simulated report failure: \(mode.rawValue)"
            ]
        )
    }
}
