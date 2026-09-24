import Foundation
import Supabase

@MainActor final class NovaEducationService {
    private let expertTicket = NovaExpertTransport.shared.capture()
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
    private func key(_ suffix: String) -> String { (expertTicket?.access.storageNamespace ?? identity.userID.uuidString) + ":" + suffix }
    func check() throws {
        try Task.checkCancellation()
        guard novaCurrentSessionIdentity() == identity else { throw NovaPersonnelFailure.denied }
    }
    private func rpc<T: Decodable, P: Encodable>(_ name: String, _ params: P) async throws -> T {
        try check()
        let data = try await NovaExpertTransport.shared.execute(name, params: params, ticket: self.expertTicket)
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
        if draft.id == nil { stampNewDraft(draft) }
    }
    /// The home page offers to finish an unsaved new training. It needs the
    /// draft's own id and last edit; they are kept next to the draft, whose
    /// stored format does not change.
    struct DraftStamp: Codable, Equatable { let ref: UUID; var updatedAt: Date; var companyID: UUID? }
    private func stampNewDraft(_ draft: NovaEducationDraft) {
        let previous = (try? storage.read(account: key("draft-stamp:new"))).flatMap { $0 }.flatMap { try? JSONDecoder().decode(DraftStamp.self, from: $0) }
        let stamp = DraftStamp(ref: previous?.ref ?? UUID(), updatedAt: Date(), companyID: Self.company(of: draft))
        try? storage.write(JSONEncoder().encode(stamp), account: key("draft-stamp:new"))
    }
    /// The unsaved new-training draft, when it holds something the expert
    /// entered: a title, a trainer or a company. An untouched editor is not
    /// unfinished work.
    func newDraftStamp() throws -> DraftStamp? {
        guard let draft = try draft(id: nil), Self.hasContent(draft) else { return nil }
        if let data = try storage.read(account: key("draft-stamp:new")),
           var stamp = try? JSONDecoder().decode(DraftStamp.self, from: data) {
            stamp.companyID = Self.company(of: draft)
            return stamp
        }
        // Saved before stamps existed: it gets an id now and counts as edited now.
        let stamp = DraftStamp(ref: UUID(), updatedAt: Date(), companyID: Self.company(of: draft))
        try? storage.write(JSONEncoder().encode(stamp), account: key("draft-stamp:new"))
        return stamp
    }
    static func hasContent(_ draft: NovaEducationDraft) -> Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !draft.trainers.isEmpty || !draft.scopes.isEmpty
    }
    private static func company(of draft: NovaEducationDraft) -> UUID? {
        let companies = Set(draft.scopes.map(\.company_id))
        return companies.count == 1 ? companies.first : nil
    }
    /// Drops the autosaved draft for this record (or for a new one, when `id`
    /// is nil) so the next open starts genuinely fresh instead of restoring
    /// whatever was last typed — the escape hatch for a draft that was
    /// preserved before a change to what counts as a "fresh" record.
    func discardDraft(id: UUID?) throws {
        try check(); try storage.remove(account: key("draft:" + (id?.uuidString ?? "new")))
        if id == nil { try? storage.remove(account: key("draft-stamp:new")) }
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
            if draft.action != "curriculum", draft.id == nil { try? storage.remove(account: key("draft-stamp:new")) }
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
         "COMMON_GROUPS_TOO_SHORT":"İlk eğitimin G1–G3 referans süresi eksik.","GROUP4_CONTEXT_MISSING":"Eğitimi yeniden kaydedin; işyerine özgü konu kapsamı otomatik aktarılır.",
         "LESSON_TOPIC_MISMATCH":"Ders dağılımı konu dakikalarıyla eşleşmiyor. Saatleri yeniden dağıtın.",
         "LESSON_BREAK_INVALID":"Temel eğitim dersleri en az 45 dakika ve araları en az 15 dakika olmalı.",
         "EMPLOYER_MISSING":"İşveren / vekili adını doldurun.","EMPLOYER_CAPACITY_MISSING":"İşveren / vekili sıfatını seçin.",
         "JOB_TITLE_MISSING":"Personelin belgeye yazılacak unvanı eksik.","PROVIDER_MISSING":"Düzenleyici kişi / kurum eksik.",
         "TRAINER_TITLE_MISSING":"Eğitici unvanı eksik."][code] ?? code
    }
    static func message(_ error: Error) -> String {
        if let e = error as? PostgrestError {
            switch e.message {
            case "FEATURE_UNAVAILABLE": return RDLocalization.string("localizable.nova.education.service.yeni.egitim.modulu.bu.hesap.icin.henuz.acilmadi.00350591", table: .localizable, fallback: "Yeni eğitim modülü bu hesap için henüz açılmadı.")
            case "VERSION_CONFLICT": return RDLocalization.string("localizable.nova.education.service.kayit.baska.bir.cihazda.degisti.kapatip.guncel.k.58098051", table: .localizable, fallback: "Kayıt başka bir cihazda değişti. Kapatıp güncel kaydı açın; form taslağınız korunur.")
            case "TRAINING_DATE_INVALID", "LESSON_OVERLAP_OR_FUTURE": return RDLocalization.string("localizable.nova.education.service.ders.saatleri.cakismamali.ve.egitimin.tamami.gec.d52bf5b0", table: .localizable, fallback: "Ders saatleri çakışmamalı ve eğitimin tamamı geçmişte olmalı.")
            case "TRAINING_HAZARD_MISMATCH": return RDLocalization.string("localizable.nova.education.service.farkli.tehlike.sinifindaki.firmalar.ayni.egitim..88be15a2", table: .localizable, fallback: "Farklı tehlike sınıfındaki firmalar aynı eğitim dosyasında yer alamaz. Ayrı kayıt oluşturun.")
            case "PARTICIPANT_DUPLICATE": return RDLocalization.string("localizable.nova.education.service.bir.personeli.yalniz.bir.egitim.kapsamina.ekleyi.d3ae9417", table: .localizable, fallback: "Bir personeli yalnız bir eğitim kapsamına ekleyin.")
            case "WORKPLACE_REQUIRED": return RDLocalization.string("localizable.nova.education.service.firmaya.ait.isyeri.secin.39f044db", table: .localizable, fallback: "Firmaya ait işyeri seçin.")
            case "TRAINER_INVALID": return RDLocalization.string("localizable.nova.education.service.en.az.bir.egitici.adi.girin.ve.konu.dagilimlarin.a0656fdb", table: .localizable, fallback: "En az bir eğitici adı girin ve konu dağılımlarını kontrol edin.")
            default: break
            }
        }
        return NovaTrainingSessionService.message(error)
    }

    static func correction(_ error: Error) -> (NovaEducationStep, String)? {
        guard let value = error as? PostgrestError else { return nil }
        switch value.message {
        case "TRAINER_INVALID": return (.trainers, "Eğitici adlarını ve konu dağılımını kontrol edin. Boş ek satır kaydedilmez.")
        case "TOPIC_INVALID", "TOPIC_HIERARCHY_INVALID": return (.topics, "Konu başlıklarını ve dakikalarını kontrol edin.")
        case "LESSON_INVALID", "LESSON_ALLOCATION_INVALID", "LESSON_OVERLAP_OR_FUTURE":
            return (.schedule, "Eğitim günlerini, ders sürelerini ve bitiş saatlerini kontrol edin.")
        case "SCOPE_INVALID", "TRAINING_HAZARD_MISMATCH", "WORKPLACE_REQUIRED":
            return (.companies, "Firma ve işyeri seçimlerini kontrol edin.")
        case "PARTICIPANT_DUPLICATE": return (.participants, "Aynı personeli birden fazla kez seçmeyin.")
        default: return nil
        }
    }
}
