import XCTest
import PDFKit
@testable import RiskDetected

@MainActor final class NovaDocumentWizardTests: XCTestCase {
    func testBundledRuntimeGeneratesWithoutCompanyAndExportsAllFormats() throws {
        let runtime = try NovaDocumentWizardRuntime()
        let preview = try runtime.generate(answers: [:], domain: "risk")
        XCTAssertFalse(preview.rows.isEmpty)
        XCTAssertEqual(runtime.questions.count, 13)
        for format in ["docx", "xlsx"] {
            let file = try runtime.download(format: format)
            XCTAssertEqual(Array(file.data.prefix(4)), [0x50, 0x4b, 0x03, 0x04])
            XCTAssertTrue(file.name.hasSuffix(".\(format)"))
        }
        let file = try runtime.download(format: "pdf")
        let pdf = try XCTUnwrap(PDFDocument(data: file.data))
        XCTAssertGreaterThan(pdf.pageCount, 1)
        let text = try XCTUnwrap(pdf.string)
        XCTAssertTrue(text.contains("Risk Değerlendirmesi Taslağı"))
        XCTAssertTrue(text.contains(preview.content_sha256))
        XCTAssertTrue(text.contains("Revizyon ve imza"))
        try file.data.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("wizard-risk-qa.pdf"))
    }
    func testOptionalWorkplaceAndEmergencyCardsUseSameBundledEngine() throws {
        let runtime = try NovaDocumentWizardRuntime()
        let preview = try runtime.generate(answers: ["scope": ["company_id": "test", "company_name": "İşletme <Ş> & 😀"], "processes": ["gas_evolving_battery_charge"], "energy": ["hydraulic"]], domain: "emergency")
        XCTAssertTrue(preview.rows.contains { $0.id == "R-21-09" })
        XCTAssertTrue(preview.rows.contains { $0.id == "R-16-08" })
        XCTAssertTrue(preview.cards.contains { $0.id == "AD-040" })
        let pdf = try XCTUnwrap(PDFDocument(data: runtime.download(format: "pdf").data))
        XCTAssertTrue(pdf.string?.contains("İşletme") == true)
        XCTAssertTrue(pdf.string?.contains(preview.content_sha256) == true)
    }
}
