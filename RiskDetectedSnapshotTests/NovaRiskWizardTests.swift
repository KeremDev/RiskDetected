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
}
