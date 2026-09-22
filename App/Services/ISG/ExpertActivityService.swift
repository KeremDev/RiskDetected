import Foundation
import Supabase

struct UsageSummary: Decodable {
    let today_seconds: Double
    let week_seconds: Double
    let month_seconds: Double
    let total_seconds: Double
    let workspace_seconds: Double
    let session_seconds: Double
    let login_count: Int
    let last_login_at: String?
    let last_active_at: String?

    static func duration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds > 0 else { return "0 dk" }
        let minutes = Int(min(seconds / 60, Double(Int.max / 60)))
        if minutes < 1 { return "1 dk'dan az" }
        if minutes < 60 { return "\(minutes) dk" }
        return "\(minutes / 60) sa \(minutes % 60) dk"
    }
}

struct BusinessActivityItem: Decodable, Identifiable {
    let id: Int64
    let action: String
    let entity_type: String
    let entity_id: UUID?
    let company_id: UUID?
    let company_name: String?
    let correlation_id: UUID?
    let created_at: String

    var title: String {
        Self.title(action: action, entity: entity_type)
    }
    static func title(action: String, entity: String? = nil) -> String {
        let domain = ["company": "Firma", "personnel": "Personel", "employee": "Personel",
                      "analysis": "Analiz", "nonconformity": "Uygunsuzluk", "training": "Eğitim",
                      "report": "Rapor", "export": "Rapor", "visit": "Ziyaret", "personal_note": "Kişisel not",
                      "assignment": "Atama", "file": "Dosya", "risk": "Risk değerlendirmesi",
                      "workplace": "İşyeri", "department": "Departman", "job_role": "Görev",
                      "checklist": "Denetim", "document": "Belge", "drill": "Tatbikat",
                      "emergency": "Acil durum planı", "equipment": "Ekipman", "inspection": "Periyodik kontrol",
                      "ppe": "KKD", "plan": "Yıllık plan", "board": "Kurul", "contract": "Sözleşme",
                      "permit": "Çalışma izni", "contractor": "Alt işveren", "certificate": "Sertifika",
                      "training_session": "Eğitim"][entity ?? action.split(separator: ".").first.map(String.init) ?? ""] ?? "İşlem"
        let verb = action.split(separator: ".").last.map(String.init) ?? action
        let label = ["create": "oluşturuldu", "created": "oluşturuldu", "update": "düzenlendi",
                     "updated": "düzenlendi", "archive": "arşivlendi", "delete": "silindi",
                     "commit": "kaydedildi", "complete": "tamamlandı", "assign": "atandı",
                     "queued": "sıraya alındı", "running": "işleniyor", "processing": "işleniyor",
                     "succeeded": "tamamlandı", "completed": "tamamlandı", "failed": "başarısız oldu",
                     "cancelled": "iptal edildi"][verb] ?? "kaydedildi"
        return "\(domain) \(label)"
    }
}

struct BusinessActivityDetail: Decodable, Identifiable {
    struct Stage: Decodable { let status: String; let at: String }
    struct Change: Decodable, Identifiable {
        let field: String
        let before: Value?
        let after: Value?
        var id: String { field }
        enum Value: Decodable {
            case text(String)
            init(from decoder: Decoder) throws {
                let value = try decoder.singleValueContainer()
                if let string = try? value.decode(String.self) { self = .text(string) }
                else if let bool = try? value.decode(Bool.self) { self = .text(bool ? "Evet" : "Hayır") }
                else { self = .text(String(try value.decode(Double.self))) }
            }
            var text: String { switch self { case .text(let value): return value } }
        }
    }
    let id: Int64
    let action: String
    let entity_type: String
    let entity_id: UUID?
    let company_id: UUID?
    let correlation_id: UUID?
    let created_at: String
    let changes: [Change]
    let stages: [Stage]?
    let link_company_id: UUID?
    let link_workspace_id: UUID?
}

@MainActor enum ExpertActivityService {
    struct Page: Decodable {
        struct Company: Decodable, Identifiable { let id: UUID; let name: String }
        let schema_version: Int
        let summary: UsageSummary
        let items: [BusinessActivityItem]
        let next_cursor: Int64?
        let actions: [String]?
        let companies: [Company]?
    }
    struct Query: Encodable {
        var p_workspace: UUID?
        var p_user: UUID?
        var p_after: Int64?
        var p_from: String?
        var p_action: String?
        var p_company: UUID?
    }
    static func page(_ query: Query) async throws -> Page {
        let identity = novaCurrentSessionIdentity()
        guard identity != nil else { throw NovaPersonnelFailure.denied }
        let name = query.p_workspace == nil ? "isg_activity_self_v1" : "isg_workspace_member_activity_v1"
        let data = try await SupabaseService.shared.client.rpc(name, params: query).execute().data
        try Task.checkCancellation()
        guard identity == novaCurrentSessionIdentity(), data.count < 2_000_000 else { throw NovaPersonnelFailure.denied }
        let page = try JSONDecoder().decode(Page.self, from: data)
        guard page.schema_version == 1, page.items.count <= 30 else { throw NovaPersonnelFailure.denied }
        return page
    }
    static func detail(_ event: Int64, workspace: UUID?) async throws -> BusinessActivityDetail {
        struct Params: Encodable { let p_event: Int64; let p_workspace: UUID? }
        let identity = novaCurrentSessionIdentity()
        guard identity != nil else { throw NovaPersonnelFailure.denied }
        let data = try await SupabaseService.shared.client.rpc("isg_activity_event_detail_v1",
            params: Params(p_event: event, p_workspace: workspace)).execute().data
        try Task.checkCancellation()
        guard identity == novaCurrentSessionIdentity(), data.count < 100_000 else { throw NovaPersonnelFailure.denied }
        return try JSONDecoder().decode(BusinessActivityDetail.self, from: data)
    }
}

/// No offline queue: failed presence requests must never be replayed as active time.
@MainActor final class ExpertUsagePresence {
    static let shared = ExpertUsagePresence()
    private var loop: Task<Void, Never>?
    private var pendingStop: Task<Void, Never>?
    private var workspace: UUID?
    private var identity: NovaSessionIdentity?
    private var epoch = UUID()

    func foreground(workspace: UUID?) {
        guard NetworkMonitor.shared.isOnline, let current = novaCurrentSessionIdentity() else { return }
        guard loop == nil || self.workspace != workspace || identity != current else { return }
        let previous = self.workspace
        let previousIdentity = identity
        let wasRunning = loop != nil
        loop?.cancel()
        self.workspace = workspace
        identity = current
        epoch = UUID()
        let expected = epoch
        let stopping = pendingStop
        loop = Task {
            defer { if epoch == expected { loop = nil } }
            await stopping?.value
            if wasRunning, let previousIdentity { await send("stop", workspace: previous, identity: previousIdentity) }
            guard !Task.isCancelled, epoch == expected else { return }
            var baseline = await send("start", workspace: workspace, identity: current)
            while !Task.isCancelled {
                do { try await Task.sleep(nanoseconds: 60_000_000_000) } catch { return }
                guard epoch == expected, current == novaCurrentSessionIdentity(), NetworkMonitor.shared.isOnline else { return }
                baseline = await send(baseline ? "heartbeat" : "start", workspace: workspace, identity: current)
            }
        }
    }
    func background() async {
        let previous = workspace
        let previousIdentity = identity
        let wasRunning = loop != nil
        epoch = UUID(); loop?.cancel(); loop = nil; workspace = nil; identity = nil
        if wasRunning, let previousIdentity {
            let stop = Task { _ = await send("stop", workspace: previous, identity: previousIdentity) }
            pendingStop = stop
            await stop.value
        }
    }
    @discardableResult private func send(_ action: String, workspace: UUID?, identity: NovaSessionIdentity) async -> Bool {
        guard NetworkMonitor.shared.isOnline, novaCurrentSessionIdentity() == identity else { return false }
        struct Params: Encodable { let p_action: String; let p_workspace: UUID? }
        do {
            _ = try await SupabaseService.shared.client.rpc("isg_usage_presence_v1",
                params: Params(p_action: action, p_workspace: workspace)).execute()
            return true
        } catch {
            // Offline intervals are discarded by the server's 90 second boundary.
            return false
        }
    }
}
