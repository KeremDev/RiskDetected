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

    func testEnglishPDFReportExtractionHasNoTurkishRegulatoryTemplateLeak() throws {
        app = XCUIApplication()
        app.launchArguments = [
            "RD_UI_TEST_PDF_REPORT_LOCALIZATION",
            "RD_UI_TEST_GLOBAL_LOCALIZATION_ENABLED",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_GB",
            "-UIViewAnimationEnabled", "NO",
            "-ApplePersistenceIgnoreState", "YES",
        ]
        app.launchEnvironment["RD_UI_TEST_PDF_REPORT_LOCALIZATION"] = "1"
        app.launchEnvironment["RD_UI_TEST_GLOBAL_LOCALIZATION_ENABLED"] = "1"
        launchPreparedApp()

        let status = app.staticTexts["pdf_report_localization.status"]
        XCTAssertTrue(status.waitForExistence(timeout: 20))
        XCTAssertEqual(status.label, "PDF_REPORT_LOCALIZATION_OK")
    }

    func testFreeTierPaywallUsesRetryWhenStorePriceUnavailable() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_FREE_TIER"])

        tap("Yükselt", timeout: 20)
        XCTAssertTrue(waitFor("in_app_paywall.plus", timeout: 10).exists)
        XCTAssertTrue(waitForOne(["Fiyat yükleniyor...", "Tekrar dene"], timeout: 15).exists)
        XCTAssertFalse(app.staticTexts["₺199,99"].exists)
        XCTAssertFalse(app.staticTexts["₺1.999,99"].exists)

        tap("Tekrar dene", timeout: 15)
        XCTAssertTrue(waitForOne(["Fiyat yükleniyor...", "Tekrar dene"], timeout: 5).exists)
    }

    func testOnboardingPersonalPlanReachesAuth() throws {
        launchApp()

        completeQuestionsToPersonalPlan()
        XCTAssertTrue(waitFor("onboarding.personal_plan.create_account").exists)

        tap("onboarding.personal_plan.create_account")
        XCTAssertTrue(waitFor("Apple ile devam et").exists)
        XCTAssertTrue(waitForOne(["onboarding.auth.google", "Google"]).exists)
        XCTAssertTrue(waitFor("E-posta ile devam et").exists)
    }

    func testTrialInviteAndTimelinePaywallRenderWithAuthBypass() throws {
        launchApp(extraArguments: ["RD_UI_TEST_BYPASS_AUTH"])

        completeQuestionsToPersonalPlan()
        tap("onboarding.personal_plan.create_account")

        XCTAssertTrue(waitFor("Ücretsiz Denemenizi İstiyoruz", timeout: 8).exists)
        XCTAssertTrue(waitFor("Herhangi bir ücret alınmaz.").exists)
        XCTAssertTrue(waitFor("0.00 TL'ye dene").exists)
        XCTAssertTrue(waitFor("onboarding.trial_invite.dismiss").exists)
        XCTAssertTrue(waitFor("onboarding.trial_invite.continue_free").exists)
        tapScrolling("onboarding.trial_invite.cta", timeout: 10)

        XCTAssertTrue(waitFor("onboarding.notification_permission", timeout: 8).exists)
        XCTAssertTrue(waitFor("Deneme süren bitmeden sana haber verelim").exists)
        XCTAssertTrue(waitFor("Plan, teklif ve uygulama hatırlatmaları için bildirimleri aç.").exists)
        XCTAssertTrue(waitFor("Bildirimleri Aç").exists)
        tap("onboarding.notification_permission.cta")

        // Onboarding 11. adım Claude Design paywall akışını kullanır.
        XCTAssertTrue(waitFor("in_app_paywall.plus", timeout: 12).exists)
        XCTAssertTrue(waitFor("PLUS Abonelik Avantajları", timeout: 8).exists)
        XCTAssertTrue(waitFor("in_app_paywall.plan.yearly").exists)
        XCTAssertTrue(waitFor("in_app_paywall.plan.monthly").exists)
        XCTAssertTrue(waitFor("Firma yönetimi").exists)
        XCTAssertTrue(waitFor("Çoklu Fotoğraf Analizi").exists)
        XCTAssertTrue(waitFor("in_app_paywall.restore").exists)
        XCTAssertTrue(waitFor("in_app_paywall.privacy").exists)

        tap("in_app_paywall.terms")
        XCTAssertTrue(waitFor("Yasal Bilgilendirme", timeout: 4).exists)
        XCTAssertTrue(waitFor("Kullanım Koşulları").exists)
        tap("Pencereyi kapat")

        tap("in_app_paywall.plan.monthly")
        XCTAssertTrue(waitFor("in_app_paywall.plan.monthly", timeout: 6).isSelected)
        XCTAssertFalse(app.staticTexts["₺199,99"].waitForExistence(timeout: 1))

        tap("in_app_paywall.plan.yearly")
        XCTAssertTrue(waitFor("in_app_paywall.plan.yearly", timeout: 6).isSelected)
        XCTAssertFalse(app.staticTexts["₺1.999,99"].waitForExistence(timeout: 1))
        XCTAssertTrue(waitForOne(["Fiyat yükleniyor...", "Tekrar dene"], timeout: 12).exists)
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
        tap("onboarding.personal_plan.create_account")

        XCTAssertTrue(waitFor("onboarding.auth", timeout: 8).exists)
        XCTAssertTrue(waitFor("onboarding.auth.apple").exists)
        XCTAssertTrue(waitFor("onboarding.auth.google").exists)
        XCTAssertTrue(waitFor("E-posta ile devam et").exists)
        XCTAssertTrue(waitFor("onboarding.auth.sign_in_existing").exists)
    }

    func testEnglishOnboardingUsesRoleAndRequiresExplicitSafetyProfile() throws {
        launchApp(extraArguments: englishLaunchArguments)

        XCTAssertTrue(waitFor("onboarding.splash", timeout: 12).exists)
        tap("onboarding.splash.start")
        XCTAssertTrue(waitFor("onboarding.pain_point", timeout: 12).exists)
        tap("onboarding.pain.continue")

        XCTAssertTrue(waitFor("onboarding.role", timeout: 8).exists)
        XCTAssertFalse(exists("A Sınıfı İSG Uzmanı", timeout: 1))
        XCTAssertFalse(exists("OSGB", timeout: 1))
        XCTAssertFalse(isEnabled("onboarding.role.continue"))

        tap("onboarding.role.safety_professional")
        XCTAssertTrue(isEnabled("onboarding.role.continue"))
        tap("onboarding.role.continue")

        XCTAssertTrue(waitFor("onboarding.safety_profile", timeout: 8).exists)
        XCTAssertTrue(waitFor("Choose your safety terminology").exists)
        XCTAssertTrue(waitFor("Select the terminology used for your work. This changes wording in analyses and reports; it does not certify legal compliance.").exists)
        XCTAssertTrue(waitFor("You can change this for future analyses in Profile.").exists)
        XCTAssertTrue(waitFor("International").exists)
        XCTAssertTrue(waitFor("UK").exists)
        XCTAssertTrue(waitFor("US").exists)
        XCTAssertTrue(waitFor("AU").exists)
        XCTAssertTrue(waitFor("CA").exists)
        XCTAssertFalse(isEnabled("onboarding.safety_profile.continue"))

        tap("onboarding.safety_profile.en-intl-generic-v1")
        XCTAssertTrue(isEnabled("onboarding.safety_profile.continue"))
    }

    func testEnglishInternationalMainHidesTurkishJurisdictionUI() throws {
        launchMainApp(
            extraArguments: [
                "RD_UI_TEST_PHOTO_TRAY_WITH_PHOTOS",
            ] + englishLaunchArguments
        )

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        XCTAssertFalse(exists("OSGB", timeout: 1))
        XCTAssertFalse(exists("A Sınıfı", timeout: 1))

        tap("home.photo_tray.primary")
        XCTAssertTrue(waitFor("analysis_sector_picker", timeout: 8).exists)
        let continueButton = waitFor("analysis_sector_continue_button")
        XCTAssertEqual(continueButton.label, "Continue")
        XCTAssertFalse(exists("Deva and", timeout: 1))
        XCTAssertFalse(exists("Quarter", timeout: 1))
        tap("analysis_sector_chip_construction")
        tap("analysis_sector_continue_button")

        XCTAssertTrue(waitFor("canvas_sheet", timeout: 8).exists)
        XCTAssertFalse(exists("canvas.legislation", timeout: 1))
    }

    func testEnglishMainAccessibilityLayoutAtLargestDynamicType() throws {
        launchMainApp(
            extraArguments: englishLaunchArguments + [
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            ]
        )

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        XCTAssertTrue(waitFor("tab.quick_scan").isHittable)
        tapTab(.profile)
        XCTAssertTrue(waitFor("profile.root", timeout: 8).exists)
        XCTAssertTrue(waitFor("profile.row.preferences").isHittable)
    }

    func testEnglishPseudolocalizationKeepsPrimaryNavigationReachable() throws {
        launchMainApp(
            extraArguments: englishLaunchArguments + [
                "-NSDoubleLocalizedStrings", "YES",
                "-UIPreferredContentSizeCategoryName",
                "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
            ]
        )

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        XCTAssertTrue(waitFor("tab.quick_scan").isHittable)
        tapTab(.profile)
        XCTAssertTrue(waitFor("profile.root", timeout: 8).exists)
        XCTAssertTrue(waitFor("profile.row.preferences").isHittable)
    }

    func testSafetyProfilePairwiseReleaseMatrix() throws {
        struct Scenario {
            let profileID: String
            let title: String
            let language: String
            let locale: String
            let tierArgument: String?
            let tierTitle: String
            let dark: Bool
            let accessibilityText: Bool
        }

        let scenarios = [
            Scenario(
                profileID: "tr-tr-current-v1",
                title: "Türkiye",
                language: "tr",
                locale: "tr_TR",
                tierArgument: "RD_UI_TEST_FREE_TIER",
                tierTitle: "FREE",
                dark: false,
                accessibilityText: false
            ),
            Scenario(
                profileID: "en-intl-generic-v1",
                title: "International",
                language: "en",
                locale: "en_GB",
                tierArgument: nil,
                tierTitle: "Plus",
                dark: false,
                accessibilityText: false
            ),
            Scenario(
                profileID: "en-gb-generic-v1",
                title: "UK",
                language: "en",
                locale: "en_GB",
                tierArgument: "RD_UI_TEST_PRO_TIER",
                tierTitle: "Pro",
                dark: true,
                accessibilityText: true
            ),
            Scenario(
                profileID: "en-us-generic-v1",
                title: "US",
                language: "en",
                locale: "en_US",
                tierArgument: "RD_UI_TEST_FREE_TIER",
                tierTitle: "Free",
                dark: false,
                accessibilityText: true
            ),
            Scenario(
                profileID: "en-au-generic-v1",
                title: "AU",
                language: "en",
                locale: "en_AU",
                tierArgument: nil,
                tierTitle: "Plus",
                dark: true,
                accessibilityText: false
            ),
            Scenario(
                profileID: "en-ca-generic-v1",
                title: "CA",
                language: "en",
                locale: "en_CA",
                tierArgument: "RD_UI_TEST_PRO_TIER",
                tierTitle: "Pro",
                dark: false,
                accessibilityText: true
            ),
        ]

        for scenario in scenarios {
            var arguments = [
                "-AppleLanguages", "(\(scenario.language))",
                "-AppleLocale", scenario.locale,
            ]
            if scenario.language == "en" {
                arguments.append("RD_UI_TEST_GLOBAL_LOCALIZATION_ENABLED")
            }
            if let tierArgument = scenario.tierArgument {
                arguments.append(tierArgument)
            }
            if scenario.dark {
                arguments.append("RD_UI_TEST_DARK_MODE")
            }
            if scenario.accessibilityText {
                arguments += [
                    "-UIPreferredContentSizeCategoryName",
                    "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge",
                ]
            }

            launchMainApp(
                extraArguments: arguments,
                environment: [
                    "RD_UI_TEST_SAFETY_PROFILE_ID": scenario.profileID,
                ]
            )

            XCTAssertTrue(
                waitFor("root.main", timeout: 10).exists,
                scenario.profileID
            )
            tapTab(.profile)
            XCTAssertTrue(waitFor("profile.root", timeout: 8).exists)
            XCTAssertTrue(
                exists(scenario.tierTitle, timeout: 3),
                "\(scenario.profileID) tier \(scenario.tierTitle)"
            )

            if scenario.language == "en" {
                tapScrolling("profile.row.preferences", timeout: 8)
                let selected = waitFor(
                    "profile.preference.\(scenario.title)",
                    timeout: 8
                )
                XCTAssertEqual(
                    (selected.value as? String)?.lowercased(),
                    "selected",
                    scenario.profileID
                )
            } else {
                XCTAssertTrue(exists("İSG Uzmanı · A Sınıfı", timeout: 3))
                XCTAssertFalse(exists("Choose your safety terminology", timeout: 1))
            }
        }
    }

    func testOnboardingSplashClassicDesignRenderAndStart() throws {
        launchApp()

        XCTAssertTrue(waitFor("onboarding.splash", timeout: 12).exists)
        XCTAssertTrue(waitFor("Profesyonel İSG Asistanı").exists)
        XCTAssertTrue(waitFor("onboarding.splash.subtitle").exists)
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

    func testHomeMultiPhotoSlotsRenderForPaidFixture() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_OPEN_PHOTO_TRAY"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        XCTAssertTrue(waitFor("Saha fotoğrafları").exists)
        XCTAssertTrue(waitFor("0/3").exists)
        XCTAssertTrue(waitFor("home.photo_tray").exists)
        XCTAssertTrue(waitFor("home.photo_slot.1").exists)
        XCTAssertTrue(waitFor("home.photo_slot.3").exists)
        XCTAssertFalse(exists("home.photo_slot.4", timeout: 1))
    }

    func testEnglishPaidPhotoTrayShowsThreeSlotsAndTwoPhotos() throws {
        launchMainApp(
            extraArguments: englishLaunchArguments + [
                "RD_UI_TEST_LIGHT_MODE",
                "RD_UI_TEST_PHOTO_TRAY_WITH_PHOTOS",
            ]
        )

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        XCTAssertTrue(waitFor("Field photos").exists)
        XCTAssertTrue(waitFor("2/3").exists)
        XCTAssertTrue(waitFor("home.photo_slot.1").exists)
        XCTAssertTrue(waitFor("home.photo_slot.2").exists)
        XCTAssertTrue(waitFor("home.photo_slot.3").exists)
        XCTAssertFalse(exists("home.photo_slot.4", timeout: 1))
        XCTAssertTrue(waitFor("Continue to analysis").exists)
        XCTAssertFalse(exists("Saha fotoğrafları", timeout: 1))
        XCTAssertFalse(exists("Analize geç", timeout: 1))
    }

    func testEnglishProfileLogoActionDoesNotLeakTurkish() throws {
        launchMainApp(
            extraArguments: englishLaunchArguments + ["RD_UI_TEST_LIGHT_MODE"]
        )

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.profile)
        tapScrolling("profile.row.info", timeout: 8)
        XCTAssertTrue(waitFor("Profile Information", timeout: 8).exists)
        XCTAssertTrue(waitFor("Add logo").exists)
        XCTAssertTrue(waitFor("Select logo").exists)
        XCTAssertFalse(exists("Logo ekle", timeout: 1))
        XCTAssertFalse(exists("Logo seç", timeout: 1))
    }

    func testQuickScanButtonOpensPhotoTray() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tap("tab.quick_scan")
        XCTAssertTrue(waitFor("home.photo_tray").exists)
        XCTAssertTrue(waitFor("home.photo_slot.3").exists)
    }

    func testFreeLockedPhotoSlotOpensPaywall() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_FREE_TIER", "RD_UI_TEST_OPEN_PHOTO_TRAY"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        XCTAssertTrue(waitFor("Çoklu fotoğraf özelliği için hesabınızı yükseltin").exists)
        tap("home.photo_slot.2")
        XCTAssertTrue(waitFor("in_app_paywall.plus", timeout: 10).exists)
    }

    func testHomePhotoUploadReturnsToTrayAfterAnnotation() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_DIRECT_HOME_PHOTO_PICK"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tap("home.photo_tray.open")
        XCTAssertTrue(waitFor("İşaretlemeyi kaydet", timeout: 8).exists)

        tap("İşaretlemeyi kaydet", timeout: 8)

        XCTAssertTrue(waitFor("home.photo_tray", timeout: 10).exists)
        XCTAssertTrue(waitFor("1/3").exists)
        XCTAssertTrue(waitFor("Analize geç").exists)
    }

    func testPhotoTrayWithExistingPhotosFixtureRenders() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_PHOTO_TRAY_WITH_PHOTOS"])

        XCTAssertTrue(waitFor("home.photo_tray", timeout: 10).exists)
        XCTAssertTrue(waitFor("2/3").exists)
        XCTAssertTrue(waitFor("home.photo_slot.1").exists)
        XCTAssertTrue(waitFor("home.photo_slot.2").exists)
        XCTAssertTrue(waitFor("home.photo_slot.3").exists)
        XCTAssertTrue(waitFor("Analize geç").exists)
    }

    func testAnalyzingProgressOverlayRendersWithPercentAndSteps() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_OPEN_ANALYZING"])

        XCTAssertTrue(waitFor("analysis.loading", timeout: 10).exists)
        XCTAssertTrue(waitFor("analysis.progress.percent", timeout: 4).exists)
        XCTAssertTrue(waitFor("Görüntü kalitesi okunuyor").exists)
        XCTAssertTrue(waitFor("Bulgular yapılandırılıyor").exists)
        XCTAssertFalse(app.staticTexts["Netlik ve görüntü okunabilirliği kontrol ediliyor"].waitForExistence(timeout: 0.5))
        XCTAssertTrue(waitFor("3 fotoğraf").exists)
        XCTAssertFalse(app.staticTexts["100"].waitForExistence(timeout: 0.5))
        XCTAssertTrue(waitFor("Bağlantı tekrar deneniyor", timeout: 6).exists)
    }

    func testAnalyzingProgressCompletesIntoResult() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_OPEN_ANALYZING_COMPLETES"])

        XCTAssertTrue(waitFor("analysis.loading", timeout: 10).exists)
        XCTAssertTrue(waitFor("analysis.progress.percent", timeout: 4).exists)
        XCTAssertTrue(waitFor("Sonuç hazırlanıyor", timeout: 8).exists)
        XCTAssertTrue(waitFor("Analiz Sonucu", timeout: 12).exists)
    }

    func testE2ERealThreePhotoAnalysisCompletes() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["RD_E2E_REAL_3_PHOTO_ANALYSIS"] == "1" else {
            throw XCTSkip("Set RD_E2E_REAL_3_PHOTO_ANALYSIS=1 to run the real Supabase 3-photo analysis gate.")
        }
        let email = environment["RD_E2E_EMAIL"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let password = environment["RD_E2E_PASSWORD"] ?? ""
        guard !email.isEmpty, !password.isEmpty else {
            throw XCTSkip("RD_E2E_EMAIL and RD_E2E_PASSWORD are required for the real Supabase E2E gate.")
        }

        app = XCUIApplication()
        app.launchArguments = [
            "RD_E2E_REAL_3_PHOTO_ANALYSIS",
            "-UIViewAnimationEnabled", "NO",
            "-ApplePersistenceIgnoreState", "YES",
        ]
        app.launchEnvironment["RD_E2E_REAL_3_PHOTO_ANALYSIS"] = "1"
        app.launchEnvironment["RD_E2E_EMAIL"] = email
        app.launchEnvironment["RD_E2E_PASSWORD"] = password
        launchPreparedApp()

        XCTAssertTrue(waitFor("analysis.loading", timeout: 75).exists)
        XCTAssertTrue(waitFor("analysis.progress.percent", timeout: 8).exists)
        XCTAssertTrue(waitFor("3 fotoğraf", timeout: 8).exists)
        XCTAssertFalse(app.staticTexts["100"].waitForExistence(timeout: 0.5))
        XCTAssertTrue(waitFor("Analiz Sonucu", timeout: 420).exists)
    }

    func testAnnotateFromPhotoTrayUsesSaveCopy() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_PHOTO_TRAY_WITH_PHOTOS"])

        XCTAssertTrue(waitFor("home.photo_tray", timeout: 10).exists)
        tap("home.photo_slot.1")
        XCTAssertTrue(waitFor("İşaretlemeyi kaydet", timeout: 8).exists)
        XCTAssertFalse(app.buttons["İşaretli alanları analiz et"].waitForExistence(timeout: 1))
    }

    func testResultFindingDeleteButtonRequiresConfirmation() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapScrolling("home.recent_analysis.3. Kat şantiye girişi", timeout: 8)
        XCTAssertTrue(waitFor("Analiz Sonucu", timeout: 8).exists)

        tapScrolling("result.finding.1.delete", timeout: 10)
        XCTAssertTrue(waitFor("Bulgu silinsin mi?", timeout: 4).exists)
        XCTAssertTrue(waitFor("Bu bulgu yeni raporlara dahil edilmeyecek. Eski rapor snapshotları ve audit kaydı korunur.", timeout: 4).exists)
        tap("Vazgeç", timeout: 4)
        XCTAssertFalse(exists("Bulgu silinsin mi?", timeout: 1))
    }

    func testResultFindingShowsFieldVerificationBadge() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_OPEN_RESULT"])

        XCTAssertTrue(waitFor("Analiz Sonucu", timeout: 8).exists)
        XCTAssertTrue(waitFor("result.finding.1.field_verification", timeout: 8).exists)
        XCTAssertTrue(waitFor("Saha teyidi", timeout: 4).exists)
    }

    func testResultFindingDetailUsesSourcePhoto() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_OPEN_RESULT"])

        XCTAssertTrue(waitFor("Analiz Sonucu", timeout: 8).exists)
        tapScrolling("result.finding.1.card", timeout: 10)
        XCTAssertTrue(waitFor("result.detail.photo_index.3", timeout: 8).exists)
        XCTAssertTrue(waitFor("Foto 3", timeout: 4).exists)
        XCTAssertTrue(waitFor("result.detail.close", timeout: 4).exists)
    }

    func testFindingEditorSheetRendersCompactControls() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_OPEN_RESULT", "RD_UI_TEST_OPEN_FINDING_EDITOR"])

        XCTAssertTrue(waitFor("Bulguyu Düzenle", timeout: 10).exists)
        XCTAssertTrue(waitFor("Tolerans dışı").exists)
        XCTAssertTrue(waitFor("finding_editor.fk_probability").exists)
        XCTAssertTrue(waitFor("finding_editor.fk_frequency").exists)
        XCTAssertTrue(waitFor("finding_editor.fk_severity").exists)
        XCTAssertTrue(waitFor("finding_editor.m5_probability").exists)
        XCTAssertTrue(waitFor("finding_editor.m5_severity").exists)
        XCTAssertTrue(waitFor("Düzeltici önlem").exists)
        XCTAssertTrue(waitFor("Önleyici kontrol").exists)
        XCTAssertTrue(waitFor("finding_editor.delete").exists)
        XCTAssertTrue(waitFor("finding_editor.cancel").exists)
        XCTAssertTrue(waitFor("finding_editor.save").exists)
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

    /// Deneme zaman çizelgesi yalnızca App Store gerçek bir tanıtım teklifi döndürdüğünde
    /// görünüyor; simülatörde bu hiç olmadığı için ekranın bu hâli test edilemiyordu.
    /// `RD_UI_TEST_FORCE_TRIAL_TIMELINE` (yalnızca DEBUG) sadece görünümü açar.
    func testTrialTimelinePaywallShowsFeatureMarqueeInsteadOfGrid() throws {
        launchMainApp(extraArguments: [
            "RD_UI_TEST_FREE_TIER",
            "RD_UI_TEST_FORCE_TRIAL_TIMELINE",
        ])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tap("Yükselt")

        XCTAssertTrue(waitFor("in_app_paywall.plus", timeout: 8).exists)
        XCTAssertTrue(waitFor("in_app_paywall.trial_timeline", timeout: 8).exists)
        XCTAssertTrue(waitFor("Ücretsiz Deneme Nasıl Çalışır?", timeout: 4).exists)
        XCTAssertTrue(waitFor("Bugün", timeout: 4).exists)
        XCTAssertTrue(waitFor("5. Gün", timeout: 4).exists)
        XCTAssertTrue(waitFor("7. Gün", timeout: 4).exists)

        // Özellikler artık kayan şeritte; "Bugün" altındaki ızgara kaldırıldı.
        XCTAssertTrue(waitFor("in_app_paywall.feature_marquee", timeout: 6).exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "trial-timeline-with-feature-marquee"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testInAppPaywallClaudePlusAndProRenderWithFreeTier() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_FREE_TIER"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tap("Yükselt")

        XCTAssertTrue(waitFor("in_app_paywall.plus", timeout: 8).exists)
        XCTAssertTrue(waitFor("PLUS Abonelik Avantajları", timeout: 8).exists)
        XCTAssertTrue(waitForOne(["Fiyat yükleniyor...", "Tekrar dene"], timeout: 15).exists)
        XCTAssertFalse(app.staticTexts["₺199,99"].exists)
        XCTAssertFalse(app.staticTexts["₺1.999,99"].exists)
        XCTAssertTrue(waitFor("Firma yönetimi").exists)
        XCTAssertTrue(waitFor("Günlük analiz").exists)

        let multiPhotoAnalysis = waitFor("Çoklu Fotoğraf Analizi")
        let plusCTA = waitForOne(["Fiyat yükleniyor...", "Tekrar dene"], timeout: 12)
        XCTAssertLessThan(multiPhotoAnalysis.frame.maxY, plusCTA.frame.minY)

        tap("in_app_paywall.terms")
        XCTAssertTrue(waitFor("Yasal Bilgilendirme", timeout: 4).exists)
        XCTAssertTrue(waitFor("Kullanım Koşulları").exists)
        tap("Pencereyi kapat")

        tap("in_app_paywall.plan.monthly")
        XCTAssertTrue(waitFor("PLUS Abonelik Avantajları").exists)
        XCTAssertTrue(waitForOne(["Fiyat yükleniyor...", "Tekrar dene"], timeout: 12).exists)

        tapScrolling("in_app_paywall.plus.pro_link", timeout: 12)
        XCTAssertTrue(waitFor("in_app_paywall.pro", timeout: 8).exists)
        XCTAssertTrue(waitFor("PRO Abonelik Avantajları").exists)
        XCTAssertTrue(waitFor("Öncelikli destek").exists)
        XCTAssertTrue(waitFor("Limitsiz").exists)

        tapScrolling("in_app_paywall.pro.plus_link", timeout: 12)
        XCTAssertTrue(waitFor("in_app_paywall.plus", timeout: 8).exists)
        XCTAssertTrue(waitFor("PLUS Abonelik Avantajları").exists)
    }

    func testPaywallYearlyMonthlyToggleForPlusAndPro() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_FREE_TIER"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tap("Yükselt")

        XCTAssertTrue(waitFor("in_app_paywall.plus", timeout: 8).exists)
        XCTAssertEqual(waitFor("in_app_paywall.plan.yearly", timeout: 8).label, "Yıllık")

        tap("in_app_paywall.plan.monthly")
        XCTAssertTrue(waitFor("in_app_paywall.plan.monthly", timeout: 6).isSelected)

        tap("in_app_paywall.plan.yearly")
        XCTAssertTrue(waitFor("in_app_paywall.plan.yearly", timeout: 6).isSelected)

        tapScrolling("in_app_paywall.plus.pro_link", timeout: 12)
        XCTAssertTrue(waitFor("in_app_paywall.pro", timeout: 8).exists)

        tap("in_app_paywall.plan.monthly")
        XCTAssertTrue(waitFor("in_app_paywall.plan.monthly", timeout: 6).isSelected)

        tap("in_app_paywall.plan.yearly")
        XCTAssertTrue(waitFor("in_app_paywall.plan.yearly", timeout: 6).isSelected)
        XCTAssertTrue(waitForOne(["Fiyat yükleniyor...", "Tekrar dene"], timeout: 12).exists)
    }

    func testCaptureAccountCreationFollowUpScreens() throws {
        launchApp(extraArguments: [
            "RD_UI_TEST_BYPASS_AUTH",
            "-UIViewAnimationEnabled", "NO",
            "-ApplePersistenceIgnoreState", "YES",
        ])

        completeQuestionsToPersonalPlan()
        tap("onboarding.personal_plan.create_account")

        XCTAssertTrue(waitFor("onboarding.trial_invite", timeout: 10).exists)
        XCTAssertTrue(waitFor("Ücretsiz Denemenizi İstiyoruz").exists)
        attachScreenshot("01-uygulamayi-dene")

        tapScrolling("onboarding.trial_invite.cta", timeout: 10)
        XCTAssertTrue(waitFor("onboarding.notification_permission", timeout: 8).exists)
        XCTAssertTrue(waitFor("Deneme süren bitmeden sana haber verelim").exists)
        attachScreenshot("02-bildirimleri-ac")

        tap("onboarding.notification_permission.cta")
        XCTAssertTrue(waitFor("in_app_paywall.plus", timeout: 12).exists)
        XCTAssertTrue(waitFor("PLUS Abonelik Avantajları", timeout: 8).exists)
        XCTAssertTrue(waitFor("in_app_paywall.plan.yearly").exists)
        XCTAssertTrue(waitFor("in_app_paywall.plan.monthly").exists)
        attachScreenshot("03-onboarding-paywall")
    }

    func testCapturePostOnboardingAndPaywallScreens() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_FREE_TIER", "RD_UI_TEST_LIGHT_MODE"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        attachScreenshot("01-ana-ekran")

        tapTab(.analyses)
        XCTAssertTrue(waitFor("Analizler").exists)
        attachScreenshot("02-analizler")

        tapTab(.reports)
        XCTAssertTrue(waitFor("Denetime hazır çıktılar").exists)
        attachScreenshot("03-raporlar")

        tapTab(.profile)
        XCTAssertTrue(waitFor("UI Test Kullanıcı").exists)
        attachScreenshot("04-profil")

        tapTab(.home)
        tap("Yükselt", timeout: 10)
        XCTAssertTrue(waitFor("in_app_paywall.plus", timeout: 8).exists)
        XCTAssertTrue(waitForOne(["Fiyat yükleniyor...", "Tekrar dene"], timeout: 15).exists)
        attachScreenshot("05-plus-yillik-paywall")

        tap("in_app_paywall.plan.monthly")
        XCTAssertTrue(waitFor("PLUS Abonelik Avantajları").exists)
        attachScreenshot("06-plus-aylik-paywall")

        tapScrolling("in_app_paywall.plus.pro_link", timeout: 12)
        XCTAssertTrue(waitFor("in_app_paywall.pro", timeout: 8).exists)
        attachScreenshot("07-pro-yillik-paywall")

        tap("in_app_paywall.plan.monthly")
        XCTAssertTrue(waitFor("PRO Abonelik Avantajları").exists)
        attachScreenshot("08-pro-aylik-paywall")

        launchMainApp(extraArguments: ["RD_UI_TEST_OPEN_PHOTO_TRAY", "RD_UI_TEST_LIGHT_MODE"])
        XCTAssertTrue(waitFor("home.photo_tray", timeout: 10).exists)
        attachScreenshot("09-fotograf-secimi")

        launchMainApp(extraArguments: ["RD_UI_TEST_OPEN_RESULT", "RD_UI_TEST_LIGHT_MODE"])
        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        attachScreenshot("10-analiz-sonucu")
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
        tap("report.archive.filter.standard")
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

        XCTAssertTrue(waitFor("document_preview.close", timeout: 20).exists)
        tap("document_preview.close")
        XCTAssertTrue(waitFor("UI Test Rapor Kaynağı", timeout: 8).exists)
    }

    func testNotificationSettingsSheetStaysSimpleWithBypass() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        tapTab(.profile)
        tapScrolling("profile.row.notifications")

        XCTAssertTrue(waitFor("Bildirimler kapalı").exists)
        XCTAssertTrue(waitFor("Açtığında analiz sonuçları, raporlar, deneme süresi ve uygulama hatırlatmalarını alabilirsin.").exists)
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
        XCTAssertTrue(waitFor("document_preview.close", timeout: 12).exists)
        tap("document_preview.close")

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

    func testHardUpdatePolicyBlocksAppWithUpdateCTA() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_FORCE_HARD_UPDATE"])

        XCTAssertTrue(waitFor("app_release.hard_update", timeout: 10).exists)
        XCTAssertTrue(waitFor("Güncelleme gerekli").exists)
        XCTAssertTrue(waitFor("Yeni sürüm mevcut. Devam etmek için uygulamayı güncelleyin.").exists)
        XCTAssertTrue(waitFor("App Store'da güncelle").exists)
    }

    func testSoftUpdatePolicyCanBeDismissed() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_FORCE_SOFT_UPDATE"])

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        XCTAssertTrue(waitFor("app_release.soft_update", timeout: 10).exists)
        XCTAssertTrue(waitFor("Yeni sürüm hazır").exists)
        tap("Daha sonra")
        XCTAssertFalse(exists("app_release.soft_update", timeout: 2))
    }

    func testHomeTextAnalysisEntryPointsAreRemoved() throws {
        launchMainApp()

        XCTAssertTrue(waitFor("root.main", timeout: 10).exists)
        XCTAssertTrue(waitFor("Saha fotoğrafları").exists)
        XCTAssertFalse(exists("home.mode.text", timeout: 1))
        XCTAssertFalse(exists("home.text_input", timeout: 1))
    }

    func testActiveAnalysisSectorPickerRequiresSelectionBeforeCanvas() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_PHOTO_TRAY_WITH_PHOTOS"])

        XCTAssertTrue(waitFor("home.photo_tray", timeout: 10).exists)
        tap("Analize geç")

        XCTAssertTrue(waitFor("Analiz kapsamını seç", timeout: 8).exists)
        XCTAssertFalse(isEnabled("Devam et"))

        tap("analysis_sector_chip_construction")
        XCTAssertTrue(isEnabled("Devam et"))
        tap("Devam et")

        XCTAssertTrue(waitFor("canvas_sheet", timeout: 8).exists)
        XCTAssertTrue(waitFor("Odaklı Analiz").exists)
    }

    func testActiveAnalysisSectorSingleSelectionReplacesPreviousChoice() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_PHOTO_TRAY_WITH_PHOTOS"])

        XCTAssertTrue(waitFor("home.photo_tray", timeout: 10).exists)
        tap("Analize geç")

        XCTAssertTrue(waitFor("Analiz kapsamını seç", timeout: 8).exists)
        tap("analysis_sector_chip_construction")
        tap("analysis_sector_chip_manufacturing")
        tap("Devam et")

        XCTAssertTrue(waitFor("canvas_sheet", timeout: 8).exists)
    }

    func testActiveAnalysisSectorFullGridShowsLogisticsWarehouseChip() throws {
        launchMainApp(extraArguments: ["RD_UI_TEST_PHOTO_TRAY_WITH_PHOTOS"])

        XCTAssertTrue(waitFor("home.photo_tray", timeout: 10).exists)
        tap("Analize geç")

        XCTAssertTrue(waitFor("Analiz kapsamını seç", timeout: 8).exists)
        XCTAssertTrue(waitFor("analysis_sector_chip_logistics_warehouse", timeout: 8).exists)
        tap("analysis_sector_chip_logistics_warehouse")
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

    private var englishLaunchArguments: [String] {
        [
            "RD_UI_TEST_GLOBAL_LOCALIZATION_ENABLED",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
        ]
    }

    private func launchMainApp(
        extraArguments: [String] = [],
        environment: [String: String] = [:]
    ) {
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
        for argument in extraArguments where argument.hasPrefix("RD_UI_TEST_") {
            app.launchEnvironment[argument] = "1"
        }
        if extraArguments.contains("RD_UI_TEST_DARK_MODE") {
            app.launchEnvironment["RD_UI_TEST_DARK_MODE"] = "1"
        }
        if extraArguments.contains("RD_UI_TEST_DEVICE_INTEGRITY_WARNING") {
            app.launchEnvironment["RD_UI_TEST_DEVICE_INTEGRITY_WARNING"] = "1"
        }
        for (key, value) in environment {
            app.launchEnvironment[key] = value
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

        XCTAssertTrue(waitFor("onboarding.personal_plan.create_account", timeout: 12).exists)
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
                    if hasUsableHitFrame(element), element.isHittable { return element }
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
                        if hasUsableHitFrame(element), element.isHittable { return element }
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

    private func hasUsableHitFrame(_ element: XCUIElement) -> Bool {
        let frame = element.frame
        let appFrame = app.frame
        guard !frame.isNull,
              !frame.isInfinite,
              !frame.isEmpty,
              frame.midX.isFinite,
              frame.midY.isFinite,
              !appFrame.isEmpty
        else {
            return false
        }
        return appFrame.contains(CGPoint(x: frame.midX, y: frame.midY))
    }

    private func tap(_ identifier: String, timeout: TimeInterval = 6) {
        let element = waitFor(identifier, timeout: timeout)
        XCTAssertTrue(element.isHittable, "Element is not hittable: \(identifier)")
        element.tap()
    }

    private func tapButton(_ label: String, timeout: TimeInterval = 8) {
        let predicate = NSPredicate(format: "identifier == %@ OR label == %@", label, label)
        let button = app.buttons.matching(predicate).firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: timeout), "Missing button: \(label)")
        XCTAssertTrue(button.isHittable, "Button is not hittable: \(label)")
        button.tap()
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

    private func attachScreenshot(_ name: String) {
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tapScrolling(_ identifier: String, timeout: TimeInterval = 8) {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for query in matchingQueries(identifier) {
                for index in 0..<query.count {
                    let element = query.element(boundBy: index)
                    guard element.exists else { continue }
                    if hasUsableHitFrame(element), element.isHittable {
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
