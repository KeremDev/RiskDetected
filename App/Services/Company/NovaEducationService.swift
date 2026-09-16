import Foundation
import Supabase

@MainActor final class NovaEducationService {
    struct Receipt: Decodable { let schema_version: Int; let owner_id: UUID; let mutation_id: UUID; let row: NovaTrainingSession?; let curriculum_saved: Bool? }
    struct CertificateRequest: Codable, Equatable {
        var action = "preview"; var session_id: UUID?; var scope_id: UUID?; var person_id: UUID?
        var expected_version: Int64?; var issued_on: String?; var mutation_id: UUID?
        var document_id: UUID?; var revision: Int?; var logo_png_base64: String?
    }
    private struct Pending: Codable { let mutation: UUID; let draft: NovaEducationDraft }
    let identity: NovaSessionIdentity
    private let storage = KeychainPersonnelPendingStorage(service: "com.riskdetected.education.v3", maximumBytes: 2_200_000)
    private static var busy = Set<UUID>()
    init(identity: NovaSessionIdentity) { self.identity = identity }
    private func key(_ suffix: String) -> String { identity.userID.uuidString + ":" + suffix }
    func check() throws {
        try Task.checkCancellation()
        guard novaCurrentSessionIdentity() == identity else { throw NovaPersonnelFailure.denied }
    }
    private func rpc<T: Decodable, P: Encodable>(_ name: String, _ params: P) async throws -> T {
        try check()
        let data = try await SupabaseService.shared.client.rpc(name, params: params).execute().data
        try check()
        guard data.count <= 16_777_216 else { throw NovaPersonnelFailure.unavailable }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func context(id: UUID? = nil) async throws -> NovaEducationContext {
        let result: NovaEducationContext = try await rpc("isg_pilot_training_detail_v3", ["p_id": PersonnelRPCValue.id(id)])
        guard result.schema_version == 3, result.owner_id == identity.userID,
              result.row == nil || result.row?.owner_id == identity.userID else { throw NovaPersonnelFailure.denied }
        return result
    }
    func draft(id: UUID?) throws -> NovaEducationDraft? {
        try check()
        guard let data = try storage.read(account: key("draft:" + (id?.uuidString ?? "new"))) else { return nil }
        return try JSONDecoder().decode(NovaEducationDraft.self, from: data)
    }
    func preserve(_ draft: NovaEducationDraft) throws {
        try check(); try storage.write(JSONEncoder().encode(draft), account: key("draft:" + (draft.id?.uuidString ?? "new")))
    }
    /// Drops the autosaved draft for this record (or for a new one, when `id`
    /// is nil) so the next open starts genuinely fresh instead of restoring
    /// whatever was last typed — the escape hatch for a draft that was
    /// preserved before a change to what counts as a "fresh" record.
    func discardDraft(id: UUID?) throws {
        try check(); try storage.remove(account: key("draft:" + (id?.uuidString ?? "new")))
    }
    func pending() throws -> NovaEducationDraft? {
        try check()
        return try storage.read(account: key("pending")).map { try JSONDecoder().decode(Pending.self, from: $0).draft }
    }
    func save(_ draft: NovaEducationDraft) async throws -> Receipt {
        try check()
        guard Self.busy.insert(identity.userID).inserted else { throw NovaPersonnelFailure.unavailable }
        defer { Self.busy.remove(identity.userID) }
        let pending: Pending
        if let data = try storage.read(account: key("pending")) {
            pending = try JSONDecoder().decode(Pending.self, from: data)
            guard pending.draft == draft else { throw NovaPersonnelFailure.conflict }
        } else {
            pending = .init(mutation: UUID(), draft: draft)
            try storage.write(JSONEncoder().encode(pending), account: key("pending"))
        }
        struct Args: Encodable { let p_mutation: UUID; let p_payload: NovaEducationDraft }
        do {
            let result: Receipt = try await rpc("isg_pilot_training_record_v3", Args(p_mutation: pending.mutation, p_payload: pending.draft))
            guard result.schema_version == 3, result.owner_id == identity.userID, result.mutation_id == pending.mutation,
                  result.row == nil || result.row?.owner_id == identity.userID else { throw NovaPersonnelFailure.denied }
            try storage.remove(account: key("pending"))
            if draft.action != "curriculum" { try storage.remove(account: key("draft:" + (draft.id?.uuidString ?? "new"))) }
            NotificationCenter.default.post(name: Notification.Name("isgada.records.changed"), object: identity.userID)
            NotificationCenter.default.post(name: Notification.Name("isgada.mutation.succeeded"), object: identity.userID,
                userInfo: ["message": draft.action == "delete" ? "Eğitim başarıyla kaldırıldı!" : draft.action == "curriculum"
                    ? NovaSuccessMessage.recordSaved("Firma müfredatı") : NovaSuccessMessage.trainingSaved])
            return result
        } catch let error as PostgrestError {
            if ["P0001","28000","22007","22008","22P02","23514","23502"].contains(error.code ?? "") { try storage.remove(account: key("pending")) }
            throw error
        }
    }
    func certificate(_ request: CertificateRequest) async throws -> NovaEducationCertificate {
        try check()
        var request = request
        let account = key("certificate:" + (request.session_id?.uuidString ?? "") + ":" + (request.scope_id?.uuidString ?? "") + ":" + (request.person_id?.uuidString ?? ""))
        if request.action == "issue" {
            if let data = try storage.read(account: account) {
                let old = try JSONDecoder().decode(CertificateRequest.self, from: data)
                guard old.expected_version == request.expected_version else { throw NovaPersonnelFailure.conflict }
                request = old
            } else { request.mutation_id = UUID(); try storage.write(JSONEncoder().encode(request), account: account) }
        }
        struct Args: Encodable { let p_payload: CertificateRequest }
        do {
            let result: NovaEducationCertificate = try await rpc("isg_pilot_training_certificate_v1", Args(p_payload: request))
            guard result.schema_version == 1, result.owner_id == identity.userID,
                  result.snapshot.completion_basis == "expert_record", result.snapshot.schema_version == 1, result.snapshot.template_version == 1, result.snapshot.theme_version == 1,
                  request.person_id == nil || result.snapshot.person.id == request.person_id else { throw NovaPersonnelFailure.denied }
            if request.action == "issue" { try storage.remove(account: account) }
            return result
        } catch let error as PostgrestError {
            if request.action == "issue", ["P0001","28000","22P02"].contains(error.code ?? "") { try storage.remove(account: account) }
            throw error
        }
    }
    static func issue(_ code: String) -> String {
        ["TOPIC_MINUTES_MISSING":"Süresi eksik konu var.","TRAINER_SCOPE_MISSING":"Konuların eğiticilerini seçin.",
         "FACE_TO_FACE_REQUIRED":"Bu kapsamın işyerine özgü bölümünü yüz yüze düzenleyin.","REQUIRED_TOPIC_MISSING":"Zorunlu konu eksik.",
         "TOTAL_TOO_SHORT":"Öğretim süresi profilin altında.","GROUP4_TOO_SHORT":"İşyerine özgü öğretim süresi eksik.",
         "COMMON_GROUPS_TOO_SHORT":"İlk eğitimin G1–G3 referans süresi eksik.","GROUP4_CONTEXT_MISSING":"İşyeri ve görev bağlamını açıklayın.",
         "LESSON_TOPIC_MISMATCH":"Ders dağılımı konu dakikalarıyla eşleşmiyor. Saatleri yeniden dağıtın.",
         "LESSON_BREAK_INVALID":"Temel eğitim dersleri en az 45 dakika ve araları en az 15 dakika olmalı.",
         "EMPLOYER_MISSING":"İşveren / vekili adını doldurun.","EMPLOYER_CAPACITY_MISSING":"İşveren / vekili sıfatını seçin.",
         "JOB_TITLE_MISSING":"Personelin belgeye yazılacak unvanı eksik.","PROVIDER_MISSING":"Düzenleyici kişi / kurum eksik.",
         "TRAINER_TITLE_MISSING":"Eğitici unvanı eksik."][code] ?? code
    }
    static func message(_ error: Error) -> String {
        if let e = error as? PostgrestError {
            switch e.message {
            case "FEATURE_UNAVAILABLE": return "Yeni eğitim modülü bu hesap için henüz açılmadı."
            case "VERSION_CONFLICT": return "Kayıt başka bir cihazda değişti. Kapatıp güncel kaydı açın; form taslağınız korunur."
            case "TRAINING_DATE_INVALID", "LESSON_OVERLAP_OR_FUTURE": return "Ders saatleri çakışmamalı ve eğitimin tamamı geçmişte olmalı."
            case "PARTICIPANT_DUPLICATE": return "Bir personeli yalnız bir eğitim kapsamına ekleyin."
            case "WORKPLACE_REQUIRED": return "Firmaya ait işyeri seçin."
            case "TRAINER_INVALID": return "En az bir eğitici adı girin ve konu dağılımlarını kontrol edin."
            default: break
            }
        }
        return NovaTrainingSessionService.message(error)
    }
}
