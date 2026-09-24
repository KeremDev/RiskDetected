import Foundation
import Supabase

struct NovaTrainingCatalog: Codable, Identifiable {
    struct Rule: Codable { let minutes: Int; let months: Int }
    let id: UUID
    let owner_id: UUID?
    let code: String
    let title: String
    let rules: [String: Rule]
    let source_url: String?
    let content_approved: Bool
}

struct NovaTrainingSession: Codable, Identifiable {
    struct Company: Codable, Identifiable {
        let id: UUID
        let company_id: UUID
        let owner_id: UUID
        let company_name: String
        let hazard_class: String
        let duration_minutes: Int
        let valid_until: String?
        let state: String
        let participants: [NovaTrainingParticipant]
    }
    let id: UUID
    let owner_id: UUID
    let catalog_id: UUID?
    let catalog_snapshot: NovaTrainingCatalog?
    let title: String
    let trainer: String
    let method: String
    let held_on: String
    let location: String
    let notes: String
    let version: Int64
    let deleted_at: String?
    let companies: [Company]
    var education: NovaEducationRecord? = nil
    /// Who recorded the session; an organization's "mine" filter reads it.
    var created_by_user_id: UUID? = nil
    var isLegacyPlan: Bool { companies.contains { $0.state == "planned" } }
    var count: Int { companies.reduce(0) { $0 + $1.participants.count } }
}

struct NovaTrainingSessionDraft: Codable, Equatable {
    struct Company: Codable, Equatable { let id: UUID; let participants: [UUID] }
    var action = "save"
    var id: UUID?
    var expected_version: Int64 = 0
    var catalog_id: UUID?
    var trainer = ""
    var method = "face_to_face"
    var held_on = ""
    var location = ""
    var notes = ""
    var confirmed = true
    var companies: [Company] = []
    // Reusable, owner-private custom catalogue creation.
    var company_id: UUID?
    var title: String?
    var minutes: Int?
    var months: Int?
}

@MainActor final class NovaTrainingSessionService {
    private let expertTicket = NovaExpertTransport.shared.capture()
    struct Page: Decodable {
        let schema_version: Int; let owner_id: UUID
        let rows: [NovaTrainingSession]; let next_id: UUID?; let catalog: [NovaTrainingCatalog]
        let writable_companies: [UUID]
    }
    struct Receipt: Decodable {
        let schema_version: Int; let owner_id: UUID; let mutation_id: UUID
        let row: NovaTrainingSession?; let catalog: NovaTrainingCatalog?
    }
    struct Pending: Codable { let mutation: UUID; let owner: UUID; let draft: NovaTrainingSessionDraft }
    let identity: NovaSessionIdentity
    init(identity: NovaSessionIdentity) { self.identity = identity }
    private let storage = KeychainPersonnelPendingStorage(service: "com.riskdetected.pilot.training.pending.v2")
    private static var inFlight = Set<UUID>()
    private var key: String { expertTicket?.access.storageNamespace ?? identity.userID.uuidString }
    private func check() throws {
        try Task.checkCancellation()
        guard novaCurrentSessionIdentity() == identity else { throw NovaPersonnelFailure.denied }
    }
    func employees(company: UUID) async throws -> [NovaEmployeeRow] {
        try check()
        let scope = NovaPersonnelScope(ownerID: identity.userID, sessionID: identity.sessionID, companyID: company, epoch: "training-\(identity.sessionID)")
        let client = NovaPersonnelService(rpc: { name, params in
            try await NovaExpertTransport.shared.execute(name, params: params, ticket: self.expertTicket)
        }, isCurrent: { candidate in
            candidate == scope && novaCurrentSessionIdentity() == self.identity
        }, storage: KeychainPersonnelPendingStorage()).client
        var people: [NovaEmployeeRow] = []; var after: UUID?; var seen = Set<UUID>()
        repeat {
            let page = try await client.employees(scope, "", false, after)
            people += page.rows; after = page.next
            if let after, !seen.insert(after).inserted { throw NovaPersonnelFailure.unavailable }
        } while after != nil
        try check()
        return people
    }
    func pending() throws -> Pending? {
        try check()
        guard let data = try storage.read(account: key) else { return nil }
        let pending = try JSONDecoder().decode(Pending.self, from: data)
        guard pending.owner == identity.userID else { throw NovaPersonnelFailure.denied }
        return pending
    }
    func list(company: UUID? = nil, after: UUID? = nil) async throws -> Page {
        try check()
        let data = try await NovaExpertTransport.shared.execute("isg_pilot_training_sessions_v2", params:
            ["p_company": PersonnelRPCValue.id(company), "p_after": .id(after)], ticket: self.expertTicket)
        try check()
        guard data.count <= 16_777_216 else { throw NovaPersonnelFailure.unavailable }
        let page = try JSONDecoder().decode(Page.self, from: data)
        guard page.schema_version == 2, page.owner_id == identity.userID, page.rows.count <= 30,
              page.rows.allSatisfy({ $0.owner_id == identity.userID && !$0.companies.isEmpty &&
                  $0.companies.allSatisfy { $0.owner_id == identity.userID } }),
              page.catalog.allSatisfy({ $0.owner_id == nil || $0.owner_id == identity.userID })
        else { throw NovaPersonnelFailure.denied }
        return page
    }
    func save(_ draft: NovaTrainingSessionDraft) async throws -> Receipt {
        try check()
        if let pending = try pending() {
            guard pending.draft == draft else { throw NovaPersonnelFailure.conflict }
            return try await send(pending)
        }
        let pending = Pending(mutation: UUID(), owner: identity.userID, draft: draft)
        try storage.write(JSONEncoder().encode(pending), account: key)
        return try await send(pending)
    }
    func retry() async throws -> Receipt {
        guard let pending = try pending() else { throw NovaPersonnelFailure.unavailable }
        return try await send(pending)
    }
    private func send(_ pending: Pending) async throws -> Receipt {
        try check()
        guard Self.inFlight.insert(identity.userID).inserted else { throw NovaPersonnelFailure.unavailable }
        defer { Self.inFlight.remove(identity.userID) }
        struct Args: Encodable { let p_mutation: UUID; let p_payload: NovaTrainingSessionDraft }
        do {
            let data = try await NovaExpertTransport.shared.execute("isg_pilot_training_record_v2", params:
                Args(p_mutation: pending.mutation, p_payload: pending.draft), ticket: self.expertTicket)
            try check()
            guard data.count <= 8_388_608 else { throw NovaPersonnelFailure.unavailable }
            let receipt = try JSONDecoder().decode(Receipt.self, from: data)
            guard receipt.schema_version == 2, receipt.owner_id == identity.userID, receipt.mutation_id == pending.mutation,
                  receipt.row == nil || receipt.row?.owner_id == identity.userID,
                  receipt.catalog == nil || receipt.catalog?.owner_id == identity.userID,
                  pending.draft.id == nil || receipt.row?.id == pending.draft.id else { throw NovaPersonnelFailure.denied }
            try storage.remove(account: key)
            NotificationCenter.default.post(name: Notification.Name("isgada.records.changed"), object: identity.userID)
            return receipt
        } catch let e as PostgrestError {
            if ["P0001", "28000", "22007", "22008", "22P02", "23514", "23502"].contains(e.code ?? "") { try storage.remove(account: key) }
            throw e
        }
    }
    static func message(_ error: Error) -> String {
        if let e = error as? PostgrestError {
            switch e.message {
            case "FACE_TO_FACE_REQUIRED": return RDLocalization.string("localizable.nova.training.session.service.ise.baslama.egitimi.yuz.yuze.verilmelidir.461e7dd4", table: .localizable, fallback: "İşe başlama eğitimi yüz yüze verilmelidir.")
            case "WORKPLACE_FACE_TO_FACE_REQUIRED": return RDLocalization.string("localizable.nova.training.session.service.tehlikeli.cok.tehlikeli.isyerlerinde.ise.ozgu.bo.6ae30522", table: .localizable, fallback: "Tehlikeli/çok tehlikeli işyerlerinde işe özgü bölüm yüz yüze olmalı. Karma veya yüz yüze yöntemi seçin.")
            case "PARTICIPANT_REQUIRED": return RDLocalization.string("localizable.nova.training.session.service.secilen.her.firmadan.en.az.bir.katilimci.secin.ed15d058", table: .localizable, fallback: "Seçilen her firmadan en az bir katılımcı seçin.")
            case "CATALOG_REQUIRED": return RDLocalization.string("localizable.nova.training.session.service.kayitli.bir.egitim.secin.veya.yeni.egitim.baslig.411d5c98", table: .localizable, fallback: "Kayıtlı bir eğitim seçin veya yeni eğitim başlığı oluşturun.")
            case "RULE_DATE_UNSUPPORTED": return RDLocalization.string("localizable.nova.training.session.service.hazir.katalog.2.nisan.2026.sonrasi.egitimler.ici.25653209", table: .localizable, fallback: "Hazır katalog 2 Nisan 2026 sonrası eğitimler içindir. Daha eski kayıt için tarihli kural incelemesi gerekir.")
            case "VALIDATION_ERROR": return RDLocalization.string("localizable.nova.training.session.service.gecmis.bugunku.egitim.tarihini.egitmeni.ve.katil.731f5520", table: .localizable, fallback: "Geçmiş/bugünkü eğitim tarihini, eğitmeni ve katılımcıları kontrol edin.")
            case "UPGRADE_REQUIRED": return RDLocalization.string("localizable.nova.training.session.service.yeni.egitim.akisi.icin.uygulamayi.guncelleyin.d45d0072", table: .localizable, fallback: "Yeni eğitim akışı için uygulamayı güncelleyin.")
            default: break
            }
        }
        return NovaTrainingService.message(error)
    }
}
