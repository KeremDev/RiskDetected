import Foundation
import JavaScriptCore

// View models decoded from RDBridge (App/WizardAssets/isg_wizard_v6/rd-bridge.js).
struct NovaRiskWizardView: Decodable {
    struct Firm: Decodable { let name: String; let address: String; let employees: String; let date: String }
    struct Sector: Decodable, Identifiable { let id: String; let title: String; let group: String; let nace: [String]; let hazardClass: String? }
    struct Option: Decodable, Identifiable { let id: String; let title: String; let badges: [String]; let selected: Bool; let exclusive: Bool }
    struct Followup: Decodable, Identifiable {
        let id: String; let question: String; let help: String; let multi: Bool; let context: String; let options: [Option]
    }
    struct Pick: Decodable, Identifiable {
        let id: String; let title: String; let subtitle: String; let reasons: [String]; let badges: [String]; let selected: Bool; let detail: String
    }
    struct Picks: Decodable { let suggested: [Pick]; let added: [Pick]; let generic: [Pick]; let allSelected: Bool; let count: Int }
    struct Item: Decodable, Identifiable { let id: String; let title: String; let subtitle: String?; let selected: Bool }
    struct Column: Decodable, Identifiable { let id: String; let title: String; let required: Bool; let residual: Bool; let selected: Bool }

    let steps: [String]
    let firm: Firm
    let hazardClass: String?
    let hazardClassLabel: String
    let hazardClassManual: Bool
    let sectors: [Sector]
    let followups: [Followup]
    let picks: [String: Picks]
    let conditions: [Item]
    let management: [Item]
    let method: String
    let preset: String
    let columns: [Column]
    let rowCount: Int
    let counts: [String: [String: Int]]
    var mode: String?
    var emergency: Emergency?

    /// Acil durum planı modu: bütün metinler ve hesaplar köprüden gelir.
    struct Emergency: Decodable {
        struct Site: Decodable, Identifiable { let id: String; let title: String; let help: String; let selected: Bool }
        struct Card: Decodable, Identifiable {
            let id: String; let title: String; let trigger: String; let mode: String
            let core: Bool; let suggested: Bool; let selected: Bool; let reasons: [String]
        }
        struct Role: Decodable, Identifiable { let id: String; let label: String; let duty: String; let required: Int?; let assigned: Int; let basis: String }
        struct Combined: Decodable { let required: Int; let assigned: Int }
        struct Teams: Decodable {
            let hazardClassLabel: String; let employees: Int?; let validYears: Int?; let small: Bool
            let roles: [Role]; let combined: Combined?; let note: String
        }
        struct Member: Decodable, Identifiable {
            let index: Int; let role: String; let name: String; let title: String; let area: String; let contact: String; let backup: Bool
            var ref: String?
            var id: Int { index }
        }
        struct Field: Decodable, Identifiable { let key: String; let label: String; let value: String; let general: Bool; let card: String; var id: String { key } }
        struct Contact: Decodable, Identifiable { let index: Int; let label: String; let number: String; var id: Int { index } }
        let texts: [String: String]
        let employees: Int?
        let site: [Site]
        let cards: [Card]
        let teams: Teams
        let members: [Member]
        let fields: [Field]
        let contacts: [Contact]
        let gaps: [String]
        let validUntil: String
        func text(_ key: String) -> String { texts[key] ?? "" }
    }
}

/// Acil durum planının belge girdisi (RDEmergency.planInput).
struct NovaEmergencyWizardPlan: Decodable {
    struct Firm: Decodable {
        let name: String; let address: String; let date: String; let validUntil: String; let hazardClassId: String
        let sector: String; let hazardClass: String; let employees: String
    }
    struct SiteField: Decodable { let key: String; let label: String; let value: String }
    struct Card: Decodable, Identifiable {
        let id: String; let title: String; let trigger: String; let mode: String; let core: Bool; let why: [String]
        let before: [String]; let worker: [String]; let team: [String]; let prohibited: [String]; let after: [String]; let reentry: String
        let siteFields: [SiteField]
    }
    struct Member: Decodable { let role: String; let roleId: String; let ref: String?; let name: String; let title: String; let area: String; let contact: String; let backup: Bool }
    let firm: Firm
    let cards: [Card]
    let teams: NovaRiskWizardView.Emergency.Teams
    let members: [Member]
    let gaps: [String]
}

struct NovaRiskWizardSectorHit: Decodable, Identifiable {
    let id: String; let title: String; let subtitle: String; let hazardClass: String?; let hazardClassLabel: String; let selected: Bool
}

struct NovaRiskWizardResult: Decodable {
    struct Score: Decodable { let p: Double?; let f: Double?; let l: Double?; let s: Double; let score: Double; let label: String; let level: String }
    struct Control: Decodable { let hierarchy: String; let label: String; let text: String; let owner: String }
    struct Row: Decodable, Identifiable {
        let id: String; let number: Int; let section: String; let hazard: String; let risk: String; let consequence: String
        let affected: String; let check: String; let reasons: [String]; let owner: String; let legal: [String]; let controls: [Control]
        let fk: Score; let rfk: Score; let m5: Score; let rm5: Score
        let m5Manual: Bool; let rm5Manual: Bool; let edited: Bool; let removed: Bool; let isNew: Bool; let severe: Bool
    }
    let counts: [String: [String: Int]]
    let total: Int
    let removedCount: Int
    let method: String
    let rows: [Row]
}

/// Offline, bundled-only risk wizard (V6 catalogue). The bridge keeps the answers; Swift sends actions and draws views.
/// No JSExport objects, network or storage API; user strings travel as values, never as source.
@MainActor final class NovaRiskWizardRuntime {
    private let context: JSContext
    private let bridge: JSValue
    let catalogVersion: String

    init(bundle: Bundle = .main) throws {
        func asset(_ name: String, _ ext: String) throws -> Data {
            guard let url = bundle.url(forResource: name, withExtension: ext, subdirectory: "WizardAssets/isg_wizard_v6")
                ?? bundle.url(forResource: name, withExtension: ext, subdirectory: "isg_wizard_v6")
                ?? bundle.url(forResource: name, withExtension: ext) else { throw NovaWizardError.unavailable }
            return try Data(contentsOf: url)
        }
        guard let vm = JSContext() else { throw NovaWizardError.unavailable }
        context = vm
        for name in ["rd-xlsx", "rd-report", "rd-engine", "rd-emergency", "rd-bridge"] {
            guard let code = String(data: try asset(name, "js"), encoding: .utf8) else { throw NovaWizardError.unavailable }
            vm.evaluateScript(code)
            if vm.exception != nil { throw NovaWizardError.unavailable }
        }
        guard let data = String(data: try asset("rd-data", "json"), encoding: .utf8),
              let value = vm.objectForKeyedSubscript("RDBridge"), !value.isUndefined else { throw NovaWizardError.unavailable }
        let info = value.invokeMethod("init", withArguments: [data])
        if vm.exception != nil { throw NovaWizardError.unavailable }
        bridge = value
        catalogVersion = info?.forProperty("version")?.toString() ?? ""
    }

    private func call<T: Decodable>(_ method: String, _ arguments: [Any] = [], as type: T.Type) throws -> T {
        let value = bridge.invokeMethod(method, withArguments: arguments)
        if let error = context.exception {
            context.exception = nil
            throw NovaWizardError.invalid(error.toString() ?? "Sihirbaz işlemi tamamlanamadı.")
        }
        guard let object = value?.toObject() else { throw NovaWizardError.unavailable }
        return try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }

    func start(firmName: String, date: String, mode: String = "risk") throws -> NovaRiskWizardView {
        try call("start", [["name": firmName, "date": date, "mode": mode]], as: NovaRiskWizardView.self)
    }
    func plan() throws -> NovaEmergencyWizardPlan { try call("result", as: NovaEmergencyWizardPlan.self) }
    func cards(_ query: String) throws -> [NovaRiskWizardView.Emergency.Card] {
        try call("cards", [query], as: [NovaRiskWizardView.Emergency.Card].self)
    }
    func act(_ action: [String: Any]) throws -> NovaRiskWizardView { try call("act", [action], as: NovaRiskWizardView.self) }
    func view() throws -> NovaRiskWizardView { try call("view", as: NovaRiskWizardView.self) }
    func result() throws -> NovaRiskWizardResult { try call("result", as: NovaRiskWizardResult.self) }
    func sectors(_ query: String) throws -> [NovaRiskWizardSectorHit] { try call("sectors", [query], as: [NovaRiskWizardSectorHit].self) }
    func search(_ kind: String, _ query: String) throws -> [NovaRiskWizardView.Pick] {
        try call("search", [kind, query], as: [NovaRiskWizardView.Pick].self)
    }

    /// Excel and Word are built by rd-report.js (acil durum: rd-emergency.js, "cards" = eylem kartları);
    /// PDF reuses the native CoreText paginator.
    func download(format: String) throws -> NovaWizardDownload {
        if format == "pdf" {
            let blocks = try call("blocks", as: [NovaWizardBlock].self)
            let name = bridge.invokeMethod("fileName", withArguments: ["pdf"])?.toString() ?? "Risk_Degerlendirmesi.pdf"
            return .init(name: name, data: try NovaDocumentWizardRuntime.pdf(blocks: blocks))
        }
        let file = try call("file", [format], as: FileReply.self)
        guard let data = Data(base64Encoded: file.base64) else { throw NovaWizardError.unavailable }
        return .init(name: file.name, data: data)
    }
    private struct FileReply: Decodable { let name: String; let base64: String }
}
