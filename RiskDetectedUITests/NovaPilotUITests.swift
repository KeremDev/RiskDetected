import XCTest

final class NovaPilotUITests: XCTestCase {
    /// The six code boxes used to be six focused fields that took the keyboard
    /// from each other every frame, so no digit ever landed and sign-up stopped.
    func testVerificationCodeAcceptsTypedDigits() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_NOVA_LOGIN", "RD_UI_TEST_LIGHT_MODE"]
        app.launch()
        let email = app.textFields["E-posta adresin"]
        XCTAssertTrue(email.waitForExistence(timeout: 20))
        email.tap(); email.typeText("harness@example.com")
        let password = app.secureTextFields["Şifren"]
        password.tap(); password.typeText("harness1")
        app.buttons["Mail ile devam et"].tap()
        let code = app.textFields["Doğrulama kodu"]
        XCTAssertTrue(code.waitForExistence(timeout: 8))
        code.typeText("123456")
        XCTAssertTrue(app.staticTexts["Hesabın hazır"].waitForExistence(timeout: 8))
        #endif
    }

    func testWizardExpansionVisualAudit() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_CHECKLIST_PICKER", "RD_UI_TEST_LIGHT_MODE"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Kontrol nerede yapılacak?"].waitForExistence(timeout: 20))
        let independent = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Bağımsız kontrol")).firstMatch
        XCTAssertTrue(independent.waitForExistence(timeout: 5)); independent.tap()
        XCTAssertTrue(app.staticTexts["Kontrol listesini seç"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Sektör")).firstMatch.exists)
        XCTAssertTrue(app.textFields["nova.checklist.start.search"].exists)
        let checklist = XCTAttachment(screenshot: app.screenshot())
        checklist.name = "İSGADA-checklist-filter-wizard"
        checklist.lifetime = .keepAlways; add(checklist)
        app.terminate()

        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_REPORT_CENTER", "RD_UI_TEST_LIGHT_MODE"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Rapor Merkezi"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Yeni rapor oluştur"].exists)
        XCTAssertTrue(app.buttons["Arşiv"].exists)
        let report = XCTAttachment(screenshot: app.screenshot())
        report.name = "İSGADA-report-center"
        report.lifetime = .keepAlways; add(report)
        let companyReport = app.buttons["report.center.kind.company"]
        XCTAssertTrue(companyReport.waitForExistence(timeout: 5)); companyReport.tap()
        XCTAssertTrue(app.staticTexts["Kapsam ve dönem"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Neyi raporlamak istiyorsunuz?"].exists)
        app.buttons["Devam"].tap()
        XCTAssertTrue(app.staticTexts["Raporda neler yer alsın?"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.textFields["Örn. Yönetici notu"].exists)
        let reportWizard = XCTAttachment(screenshot: app.screenshot())
        reportWizard.name = "İSGADA-report-content-wizard"
        reportWizard.lifetime = .keepAlways; add(reportWizard)
        app.terminate()

        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_COMPANY_WIZARD", "RD_UI_TEST_LIGHT_MODE"]
        app.launch()
        XCTAssertTrue(app.staticTexts["1 / 3"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Firma bilgileri"].exists)
        let company = XCTAttachment(screenshot: app.screenshot())
        company.name = "İSGADA-company-fullscreen-wizard"
        company.lifetime = .keepAlways; add(company)
        app.terminate()
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testCompanyDetailShowsCompactSectionsWithoutTrackingCard() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_COMPANY_PROGRESS", "RD_UI_TEST_LIGHT_MODE"]
        app.launch(); defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["Firma Detayı"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.descendants(matching: .any)["company.progress"].waitForExistence(timeout: 8))
        let progressSegments = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "company.progress.segment."))
        XCTAssertEqual(progressSegments.count, 10)
        let riskSegment = app.buttons["company.progress.segment.risk"]
        XCTAssertTrue(riskSegment.exists)
        for _ in 0..<3 where !riskSegment.isHittable { app.swipeUp() }
        XCTAssertTrue(riskSegment.isHittable); riskSegment.tap()
        XCTAssertFalse(app.buttons["Dosya Ekle"].exists)
        XCTAssertFalse(app.buttons["Evrak Takibi"].exists)
        XCTAssertFalse(app.staticTexts["Evrak süreleri"].exists)
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Personel,")).firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["company.section.nonconformities"].waitForExistence(timeout: 8))

        let top = XCTAttachment(screenshot: app.screenshot())
        top.name = "İSGADA-company-detail-progress"
        top.lifetime = .keepAlways
        add(top)

        XCTAssertFalse(app.staticTexts["Firma Takibi"].exists)
        let inspections = app.buttons["company.section.inspections"]
        for _ in 0..<10 where !inspections.exists { app.swipeUp() }
        XCTAssertTrue(inspections.exists); inspections.tap()
        XCTAssertTrue(app.buttons["equipment.inspection.new"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "equipment.stat.")).firstMatch.exists)
        XCTAssertFalse(app.staticTexts["Süreçler ve Takip"].exists)

        let bottom = XCTAttachment(screenshot: app.screenshot())
        bottom.name = "İSGADA-company-detail-tracking-bottom"
        bottom.lifetime = .keepAlways
        add(bottom)
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testPeriodicControlUsesCompactAccordion() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_PERIODIC", "RD_UI_TEST_LIGHT_MODE"]
        app.launch(); defer { app.terminate() }

        let company = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "equipment.company.")).firstMatch
        XCTAssertTrue(company.waitForExistence(timeout: 20)); company.tap()
        XCTAssertTrue(app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "equipment.stat.")).firstMatch.waitForExistence(timeout: 8))
        let addButton = app.buttons["equipment.inspection.new"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 8)); addButton.tap()
        let serials = app.staticTexts.matching(NSPredicate(format: "label == %@", "KRN-001"))
        XCTAssertTrue(serials.firstMatch.waitForExistence(timeout: 8))
        guard let serial = serials.allElementsBoundByIndex.min(by: { $0.frame.minY < $1.frame.minY }) else {
            XCTFail("No equipment choice")
            return
        }
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: serial.frame.midX, dy: serial.frame.midY)).tap()

        XCTAssertTrue(app.descendants(matching: .any)["equipment.task.performed"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.descendants(matching: .any)["equipment.task.due"].exists)
        XCTAssertTrue(app.staticTexts["1 / 3"].exists)
        app.buttons["Devam"].tap()
        XCTAssertTrue(app.staticTexts["2 / 3"].waitForExistence(timeout: 5))
        app.buttons["Devam"].tap()
        XCTAssertTrue(app.staticTexts["3 / 3"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Kontrolü kaydet"].exists)
        XCTAssertFalse(app.buttons["Düzenle"].exists)
        XCTAssertFalse(app.buttons["Envanterden çıkar"].exists)

        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "İSGADA-periodic-control-accordion"
        shot.lifetime = .keepAlways
        add(shot)
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testCompanyCardExposesDirectLogoPickerAndLargePopupCloseTarget() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW"]
        app.launch(); defer { app.terminate() }
        let company = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "nova.company.")).firstMatch
        XCTAssertTrue(company.waitForExistence(timeout: 20)); company.tap()
        XCTAssertTrue(app.buttons["company.logo.picker"].waitForExistence(timeout: 5))
        let logo = XCTAttachment(screenshot: app.screenshot()); logo.name = "İSGADA-company-direct-logo-picker"; logo.lifetime = .keepAlways; add(logo)
        app.buttons["company.edit"].tap()
        let close = app.buttons["nova.popup.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(close.frame.width, 47)
        XCTAssertGreaterThanOrEqual(close.frame.height, 47)
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "İSGADA-company-editor"; shot.lifetime = .keepAlways; add(shot)
        close.tap()
        XCTAssertTrue(app.buttons["company.edit"].waitForExistence(timeout: 5))
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testDirectPersonnelSheetPreservesCompanyAccordion() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW"]
        app.launch(); defer { app.terminate() }
        let company = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "nova.company.")).firstMatch
        XCTAssertTrue(company.waitForExistence(timeout: 20)); company.tap()
        let section = app.buttons["company.section.personnel"]
        XCTAssertTrue(section.waitForExistence(timeout: 5)); section.tap()
        XCTAssertTrue(app.textFields["personnel.search"].waitForExistence(timeout: 5))
        let create = app.buttons["personnel.add"]
        XCTAssertTrue(create.waitForExistence(timeout: 5)); create.tap()
        XCTAssertTrue(app.textFields["personnel.name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.textFields["personnel.job"].exists)
        XCTAssertTrue(app.buttons["nova.popup.close"].exists)
        let popup = XCTAttachment(screenshot: app.screenshot()); popup.name = "İSGADA-centered-personnel-popup"; popup.lifetime = .keepAlways; add(popup)
        app.buttons["nova.popup.close"].tap()
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Personeller"].exists)
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testDirectorySearchAndPersonnelSheet() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW"]
        app.launch(); defer { app.terminate() }
        let company = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "nova.company.")).firstMatch
        XCTAssertTrue(company.waitForExistence(timeout: 20)); company.tap()
        for _ in 0..<5 { if app.buttons["company.directory.workplaces"].exists { break }; app.swipeUp() }
        app.buttons["company.directory.workplaces"].tap()
        XCTAssertTrue(app.textFields["directory.search"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Merkez"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["W-hidden-internal-code"].exists)
        XCTAssertTrue(app.buttons["Bilgi geçmişi"].exists)
        let directory = XCTAttachment(screenshot: app.screenshot()); directory.name = "İSGADA-compact-directory"; directory.lifetime = .keepAlways; add(directory)
        let search = app.textFields["directory.search"]
        search.tap(); search.typeText("bulunamayan")
        XCTAssertTrue(app.staticTexts["Aramanızla eşleşen kayıt yok."].waitForExistence(timeout: 5))
        app.buttons["nova.popup.close"].tap()
        app.buttons["company.section.personnel"].tap()
        let add = app.buttons["personnel.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 5)); add.tap()
        XCTAssertTrue(app.textFields["personnel.name"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["personnel.save"].isEnabled)
        app.buttons["personnel.save"].tap()
        XCTAssertTrue(app.staticTexts["personnel.message"].exists)
        let name = app.textFields["personnel.name"]
        name.tap(); name.typeText("Deneme")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.48)).tap()
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.keyboards.firstMatch)
        waitForExpectations(timeout: 3)
        XCTAssertEqual(name.value as? String, "Deneme")
        let form = XCTAttachment(screenshot: app.screenshot()); form.name = "İSGADA-personnel-sheet"; form.lifetime = .keepAlways; self.add(form)
        app.buttons["nova.popup.close"].tap()
        XCTAssertTrue(app.buttons["personnel.add"].waitForExistence(timeout: 5))
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testConfirmedCompanySuccessAutoDismisses() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW"]
        app.launch(); defer { app.terminate() }
        let create = app.buttons["nova.pilot.company.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 20)); create.tap()
        let name = app.textFields["nova.pilot.company.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5)); name.tap(); name.typeText("Yeni Firma")
        let sector = app.textFields["nova.pilot.company.sector"]
        sector.tap(); sector.typeText("Metal\n")
        app.buttons["nova.pilot.company.submit"].tap()
        let popup = app.descendants(matching: .any).matching(identifier: "nova.success").firstMatch
        XCTAssertTrue(popup.waitForExistence(timeout: 3))
        let shot = XCTAttachment(screenshot: app.screenshot()); shot.name = "İSGADA-success"; shot.lifetime = .keepAlways; add(shot)
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: popup)
        waitForExpectations(timeout: 5)
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testCompactCompanyAndPersonnelScreens() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_DARK_MODE"]
        app.launch()
        defer { app.terminate() }
        let create = app.buttons["nova.pilot.company.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 20))
        XCTAssertFalse(app.staticTexts["Panele dön"].exists)
        let companyRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "nova.company.")).firstMatch
        XCTAssertTrue(companyRow.exists)
        create.tap()
        let name = app.textFields["nova.pilot.company.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["nova.pilot.company.submit"].isEnabled)
        app.buttons["nova.pilot.company.submit"].tap()
        XCTAssertTrue(app.staticTexts["nova.pilot.company.error"].waitForExistence(timeout: 3))
        name.tap(); name.typeText("Yeni Firma")
        XCTAssertTrue(app.buttons["nova.pilot.company.submit"].isEnabled)
        let sector = app.textFields["nova.pilot.company.sector"]
        sector.tap(); sector.typeText("Metal")
        XCTAssertTrue(app.buttons["nova.pilot.company.submit"].isEnabled)
        let form = XCTAttachment(screenshot: app.screenshot()); form.name = "İSGADA-company-form"; form.lifetime = .keepAlways; add(form)
        app.buttons["nova.popup.close"].tap()
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "nova.company.")).firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Firma Detayı"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["company.section.personnel"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["company.section.info"].exists)
        let company = XCTAttachment(screenshot: app.screenshot()); company.name = "İSGADA-company-summary"; company.lifetime = .keepAlways; add(company)
        app.buttons["company.section.personnel"].tap()
        let person = app.buttons["personnel.row.00000000-0000-4000-8000-000000000004"]
        XCTAssertTrue(person.waitForExistence(timeout: 5)); person.tap()
        XCTAssertTrue(app.buttons["personnel.back"].isHittable)
        let archive = app.buttons["personnel.detail.archive"]
        XCTAssertTrue(archive.waitForExistence(timeout: 5)); archive.tap()
        XCTAssertTrue(app.buttons["personnel.archive.confirm"].waitForExistence(timeout: 5))
        app.buttons["personnel.archive.cancel"].tap()
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }
    func testPilotDesignAndUnavailableCompanyState() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_PILOT", "RD_UI_TEST_LIGHT_MODE"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.otherElements["nova.pilot.root"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Özet verileri henüz bağlı değil."].exists)
        app.buttons["nova.home.assistant"].tap()
        XCTAssertTrue(app.alerts["İSGADA pilot"].waitForExistence(timeout: 5))
        app.alerts.buttons["Tamam"].tap()
        app.buttons["nova.tab.companies"].tap()
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH %@", "Yeni tasarım hazır.")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["nova.pilot.company.create"].exists)
        XCTAssertFalse(app.buttons["Firma ekle / düzenle"].exists)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "İSGADA-pilot-unavailable-company-state"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["nova.tab.profile"].tap()
        XCTAssertTrue(app.scrollViews["profile.root"].waitForExistence(timeout: 5))
        #else
        throw XCTSkip("Requires the private NOVA_PILOT_BUILD configuration")
        #endif
    }

    func testNonPilotRetainsLegacyRoot() throws {
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_LIGHT_MODE"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.otherElements["root.main"].waitForExistence(timeout: 20))
        XCTAssertFalse(app.otherElements["nova.pilot.root"].exists)
    }
}

/// Screenshot-only audit of the current analysis surfaces. The review build
/// supplies deterministic fixture data and never writes to a live account.
final class NovaDesignAuditUITests: XCTestCase {
    private let analysisID = "00000000-0000-4000-8000-000000000006"

    func testLegacyAnalysisOpensFromSavedFindingsWithoutProjection() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = [
            "RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_AUDIT_ANALYSIS",
            "RD_UI_TEST_LEGACY_ANALYSIS_DETAIL", "RD_UI_TEST_RESULT_HUB_MISSING", "RD_UI_TEST_LIGHT_MODE"
        ]
        app.launch()
        defer { app.terminate() }

        let row = app.buttons["analysis.list.row.\(analysisID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        row.tap()
        XCTAssertTrue(app.staticTexts["UI Test Saha Analizi"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts[
            "Bu eski analiz kayıtlı bulgularından gösteriliyor; bazı ek öneri bölümleri bulunmayabilir."
        ].exists)
        XCTAssertTrue(app.buttons["analysis.detail.section.risk_analysis"].label.contains("3"))
        XCTAssertTrue(app.buttons["analysis.detail.section.expert_recommendations"].label.contains("2"))
        XCTAssertFalse(app.buttons["analysis.detail.select.all"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "İSGADA-legacy-analysis-fallback"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testAnalysisResultAndSectionSurfaces() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_AUDIT_ANALYSIS", "RD_UI_TEST_LIGHT_MODE"]
        app.launch()
        defer { app.terminate() }

        let row = app.buttons["analysis.list.row.\(analysisID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        capture(app, name: "01-analysis-list")
        row.tap()
        XCTAssertTrue(app.staticTexts["Analiz Sonucu"].waitForExistence(timeout: 10))
        capture(app, name: "02-analysis-result-risk")
        XCTAssertTrue(app.buttons["analysis.detail.method.fine_kinney"].exists)
        XCTAssertFalse(app.buttons["analysis.detail.select.all"].exists)
        XCTAssertFalse(app.buttons["analysis.detail.section.approved_notebook"].exists)

        app.buttons["analysis.detail.report"].tap()
        XCTAssertTrue(app.buttons["analysis.report.run"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["analysis.detail.select.all"].exists)
        capture(app, name: "02b-analysis-report-options")
        app.buttons["nova.popup.close"].tap()

        let finding = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "analysis.finding.")).firstMatch
        XCTAssertTrue(finding.waitForExistence(timeout: 5))
        finding.tap()
        XCTAssertTrue(app.staticTexts["Bulgu Detayı"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Korkuluk eksik"].exists)
        sleep(1) // Let the full-screen push finish before the visual audit capture.
        capture(app, name: "04-analysis-finding-detail")

        app.buttons["analysis.finding.file"].tap()
        XCTAssertTrue(app.staticTexts["Uygunsuzluk oluştur"].waitForExistence(timeout: 5))
        capture(app, name: "04b-analysis-filing-company")
        let company = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Örnek Metal A.Ş.")).firstMatch
        XCTAssertTrue(company.waitForExistence(timeout: 5))
        company.tap()
        let create = app.buttons["analysis.file.run"]
        XCTAssertTrue(create.waitForExistence(timeout: 5))
        XCTAssertTrue(create.isEnabled)
        create.tap()
        XCTAssertTrue(app.staticTexts["Bulgu Detayı"].waitForExistence(timeout: 5))

        app.buttons["analysis.finding.detail.back"].tap()

        for section in ["expert_recommendations", "training_recommendations"] {
            let tab = app.buttons["analysis.detail.section.\(section)"]
            XCTAssertTrue(tab.waitForExistence(timeout: 5), "Missing analysis section tab: \(section)")
            tab.tap()
            capture(app, name: "03-analysis-\(section)")
        }
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    func testFindingDetailSurface() throws {
        #if NOVA_PILOT_BUILD
        let app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_NOVA_REVIEW", "RD_UI_TEST_AUDIT_FINDING", "RD_UI_TEST_LIGHT_MODE"]
        app.launch()
        defer { app.terminate() }

        let row = app.buttons["nonconformity.row.\(analysisID)"]
        XCTAssertTrue(row.waitForExistence(timeout: 20))
        capture(app, name: "05-findings-list")
        row.tap()
        XCTAssertTrue(app.staticTexts["Kayıt detayı"].waitForExistence(timeout: 10))
        capture(app, name: "06-finding-detail")
        #else
        throw XCTSkip("Requires private pilot build")
        #endif
    }

    #if NOVA_PILOT_BUILD
    private func capture(_ app: XCUIApplication, name: String, file: StaticString = #filePath, line: UInt = #line) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    #endif
}
