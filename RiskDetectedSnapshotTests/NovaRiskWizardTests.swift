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
}

