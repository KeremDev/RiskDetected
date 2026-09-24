import XCTest
import PDFKit
@testable import RiskDetected

@MainActor final class NovaRiskWizardTests: XCTestCase {
    func testBundledCatalogueDrivesFollowupsScoresAndExports() throws {
        let runtime = try NovaRiskWizardRuntime()
        var view = try runtime.start(firmName: "İşletme <Ş> & 😀", date: "24.09.2026")
        XCTAssertEqual(view.steps.first, "firm")
        XCTAssertTrue(try runtime.sectors("akaryakıt").contains { $0.id == "S139" })
        view = try runtime.act(["type": "sector", "id": "S139"])
        XCTAssertTrue(view.steps.contains("fu:FU-AKY-1"))
        XCTAssertFalse(view.steps.contains("fu:FU-AKY-4"), "LPG tank question waits for the LPG answer")
        view = try runtime.act(["type": "fu", "fid": "FU-AKY-1", "id": "lpg"])
        XCTAssertTrue(view.steps.contains("fu:FU-AKY-4"))
        let result = try runtime.result()
        XCTAssertTrue(result.rows.contains { $0.id == "R-55-20" })
        XCTAssertFalse(result.rows.contains { $0.id == "R-18-02" }, "generic solvent risk is excluded for fuel stations")
        let first = try XCTUnwrap(result.rows.first)
        XCTAssertGreaterThan(first.fk.score, first.rfk.score)
        _ = try runtime.act(["type": "edit", "id": first.id, "key": "fk", "field": "p", "value": 10])
        XCTAssertTrue(try runtime.result().rows.first { $0.id == first.id }?.edited == true)
        for format in ["xlsx", "docx"] {
            let file = try runtime.download(format: format)
            XCTAssertEqual(Array(file.data.prefix(4)), [0x50, 0x4b, 0x03, 0x04])
            XCTAssertTrue(file.name.hasSuffix(".\(format)"))
        }
        let pdf = try XCTUnwrap(PDFDocument(data: runtime.download(format: "pdf").data))
        XCTAssertTrue(pdf.string?.contains("Risk Değerlendirmesi") == true)
    }

    func testEmergencyModeSelectsScenariosCountsTeamsAndExports() throws {
        let runtime = try NovaRiskWizardRuntime()
        var view = try runtime.start(firmName: "Yıldız Akaryakıt", date: "24.09.2026", mode: "emergency")
        XCTAssertEqual(view.mode, "emergency")
        view = try runtime.act(["type": "sector", "id": "S139"])
        view = try runtime.act(["type": "fu", "fid": "FU-AKY-1", "id": "lpg"])
        view = try runtime.act(["type": "emp", "value": 65])
        let emergency = try XCTUnwrap(view.emergency)
        XCTAssertTrue(view.steps.contains("cards") && view.steps.contains("team") && view.steps.last == "summary")
        XCTAssertFalse(view.steps.contains("mgmt"), "risk-only steps stay out of the plan flow")
        let selected = Set(emergency.cards.filter(\.selected).map(\.id))
        XCTAssertTrue(selected.isSuperset(of: ["AD-001", "AD-039", "AD-040", "AD-052", "AD-069"]), "core scenarios are always planned")
        XCTAssertTrue(selected.contains("AD-013"), "LPG answer brings the LPG leak scenario")
        XCTAssertFalse(selected.contains("AD-071"), "a fuel station gets no mine scenario")
        XCTAssertEqual(emergency.teams.roles.map(\.required), [3, 3, 3, 7], "very hazardous, 65 employees: 30 / 30 / 30 and 10 per first aider")
        XCTAssertEqual(emergency.validUntil, "24.09.2028")
        XCTAssertFalse(emergency.text("title").isEmpty)

        view = try runtime.act(["type": "card", "id": "AD-001"])
        XCTAssertTrue(view.emergency?.cards.first { $0.id == "AD-001" }?.selected == true, "a core scenario cannot be switched off")
        view = try runtime.act(["type": "card", "id": "AD-013"])
        XCTAssertTrue(view.emergency?.cards.first { $0.id == "AD-013" }?.selected == false)
        view = try runtime.act(["type": "member", "op": "add", "role": "sondurme", "name": "Ahmet Kaya", "ref": "e1"])
        view = try runtime.act(["type": "member", "op": "add", "role": "kurtarma", "name": "Ayşe Demir"])
        XCTAssertEqual(view.emergency?.teams.roles.first { $0.id == "sondurme" }?.assigned, 1)

        let plan = try runtime.plan()
        XCTAssertEqual(plan.firm.hazardClassId, "high")
        XCTAssertFalse(plan.cards.contains { $0.id == "AD-013" })
        XCTAssertEqual(plan.members.map(\.roleId), ["sondurme", "kurtarma"])
        XCTAssertEqual(plan.members.map { NovaEmergencyWizardSaver.role($0.roleId) }, [.fire, .other])
        XCTAssertEqual(NovaEmergencyWizardSaver.isoDay("4.9.2026"), "2026-09-04")
        for format in ["docx", "cards"] {
            let file = try runtime.download(format: format)
            XCTAssertEqual(Array(file.data.prefix(4)), [0x50, 0x4b, 0x03, 0x04])
            XCTAssertTrue(file.name.hasSuffix(".docx"))
        }
        let pdf = try XCTUnwrap(PDFDocument(data: runtime.download(format: "pdf").data))
        XCTAssertTrue(pdf.string?.contains("Acil Durum Planı") == true)
    }

    func testEmergencyOfficeGetsOnlyCoreScenariosAndSmallTeamRule() throws {
        let runtime = try NovaRiskWizardRuntime()
        _ = try runtime.start(firmName: "", date: "24.09.2026", mode: "emergency")
        let office = try XCTUnwrap(runtime.sectors("yazılım").first)
        _ = try runtime.act(["type": "sector", "id": office.id])
        let view = try runtime.act(["type": "emp", "value": 8])
        let emergency = try XCTUnwrap(view.emergency)
        XCTAssertEqual(Set(emergency.cards.filter(\.selected).map(\.id)), ["AD-001", "AD-039", "AD-040", "AD-052", "AD-069"])
        XCTAssertEqual(emergency.teams.combined?.required, 1, "fewer than 10 employees: one support person covers fire, rescue and protection")
        XCTAssertEqual(emergency.teams.roles.first { $0.id == "ilkyardim" }?.required, 1)
    }

    func testChecklistModeSuggestsTopicsExportsAndPublishesToListelerim() async throws {
        let runtime = try NovaRiskWizardRuntime()
        var view = try runtime.start(firmName: "Deniz Lojistik", date: "24.09.2026", mode: "checklist")
        XCTAssertEqual(view.mode, "checklist")
        XCTAssertEqual(Array(view.steps.suffix(4)), ["purpose", "topics", "items", "summary"])
        XCTAssertFalse(view.steps.contains("method"), "risk-only steps stay out of the checklist flow")
        view = try runtime.act(["type": "sector", "id": "S127"])
        view = try runtime.act(["type": "pick", "kind": "equipment", "id": "E041"])
        view = try runtime.act(["type": "pick", "kind": "equipment", "id": "E051"])
        let checklist = try XCTUnwrap(view.checklist)
        XCTAssertTrue(Set(checklist.topics.map(\.id)).isSuperset(of: ["WAREHOUSE", "FORK", "RACK", "FIRE"]))
        XCTAssertFalse(checklist.topics.contains { $0.id == "LOTO" }, "a forklift does not bring machine lockout checks")
        XCTAssertTrue(checklist.topics.first { $0.id == "FORK" }?.reasons.contains("Denge ağırlıklı forklift") == true)
        XCTAssertFalse(checklist.text("title").isEmpty)
        XCTAssertTrue(try runtime.checklistTopics("iskele").contains { $0.id == "SCAFFOLD" })
        view = try runtime.act(["type": "ckTopic", "id": "BATTERY"])
        view = try runtime.act(["type": "ckCustom", "op": "add", "pack": "FORK", "text": "Forklift anahtarları vardiya sonunda teslim ediliyor mu?"])

        let list = try runtime.checklistList()
        XCTAssertEqual(list.lists.count, 1)
        XCTAssertEqual(list.lists[0].items.count, list.total)
        XCTAssertEqual(list.fromCatalog + list.newCatalog + list.own, list.total)
        XCTAssertGreaterThan(list.newCatalog, 0, "the battery topic comes from the wizard extension")
        for format in ["docx", "xlsx"] {
            let file = try runtime.download(format: format)
            XCTAssertEqual(Array(file.data.prefix(4)), [0x50, 0x4b, 0x03, 0x04])
            XCTAssertEqual(file.name, "Deniz_Lojistik_Kontrol_Listesi_24-09-2026.\(format)")
        }
        let pdf = try XCTUnwrap(PDFDocument(data: runtime.download(format: "pdf").data))
        XCTAssertTrue(pdf.string?.contains("İSG saha kontrol listesi") == true)

        final class Calls {
            var drafted: [String] = []
            var copied: [NovaChecklistItemSelection] = []
            var written: [(code: String, position: Int, section: String)] = []
            var revisions: [Int64] = []
            var published: (revision: Int64, note: String)?
        }
        let calls = Calls()
        let existing = NovaChecklistTemplate(templateCode: "c_old", title: list.title, isProduct: false, isArchived: false, versions: [])
        let client = NovaChecklistClient(catalogue: { _ in throw NovaChecklistFailure.unavailable },
            library: { _, _, _, _ in throw NovaChecklistFailure.unavailable }, templateDetail: { _ in throw NovaChecklistFailure.unavailable },
            templates: { _ in
                guard let title = calls.drafted.last else { return [existing] }
                return [existing, NovaChecklistTemplate(templateCode: "c_new", title: title, isProduct: false, isArchived: false, versions: [
                    NovaChecklistTemplateVersion(version: 1, revision: 0, status: "draft", publishedAt: nil, approvalNote: nil, items: [])])]
            },
            assignments: { _ in [] }, board: { _ in throw NovaChecklistFailure.unavailable }, companies: { [] },
            detail: { _ in throw NovaChecklistFailure.unavailable }, startRun: { _, _, _, _, _, _, _ in nil }, answer: { _, _ in nil },
            uploadEvidence: { _, _ in UUID() }, submit: { _, _, _ in nil }, cancel: { _, _, _ in nil }, revise: { _, _, _, _ in nil },
            draftTemplate: { _, title in calls.drafted.append(title) },
            setItem: { _, _, _, _, _, _, _, _ in XCTFail("the section-aware write is used when the client offers it") },
            copyItems: { _, code, _, revision, items in XCTAssertEqual(code, "c_new"); calls.revisions.append(revision); calls.copied += items },
            reorderItems: { _, _, _, _, _ in }, removeItem: { _, _, _, _, _ in },
            publishTemplate: { _, _, _, revision, note in calls.published = (revision, note) },
            copyTemplate: { _, _, _ in }, assignTemplate: { _, _, _ in }, deactivateAssignment: { _, _ in },
            pendingAnswers: { (0, 0) }, syncPendingAnswers: { (0, 0) },
            setSectionItem: { _, code, _, revision, item, _, _, position, section in
                XCTAssertEqual(item, "w\(position)")
                calls.revisions.append(revision); calls.written.append((code, position, section))
            })
        let codes = try await NovaChecklistWizardSaver.save(runtime: runtime, client: client, company: nil)
        XCTAssertEqual(codes, ["c_new"])
        XCTAssertEqual(calls.drafted, [list.title + " (2)"], "an existing title would reopen that list; the wizard makes a new one")
        XCTAssertEqual(calls.copied.count, list.fromCatalog)
        XCTAssertEqual(calls.copied.first?.sourceTemplateCode, "catalog_dpo_01")
        XCTAssertEqual(calls.written.count, list.newCatalog + list.own)
        XCTAssertTrue(calls.written.contains { $0.section == "Forklift kullanım öncesi kontrolü" })
        XCTAssertEqual(calls.revisions, Array(0..<Int64(calls.revisions.count)), "each template action moves the draft one revision on")
        XCTAssertEqual(calls.published?.revision, Int64(calls.revisions.count))
        XCTAssertEqual(calls.published?.note, list.approvalNote)
        XCTAssertEqual(NovaChecklistWizardSaver.unique("Liste", taken: ["liste", "liste (2)"]), "Liste (3)")
    }
}

