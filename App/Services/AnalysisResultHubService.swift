import Foundation
import Supabase

@MainActor
final class AnalysisResultHubService {
    static let shared = AnalysisResultHubService()
    private let functions = SupabaseService.shared.functions

    private struct BaseBody: Encodable {
        let action: String
        let analysis_id: String
        let language: String
        let client_capabilities: [String: Bool]
        let client_platform: String
        let client_app_version: String
        let client_app_build: String
    }

    func load(analysisID: UUID, language: RDLanguage) async throws -> AnalysisResultHubResponse {
        #if DEBUG
        if CommandLine.arguments.contains("RD_UI_TEST_RESULT_HUB") ||
            ProcessInfo.processInfo.environment["RD_UI_TEST_RESULT_HUB"] == "1" {
            return try uiTestFixture(analysisID: analysisID, language: language)
        }
        #endif
        return try await functions.invoke(
            "analysis-result-sections",
            options: FunctionInvokeOptions(body: BaseBody(
                action: "load",
                analysis_id: analysisID.uuidString,
                language: language.rawValue,
                client_capabilities: AppClientMetadata.capabilities,
                client_platform: AppClientMetadata.platform,
                client_app_version: AppClientMetadata.appVersion,
                client_app_build: AppClientMetadata.appBuild
            ))
        )
    }

    func setFeedback(
        analysisID: UUID,
        language: RDLanguage,
        section: AnalysisResultSectionID,
        item: AnalysisResultHubItem,
        reaction: AnalysisItemReaction,
        reason: String? = nil
    ) async throws {
        struct Body: Encodable {
            let action = "feedback"
            let analysis_id: String
            let language: String
            let client_capabilities: [String: Bool]
            let client_platform: String
            let client_app_version: String
            let client_app_build: String
            let target_kind: String
            let target_key: String
            let section: String
            let rating: Int
            let reason_code: String?
        }
        let isNotebook = section == .approvedNotebook
        let body = Body(
            analysis_id: analysisID.uuidString,
            language: language.rawValue,
            client_capabilities: AppClientMetadata.capabilities,
            client_platform: AppClientMetadata.platform,
            client_app_version: AppClientMetadata.appVersion,
            client_app_build: AppClientMetadata.appBuild,
            target_kind: isNotebook ? "notebook_entry" : "finding",
            target_key: item.id.uuidString,
            section: section.rawValue,
            rating: reaction == .like ? 1 : reaction == .dislike ? -1 : 0,
            reason_code: reason
        )
        let _: EmptyResponse = try await functions.invoke(
            "analysis-result-sections",
            options: FunctionInvokeOptions(body: body)
        )
    }

    func mutateNotebook(
        analysisID: UUID,
        language: RDLanguage,
        entryID: UUID,
        mutation: String,
        findingText: String? = nil,
        recommendationText: String? = nil
    ) async throws {
        struct Body: Encodable {
            let action = "mutate_notebook"
            let analysis_id: String
            let language: String
            let client_capabilities: [String: Bool]
            let client_platform: String
            let client_app_version: String
            let client_app_build: String
            let entry_id: String
            let mutation: String
            let finding_text: String?
            let recommendation_text: String?
        }
        let _: EmptyResponse = try await functions.invoke(
            "analysis-result-sections",
            options: FunctionInvokeOptions(body: Body(
                analysis_id: analysisID.uuidString,
                language: language.rawValue,
                client_capabilities: AppClientMetadata.capabilities,
                client_platform: AppClientMetadata.platform,
                client_app_version: AppClientMetadata.appVersion,
                client_app_build: AppClientMetadata.appBuild,
                entry_id: entryID.uuidString,
                mutation: mutation,
                finding_text: findingText,
                recommendation_text: recommendationText
            ))
        )
    }

    func createReportIntent(
        analysisID: UUID,
        language: RDLanguage,
        section: AnalysisResultSectionID,
        format: String,
        selectedIDs: [UUID],
        requestID: UUID
    ) async throws -> AnalysisReportIntent {
        struct Body: Encodable {
            let action = "create_report_intent"
            let analysis_id: String
            let language: String
            let client_capabilities: [String: Bool]
            let client_platform: String
            let client_app_version: String
            let client_app_build: String
            let section: String
            let format: String
            let selected_item_keys: [String]
            let request_id: String
        }
        struct Response: Decodable { let report_intent: AnalysisReportIntent }
        let response: Response = try await functions.invoke(
            "analysis-result-sections",
            options: FunctionInvokeOptions(body: Body(
                analysis_id: analysisID.uuidString,
                language: language.rawValue,
                client_capabilities: AppClientMetadata.capabilities,
                client_platform: AppClientMetadata.platform,
                client_app_version: AppClientMetadata.appVersion,
                client_app_build: AppClientMetadata.appBuild,
                section: section.rawValue,
                format: format,
                selected_item_keys: selectedIDs.map(\.uuidString),
                request_id: requestID.uuidString
            ))
        )
        return response.report_intent
    }

    func recordEvent(
        analysisID: UUID,
        language: RDLanguage,
        name: String,
        section: AnalysisResultSectionID?,
        itemID: UUID? = nil,
        funnelSessionID: UUID
    ) async {
        struct Body: Encodable {
            let action = "event"
            let analysis_id: String
            let language: String
            let client_capabilities: [String: Bool]
            let client_platform: String
            let client_app_version: String
            let client_app_build: String
            let client_event_id: String
            let funnel_session_id: String
            let event_name: String
            let section: String?
            let target_key: String?
        }
        let body = Body(
            analysis_id: analysisID.uuidString,
            language: language.rawValue,
            client_capabilities: AppClientMetadata.capabilities,
            client_platform: AppClientMetadata.platform,
            client_app_version: AppClientMetadata.appVersion,
            client_app_build: AppClientMetadata.appBuild,
            client_event_id: UUID().uuidString,
            funnel_session_id: funnelSessionID.uuidString,
            event_name: name,
            section: section?.rawValue,
            target_key: itemID?.uuidString
        )
        let _: EmptyResponse? = try? await functions.invoke(
            "analysis-result-sections",
            options: FunctionInvokeOptions(body: body)
        )
    }

    private struct EmptyResponse: Decodable {}

    #if DEBUG
    private func uiTestFixture(analysisID: UUID, language: RDLanguage) throws -> AnalysisResultHubResponse {
        let isFree = CommandLine.arguments.contains("RD_UI_TEST_FREE_TIER") ||
            ProcessInfo.processInfo.environment["RD_UI_TEST_FREE_TIER"] == "1"
        let premiumAccess = isFree ? "teaser" : "full"
        let premiumCanEdit = isFree ? "false" : "true"
        let json = """
        {
          "enabled": true,
          "contract_version": "analysis-result-sections-v1",
          "ui_version": "analysis-result-hub-v1",
          "analysis_id": "\(analysisID.uuidString)",
          "analysis_edit_version": 0,
          "tier": "\(isFree ? "free" : "plus")",
          "language": "\(language.rawValue)",
          "disclaimers": {
            "expert": "Bu içerik bağlayıcı uzman görüşü değildir; saha teyidi ve uzman değerlendirmesi gerekir.",
            "notebook": "Onaylı Defter önerisi/taslağıdır; uzman değerlendirmesi ve resmî deftere aktarım gerekir."
          },
          "sections": [
            {
              "id": "risk_analysis", "access": "full", "count": 3, "can_edit": true, "can_report": true,
              "items": [
                {"id":"10000000-0000-4000-8000-000000000001","analysis_id":"\(analysisID.uuidString)","ordinal":1,"title":"Açık Kenarda Düşme Tehlikesi","category":"Yüksekte Çalışma","description":"Çalışma platformunun erişilebilir açık kenarında düşmeyi önleyen yeterli korkuluk sistemi görülmemektedir.","recommended_action":"Üst ve ara korkuluk ile topuk levhasından oluşan uygun kenar koruması kurulmalıdır.","root_cause_text":"Kenar koruma sisteminin çalışma başlamadan önce tamamlanmaması.","needs_field_verification":true,"fk_probability":6,"fk_frequency":6,"fk_severity":40,"fk_score":1440,"fk_band":"critical","m5_probability":5,"m5_severity":5,"m5_score":25,"m5_band":"critical","source_photo_indices":[1,2],"item_class":"observed_finding","is_scored":true,"display_order":0},
                {"id":"10000000-0000-4000-8000-000000000002","analysis_id":"\(analysisID.uuidString)","ordinal":2,"title":"Geçiş Yolunda Malzeme Birikimi","category":"Düzen ve Temizlik","description":"Yaya geçiş güzergâhında takılmaya neden olabilecek dağınık malzeme bulunmaktadır.","recommended_action":"Geçiş yolu temizlenmeli ve malzeme için belirlenmiş depolama alanı kullanılmalıdır.","fk_probability":3,"fk_frequency":6,"fk_severity":7,"fk_score":126,"fk_band":"medium","m5_probability":3,"m5_severity":3,"m5_score":9,"m5_band":"medium","source_photo_indices":[2],"item_class":"observed_finding","is_scored":true,"display_order":1},
                {"id":"10000000-0000-4000-8000-000000000003","analysis_id":"\(analysisID.uuidString)","ordinal":3,"title":"Düşen Cisim Maruziyeti","category":"Yüksekte Çalışma","description":"Alt çalışma bölgesine malzeme düşmesini engelleyecek fiziksel ayırma görünür değildir.","recommended_action":"Düşen cisim bölgesi fiziksel olarak ayrılmalı ve malzemeler sabitlenmelidir.","fk_probability":3,"fk_frequency":3,"fk_severity":40,"fk_score":360,"fk_band":"high","m5_probability":4,"m5_severity":5,"m5_score":20,"m5_band":"critical","source_photo_indices":[3],"item_class":"observed_finding","is_scored":true,"display_order":2}
              ]
            },
            {
              "id": "expert_recommendations", "access": "\(premiumAccess)", "count": 2, "can_edit": \(premiumCanEdit), "can_report": \(!isFree),
              "items": [
                {"id":"20000000-0000-4000-8000-000000000001","analysis_id":"\(analysisID.uuidString)","title":"İskele Kurulum Güvencesinin Doğrulanması","description":"İskelenin kurulum, ankraj ve taşıma uygunluğu yetkili saha kontrolüyle doğrulanmalıdır.","recommended_action":"Kurulum planı ve saha koşulları birlikte kontrol edilmelidir.","needs_field_verification":true,"source_photo_indices":[1],"item_class":"assurance_requirement","is_scored":false,"display_order":0},
                {"id":"20000000-0000-4000-8000-000000000002","analysis_id":"\(analysisID.uuidString)","title":"Platform Sürekliliğinin Saha Teyidi","description":"Görüntüde kısmen örtülü kalan platform birleşimlerinin kesintisiz geçiş sağladığı sahada doğrulanmalıdır.","recommended_action":"Boşluk veya seviye farkı belirlenirse uygun platform elemanlarıyla giderilmelidir.","needs_field_verification":true,"source_photo_indices":[2],"item_class":"verification_request","is_scored":false,"display_order":1}
              ]
            },
            {
              "id": "approved_notebook", "access": "\(premiumAccess)", "count": 2, "can_edit": \(premiumCanEdit), "can_report": \(!isFree),
              "items": [
                {"id":"30000000-0000-4000-8000-000000000001","finding_text":"Çalışma platformunun erişilebilir açık kenarında yeterli kenar koruması bulunmamaktadır.","recommendation_text":"Uygun üst ve ara korkuluk ile topuk levhası kurulmalı; çalışma güvenli sistem tamamlanıncaya kadar durdurulmalıdır.","reference_text":null,"source_finding_ids":["10000000-0000-4000-8000-000000000001"],"display_order":0,"source_photo_indices":[1]},
                {"id":"30000000-0000-4000-8000-000000000002","finding_text":"İskele kurulum ve ankraj uygunluğu saha veya kayıt teyidi gerektirmektedir.","recommendation_text":"Kurulum güvencesi yetkili saha kontrolü ve ilgili kayıtlarla doğrulanmalıdır.","reference_text":null,"source_finding_ids":["20000000-0000-4000-8000-000000000001"],"display_order":1,"source_photo_indices":[1]}
              ]
            }
          ]
        }
        """
        return try JSONDecoder().decode(AnalysisResultHubResponse.self, from: Data(json.utf8))
    }
    #endif
}
