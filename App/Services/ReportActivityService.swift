import Foundation
import OSLog

enum ReportActivitySource: String, Sendable {
    case resultHub = "result_hub"
    case resultDetail = "result_detail"
    case reportsArchive = "reports_archive"
    case home
    case unknown
}

/// Best-effort client telemetry for report file delivery. Report creation is
/// captured authoritatively by the database trigger on `public.reports`.
final class ReportActivityService {
    static let shared = ReportActivityService()

    private static let logger = Logger(
        subsystem: "com.riskdetected.app",
        category: "ReportActivityService"
    )
    private let supabase: SupabaseService

    init(supabase: SupabaseService = .shared) {
        self.supabase = supabase
    }

    func recordDownload(
        reportID: UUID,
        succeeded: Bool,
        source: ReportActivitySource,
        requestID: String,
        supportID: String,
        failureStage: String? = nil
    ) async {
        guard supabase.currentUserID != nil else { return }

        struct Payload: Encodable {
            let p_client_event_id: String
            let p_event_name: String
            let p_report_id: String
            let p_source_surface: String
            let p_client_platform: String
            let p_client_app_version: String
            let p_client_app_build: String
            let p_request_id: String
            let p_support_id: String
            let p_metadata: [String: String]
        }

        let eventID = UUID().uuidString.lowercased()
        let payload = Payload(
            p_client_event_id: eventID,
            p_event_name: succeeded ? "report_downloaded" : "report_download_failed",
            p_report_id: reportID.uuidString.lowercased(),
            p_source_surface: source.rawValue,
            p_client_platform: AppClientMetadata.platform,
            p_client_app_version: AppClientMetadata.appVersion,
            p_client_app_build: AppClientMetadata.appBuild,
            p_request_id: requestID,
            p_support_id: supportID,
            p_metadata: failureStage.map { ["failure_stage": $0] } ?? [:]
        )

        for attempt in 1...2 {
            do {
                try await supabase.client
                    .rpc("record_report_activity_event_v1", params: payload)
                    .execute()
                return
            } catch {
                Self.logger.error(
                    "Report activity write failed report=\(reportID.uuidString, privacy: .public) event=\(payload.p_event_name, privacy: .public) attempt=\(attempt, privacy: .public) error=\(error.localizedDescription, privacy: .public)"
                )
                if attempt < 2 {
                    try? await Task.sleep(nanoseconds: 350_000_000)
                }
            }
        }
    }
}
