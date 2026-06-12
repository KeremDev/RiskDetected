import CryptoKit
import Foundation
import Security
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

    func testFreeTierPlusPurchaseCTAStarts() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_FREE_TIER"])

        tap("Yükselt", timeout: 20)
        XCTAssertTrue(waitFor("in_app_paywall.plus", timeout: 10).exists)
        XCTAssertTrue(waitFor("in_app_paywall.cta.ready", timeout: 10).exists)

        tap("in_app_paywall.cta", timeout: 10)
        RunLoop.current.run(until: Date().addingTimeInterval(3))
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
        XCTAssertTrue(waitFor("₺0,00'ye dene").exists)
        XCTAssertTrue(waitFor("Geri yükle").exists)
        XCTAssertTrue(waitFor("Kullanım Şartları").exists)
        XCTAssertTrue(waitFor("Gizlilik Politikası").exists)

        tap("Kullanım Şartları")
        XCTAssertTrue(waitFor("Yasal Bilgilendirme", timeout: 4).exists)
        XCTAssertTrue(waitFor("Kullanım Koşulları").exists)
        tap("Pencereyi kapat")

        tap("Aylık")
        XCTAssertTrue(app.staticTexts["₺199,99/ay — istediğin zaman iptal"].waitForExistence(timeout: 3))

        tap("Yıllık")
        XCTAssertTrue(waitFor("7 gün ücretsiz, sonra ₺1.999,99 (₺166,67/ay)", timeout: 3).exists)
    }

    func testOnboardingAllQuestionScreensAndAuthEmailPanelRender() throws {
        launchApp()

        XCTAssertTrue(waitFor("onboarding.splash", timeout: 12).exists)
        tap("onboarding.splash.start")

        XCTAssertTrue(waitFor("onboarding.pain_point").exists)
        XCTAssertTrue(waitFor("Saatlerce süren rapor yazımı.").exists)
        tap("Devam")

        XCTAssertTrue(waitFor("onboarding.certificate").exists)
        tap("onboarding.certificate.a")
        tap("Devam")

        XCTAssertTrue(waitFor("onboarding.hazard").exists)
        tap("onboarding.hazard.critical")
        tap("onboarding.hazard.high")
        tap("Devam")

        XCTAssertTrue(waitFor("onboarding.sector").exists)
        XCTAssertTrue(waitFor("Birden fazla seçebilirsin. Her analiz öncesinde, o fotoğrafı hangi sektör kapsamında değerlendirmek istediğini ayrıca soracağız.").exists)
        tap("onboarding.sector.construction")
        tap("onboarding.sector.manufacturing")
        tap("onboarding.sector.mining")
        tap("Devam")

        XCTAssertTrue(waitFor("onboarding.frequency").exists)
        tap("onboarding.frequency.6_15")
        tap("Planımı Hazırla")

        XCTAssertTrue(waitFor("onboarding.loading", timeout: 8).exists)
        XCTAssertTrue(waitFor("onboarding.personal_plan", timeout: 12).exists)
        tap("Hesabımı Oluştur")

        XCTAssertTrue(waitFor("onboarding.auth", timeout: 8).exists)
        XCTAssertTrue(waitFor("onboarding.auth.apple").exists)
        XCTAssertTrue(waitFor("onboarding.auth.google").exists)
        XCTAssertTrue(waitFor("E-posta ile devam et").exists)
        XCTAssertTrue(waitFor("onboarding.auth.sign_in_existing").exists)
    }

    func testOnboardingSplashClassicDesignRenderAndStart() throws {
        launchApp()

        XCTAssertTrue(waitFor("onboarding.splash", timeout: 12).exists)
        XCTAssertTrue(waitFor("Profesyonel İSG Asistanı").exists)
        XCTAssertTrue(waitFor("Fotoğraf çek; yapay zekâ uygunsuzlukları otomatik tespit etsin ve raporunu anında oluştursun.").exists)
        XCTAssertTrue(waitFor("onboarding.splash.preview_phone").exists)
        XCTAssertTrue(waitFor("onboarding.splash.progress").exists)
        XCTAssertTrue(waitFor("onboarding.splash.chip.detection").exists)
        XCTAssertTrue(waitFor("onboarding.splash.chip.preparing").exists)
        XCTAssertTrue(waitFor("onboarding.splash.skip").exists)

        tap("onboarding.splash.start")
        XCTAssertTrue(waitFor("onboarding.pain_point").exists)
    }

    func testOnboardingSplashSkipShowsConfirmation() throws {
        launchApp()

        XCTAssertTrue(waitFor("onboarding.splash", timeout: 12).exists)
        tap("onboarding.splash.skip")

        XCTAssertTrue(waitFor("onboarding.skip_confirmation").exists)
        XCTAssertTrue(waitFor("Sana özel sonuçlar veremeyeceğiz").exists)
        XCTAssertTrue(waitFor("Cevaplamaya devam et").exists)
        XCTAssertTrue(waitFor("Yine de atla").exists)
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

    func testProfileDarkModePreferencesCanSwitchTheme() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_DARK_MODE"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.profile)
        XCTAssertTrue(waitFor("profile.root").exists)
        XCTAssertTrue(waitFor("profile.hero.card").exists)
        XCTAssertTrue(waitFor("profile.row.notifications").exists)
        XCTAssertTrue(waitFor("profile.row.companies").exists)
    }

    func testInAppPaywallClaudePlusAndProRenderWithFreeTier() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_FREE_TIER"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tap("Yükselt")

        XCTAssertTrue(waitFor("İlk haftanız bizden.", timeout: 8).exists)
        XCTAssertTrue(waitFor("Neler dahil?").exists)
        XCTAssertTrue(waitFor("Ücretsiz denemeyi başlat", timeout: 15).exists)
        XCTAssertFalse(app.staticTexts["Seçili abonelik paketi şu an alınamadı. İnternet bağlantını kontrol edip tekrar dene."].exists)
        let companyTracking = waitFor("Firma takibi")
        let plusCTA = waitFor("Ücretsiz denemeyi başlat")
        XCTAssertLessThan(companyTracking.frame.maxY, plusCTA.frame.minY)

        tap("Şartlar")
        XCTAssertTrue(waitFor("Yasal Bilgilendirme", timeout: 4).exists)
        XCTAssertTrue(waitFor("Kullanım Koşulları").exists)
        tap("Pencereyi kapat")

        tap("Aylık")
        XCTAssertTrue(waitFor("Plus’a abone olun.").exists)
        XCTAssertTrue(waitFor("Aboneliği Başlat").exists)

        tap("in_app_paywall.plus.pro_link")
        XCTAssertTrue(waitFor("Limitsiz Özellikler").exists)
        XCTAssertTrue(waitFor("Tüm Plus özellikleri dahil").exists)
        tap("Aylık")
        XCTAssertTrue(waitFor("Tüm Pro özellikleri aylık ₺499,99 ile.").exists)
        tap("Yıllık")
        XCTAssertTrue(waitFor("Yıllık ₺4.999,99 ile tüm Pro özellikleri.").exists)
        XCTAssertTrue(waitFor("Plus aboneliğini incele").exists)

        tap("in_app_paywall.pro.plus_link")
        XCTAssertTrue(waitFor("İlk haftanız bizden.").exists)
    }

    func testPaywallYearlyMonthlyToggleForPlusAndPro() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_FREE_TIER"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tap("Yükselt")

        XCTAssertTrue(waitFor("in_app_paywall.plus", timeout: 8).exists)
        tap("Aylık")
        XCTAssertTrue(waitFor("Plus’a abone olun.").exists)
        tap("Yıllık")
        XCTAssertTrue(waitFor("İlk haftanız bizden.").exists)

        tap("in_app_paywall.plus.pro_link")
        XCTAssertTrue(waitFor("in_app_paywall.pro", timeout: 8).exists)
        tap("Aylık")
        XCTAssertTrue(waitFor("Tüm Pro özellikleri aylık ₺499,99 ile.").exists)
        tap("Yıllık")
        XCTAssertTrue(waitFor("Yıllık ₺4.999,99 ile tüm Pro özellikleri.").exists)
    }

    func testCompanyPickerV2FieldsRenderWithFixtures() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.profile)
        tapScrolling("Firmalarım")

        XCTAssertTrue(waitFor("Firmalarım").exists)
        XCTAssertTrue(waitFor("Test Aktif Firma").exists)
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

    func testCompanyManagementAddEditArchiveWithFixtures() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.profile)
        tapScrolling("Firmalarım")

        tap("company_picker.add")
        XCTAssertTrue(waitFor("Yeni firma").exists)
        typeInto("company.editor.name", text: "Test V2 Firma")
        tapScrolling("Az Tehlikeli")
        tapScrolling("Firmayı kaydet")

        XCTAssertTrue(waitFor("Test V2 Firma", timeout: 8).exists)
        XCTAssertTrue(waitFor("Az Tehlikeli").exists)

        tap("Test V2 Firma işlemleri")
        tap("Düzenle")
        clearAndType("company.editor.name", text: "Test V2 Firma Güncel")
        tapScrolling("Firmayı kaydet")

        XCTAssertTrue(waitFor("Test V2 Firma Güncel", timeout: 8).exists)
        tap("Test V2 Firma Güncel işlemleri")
        tap("Arşivle")
        tap("Arşivle")
        XCTAssertFalse(exists("Test V2 Firma Güncel", timeout: 3))
        XCTAssertTrue(waitFor("Test Aktif Firma").exists)
    }

    func testCompanyFilterSheetsRenderWithFixtures() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.analyses)
        tap("analysis.company_filter")
        XCTAssertTrue(waitFor("Analiz firma filtresi").exists)
        XCTAssertTrue(waitFor("Test Aktif Firma").exists)
        tap("Pencereyi kapat")

        tapTab(.reports)
        tap("report.company_filter")
        XCTAssertTrue(waitFor("Rapor firma filtresi").exists)
        XCTAssertTrue(waitFor("Test Aktif Firma").exists)
    }

    func testReportArchiveSearchFilterAndDeleteWithFixtures() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.reports)
        XCTAssertTrue(waitFor("report.root").exists)
        XCTAssertTrue(waitFor("Test Firma Raporu", timeout: 8).exists)

        typeInto("report.archive.search", text: "Test Firma")
        XCTAssertTrue(waitFor("Test Firma Raporu").exists)
        tap("report.archive.filter.Standart")
        XCTAssertTrue(waitFor("Test Firma Raporu").exists)

        longPress("report.archive.row.00000000-0000-0000-0000-00000000A101")
        tap("Raporu sil")
        tap("Raporu sil")
        XCTAssertFalse(exists("Test Firma Raporu", timeout: 3))
    }

    func testReportCreationFromArchiveAnalysisWithFixtures() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.reports)
        XCTAssertTrue(waitFor("report.root").exists)
        tap("report.analysis.row.00000000-0000-0000-0000-00000000A201", timeout: 8)

        XCTAssertTrue(waitFor("report.source_sheet", timeout: 8).exists)
        tap("report.source_sheet.open_settings")
        XCTAssertTrue(waitFor("report.settings", timeout: 8).exists)
        XCTAssertTrue(waitFor("Standart Rapor").exists)
        tap("report.settings.kind.standard")
        tap("Rapor oluştur")

        XCTAssertTrue(waitFor("Önizlemeyi kapat", timeout: 20).exists)
        tap("Önizlemeyi kapat")
        XCTAssertTrue(waitFor("UI Test Rapor Kaynağı", timeout: 8).exists)
    }

    func testNotificationSettingsSheetStaysSimpleWithBypass() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.profile)
        tapScrolling("profile.row.notifications")

        XCTAssertTrue(waitFor("Bildirimler kapalı").exists)
        XCTAssertTrue(waitFor("Açtığında analiz sonucu, rapor hazır olma ve önemli hesap güvenliği bildirimlerini alabilirsin.").exists)
        XCTAssertTrue(waitFor("Bildirimleri aç").exists)
        XCTAssertFalse(exists("Supabase", timeout: 1))
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

    func testProfileAccountDeletionVisibleAndCopyWithBypass() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.profile)
        tapScrolling("profile.row.delete_account")
        XCTAssertTrue(waitFor("Hesabın ve verilerin silinsin mi?").exists)
        XCTAssertTrue(waitFor("Hesabın, profilin, analizlerin, raporların ve saklanan dosyaların kalıcı olarak silinir. Silme işlemi uygulama içinde tamamlanır; e-posta, destek veya web sitesi gerekmez. Aktif App Store aboneliğin varsa iptal ve yönetim işlemleri Apple abonelik ayarlarından yapılır. Bu işlem geri alınamaz.").exists)
        XCTAssertTrue(waitFor("Hesabımı sil / Delete Account").exists)
    }

    func testActiveAnalysisSectorPickerRequiresSelectionBeforeCanvas() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tap("home.mode.text")
        typeInto("home.text_input", text: "Korkuluk eksik, işçi emniyet kemeri kullanmıyor.")
        tap("home.start_scan")

        XCTAssertTrue(waitFor("Analiz kapsamını seç", timeout: 8).exists)
        XCTAssertFalse(isEnabled("Devam et"))

        tap("analysis_sector_chip_construction")
        XCTAssertTrue(isEnabled("Devam et"))
        tap("Devam et")

        XCTAssertTrue(waitFor("canvas_sheet", timeout: 8).exists)
        XCTAssertTrue(waitFor("Odaklı Analiz").exists)
    }

    func testActiveAnalysisSectorSingleSelectionReplacesPreviousChoice() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tap("home.mode.text")
        typeInto("home.text_input", text: "Forklift yaya yoluna girdi, raf istifi yüksek.")
        tap("home.start_scan")

        XCTAssertTrue(waitFor("Analiz kapsamını seç", timeout: 8).exists)
        tap("analysis_sector_chip_construction")
        tap("analysis_sector_chip_manufacturing")
        tap("Devam et")

        XCTAssertTrue(waitFor("canvas_sheet", timeout: 8).exists)
    }

    func testActiveAnalysisSectorCatalogSheetIsSearchable() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tap("home.mode.text")
        typeInto("home.text_input", text: "Depo rampasında zemin kaygan ve forklift trafiği yoğun.")
        tap("home.start_scan")

        XCTAssertTrue(waitFor("Analiz kapsamını seç", timeout: 8).exists)
        tapScrolling("Tüm sektörleri göster", timeout: 10)
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        searchField.tap()
        searchField.typeText("Depo")
        XCTAssertTrue(waitFor("analysis_sector_chip_logistics_warehouse").exists)
        tap("analysis_sector_chip_logistics_warehouse")
        XCTAssertTrue(waitFor("Analiz kapsamını seç", timeout: 8).exists)
        tap("Devam et")
        XCTAssertTrue(waitFor("canvas_sheet", timeout: 8).exists)
    }

    func testProfileShowsDeviceIntegrityWarningWhenFlagged() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_DEVICE_INTEGRITY_WARNING"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.profile)

        XCTAssertTrue(waitFor("profile.device_integrity.warning").exists)
        XCTAssertTrue(waitFor("Cihaz güvenliği uyarısı").exists)
        XCTAssertTrue(waitFor("Bu cihazda güvenliği etkileyebilecek sistem değişikliği sinyalleri var: UI test sinyali.").exists)
    }

    func testRealDeviceSupabasePinnedConnection() async throws {
        let probe = SupabasePinnedConnectionProbe(
            pinnedHost: "ppcrzemgiztzcgddbins.supabase.co",
            pinnedCertificateHashes: ["HfwWBfutNY2LyET3bRUgP6ycpcGnn9SFf/ryhk++v5Y="]
        )
        let session = URLSession(configuration: .ephemeral, delegate: probe, delegateQueue: nil)
        var request = URLRequest(url: try XCTUnwrap(URL(string: "https://ppcrzemgiztzcgddbins.supabase.co/auth/v1/health")))
        request.timeoutInterval = 15

        let (_, response) = try await session.data(for: request)
        let statusCode = try XCTUnwrap((response as? HTTPURLResponse)?.statusCode)
        XCTAssert((200..<500).contains(statusCode), "Unexpected Supabase health status: \(statusCode)")
        XCTAssertEqual(probe.didMatchPinnedCertificate, true)
    }

    private func launchApp(extraArguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = ["RD_UI_TEST_RESET_STATE"] + extraArguments
        app.launchEnvironment["RD_UI_TEST_RESET_STATE"] = "1"
        launchPreparedApp()
    }

    private func launchMainApp(extraArguments: [String] = []) {
        app = XCUIApplication()
        app.launchArguments = [
            "RD_UI_TEST_MAIN",
            "RD_UI_TEST_COMPANY_FIXTURES",
            "RD_UI_TEST_REPORT_FIXTURES",
            "-UIViewAnimationEnabled", "NO",
            "-ApplePersistenceIgnoreState", "YES",
        ] + extraArguments
        app.launchEnvironment["RD_UI_TEST_MAIN"] = "1"
        app.launchEnvironment["RD_UI_TEST_COMPANY_FIXTURES"] = "1"
        app.launchEnvironment["RD_UI_TEST_REPORT_FIXTURES"] = "1"
        if extraArguments.contains("RD_UI_TEST_DARK_MODE") {
            app.launchEnvironment["RD_UI_TEST_DARK_MODE"] = "1"
        }
        if extraArguments.contains("RD_UI_TEST_DEVICE_INTEGRITY_WARNING") {
            app.launchEnvironment["RD_UI_TEST_DEVICE_INTEGRITY_WARNING"] = "1"
        }
        launchPreparedApp()
    }

    private func launchPreparedApp() {
        if app.state != .notRunning {
            app.terminate()
        }
        app.launch()
    }

    private func completeQuestionsToPersonalPlan() {
        tap("onboarding.splash.start", timeout: 12)

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

    private func isEnabled(_ identifier: String, timeout: TimeInterval = 3) -> Bool {
        let element = waitFor(identifier, timeout: timeout)
        return element.isEnabled
    }

    private func exists(_ identifier: String, timeout: TimeInterval = 1.5) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for query in matchingQueries(identifier) {
                if query.firstMatch.exists { return true }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        } while Date() < deadline
        return false
    }

    private func typeInto(_ identifier: String, text: String, timeout: TimeInterval = 6) {
        let element = waitFor(identifier, timeout: timeout)
        XCTAssertTrue(element.isHittable, "Text field is not hittable: \(identifier)")
        element.tap()
        element.typeText(text)
    }

    private func clearAndType(_ identifier: String, text: String, timeout: TimeInterval = 6) {
        let element = waitFor(identifier, timeout: timeout)
        XCTAssertTrue(element.isHittable, "Text field is not hittable: \(identifier)")
        element.tap()
        let currentValue = (element.value as? String) ?? ""
        if !currentValue.isEmpty {
            element.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: currentValue.count))
        }
        element.typeText(text)
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

    private func longPress(_ identifier: String, timeout: TimeInterval = 6) {
        let element = waitFor(identifier, timeout: timeout)
        XCTAssertTrue(element.exists, "Element does not exist: \(identifier)")
        element.press(forDuration: 1.0)
    }

}

private final class SupabasePinnedConnectionProbe: NSObject, URLSessionDelegate, @unchecked Sendable {
    private let pinnedHost: String
    private let pinnedCertificateHashes: Set<String>
    private let lock = NSLock()
    private var matchedPinnedCertificate = false

    var didMatchPinnedCertificate: Bool {
        lock.withLock { matchedPinnedCertificate }
    }

    init(pinnedHost: String, pinnedCertificateHashes: Set<String>) {
        self.pinnedHost = pinnedHost
        self.pinnedCertificateHashes = pinnedCertificateHashes
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.host == pinnedHost,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust
        else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        var trustError: CFError?
        guard SecTrustEvaluateWithError(serverTrust, &trustError),
              certificateHashes(for: serverTrust).contains(where: pinnedCertificateHashes.contains)
        else {
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        lock.withLock {
            matchedPinnedCertificate = true
        }
        completionHandler(.useCredential, URLCredential(trust: serverTrust))
    }

    private func certificateHashes(for trust: SecTrust) -> [String] {
        guard let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else {
            return []
        }

        return certificates.map { certificate in
            let data = SecCertificateCopyData(certificate) as Data
            return Data(SHA256.hash(data: data)).base64EncodedString()
        }
    }
}
