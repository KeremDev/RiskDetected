import Foundation
import Supabase

struct NovaTrainingParticipant: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var attended: Bool
}

struct NovaTrainingRecord: Codable, Identifiable {
    let id: UUID
    let company_id: UUID
    let owner_id: UUID
    let title: String
    let trainer: String
    let location: String
    let notes: String
    let starts_at: String
    let duration_minutes: Int
    let valid_until: String?
    let state: String
    let version: Int64
    let participants: [NovaTrainingParticipant]
    var start: Date { NovaTrainingDraft.date(starts_at) ?? .distantPast }
    var attendedCount: Int { participants.filter(\.attended).count }
}

struct NovaTrainingDraft: Codable, Equatable {
    struct Person: Codable, Equatable { let id: UUID; let attended: Bool }
    var action = "save"
    var id: UUID?
    var expected_version: Int64 = 0
    var title = ""
    var trainer = ""
    var location = ""
    var notes = ""
    var starts_at = ISO8601DateFormatter().string(from: Date())
    var duration_minutes = 60
    var valid_until: String?
    var participants: [Person] = []

    init() {}
    init(_ record: NovaTrainingRecord) {
        id = record.id; expected_version = record.version; title = record.title; trainer = record.trainer
        location = record.location; notes = record.notes; starts_at = record.starts_at
        duration_minutes = record.duration_minutes; valid_until = record.valid_until
        participants = record.participants.map { Person(id: $0.id, attended: $0.attended) }
    }
    static func date(_ value: String) -> Date? {
        let f = ISO8601DateFormatter()
        if let date = f.date(from: value) { return date }
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.date(from: value)
    }
    var isValid: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && title.count <= 200 &&
        !trainer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && trainer.count <= 200 &&
        (1...1440).contains(duration_minutes) && location.count <= 300 && notes.count <= 2000 &&
        participants.count <= 500 && Set(participants.map(\.id)).count == participants.count
    }
}

@MainActor final class NovaTrainingService {
    struct Page: Decodable {
        let schema_version: Int; let owner_id: UUID; let company_id: UUID
        let rows: [NovaTrainingRecord]; let next_id: UUID?; let total: Int?; let completed: Int?
    }
    struct Pending: Codable {
        let owner: UUID; let company: UUID; let mutation: UUID; let payload: NovaTrainingDraft
    }
    private let identity: NovaSessionIdentity
    private let storage = KeychainPersonnelPendingStorage(service: "com.riskdetected.pilot.training.pending.v1")
    private static var busy = Set<String>()
    init(identity: NovaSessionIdentity) { self.identity = identity }
    private func check() throws {
        try Task.checkCancellation()
        guard novaCurrentSessionIdentity() == identity else { throw NovaPersonnelFailure.denied }
    }
    private func key(_ company: UUID) -> String { "\(identity.userID):\(company)" }
    func pending(_ company: UUID) throws -> Pending? {
        try check()
        guard let data = try storage.read(account: key(company)) else { return nil }
        let value = try JSONDecoder().decode(Pending.self, from: data)
        guard value.owner == identity.userID, value.company == company else { throw NovaPersonnelFailure.denied }
        return value
    }
    func list(_ company: UUID, after: UUID? = nil, id: UUID? = nil) async throws -> Page {
        try check()
        let data = try await SupabaseService.shared.client.rpc("isg_pilot_training_read_v1", params: [
            "p_company": PersonnelRPCValue.id(company), "p_id": .id(id), "p_after": .id(after)]).execute().data
        try check()
        guard data.count <= 8_388_608 else { throw NovaPersonnelFailure.unavailable }
        let page = try JSONDecoder().decode(Page.self, from: data)
        guard page.schema_version == 1, page.owner_id == identity.userID, page.company_id == company,
              page.rows.count <= 50, Set(page.rows.map(\.id)).count == page.rows.count,
              page.rows.allSatisfy({ $0.owner_id == identity.userID && $0.company_id == company &&
                  (id == nil || $0.id == id) && ["planned", "completed", "cancelled"].contains($0.state) })
        else { throw NovaPersonnelFailure.denied }
        return page
    }
    func save(_ company: UUID, draft: NovaTrainingDraft) async throws -> NovaTrainingRecord {
        try check()
        if let saved = try pending(company) {
            guard saved.payload == draft else { throw NovaPersonnelFailure.conflict }
            return try await send(saved)
        }
        let intent = Pending(owner: identity.userID, company: company, mutation: UUID(), payload: draft)
        try storage.write(JSONEncoder().encode(intent), account: key(company))
        return try await send(intent)
    }
    func retry(_ company: UUID) async throws -> NovaTrainingRecord {
        guard let intent = try pending(company) else { throw NovaPersonnelFailure.unavailable }
        return try await send(intent)
    }
    private func send(_ intent: Pending) async throws -> NovaTrainingRecord {
        try check()
        let account = key(intent.company)
        guard Self.busy.insert(account).inserted else { throw NovaPersonnelFailure.unavailable }
        defer { Self.busy.remove(account) }
        struct Args: Encodable { let p_company: UUID; let p_mutation: UUID; let p_payload: NovaTrainingDraft }
        struct Receipt: Decodable {
            let schema_version: Int; let owner_id: UUID; let company_id: UUID; let mutation_id: UUID; let row: NovaTrainingRecord
        }
        do {
            let data = try await SupabaseService.shared.client.rpc("isg_pilot_training_save_v1", params:
                Args(p_company: intent.company, p_mutation: intent.mutation, p_payload: intent.payload)).execute().data
            try check()
            guard data.count <= 262144 else { throw NovaPersonnelFailure.unavailable }
            let receipt = try JSONDecoder().decode(Receipt.self, from: data)
            guard receipt.schema_version == 1, receipt.owner_id == identity.userID, receipt.company_id == intent.company,
                  receipt.mutation_id == intent.mutation, receipt.row.company_id == intent.company,
                  receipt.row.owner_id == identity.userID,
                  intent.payload.id == nil || intent.payload.id == receipt.row.id else { throw NovaPersonnelFailure.denied }
            try storage.remove(account: account)
            return receipt.row
        } catch let error as PostgrestError {
            // Only a definite SQL rejection clears the request. Network/unknown
            // failures retain the exact same mutation across dismiss/relaunch.
            if ["P0001", "28000", "22007", "22P02", "23514", "23502"].contains(error.code ?? "") {
                try storage.remove(account: account)
            }
            throw error
        }
    }
    static func message(_ error: Error) -> String {
        if let e = error as? PostgrestError {
            switch e.message {
            case "TRAINING_NOT_ENDED": return "Eğitim henüz bitmedi. Bitiş saatinden sonra tamamlayabilirsiniz."
            case "ATTENDANCE_REQUIRED": return "Tamamlamak için en az bir katılımcının yoklamasını işaretleyip kaydedin."
            case "FUTURE_ATTENDANCE": return "Gelecekteki eğitim için katılım işaretlenemez."
            case "PARTICIPANT_UNAVAILABLE": return "Seçilen personel artık aktif değil. Katılımcı listesini güncelleyin."
            case "VERSION_CONFLICT", "TRAINING_LOCKED": return "Kayıt değişti veya kapatıldı. Listeyi yenileyip tekrar açın."
            case "VALIDATION_ERROR": return "Eğitim adı, eğitmen, tarih ve süre bilgilerini kontrol edin."
            case "FEATURE_UNAVAILABLE", "ACCESS_DENIED", "AUTH_REQUIRED", "PAID_PLAN_REQUIRED": return "Bu firma için eğitim erişimi doğrulanamadı. Oturumunuzu ve pilot erişiminizi kontrol edin."
            default: break
            }
        }
        return "İşlem doğrulanamadı. Bağlantınızı kontrol edip tekrar deneyin; bekleyen kayıt aynı işlemle sürdürülecek."
    }
}
