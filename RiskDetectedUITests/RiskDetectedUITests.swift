import XCTest

final class RiskDetectedUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        app?.terminate()
        app = nil
    }

    func testOnboardingPersonalPlanReachesAuth() throws {
        launchApp()

        completeQuestionsToPersonalPlan()
        XCTAssertTrue(waitFor("Hesabımı Oluştur").exists)

        tap("Hesabımı Oluştur")
        XCTAssertTrue(waitFor("Apple ile devam et").exists)
        XCTAssertTrue(waitForOne(["onboarding.auth.google", "Google"]).exists)
        XCTAssertTrue(waitFor("E-posta ile devam et").exists)
    }

    func testTrialInviteAndTimelinePaywallRenderWithAuthBypass() throws {
        launchApp(extraArguments: ["RD_UI_TEST_BYPASS_AUTH"])

        completeQuestionsToPersonalPlan()
        tap("Hesabımı Oluştur")

        tapScrolling("₺0,00'ye dene", timeout: 10)

        XCTAssertTrue(waitFor("onboarding.notification_permission", timeout: 8).exists)
        XCTAssertTrue(waitFor("Şimdi ödeme alınmayacak").exists)
        tap("onboarding.notification_permission.cta")

        XCTAssertTrue(waitFor("Yıllık", timeout: 8).exists)
        XCTAssertTrue(waitFor("Aylık").exists)

        tap("Aylık")
        XCTAssertTrue(app.staticTexts["₺199,90/ay — istediğin zaman iptal"].waitForExistence(timeout: 3))

        tap("Yıllık")
        XCTAssertTrue(app.staticTexts["7 gün ücretsiz, sonra 1.999 TL (166.58/ay)"].waitForExistence(timeout: 3))
    }

    func testMainTabsProfileAndDarkModeRenderWithBypass() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_DARK_MODE"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.profile)
        XCTAssertTrue(waitFor("UI Test Kullanıcı").exists)
        XCTAssertTrue(waitFor("Firmalarım").exists)

        tapTab(.analyses)
        XCTAssertTrue(waitFor("Analizler").exists)

        tapTab(.reports)
        XCTAssertTrue(waitFor("Denetime hazır çıktılar").exists)

        tapTab(.home)
        XCTAssertTrue(waitFor("Saha fotoğrafı yükle").exists)
    }

    func testInAppPaywallClaudePlusAndProRenderWithFreeTier() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_FREE_TIER"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tap("Yükselt")

        XCTAssertTrue(waitFor("İlk haftanız bizden.", timeout: 8).exists)
        XCTAssertTrue(waitFor("Neler dahil?").exists)
        XCTAssertTrue(waitFor("Ücretsiz denemeyi başlat").exists)
        let companyTracking = waitFor("Firma takibi")
        let plusCTA = waitFor("Ücretsiz denemeyi başlat")
        XCTAssertLessThan(companyTracking.frame.maxY, plusCTA.frame.minY)

        tap("Aylık")
        XCTAssertTrue(waitFor("Plus’a abone olun.").exists)
        XCTAssertTrue(waitFor("Aboneliği Başlat").exists)

        tap("in_app_paywall.plus.pro_link")
        XCTAssertTrue(waitFor("Limitsiz Özellikler").exists)
        XCTAssertTrue(waitFor("Tüm Plus özellikleri dahil").exists)
        tap("Aylık")
        XCTAssertTrue(waitFor("Tüm Pro özellikleri aylık ₺499,90 ile.").exists)
        tap("Yıllık")
        XCTAssertTrue(waitFor("Yıllık ₺4.999 ile tüm Pro özellikleri.").exists)
        XCTAssertTrue(waitFor("Plus aboneliğini incele").exists)

        tap("in_app_paywall.pro.plus_link")
        XCTAssertTrue(waitFor("İlk haftanız bizden.").exists)
    }

    func testCompanyPickerV2FieldsRenderWithFixtures() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.profile)
        tapScrolling("Firmalarım")

        XCTAssertTrue(waitFor("Firmalarım").exists)
        XCTAssertTrue(waitFor("QA Aktif Firma").exists)
        XCTAssertTrue(waitFor("Çok Tehlikeli · Bakım Ekibi").exists)

        tap("company_picker.add")
        XCTAssertTrue(waitFor("Yeni firma").exists)
        XCTAssertTrue(waitFor("Firma adı").exists)
        XCTAssertTrue(waitFor("Firma detayları").exists)
        XCTAssertTrue(waitFor("Adres").exists)
        XCTAssertTrue(waitFor("İlgili kişi").exists)
        XCTAssertTrue(waitFor("Departman / ekip").exists)
        XCTAssertTrue(waitFor("Rapor varsayılanları").exists)
        XCTAssertTrue(waitFor("Varsayılan sorumlu").exists)
        XCTAssertTrue(waitFor("Varsayılan termin günü").exists)
    }

    func testCompanyFilterSheetsRenderWithFixtures() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.analyses)
        tap("analysis.company_filter")
        XCTAssertTrue(waitFor("Analiz firma filtresi").exists)
        XCTAssertTrue(waitFor("QA Aktif Firma").exists)
        tap("Pencereyi kapat")

        tapTab(.reports)
        tap("report.company_filter")
        XCTAssertTrue(waitFor("Rapor firma filtresi").exists)
        XCTAssertTrue(waitFor("QA Aktif Firma").exists)
    }

    func testFreeRiskAnalysisTrialDoesNotLockStandardReport() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_FREE_TIER", "RD_UI_TEST_LONG_REPORT_FIELDS", "RD_UI_TEST_REPORT_LOGO"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        app.swipeUp()
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.53)).tap()
        XCTAssertTrue(waitFor("Analiz Sonucu", timeout: 8).exists)

        tapScrolling("Rapor Oluştur", timeout: 10)
        XCTAssertTrue(waitFor("report.settings", timeout: 8).exists)
        XCTAssertTrue(waitFor("Hoş geldin, 1 risk analizi oluşturma hakkını hemen kullan!").exists)
        XCTAssertTrue(waitFor("Tebrikler! Bir tane risk analizi oluşturma hakkı tanımlandı. Hemen deneyebilirsin.").exists)
        XCTAssertTrue(waitFor("Hızlı Uygunsuzluk Raporu, ek bilgi girmeden oluşturulur.").exists)

        tap("report.settings.kind.riskAnalysis")
        XCTAssertTrue(waitFor("Risk analizi PDF oluştur", timeout: 5).exists)
        XCTAssertFalse(app.staticTexts["Bugünkü standart rapor hakkın doldu. Hakların yarın yenilenir."].exists)

        tap("Risk analizi PDF oluştur")
        XCTAssertTrue(waitFor("Önizlemeyi kapat", timeout: 12).exists)
        tap("Önizlemeyi kapat")

        tapScrolling("Rapor Oluştur", timeout: 10)
        XCTAssertTrue(waitFor("report.settings", timeout: 8).exists)
        XCTAssertFalse(app.staticTexts["Hoş geldin, 1 risk analizi oluşturma hakkını hemen kullan!"].exists)
        XCTAssertTrue(waitFor("Bir kez tanımlanan hakkını kullandın. Risk analizi tabloları Plus ile devam eder.").exists)
        XCTAssertTrue(waitFor("Hızlı Uygunsuzluk Raporu, ek bilgi girmeden oluşturulur.").exists)
    }

    private func launchApp(extraArguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_RESET_STATE"] + extraArguments
        app.launchEnvironment["RD_UI_TEST_RESET_STATE"] = "1"
        app.launch()
    }

    private func launchMainApp(extraArguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_MAIN", "RD_UI_TEST_COMPANY_FIXTURES", "RD_UI_TEST_REPORT_FIXTURES"] + extraArguments
        app.launchEnvironment["RD_UI_TEST_MAIN"] = "1"
        app.launchEnvironment["RD_UI_TEST_COMPANY_FIXTURES"] = "1"
        app.launchEnvironment["RD_UI_TEST_REPORT_FIXTURES"] = "1"
        if extraArguments.contains("RD_UI_TEST_DARK_MODE") {
            app.launchEnvironment["RD_UI_TEST_DARK_MODE"] = "1"
        }
        app.launch()
    }

    private func completeQuestionsToPersonalPlan() {
        tap("Başlayalım", timeout: 12)

        tap("Devam")

        tap("A Sınıfı İSG Uzmanı")
        tap("Devam")

        tap("Çok Tehlikeli")
        tap("Devam")

        tap("İnşaat")
        tap("Devam")

        tap("6-15")
        tap("Planımı Hazırla")

        XCTAssertTrue(waitFor("Hesabımı Oluştur", timeout: 12).exists)
    }

    @discardableResult
    private func waitFor(_ identifier: String, timeout: TimeInterval = 6) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)
        var firstExisting: XCUIElement?

        repeat {
            for query in matchingQueries(identifier) {
                for index in 0..<query.count {
                    let element = query.element(boundBy: index)
                    guard element.exists else { continue }
                    if element.isHittable { return element }
                    if firstExisting == nil { firstExisting = element }
                }
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        } while Date() < deadline

        if let firstExisting { return firstExisting }
        XCTFail("Missing accessibility identifier: \(identifier)")
        return app.otherElements[identifier]
    }

    private func waitForOne(_ identifiers: [String], timeout: TimeInterval = 6) -> XCUIElement {
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            for identifier in identifiers {
                for query in matchingQueries(identifier) {
                    for index in 0..<query.count {
                        let element = query.element(boundBy: index)
                        guard element.exists else { continue }
                        if element.isHittable { return element }
                        return element
                    }
                }
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        } while Date() < deadline

        XCTFail("Missing any accessibility identifier: \(identifiers.joined(separator: ", "))")
        return app.otherElements[identifiers.first ?? ""]
    }

    private func matchingQueries(_ identifier: String) -> [XCUIElementQuery] {
        let predicate = NSPredicate(
            format: "identifier == %@ OR label == %@",
            identifier,
            identifier
        )
        return [
            app.buttons.matching(predicate),
            app.otherElements.matching(predicate),
            app.textFields.matching(predicate),
            app.secureTextFields.matching(predicate),
            app.staticTexts.matching(predicate),
            app.images.matching(predicate),
            app.descendants(matching: .any).matching(predicate)
        ]
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 6) {
        let element = waitFor(identifier, timeout: timeout)
        XCTAssertTrue(element.isHittable, "Element is not hittable: \(identifier)")
        element.tap()
    }

    private enum TestTab {
        case home
        case analyses
        case reports
        case profile

        var identifier: String {
            switch self {
            case .home: return "tab.home"
            case .analyses: return "tab.analyses"
            case .reports: return "tab.reports"
            case .profile: return "tab.profile"
            }
        }
    }

    private func tapTab(_ tab: TestTab) {
        tap(tab.identifier, timeout: 8)
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }

    private func tapScrolling(_ identifier: String, timeout: TimeInterval = 8) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for query in matchingQueries(identifier) {
                for index in 0..<query.count {
                    let element = query.element(boundBy: index)
                    guard element.exists else { continue }
                    if element.isHittable {
                        element.tap()
                        return
                    }
                }
            }
            app.swipeUp()
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        } while Date() < deadline

        XCTFail("Element is not hittable after scrolling: \(identifier)")
    }
}
