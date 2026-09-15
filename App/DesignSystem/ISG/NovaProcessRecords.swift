import SwiftUI
import Supabase

struct NovaProcessField: Identifiable {
    let id: String
    let title: String
    var type = "text"
    var choices: [String: String] = [:]
    var required = false
}
struct NovaProcessKind {
    let code: String
    let title: String
    let fields: [NovaProcessField]
    var child: String?
    var parentKey: String?
    static func get(_ code: String) -> Self {
        func f(_ key: String, _ title: String, _ type: String = "text", _ required: Bool = false, _ choices: [String:String] = [:]) -> NovaProcessField {
            .init(id: key, title: title, type: type, choices: choices, required: required)
        }
        let workplace = f("workplace_id", "İşyeri", "workplaces", true)
        switch code {
        case "katip_contract": return .init(code: code, title: "İSG-KATİP Sözleşmeleri", fields: [workplace,f("counterparty","Sözleşme tarafı","text",true),f("expert_contact","Uzman / iletişim","text",true),f("scope","Hizmet kapsamı","text",true),f("starts_on","Başlangıç","date",true),f("ends_before","Bitiş (hariç)","date"),f("declared_monthly_minutes","Beyan edilen aylık dakika","number"),f("declared_note","Hizmet notu"),f("asset_id","Sözleşme dosyası","file")])
        case "annual_work_plan": return .init(code: code,title:"Yıllık Çalışma Planı",fields:[workplace,f("plan_year","Plan yılı","number",true)],child:"annual_work_item")
        case "annual_work_item": return .init(code:code,title:"Plan Faaliyetleri",fields:[f("activity","Faaliyet / hedef","multiline",true),f("responsible_contact","Sorumlu"),f("planned_on","Planlanan tarih","date",true),f("state","Durum","choice",true,["planned":"Planlandı","performed":"Gerçekleşti","carried_over":"Ertelendi","cancelled":"İptal"]),f("performed_on","Gerçekleşme tarihi","date"),f("carry_over_reason","Erteleme gerekçesi","multiline")],parentKey:"plan_id")
        case "board": return .init(code:code,title:"Kurul ve Toplantılar",fields:[workplace,f("applicability","Toplantı türü","choice",true,["mandatory":"Mevzuat zorunlu toplantı"]),f("agenda","Gündem (her satıra bir madde)","lines",true),f("planned_on","Toplantı tarihi","date",true),f("state","Durum","choice",true,["held":"Gerçekleşti","cancelled":"İptal"]),f("held_on","Gerçekleşme tarihi","date"),f("attendance","Katılımcılar","employees"),f("cancelled_reason","İptal gerekçesi","multiline")],child:"board_decision")
        case "board_decision": return .init(code:code,title:"Kararlar ve Takip",fields:[f("decision_no","Karar no","number",true),f("decision_text","Karar / aksiyon","multiline",true),f("responsible_contact","Sorumlu"),f("due_on","Termin","date"),f("state","Durum","choice",true,["open":"Açık","done":"Tamamlandı","cancelled":"İptal"])],parentKey:"meeting_id")
        case "site_visit": return .init(code:code,title:"Saha Ziyaretleri",fields:[workplace,f("visited_on","Ziyaret tarihi","date",true),f("location_note","Ziyaret yeri"),f("expert_note","Ziyaret notu","multiline",true),f("responsible_contact","Sorumlu")],child:"site_observation")
        case "site_observation": return .init(code:code,title:"Gözlemler",fields:[f("note","Gözlem / aksiyon","multiline",true),f("external_ref","Uygunsuzluk / kanıt referansı")],parentKey:"visit_id")
        case "work_permit": return .init(code:code,title:"Çalışma İzni Formları",fields:[workplace,f("template_code","Form türü","choice",true,["general":"Genel çalışma","hot_work":"Sıcak iş","work_at_height":"Yüksekte çalışma","confined_space":"Kapalı alan","electrical":"Elektrik işi"]),f("job_description","İş tanımı","multiline",true),f("planned_on","Planlanan tarih","date",true),f("work_location","Çalışma yeri"),f("starts_at","Başlangıç saati","datetime"),f("ends_at","Bitiş saati","datetime"),f("parties","İlgili personeller","employees"),f("risk_precautions","Riskler, önlemler ve sorumlular","multiline")])
        case "contractor": return .init(code:code,title:"Taşeron ve Dış Firmalar",fields:[f("code","Firma kodu","text",true),f("name","Ticari ad","text",true),f("relationship","İlişki","choice",true,["subcontractor":"Alt işveren (beyan)","contractor":"Yüklenici","supplier":"Tedarikçi","other":"Diğer"]),f("contact","Yetkili / iletişim"),f("identifiers","Vergi / işyeri tanımlayıcısı"),f("notes","Notlar","multiline")],child:"contractor_engagement")
        default: return .init(code:"contractor_engagement",title:"İş ve Sözleşmeler",fields:[f("organization_id","Dış firma","organizations",true),workplace,f("starts_on","Başlangıç","date",true),f("ends_before","Bitiş (hariç)","date"),f("description","Yapılan iş","multiline",true)])
        }
    }
}
struct NovaProcessRow: Decodable, Identifiable {
    let id: UUID; let company_id: UUID; let company_name: String
    let title: String; let date: String; let expected: String
    let values: [String:NovaModuleValue]
    var number: String?
    var revision: Int?
    var children: [NovaProcessRow]?
    var child_kind: String?
    struct ChildSummary: Decodable { let total: Int; let open: Int; let overdue: Int }
    var child_summary: ChildSummary?
    var workplace_name: String?
    var document_id: UUID?; var related_kind: String?; var related_id: UUID?
}
struct NovaProcessPage: Decodable {
    let rows: [NovaProcessRow]; let has_more: Bool
    let workplaces: [NovaModuleEditor.Option]; let employees: [NovaModuleEditor.Option]
    let documents: [NovaModuleEditor.Option]; let organizations: [NovaModuleEditor.Option]
}
@MainActor struct NovaProcessService {
    let identity: NovaSessionIdentity
    private func check() throws {
        guard let s = SupabaseService.shared.client.auth.currentSession, s.user.id == identity.userID,
              NovaPersonnelService.sessionID(s.accessToken) == identity.sessionID else { throw NovaPPEFailure.denied }
    }
    func read(kind: String, company: UUID?, id: UUID? = nil, parent: UUID? = nil, query: String = "", offset: Int = 0) async throws -> Data {
        try check()
        let args: [String:PersonnelRPCValue] = ["p_kind":.string(kind),"p_company":company.map(PersonnelRPCValue.id) ?? .null,"p_id":id.map(PersonnelRPCValue.id) ?? .null,"p_parent":parent.map(PersonnelRPCValue.id) ?? .null,"p_query":.string(query),"p_offset":.number(Int64(offset))]
        let data = try await SupabaseService.shared.client.rpc("isg_pilot_process_read_v1",params:args).execute().data
        try check(); return data
    }
    func references(kind: String, company: UUID, id: UUID? = nil, query: String = "", offset: Int = 0) async throws -> NovaProcessPage {
        try check()
        let args: [String: PersonnelRPCValue] = ["p_kind": .string(kind), "p_company": .id(company), "p_id": id.map(PersonnelRPCValue.id) ?? .null, "p_query": .string(query), "p_offset": .number(Int64(offset))]
        let data = try await SupabaseService.shared.client.rpc("isg_pilot_process_references_v1", params: args).execute().data
        try check(); return try JSONDecoder().decode(NovaProcessPage.self, from: data)
    }
    static func referenceTitle(_ kind: String) -> String {
        switch kind {
        case "training_record": return "Gerçekleşen eğitim"
        case "equipment_inspection": return "Ekipman kontrolü"
        case "nonconformity": return "Uygunsuzluk"
        case "checklist_run": return "Tamamlanan kontrol"
        default: return NovaProcessKind.get(kind).title
        }
    }
    func mutate(company: UUID, action: String, payload: [String:PersonnelRPCValue]) async throws -> Data {
        try await NovaModuleMutationJournal.run(function:"isg_pilot_process_mutate_v1",identity:identity,company:company,action:action,payload:payload,rpc:{ fn,args in
            try await SupabaseService.shared.client.rpc(fn,params:args).execute().data
        },validate:{try check()},decode:{$0})
    }
    func documents(company: UUID? = nil, document: UUID? = nil, version: Int? = nil, offset: Int = 0) async throws -> Data {
        try check()
        let args: [String: PersonnelRPCValue] = ["p_company":company.map(PersonnelRPCValue.id) ?? .null,"p_document":document.map(PersonnelRPCValue.id) ?? .null,"p_version":version.map{.number(Int64($0))} ?? .null,"p_offset":.number(Int64(offset))]
        let data = try await SupabaseService.shared.client.rpc("isg_pilot_process_documents_v1",params:args).execute().data
        try check();return data
    }
    static func message(_ error: Error) -> String {
        guard let e = error as? PostgrestError else { return "İşlem tamamlanamadı. Bağlantıyı kontrol edip yeniden deneyin." }
        switch e.message {
        case "VERSION_CONFLICT": return "Kayıt başka bir işlemde değişti. Kapatıp güncel kaydı yeniden açın."
        case "DEPENDENT_RECORDS": return "Önce bu kayda bağlı alt kayıtları kaldırın."
        case "PLAN_YEAR_MISMATCH": return "Faaliyet tarihi plan yılı içinde olmalı."
        case "FUTURE_DATE": return "Gerçekleşme tarihi gelecekte olamaz."
        case "ACCESS_DENIED": return "Firma, işyeri ve personel bağlantılarını kontrol edin."
        default: return "Bilgiler kaydedilemedi. Zorunlu alanları, tarihleri ve durum seçimini kontrol edin."
        }
    }
}
