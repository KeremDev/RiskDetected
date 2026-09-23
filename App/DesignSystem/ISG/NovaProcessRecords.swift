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
    var help: String {
        switch code {
        case "annual_work_plan": return RDLocalization.string("localizable.nova.process.records.yillik.plani.acin.faaliyetleri.sorumlulari.ve.ge.690ab267", table: .localizable, fallback: "Yıllık planı açın; faaliyetleri, sorumluları ve gerçekleşme durumunu takip edin.")
        case "annual_work_item": return RDLocalization.string("localizable.nova.process.records.faaliyeti.ve.tarihini.kaydedin.gerceklestiginde..4d0d8a94", table: .localizable, fallback: "Faaliyeti ve tarihini kaydedin; gerçekleştiğinde durumunu güncelleyin.")
        case "board": return RDLocalization.string("localizable.nova.process.records.gerceklesen.toplantinin.gundemini.ve.katilimcila.f942c110", table: .localizable, fallback: "Gerçekleşen toplantının gündemini ve katılımcılarını ekleyin; kararlarını takip edin.")
        case "board_decision": return RDLocalization.string("localizable.nova.process.records.her.karari.ayri.ekleyin.sorumlusunu.ve.varsa.tam.22b0c7c3", table: .localizable, fallback: "Her kararı ayrı ekleyin; sorumlusunu ve varsa tamamlanma tarihini belirtin.")
        case "completed_drill": return RDLocalization.string("localizable.nova.process.records.gerceklesen.tatbikati.kaydedin.senaryo.sure.foto.dce05a31", table: .localizable, fallback: "Gerçekleşen tatbikatı kaydedin; senaryo, süre, fotoğraf ve raporunu birlikte takip edin.")
        case "personnel_certificate": return RDLocalization.string("localizable.nova.process.records.personelin.belgesini.kaydedin.dosya.istege.bagli.7ea04c97", table: .localizable, fallback: "Personelin belgesini kaydedin. Dosya isteğe bağlıdır; geçerlilik tarihi firma takibine yansır.")
        case "approved_notebook": return RDLocalization.string("localizable.nova.process.records.onayli.defter.sayfasinin.fotografini.firmanin.ar.56526b52", table: .localizable, fallback: "Onaylı defter sayfasının fotoğrafını firmanın arşivine ekleyin; dilediğinizde açıp indirin.")
        case "site_visit": return RDLocalization.string("localizable.nova.process.records.ziyaret.tarihini.ve.yaptiginiz.islemleri.kaydedi.f6776c8e", table: .localizable, fallback: "Ziyaret tarihini ve yaptığınız işlemleri kaydedin; görüşülen kişiyi isteğe bağlı ekleyin.")
        case "site_observation": return RDLocalization.string("localizable.nova.process.records.ziyaretteki.gozlemi.veya.aksiyonu.kaydedin.ilgil.d425e658", table: .localizable, fallback: "Ziyaretteki gözlemi veya aksiyonu kaydedin; ilgili kayda bağlayabilirsiniz.")
        case "contractor", "contractor_engagement": return RDLocalization.string("localizable.nova.process.records.firmanin.taseronlarini.ve.birlikte.yurutulen.isl.ede31d20", table: .localizable, fallback: "Firmanın taşeronlarını ve birlikte yürütülen işleri kaydedin.")
        case "work_permit": return RDLocalization.string("localizable.nova.process.records.calismayi.ilgili.kisileri.ve.alinacak.onlemleri..ac7c3852", table: .localizable, fallback: "Çalışmayı, ilgili kişileri ve alınacak önlemleri belirtin; formu indirin.")
        default: return RDLocalization.string("localizable.nova.process.records.firmanin.kaydini.ekleyin.bilgilerini.duzenleyin..3316440b", table: .localizable, fallback: "Firmanın kaydını ekleyin, bilgilerini düzenleyin ve gerektiğinde çıktısını alın.")
        }
    }
    var emptyTitle: String {
        switch code {
        case "katip_contract": return RDLocalization.string("localizable.nova.process.records.henuz.isg.katip.sozlesmesi.yok.ee8adc31", table: .localizable, fallback: "Henüz İSG-KATİP sözleşmesi yok")
        case "annual_work_plan": return RDLocalization.string("localizable.nova.process.records.henuz.yillik.calisma.plani.yok.835088e2", table: .localizable, fallback: "Henüz yıllık çalışma planı yok")
        case "board": return RDLocalization.string("localizable.nova.process.records.henuz.kurul.veya.toplanti.kaydi.yok.05a111bd", table: .localizable, fallback: "Henüz kurul veya toplantı kaydı yok")
        case "site_visit": return RDLocalization.string("localizable.nova.process.records.henuz.saha.ziyareti.kaydi.yok.fab9b4bc", table: .localizable, fallback: "Henüz saha ziyareti kaydı yok")
        case "work_permit": return RDLocalization.string("localizable.nova.process.records.henuz.calisma.izni.formu.yok.928b5aa4", table: .localizable, fallback: "Henüz çalışma izni formu yok")
        case "contractor": return RDLocalization.string("localizable.nova.process.records.henuz.taseron.veya.dis.firma.kaydi.yok.de3df479", table: .localizable, fallback: "Henüz taşeron veya dış firma kaydı yok")
        default: return RDLocalization.string("localizable.nova.process.records.henuz.kayit.yok.0491cfdb", table: .localizable, fallback: "Henüz kayıt yok")
        }
    }
    var emptyMessage: String {
        switch code {
        case "katip_contract": return RDLocalization.string("localizable.nova.process.records.sozlesmeyi.ekleyerek.hizmet.kapsamini.suresini.v.bdd2b849", table: .localizable, fallback: "Sözleşmeyi ekleyerek hizmet kapsamını, süresini ve sözleşme dosyasını firma bazında takip edebilirsiniz.")
        case "annual_work_plan": return RDLocalization.string("localizable.nova.process.records.yillik.plani.ekleyerek.faaliyetleri.sorumlulari..3df0c8dd", table: .localizable, fallback: "Yıllık planı ekleyerek faaliyetleri, sorumluları ve gerçekleşme durumlarını tek yerden takip edebilirsiniz.")
        case "board": return RDLocalization.string("localizable.nova.process.records.gerceklesen.toplantiyi.ekleyerek.gundemi.katilim.5853e5a4", table: .localizable, fallback: "Gerçekleşen toplantıyı ekleyerek gündemi, katılımcıları ve kararları birlikte izleyebilirsiniz.")
        case "site_visit": return RDLocalization.string("localizable.nova.process.records.saha.ziyaretini.ekleyerek.yapilan.islemleri.notl.7cd8a54e", table: .localizable, fallback: "Saha ziyaretini ekleyerek yapılan işlemleri, notları ve kanıtları dijital ortamda saklayabilirsiniz.")
        case "work_permit": return RDLocalization.string("localizable.nova.process.records.calisma.izni.formunu.ekleyerek.isi.taraflari.ve..31831948", table: .localizable, fallback: "Çalışma izni formunu ekleyerek işi, tarafları ve alınacak önlemleri kayıt altına alabilirsiniz.")
        case "contractor": return RDLocalization.string("localizable.nova.process.records.taseron.veya.dis.firmayi.ekleyerek.yurutulen.isl.ead43e8b", table: .localizable, fallback: "Taşeron veya dış firmayı ekleyerek yürütülen işleri ve iletişim bilgilerini takip edebilirsiniz.")
        default: return RDLocalization.string("localizable.nova.process.records.yeni.kayit.ekleyerek.bu.sureci.dijital.ortamda.d.1f6483ac", table: .localizable, fallback: "Yeni kayıt ekleyerek bu süreci dijital ortamda düzenli biçimde takip edebilirsiniz.")
        }
    }
    static func get(_ code: String) -> Self {
        func f(_ key: String, _ title: String, _ type: String = "text", _ required: Bool = false, _ choices: [String:String] = [:]) -> NovaProcessField {
            .init(id: key, title: title, type: type, choices: choices, required: required)
        }
        let workplace = f("workplace_id", "İşyeri", "workplaces", true)
        switch code {
        case "katip_contract": return .init(code: code, title: RDLocalization.string("localizable.nova.process.records.isg.katip.sozlesmeleri.53f43382", table: .localizable, fallback: "İSG-KATİP Sözleşmeleri"), fields: [workplace,f("counterparty","Sözleşme tarafı","text",true),f("expert_contact","Uzman / iletişim","text",true),f("scope","Hizmet kapsamı","text",true),f("starts_on","Başlangıç","date",true),f("ends_before","Bitiş (hariç)","date"),f("declared_monthly_minutes","Beyan edilen aylık dakika","number"),f("declared_note","Hizmet notu"),f("asset_id","Sözleşme dosyası","file")])
        case "annual_work_plan": return .init(code: code,title:RDLocalization.string("localizable.nova.process.records.yillik.calisma.plani.afebccb4", table: .localizable, fallback: "Yıllık Çalışma Planı"),fields:[workplace,f("plan_year","Plan yılı","number",true)],child:"annual_work_item")
        case "annual_work_item": return .init(code:code,title:RDLocalization.string("localizable.nova.process.records.plan.faaliyetleri.0e167be0", table: .localizable, fallback: "Plan Faaliyetleri"),fields:[f("activity","Faaliyet / hedef","multiline",true),f("responsible_contact","Sorumlu"),f("planned_on","Planlanan tarih","date",true),f("state","Durum","choice",true,["planned":"Planlandı","performed":"Gerçekleşti","carried_over":"Ertelendi","cancelled":"İptal"]),f("performed_on","Gerçekleşme tarihi","date"),f("carry_over_reason","Erteleme gerekçesi","multiline")],parentKey:"plan_id")
        case "board": return .init(code:code,title:RDLocalization.string("localizable.nova.process.records.kurul.ve.toplantilar.01170f30", table: .localizable, fallback: "Kurul ve Toplantılar"),fields:[workplace,f("applicability","Toplantı türü","choice",true,["mandatory":"Mevzuat zorunlu toplantı"]),f("agenda","Gündem maddeleri","lines",true),f("initial_decisions","Alınan kararlar","lines"),f("planned_on","Toplantı tarihi","date",true),f("state","Durum","choice",true,["held":"Gerçekleşti","cancelled":"İptal"]),f("held_on","Gerçekleşme tarihi","date"),f("attendance","Katılımcılar","employees"),f("cancelled_reason","İptal gerekçesi","multiline"),f("minutes_asset_id","Toplantı dosyası","file")],child:"board_decision")
        case "board_decision": return .init(code:code,title:RDLocalization.string("localizable.nova.process.records.kararlar.ve.takip.0429ea86", table: .localizable, fallback: "Kararlar ve Takip"),fields:[f("decision_no","Karar no","number",true),f("decision_text","Karar / aksiyon","multiline",true),f("responsible_contact","Sorumlu"),f("due_on","Termin","date"),f("state","Durum","choice",true,["open":"Açık","done":"Tamamlandı","cancelled":"İptal"])],parentKey:"meeting_id")
        case "completed_drill": return .init(code:code,title:"Tatbikatlar",fields:[workplace,f("held_on","Tatbikat tarihi","date",true),f("drill_type","Tatbikat türü","choice",true,["emergency":"Acil durum","fire":"Yangın"]),f("announcement","Haber durumu","choice",true,["announced":"Haberli","unannounced":"Habersiz"]),f("bekra","BEKRA tatbikatı","bool"),f("duration_minutes","Tamamlanma süresi (dakika)","number"),f("scenario","Senaryo","multiline",true),f("note","Notlar","multiline"),f("photo_ids","Fotoğraflar · en fazla 10","photos"),f("asset_id","Tatbikat raporu · PDF","pdf"),f("due_override","Takip tarihini değiştir","bool"),f("valid_until","Sonraki tatbikat tarihi","date")])
        case "personnel_certificate": return .init(code:code,title:RDLocalization.string("localizable.nova.process.records.personel.belgeleri.e37c34d2", table: .localizable, fallback: "Personel Belgeleri"),fields:[f("employee_id","Personel","employee",true),f("certificate_kind","Belge türü","choice",true,["first_aid":"İlk yardım","myk":"MYK","custom":"Diğer"]),f("title","Belge adı","text",true),f("issued_on","Düzenleme tarihi","date",true),f("due_override","Geçerlilik tarihini değiştir","bool"),f("valid_until","Geçerlilik tarihi","date"),f("asset_id","Belge dosyası · isteğe bağlı","file"),f("note","Not","multiline")])
        case "approved_notebook": return .init(code:code,title:RDLocalization.string("localizable.nova.process.records.onayli.defter.ecb79831", table: .localizable, fallback: "Onaylı Defter"),fields:[f("title","Başlık","text",true),f("asset_id","Defter görseli","photo",true),f("note","Not","multiline")])
        case "site_visit": return .init(code:code,title:RDLocalization.string("localizable.nova.process.records.saha.ziyaretleri.dd9337c5", table: .localizable, fallback: "Saha Ziyaretleri"),fields:[workplace,f("visited_on","Ziyaret tarihi","date",true),f("expert_note","Ziyaret notu","multiline",true),f("location_note","Ziyaret yeri"),f("responsible_contact","Görüşülen kişi"),f("duration_minutes","Ziyaret süresi (dakika)","number"),f("visit_asset_id","Ziyaret fotoğrafı","photo")],child:"site_observation")
        case "site_observation": return .init(code:code,title:RDLocalization.string("localizable.nova.process.records.gozlemler.fade94ab", table: .localizable, fallback: "Gözlemler"),fields:[f("note","Gözlem / aksiyon","multiline",true),f("external_ref","Uygunsuzluk / kanıt referansı")],parentKey:"visit_id")
        case "work_permit": return .init(code:code,title:RDLocalization.string("localizable.nova.process.records.calisma.izni.formlari.c2b0c51f", table: .localizable, fallback: "Çalışma İzni Formları"),fields:[workplace,f("template_code","Form türü","choice",true,["general":"Genel çalışma","hot_work":"Sıcak iş","work_at_height":"Yüksekte çalışma","confined_space":"Kapalı alan","electrical":"Elektrik işi"]),f("job_description","İş tanımı","multiline",true),f("planned_on","Planlanan tarih","date",true),f("work_location","Çalışma yeri"),f("starts_at","Başlangıç saati","datetime"),f("ends_at","Bitiş saati","datetime"),f("parties","İlgili personeller","employees"),f("risk_precautions","Riskler, önlemler ve sorumlular","multiline")])
        case "contractor": return .init(code:code,title:RDLocalization.string("localizable.nova.process.records.taseron.ve.dis.firmalar.369dae5b", table: .localizable, fallback: "Taşeron ve Dış Firmalar"),fields:[f("code","Firma kodu","text",true),f("name","Ticari ad","text",true),f("relationship","İlişki","choice",true,["subcontractor":"Alt işveren (beyan)","contractor":"Yüklenici","supplier":"Tedarikçi","other":"Diğer"]),f("contact","Yetkili / iletişim"),f("identifiers","Vergi / işyeri tanımlayıcısı"),f("notes","Notlar","multiline")],child:"contractor_engagement")
        default: return .init(code:"contractor_engagement",title:RDLocalization.string("localizable.nova.process.records.is.ve.sozlesmeler.d1b8ac68", table: .localizable, fallback: "İş ve Sözleşmeler"),fields:[f("organization_id","Dış firma","organizations",true),workplace,f("starts_on","Başlangıç","date",true),f("ends_before","Bitiş (hariç)","date"),f("description","Yapılan iş","multiline",true)])
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
struct NovaVisitSummary: Decodable {
    let schema_version: Int
    let owner_id: UUID
    let company_id: UUID?
    let visits: Int
    let recorded_minutes: Int?
    let timed_visits: Int
    let last_visited_on: String?
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
        let data = try await NovaExpertTransport.shared.execute("isg_pilot_process_read_v1",params:args, ticket: NovaExpertTransport.shared.capture())
        try check(); return data
    }
    func visitSummary(company: UUID?, from: String? = nil, to: String? = nil) async throws -> NovaVisitSummary {
        try check()
        let data = try await NovaExpertTransport.shared.execute("isg_pilot_visit_summary_v1", params: [
            "p_company": PersonnelRPCValue.id(company), "p_from": from.map(PersonnelRPCValue.string) ?? .null, "p_to": to.map(PersonnelRPCValue.string) ?? .null], ticket: NovaExpertTransport.shared.capture())
        try check()
        let result = try JSONDecoder().decode(NovaVisitSummary.self, from: data)
        guard result.schema_version == 1, result.owner_id == identity.userID, result.company_id == company,
              result.visits >= 0, result.timed_visits >= 0, result.timed_visits <= result.visits else { throw NovaPPEFailure.denied }
        return result
    }
    func attachment(kind: String, record: UUID, field: String) async throws -> NovaFileEntry {
        try check()
        let data = try await NovaExpertTransport.shared.execute("isg_pilot_process_attachment_v1", params: [
            "p_kind": PersonnelRPCValue.string(kind), "p_record": .id(record), "p_field": .string(field)], ticket: NovaExpertTransport.shared.capture())
        try check()
        struct Result: Decodable { let entry_id: UUID }
        let id = try JSONDecoder().decode(Result.self, from: data).entry_id
        let entry = try await NovaFileLibraryService.live().detail(identity, entry: id)
        try check(); return entry
    }
    func references(kind: String, company: UUID, id: UUID? = nil, query: String = "", offset: Int = 0) async throws -> NovaProcessPage {
        try check()
        let args: [String: PersonnelRPCValue] = ["p_kind": .string(kind), "p_company": .id(company), "p_id": id.map(PersonnelRPCValue.id) ?? .null, "p_query": .string(query), "p_offset": .number(Int64(offset))]
        let data = try await NovaExpertTransport.shared.execute("isg_pilot_process_references_v1", params: args, ticket: NovaExpertTransport.shared.capture())
        try check(); return try JSONDecoder().decode(NovaProcessPage.self, from: data)
    }
    static func referenceTitle(_ kind: String) -> String {
        switch kind {
        case "training_record": return RDLocalization.string("localizable.nova.process.records.gerceklesen.egitim.defdad4f", table: .localizable, fallback: "Gerçekleşen eğitim")
        case "equipment_inspection": return RDLocalization.string("localizable.nova.process.records.ekipman.kontrolu.3a04567c", table: .localizable, fallback: "Ekipman kontrolü")
        case "nonconformity": return "Uygunsuzluk"
        case "checklist_run": return RDLocalization.string("localizable.nova.process.records.tamamlanan.kontrol.a0ab1d5e", table: .localizable, fallback: "Tamamlanan kontrol")
        default: return NovaProcessKind.get(kind).title
        }
    }
    func mutate(company: UUID, action: String, payload: [String:PersonnelRPCValue]) async throws -> Data {
        try await NovaModuleMutationJournal.run(function:"isg_pilot_process_mutate_v1",identity:identity,company:company,action:action,payload:payload,rpc:{ fn,args in
            try await NovaExpertTransport.shared.execute(fn,params:args, ticket: NovaExpertTransport.shared.capture())
        },validate:{try check()},decode:{ data in
            if action == "delete" {
                struct Deleted: Decodable { let deleted: Bool }
                guard try JSONDecoder().decode(Deleted.self, from: data).deleted else { throw NovaPPEFailure.denied }
            } else {
                let row = try JSONDecoder().decode(NovaProcessRow.self, from: data)
                guard row.company_id == company, !row.expected.isEmpty else { throw NovaPPEFailure.denied }
            }
            return data
        })
    }
    func documents(company: UUID? = nil, document: UUID? = nil, version: Int? = nil, offset: Int = 0) async throws -> Data {
        try check()
        let args: [String: PersonnelRPCValue] = ["p_company":company.map(PersonnelRPCValue.id) ?? .null,"p_document":document.map(PersonnelRPCValue.id) ?? .null,"p_version":version.map{.number(Int64($0))} ?? .null,"p_offset":.number(Int64(offset))]
        let data = try await NovaExpertTransport.shared.execute("isg_pilot_process_documents_v1",params:args, ticket: NovaExpertTransport.shared.capture())
        try check();return data
    }
    static func message(_ error: Error) -> String {
        guard let e = error as? PostgrestError else { return RDLocalization.string("localizable.nova.process.records.islem.tamamlanamadi.baglantiyi.kontrol.edip.yeni.cbf3db18", table: .localizable, fallback: "İşlem tamamlanamadı. Bağlantıyı kontrol edip yeniden deneyin.") }
        switch e.message {
        case "VERSION_CONFLICT": return RDLocalization.string("localizable.nova.process.records.kayit.baska.bir.islemde.degisti.kapatip.guncel.k.f76a189c", table: .localizable, fallback: "Kayıt başka bir işlemde değişti. Kapatıp güncel kaydı yeniden açın.")
        case "DEPENDENT_RECORDS": return RDLocalization.string("localizable.nova.process.records.once.bu.kayda.bagli.alt.kayitlari.kaldirin.38d66be9", table: .localizable, fallback: "Önce bu kayda bağlı alt kayıtları kaldırın.")
        case "PLAN_YEAR_MISMATCH": return RDLocalization.string("localizable.nova.process.records.faaliyet.tarihi.plan.yili.icinde.olmali.6ffce2eb", table: .localizable, fallback: "Faaliyet tarihi plan yılı içinde olmalı.")
        case "FUTURE_DATE": return RDLocalization.string("localizable.nova.process.records.gerceklesme.tarihi.gelecekte.olamaz.21395377", table: .localizable, fallback: "Gerçekleşme tarihi gelecekte olamaz.")
        case "ACCESS_DENIED": return RDLocalization.string("localizable.nova.process.records.firma.isyeri.ve.personel.baglantilarini.kontrol..f5b7eb5c", table: .localizable, fallback: "Firma, işyeri ve personel bağlantılarını kontrol edin.")
        default: return RDLocalization.string("localizable.nova.process.records.bilgiler.kaydedilemedi.zorunlu.alanlari.tarihler.c9d05369", table: .localizable, fallback: "Bilgiler kaydedilemedi. Zorunlu alanları, tarihleri ve durum seçimini kontrol edin.")
        }
    }
}
