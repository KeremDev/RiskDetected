import SwiftUI
import Supabase

enum NovaModuleValue: Codable, Equatable {
    case string(String), number(Double), bool(Bool), array([NovaModuleValue]), object([String: NovaModuleValue]), null
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode([NovaModuleValue].self) { self = .array(v) }
        else { self = .object(try c.decode([String: NovaModuleValue].self)) }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self { case .null: try c.encodeNil(); case .string(let v): try c.encode(v)
        case .number(let v): try c.encode(v); case .bool(let v): try c.encode(v)
        case .array(let v): try c.encode(v); case .object(let v): try c.encode(v) }
    }
    var text: String { if case .string(let v) = self { return v }; if case .number(let v) = self { return String(v) }; return "" }
    var rpc: PersonnelRPCValue {
        switch self { case .string(let v): return .string(v); case .number(let v): return .string(String(v))
        case .bool(let v): return .string(v ? "true" : "false"); case .null: return .null
        case .array(let v): return .array(v.map(\.rpc)); case .object(let v): return .object(v.mapValues(\.rpc)) }
    }
}

struct NovaModuleEditor: View {
    let identity: NovaSessionIdentity
    let module: String
    let company: UUID
    let record: UUID
    let fileClient: NovaFileLibraryClient
    struct Option: Decodable, Identifiable { let id: UUID; let name: String }
    struct Envelope: Decodable {
        let snapshot: [String: NovaModuleValue]
        let expected: String
        let company_name: String
        let workplaces: [Option]; let employees: [Option]; let documents: [Option]; let plans: [Option]
    }
    @State private var envelope: Envelope?
    @State private var values: [String: NovaModuleValue] = [:]
    @State private var document = ""
    @State private var busy = false
    @State private var failure: String?
    @State private var confirmDelete = false
    @State private var showingDocuments = false
    @Environment(\.dismiss) private var dismiss

    private var keys: [String] {
        switch module {
        case "emergency_plan": return ["workplace_id","scope","prepared_on","valid_until","review_note","team_snapshot"]
        case "drill": return ["plan_id","planned_on","performed_on","participants","observation","improvement"]
        case "ppe": return ["employee_id","item","quantity","unit","handed_on","signed_copy_location"]
        default: return ["employee_id","kind","scope_workplace_id","starts_on","ends_before","basis","basis_note","asset_id"]
        }
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let data = envelope {
                        NovaText(text: data.company_name, style: .cardTitle)
                        NovaCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 14) { fields(data) }
                        }
                        NovaCard(padding: 16) {
                            VStack(alignment: .leading, spacing: 12) {
                                NovaText(text: "Bağlı evrak", style: .cardTitle)
                                Picker("Firma evrakı", selection: $document) {
                                    Text("Bağlantı yok").tag("")
                                    ForEach(data.documents) { Text($0.name).tag($0.id.uuidString.lowercased()) }
                                }
                                NovaText(text: "Firmanın evrak takip kaydını bu kayda bağlar.", style: .metaQuiet)
                                NovaButton(label: "Evrak bağlantısını kaydet", symbol: "link", variant: .surface) {
                                    Task { await save("link_document", close: false) }
                                }
                                NovaButton(label: "Firma evraklarını aç / ekle", symbol: "folder", variant: .surface) { showingDocuments = true }
                            }
                        }
                        NovaButton(label: "Değişiklikleri kaydet", symbol: "checkmark", variant: .primary) { Task { await save("update", close: true) } }
                        NovaButton(label: "Kaydı sil", symbol: "trash", variant: .surface) { confirmDelete = true }
                    } else if busy { ProgressView("Kayıt yükleniyor…").frame(maxWidth: .infinity) }
                    if let failure { NovaText(text: failure, style: .body) }
                }.padding(20).disabled(busy)
            }
            .background(NovaColorToken.canvas.color(in: .light))
            .navigationTitle("Kaydı düzenle").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Kapat") { dismiss() } } }
            .task { await load() }
            .confirmationDialog("Kayıt listeden kaldırılacak. İşlem geçmişi korunacak.", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Kaydı sil", role: .destructive) { Task { await save("delete", close: true) } }
            }
            .sheet(isPresented: $showingDocuments, onDismiss: { Task { await load(preserveValues: true) } }) {
                NovaModuleDocumentsHost(identity: identity, company: company, onClose: { showingDocuments = false })
            }
        }
    }
    @ViewBuilder private func fields(_ data: Envelope) -> some View {
        switch module {
        case "emergency_plan":
            options("İşyeri", "workplace_id", data.workplaces)
            field("Kapsam", "scope"); field("Hazırlık tarihi (YYYY-AA-GG)", "prepared_on")
            field("Geçerlilik tarihi (isteğe bağlı)", "valid_until"); field("Dayanak / açıklama", "review_note")
            teamFields
        case "drill":
            options("Acil durum planı", "plan_id", data.plans)
            field("Planlanan tarih (YYYY-AA-GG)", "planned_on")
            if values["state"]?.text == "performed" {
                field("Gerçekleşme tarihi (YYYY-AA-GG)", "performed_on")
                NovaText(text: "Katılımcılar", style: .label)
                ForEach(data.employees) { employee in
                    Toggle(employee.name, isOn: participant(employee.id))
                }
            }
            field("Gözlemler", "observation"); field("İyileştirmeler", "improvement")
        case "ppe":
            options("Personel", "employee_id", data.employees)
            field("KKD adı", "item"); field("Miktar", "quantity")
            choices("Birim", "unit", [("piece","Adet"),("pair","Çift"),("set","Takım"),("metre","Metre"),("litre","Litre")])
            field("Teslim tarihi (YYYY-AA-GG)", "handed_on"); field("Belgenin bulunduğu yer", "signed_copy_location")
        default:
            options("Personel", "employee_id", data.employees); options("İşyeri", "scope_workplace_id", data.workplaces)
            choices("Görev", "kind", [("representative","Çalışan temsilcisi"),("support_staff","Destek elemanı"),("team_member","Ekip üyesi"),("first_aid","İlk yardımcı"),("fire_team","Yangın ekibi")])
            field("Başlangıç tarihi (YYYY-AA-GG)", "starts_on"); field("Bitiş tarihi (isteğe bağlı)", "ends_before")
            choices("Dayanak", "basis", [("elected","Seçim"),("appointed","Atama")])
            field("Dayanak açıklaması", "basis_note")
            VStack(alignment: .leading, spacing: 5) {
                NovaText(text: "Atama yazısı", style: .label)
                NovaInlineFileField(category: "personnel_document", company: company, fileClient: fileClient,
                    assetID: binding("asset_id"))
            }
        }
    }
    private func binding(_ key: String) -> Binding<String> {
        Binding(get: { values[key]?.text ?? "" }, set: { values[key] = $0.isEmpty ? .null : .string($0) })
    }
    private func field(_ title: String, _ key: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            NovaText(text: title, style: .label)
            TextField(title, text: binding(key), axis: .vertical).font(NovaFont.font(.body))
                .textInputAutocapitalization(.sentences).padding(10).background(Color.white, in: RoundedRectangle(cornerRadius: 10))
        }
    }
    private func options(_ title: String, _ key: String, _ items: [Option]) -> some View {
        Picker(title, selection: binding(key)) {
            Text("Seçin").tag("")
            ForEach(items) { Text($0.name).tag($0.id.uuidString.lowercased()) }
        }
    }
    private func choices(_ title: String, _ key: String, _ items: [(String,String)]) -> some View {
        Picker(title, selection: binding(key)) { ForEach(items, id: \.0) { Text($0.1).tag($0.0) } }
    }
    private var members: [[String: NovaModuleValue]] {
        guard case .array(let list) = values["team_snapshot"] else { return [] }
        return list.compactMap { if case .object(let item) = $0 { return item }; return nil }
    }
    private var teamFields: some View {
        VStack(alignment: .leading, spacing: 10) {
            NovaText(text: "Ekip", style: .cardTitle)
            ForEach(members.indices, id: \.self) { index in
                TextField("Ad soyad", text: memberBinding(index,"full_name"))
                Picker("Görev", selection: memberBinding(index,"role")) {
                    Text("Koordinatör").tag("coordinator"); Text("Yangın").tag("fire")
                    Text("İlk yardım").tag("first_aid"); Text("Tahliye").tag("evacuation"); Text("Diğer").tag("other")
                }
                TextField("İletişim", text: memberBinding(index,"contact"))
                Button("Ekipten kaldır", role: .destructive) {
                    var list=members; list.remove(at:index); values["team_snapshot"] = .array(list.map { .object($0) })
                }
            }
            Button("Ekip üyesi ekle") {
                var list=members; list.append(["full_name":.string(""),"role":.string("other")])
                values["team_snapshot"] = .array(list.map { .object($0) })
            }
        }
    }
    private func memberBinding(_ index: Int, _ key: String) -> Binding<String> {
        Binding(get: { members.indices.contains(index) ? members[index][key]?.text ?? "" : "" }, set: { value in
            var list=members; guard list.indices.contains(index) else { return }
            list[index][key] = .string(value); values["team_snapshot"] = .array(list.map { .object($0) })
        })
    }
    private func participant(_ id: UUID) -> Binding<Bool> {
        let key=id.uuidString.lowercased()
        func selected() -> [String] { if case .array(let array)=values["participants"] { return array.map(\.text) }; return [] }
        return Binding(get: { selected().contains(key) }, set: { value in
            var list=selected().filter { $0 != key }; if value { list.append(key) }
            values["participants"] = .array(list.map { .string($0) })
        })
    }
    private func check() throws {
        guard let session=SupabaseService.shared.client.auth.currentSession,
              session.user.id==identity.userID, NovaPersonnelService.sessionID(session.accessToken)==identity.sessionID else { throw NovaKatipFailure.denied }
    }
    private func load(preserveValues: Bool = false) async {
        busy=true; failure=nil; defer { busy=false }
        do {
            try check()
            let data=try await SupabaseService.shared.client.rpc("isg_pilot_module_editor_v1",params:["p_module":PersonnelRPCValue.string(module),"p_company":.id(company),"p_id":.id(record)]).execute().data
            try check(); let result=try JSONDecoder().decode(Envelope.self,from:data)
            if preserveValues, let previous = envelope,
               previous.snapshot.filter({ $0.key != "document_id" }) != result.snapshot.filter({ $0.key != "document_id" }) {
                failure = "Kayıt başka bir yerden değişmiş. Kapatıp yeniden açın."
                return
            }
            envelope=result; if !preserveValues { values=result.snapshot }
            document=result.snapshot["document_id"]?.text ?? ""
        } catch { failure=message(error) }
    }
    private func save(_ action: String, close: Bool) async {
        guard let envelope, !busy else { return }; busy=true; failure=nil
        do {
            let payload: [String: PersonnelRPCValue] = ["module":.string(module),"id":.id(record),"expected":.string(envelope.expected),
                "values":.object(Dictionary(uniqueKeysWithValues:keys.map { ($0,values[$0]?.rpc ?? .null) })),
                "document_id":document.isEmpty ? .null : .string(document)]
            let _: [String: NovaModuleValue] = try await NovaModuleMutationJournal.run(function:"isg_pilot_module_mutate_v1",identity:identity,company:company,action:action,payload:payload,
                rpc:{ function,args in try await SupabaseService.shared.client.rpc(function,params:args).execute().data },validate:check,
                decode:{ try JSONDecoder().decode([String:NovaModuleValue].self,from:$0) })
            busy=false
            if close { dismiss() } else { await load(preserveValues:true) }
        } catch { busy=false; failure=message(error) }
    }
    private func message(_ error: Error) -> String {
        if let e=error as? PostgrestError {
            switch e.message {
            case "VERSION_CONFLICT": return "Kayıt değişmiş. Kapatıp yeniden açarak güncel bilgilerle deneyin."
            case "DEPENDENT_RECORDS": return "Bu plana bağlı tatbikat var. Önce bağlı tatbikatı kaldırın."
            case "RETURN_CONFLICT": return "Teslim bilgileri kayıtlı iadelerle çelişiyor."
            case "ACCESS_DENIED": return "Firma, personel, işyeri veya evrak bu kayda uygun değil."
            default: return "Bilgileri kontrol edin. Kayıt güncellenemedi."
            }
        }
        return "İşlem tamamlanamadı. Bağlantınızı kontrol edip yeniden deneyin."
    }
}

struct NovaModuleManageAction: View {
    let content: () -> AnyView
    let onDone: () -> Void
    @State private var showing = false
    var body: some View {
        NovaButton(label:"Düzenle · Evrak bağla · Sil",symbol:"slider.horizontal.3",variant:.surface) { showing=true }
            .padding(12).frame(maxWidth:.infinity).background(Color.white)
            .sheet(isPresented:$showing,onDismiss:onDone,content:content)
    }
}

private struct NovaModuleDocumentsHost: View {
    let identity: NovaSessionIdentity
    let company: UUID
    let onClose: () -> Void
    @StateObject private var controller = NovaWorkspaceController()
    var body: some View {
        NovaPilotDocumentGate(identity: identity, scope: controller.scope, canWrite: true,
            select: controller.select, currentScope: { controller.scope },
            onBack: onClose, onCompanies: onClose, initialCompany: company)
            .task { await controller.observe() }
    }
}
