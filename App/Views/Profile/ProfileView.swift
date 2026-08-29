import SwiftUI
import PhotosUI
import Supabase
import UIKit
import UserNotifications

struct ProfileView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openURL) private var openURL
    @StateObject private var notifications = NotificationService.shared
    @State private var showPaywall = false
    @State private var showProfileEditor = false
    @State private var showCompanyPicker = false
    @State private var showNotificationSettings = false
    @State private var showDataControls = false
    @State private var showPreferences = false
    @State private var showLegalInfo = false
    @State private var showSupport = false
    @State private var showProfessionalTitlesFromHeader = false
    @State private var profileBadgesSheet: ProfileBadgesSheetItem?
    @State private var isRestoringPurchases = false
    @State private var restoreMessage: String?
    @State private var stats: ProfileStats? = nil
    @State private var professionalProgressSummary: ProfessionalProgressSummary? = nil
    @State private var onboardingSummary: ProfileOnboardingSummary? = nil
    @State private var selectedProfileAvatarItem: PhotosPickerItem?
    @State private var profileAvatarImage: UIImage?
    @State private var isUpdatingProfileAvatar = false
    @State private var profileAvatarError: String?
    @State private var dataActionInProgress: ProfileDataAction?
    @State private var pendingDataAction: ProfileDataAction?
    @State private var dataMessage: String?
    @State private var shouldSignOutAfterDataMessageDismiss = false
    @State private var exportedDataFile: ShareItem?
    @State private var deviceIntegrity = DeviceIntegrityService.assess()
    private var preferredModalColorScheme: ColorScheme {
        app.themePreference.colorScheme ?? colorScheme
    }
    private var profileCardFill: Color {
        colorScheme == .dark ? Color(hex: "#101413") : Color.rdWhite
    }
    private var profileElevatedFill: Color {
        colorScheme == .dark ? Color(hex: "#151A18") : Color.rdWhite
    }
    private var profileLine: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.rdLine
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    profileHeader
                    if RDConfig.Features.professionalProgressEnabled,
                       RDProfessionalProgressLocalizationReview.isAvailable,
                       let professionalProgressSummary {
                        ProfessionalProgressProfileSection(
                            summary: professionalProgressSummary,
                            onRefresh: { await loadProfessionalProgress() }
                        )
                    }
                    if app.currentTier.isPaid { proCard } else { upsellCard }
                    accountList
                    settingsList
                    if deviceIntegrity.isWarning {
                        deviceIntegrityWarningCard
                    }
                    deleteAccountCard
                    signOutCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 0)
                .padding(.bottom, RDTabBar.contentClearance)
            }
        }
        .background(Color.rdPaper)
        .accessibilityIdentifier("profile.root")
        .task {
            await loadStats()
            await loadProfessionalProgress()
            await loadOnboardingSummary()
        }
        .task(id: app.profile?.avatarURL) {
            await loadProfileAvatarImage()
        }
        .onAppear {
            consumePendingProfileDestinationIfNeeded()
        }
        .onChange(of: app.auth.session?.user.id) { _ in
            Task {
                await loadStats()
                await loadProfessionalProgress()
                await loadOnboardingSummary()
                await loadProfileAvatarImage()
            }
        }
        .onChange(of: app.pendingProfileDestination) { _ in
            consumePendingProfileDestinationIfNeeded()
        }
        .onChange(of: selectedProfileAvatarItem) { newItem in
            guard let newItem else { return }
            Task { await handleProfileAvatarSelection(newItem) }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            FreeAwarePaywallView(onClose: { showPaywall = false },
                        onSubscribe: {
                            showPaywall = false
                            Task {
                                await app.auth.refreshProfile()
                                await loadStats()
                            }
                        })
            .preferredColorScheme(preferredModalColorScheme)
        }
        .sheet(isPresented: $showDataControls, onDismiss: cleanupExportedDataFile) {
            ProfileDataControlsSheet(
                stats: stats,
                actionInProgress: dataActionInProgress,
                exportedFile: $exportedDataFile,
                onExport: { runDataAction(.exportData) },
                onDeleteReports: { pendingDataAction = .deleteReports },
                onDeleteAnalyses: { pendingDataAction = .deleteAnalyses },
                onRequestAccountDeletion: { pendingDataAction = .requestAccountDeletion },
                onClose: { showDataControls = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(preferredModalColorScheme)
        }
        .sheet(isPresented: $showProfileEditor) {
            ProfileEditSheet(
                profile: app.profile,
                auth: app.auth,
                appLanguage: app.languagePreference,
                onSaved: {
                    showProfileEditor = false
                },
                onClose: { showProfileEditor = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(preferredModalColorScheme)
        }
        .sheet(isPresented: $showCompanyPicker) {
            CompanyPickerSheet(
                title: RDLocalization.string("localizable.profile.view.firmalarim.720bb423", table: .localizable, fallback: "Firmalarım"),
                accessTier: app.currentTier,
                selectedCompanyID: nil,
                allowNoCompany: false,
                allowsSelection: false,
                onSelect: { _ in },
                onPaywall: {
                    PaywallEventService.shared.beginEntry(
                        at: .profileCompanyPicker,
                        currentTier: app.currentTier,
                        targetTier: .plus
                    )
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                        showPaywall = true
                    }
                }
            )
            .presentationDetents(CompanyPickerSheet.presentationDetents(for: app.currentTier, allowNoCompany: false))
            .presentationDragIndicator(.visible)
            .preferredColorScheme(preferredModalColorScheme)
        }
        .sheet(isPresented: $showNotificationSettings) {
            NotificationSettingsSheet(
                notificationService: notifications,
                onClose: { showNotificationSettings = false }
            )
            .presentationDetents([.height(690), .large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(preferredModalColorScheme)
        }
        .sheet(isPresented: $showPreferences) {
            ProfilePreferencesSheet(
                themePreference: app.themePreference,
                languagePreference: app.languagePreference,
                safetyProfileID: app.safetyProfileID,
                onThemeChange: { app.setThemePreference($0) },
                onSafetyProfileChange: { app.setSafetyProfile($0) }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(preferredModalColorScheme)
        }
        .sheet(isPresented: $showLegalInfo) {
            LegalInfoSheet(onClose: { showLegalInfo = false })
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(preferredModalColorScheme)
        }
        .sheet(isPresented: $showSupport) {
            SupportContactSheet(
                profile: app.profile,
                tier: app.currentTier,
                appLanguage: app.languagePreference.appLanguage,
                contentLocale: app.activeSafetyProfile?.contentLocale
                    ?? (app.languagePreference == .turkish
                        ? .turkishTurkey
                        : .englishInternational),
                onClose: { showSupport = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(preferredModalColorScheme)
        }
        .sheet(isPresented: $showProfessionalTitlesFromHeader) {
            if RDProfessionalProgressLocalizationReview.isAvailable,
               let professionalProgressSummary {
                ProfessionalProgressTitlesSheet(summary: professionalProgressSummary)
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
                    .preferredColorScheme(preferredModalColorScheme)
            }
        }
        .sheet(item: $profileBadgesSheet) { item in
            ProfessionalProgressBadgesView(summary: item.summary)
                .presentationDetents([.height(360)])
                .presentationDragIndicator(.visible)
                .preferredColorScheme(preferredModalColorScheme)
        }
        .alert(RDLocalization.string("localizable.profile.view.profil.fotografi.guncellenemedi.b285e0c1", table: .localizable, fallback: "Profil fotoğrafı güncellenemedi"), isPresented: Binding(
            get: { profileAvatarError != nil },
            set: { if !$0 { profileAvatarError = nil } }
        )) {
            Button(
                RDLocalization.string(
                    "localizable.profile.view.tamam.8c55612a",
                    table: .localizable,
                    fallback: "Tamam"
                ),
                role: .cancel
            ) { profileAvatarError = nil }
        } message: {
            Text(profileAvatarError ?? "")
        }
        .confirmationDialog(
            pendingDataAction?.confirmationTitle ?? RDLocalization.string("localizable.profile.view.islem.onayi.f310df5d", table: .localizable, fallback: "İşlem onayı"),
            isPresented: Binding(
                get: { pendingDataAction != nil },
                set: { if !$0 { pendingDataAction = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let action = pendingDataAction {
                Button(action.confirmationButtonTitle, role: action.role) {
                    runDataAction(action)
                }
            }
            Button(RDLocalization.string("localizable.profile.view.vazgec.1c559f79", table: .localizable, fallback: "Vazgeç"), role: .cancel) {
                pendingDataAction = nil
            }
        } message: {
            Text(pendingDataAction?.confirmationMessage ?? "")
        }
        .alert(dataAlertTitle, isPresented: Binding(
            get: { dataMessage != nil },
            set: { if !$0 { dismissDataMessage() } }
        )) {
            Button(RDLocalization.string("localizable.profile.view.tamam.8c55612a", table: .localizable, fallback: "Tamam")) { dismissDataMessage() }
        } message: {
            Text(dataMessage ?? "")
        }
        .alert(RDLocalization.string("localizable.profile.view.satin.alimlari.geri.yukle.efbb27c9", table: .localizable, fallback: "Satın alımları geri yükle"), isPresented: Binding(
            get: { restoreMessage != nil },
            set: { if !$0 { restoreMessage = nil } }
        )) {
            Button(RDLocalization.string("localizable.profile.view.tamam.dd979b9f", table: .localizable, fallback: "Tamam")) { restoreMessage = nil }
        } message: {
            Text(restoreMessage ?? "")
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                VStack(spacing: 0) {
                    profileCover
                        .frame(height: 148)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(profileDisplayName)
                            .font(RDTypography.font(size: RDFontScale.size(23), weight: .bold, design: .rounded))
                            .foregroundStyle(Color.rdBlack)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .padding(.top, 50)

                        Text(profileExpertiseLabel)
                            .font(RDTypography.font(size: RDFontScale.size(13.5), weight: .medium, design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                            .lineSpacing(2)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if RDProfessionalProgressLocalizationReview.isAvailable,
                           let professionalProgressSummary {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showProfileBadges(professionalProgressSummary)
                            } label: {
                                Label(RDLocalization.string("localizable.profile.view.basarilarim.9425dd36", table: .localizable, fallback: "Başarılarım"), systemImage: "rosette")
                                    .font(RDTypography.font(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.rdGreenDark)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 6)
                            .accessibilityLabel(RDLocalization.string("localizable.profile.view.basarilarim.e21f7c9f", table: .localizable, fallback: "Başarılarım"))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, professionalProgressSummary == nil ? 16 : 12)

                    profileHeroStatsRow
                }

                profileAvatarPicker
                    .offset(x: 28, y: 96)

                if RDProfessionalProgressLocalizationReview.isAvailable,
                   professionalProgressSummary != nil {
                    professionalTitleBadge
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.leading, 202)
                        .padding(.trailing, 16)
                        .offset(y: 172)
                }
            }
        }
        .background(profileCardFill)
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(profileLine, lineWidth: 1)
        )
        .profileCardDepth(colorScheme: colorScheme, accent: Color(hex: "#AFC6D6"))
        .accessibilityIdentifier("profile.hero.card")
    }

    private var profileCover: some View {
        ZStack {
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(hex: "#1A2529"), Color(hex: "#202C31"), Color(hex: "#0D1514")]
                    : [Color(hex: "#C8E0EF"), Color(hex: "#E0EFF7"), Color(hex: "#AFCFE4")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Circle()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.10 : 0.40))
                .frame(width: 150, height: 150)
                .blur(radius: 9)
                .offset(x: 52, y: -44)

            Capsule()
                .fill(Color.white.opacity(colorScheme == .dark ? 0.08 : 0.34))
                .frame(width: 160, height: 70)
                .blur(radius: 10)
                .offset(x: 112, y: 2)

            Circle()
                .fill(Color.rdGreen.opacity(colorScheme == .dark ? 0.14 : 0.10))
                .frame(width: 150, height: 150)
                .blur(radius: 22)
                .offset(x: -138, y: 54)

            profileCoverClouds

            LinearGradient(
                colors: [.clear, profileCardFill.opacity(0.74)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var profileCoverClouds: some View {
        ZStack {
            Group {
                Circle()
                    .frame(width: 76, height: 76)
                    .offset(x: -60, y: -8)
                Circle()
                    .frame(width: 116, height: 116)
                    .offset(x: 0, y: -26)
                Circle()
                    .frame(width: 88, height: 88)
                    .offset(x: 66, y: -10)
                Capsule(style: .continuous)
                    .frame(width: 196, height: 56)
                    .offset(x: 8, y: 12)
            }
            .foregroundStyle(Color.white.opacity(colorScheme == .dark ? 0.34 : 0.96))

            Group {
                Circle()
                    .frame(width: 54, height: 54)
                    .offset(x: 98, y: -22)
                Capsule(style: .continuous)
                    .frame(width: 112, height: 34)
                    .offset(x: 94, y: 12)
            }
            .foregroundStyle(Color.white.opacity(colorScheme == .dark ? 0.24 : 0.78))
        }
        .blur(radius: 1.4)
        .shadow(color: Color(hex: "#AFC6D6").opacity(colorScheme == .dark ? 0.10 : 0.20), radius: 14, x: 0, y: 8)
        .offset(x: 48, y: 10)
        .allowsHitTesting(false)
    }

    private var profileAvatarPicker: some View {
        PhotosPicker(
            selection: $selectedProfileAvatarItem,
            matching: .images,
            photoLibrary: .shared()
        ) {
            profileAvatarContent
        }
        .buttonStyle(.plain)
        .disabled(isUpdatingProfileAvatar)
        .accessibilityLabel(RDLocalization.string("localizable.profile.view.profil.fotografi.15f95820", table: .localizable, fallback: "Profil fotoğrafı"))
        .accessibilityHint(RDLocalization.string("localizable.profile.view.fotograf.secmek.veya.degistirmek.icin.dokun.848178f0", table: .localizable, fallback: "Fotoğraf seçmek veya değiştirmek için dokun"))
    }

    private var profileAvatarContent: some View {
        ZStack {
            if let profileAvatarImage {
                Image(uiImage: profileAvatarImage)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 96, height: 96)
                    .clipShape(Circle())
            } else {
                RDAvatar(
                    initials: app.profile?.displayInitials ?? "—",
                    size: 96,
                    tier: .free
                )
            }

            if isUpdatingProfileAvatar {
                Circle()
                    .fill(Color.black.opacity(0.28))
                    .frame(width: 96, height: 96)
                ProgressView()
                    .tint(.white)
            }
        }
        .frame(width: 96, height: 96)
        .overlay(Circle().stroke(profileCardFill, lineWidth: 5))
        .overlay(alignment: .topTrailing) {
            profileAvatarTierBadge
                .offset(x: 5, y: -5)
        }
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "camera.fill")
                .font(RDTypography.font(size: RDFontScale.size(11), weight: .black, design: .rounded))
                .foregroundStyle(Color.rdWhite)
                .frame(width: 26, height: 26)
                .background(Color.rdBlack.opacity(0.88))
                .clipShape(Circle())
                .overlay(Circle().stroke(profileCardFill, lineWidth: 3))
                .offset(x: 3, y: 3)
        }
        .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.12), radius: 12, x: 0, y: 7)
    }

    @ViewBuilder
    private var profileAvatarTierBadge: some View {
        switch app.currentTier {
        case .plus:
            Image(systemName: "crown.fill")
                .font(RDTypography.font(size: RDFontScale.size(12), weight: .black, design: .rounded))
                .foregroundStyle(Color.rdWhite)
                .frame(width: 28, height: 28)
                .background(Color.rdPlanPlus)
                .clipShape(Circle())
                .overlay(Circle().stroke(profileCardFill, lineWidth: 3))
                .shadow(color: Color.rdPlanPlus.opacity(0.30), radius: 8, x: 0, y: 4)
        case .pro:
            Image(systemName: "star.fill")
                .font(RDTypography.font(size: RDFontScale.size(12), weight: .black, design: .rounded))
                .foregroundStyle(Color.rdWhite)
                .frame(width: 28, height: 28)
                .background(Color.rdGreen)
                .clipShape(Circle())
                .overlay(Circle().stroke(profileCardFill, lineWidth: 3))
                .shadow(color: Color.rdGreen.opacity(0.30), radius: 8, x: 0, y: 4)
        case .free:
            EmptyView()
        }
    }

    private var professionalTitleBadge: some View {
        Button {
            guard professionalProgressSummary != nil else { return }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            showProfessionalTitlesFromHeader = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: professionalTitleIcon)
                    .font(RDTypography.font(size: RDFontScale.size(10.5), weight: .black, design: .rounded))
                    .foregroundStyle(Color.rdWhite)
                    .frame(width: 21, height: 21)
                    .background(professionalTitleAccent)
                    .clipShape(Circle())

                Text(professionalTitleLabel)
                    .font(RDTypography.font(size: RDFontScale.size(11.5), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .padding(.vertical, 5)
            .padding(.leading, 6)
            .padding(.trailing, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(profileCardFill.opacity(colorScheme == .dark ? 0.94 : 0.92))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(professionalTitleAccent.opacity(0.22), lineWidth: 1)
            )
            .shadow(color: professionalTitleAccent.opacity(0.12), radius: 7, x: 0, y: 4)
            .frame(maxWidth: 155, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(professionalProgressSummary == nil)
        .accessibilityLabel(RDLocalization.format("localizable.profile.view.mesleki.unvan.1.81bb1fba", table: .localizable, fallback: "Mesleki ünvan: %1$@", arguments: [String(describing: professionalTitleLabel)]))
        .accessibilityHint(RDLocalization.string("localizable.profile.view.mesleki.ilerleme.penceresini.acar.20f2951f", table: .localizable, fallback: "Mesleki ilerleme penceresini açar"))
    }

    private var profileHeroStatsRow: some View {
        HStack(spacing: 0) {
            ForEach(Array(profileHeroStats.enumerated()), id: \.offset) { index, item in
                if index > 0 {
                    Rectangle()
                        .fill(profileLine)
                        .frame(width: 1)
                }

                profileHeroStatCell(item, index: index)
            }
        }
        .overlay(alignment: .top) {
            Rectangle()
                .fill(profileLine)
                .frame(height: 1)
        }
        .accessibilityIdentifier("profile.hero.stats")
    }

    private func profileHeroStatCell(_ item: ProfileHeroStat, index: Int) -> some View {
        Button {
            switch index {
            case 0:
                withAnimation(.easeInOut(duration: 0.15)) {
                    app.activeTab = .analyses
                }
                UISelectionFeedbackGenerator().selectionChanged()
            case 1:
                withAnimation(.easeInOut(duration: 0.15)) {
                    app.activeTab = .reports
                }
                UISelectionFeedbackGenerator().selectionChanged()
            default:
                break
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: item.icon)
                    .font(RDTypography.font(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
                    .foregroundStyle(item.color)
                    .frame(width: 22, height: 22)
                    .background(item.color.opacity(colorScheme == .dark ? 0.16 : 0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                VStack(alignment: .leading, spacing: 0) {
                    Text(item.value)
                        .rdMono(size: 17, weight: .bold)
                        .foregroundStyle(Color.rdBlack)
                        .lineLimit(1)
                        .minimumScaleFactor(0.64)

                    Text(item.label)
                        .font(RDTypography.font(size: RDFontScale.size(9), weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .lineLimit(2)
                        .minimumScaleFactor(0.68)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(index == 0 ? "profile.hero.stat.analyses" : index == 1 ? "profile.hero.stat.reports" : "profile.hero.stat.\(index)")
    }

    private struct ProfileHeroStat {
        let value: String
        let label: String
        let icon: String
        let color: Color
    }

    private var profileHeroStats: [ProfileHeroStat] {
        [
            .init(
                value: stats.map { "\($0.analysisCount)" } ?? "—",
                label: RDLocalization.string("localizable.profile.view.analiz.1f6e1762", table: .localizable, fallback: "Analiz"),
                icon: "waveform.path.ecg",
                color: .rdInfo
            ),
            .init(
                value: stats.map { "\($0.reportCount)" } ?? "—",
                label: RDLocalization.string("localizable.profile.view.rapor.9274cfc1", table: .localizable, fallback: "Rapor"),
                icon: "doc.text.fill",
                color: .rdGreen
            ),
            .init(
                value: weeklyProfileStatValue,
                label: RDLocalization.string("localizable.profile.view.bu.hafta.8242025a", table: .localizable, fallback: "Bu hafta"),
                icon: "calendar.badge.checkmark",
                color: .rdPlanPlus
            ),
            .init(
                value: professionalProgressSummary.map { "\($0.profile.highFindings + $0.profile.criticalFindings)" } ?? "—",
                label: RDLocalization.string("localizable.profile.view.yuksek.kritik.240f194b", table: .localizable, fallback: "Yüksek/ Kritik"),
                icon: "exclamationmark.triangle.fill",
                color: .rdCritical
            )
        ]
    }

    private var weeklyProfileStatValue: String {
        if let professionalProgressSummary {
            return "\(professionalProgressSummary.weeklyTracking.reportsCount)"
        }
        return stats.map { "\($0.weeklyAnalysisCount)" } ?? "—"
    }

    private var profileDisplayName: String {
        app.profile?.displayName ?? RDLocalization.string("localizable.profile.view.kullanici.b1a2c01b", table: .localizable, fallback: "Kullanıcı")
    }

    private var profileExpertiseLabel: String {
        if app.languagePreference == .english {
            if let title = app.profile?.title?.trimmingCharacters(in: .whitespacesAndNewlines),
               !title.isEmpty {
                return title
            }
            return RDLocalization.string("localizable.profile.view.safety.professional.75b686e2", table: .localizable, fallback: "Güvenlik uzmanı")
        }
        switch onboardingSummary?.certificateClass {
        case "A":
            return RDLocalization.string("localizable.profile.view.a.sinifi.is.guvenligi.uzmani.e9664d53", table: .localizable, fallback: "A Sınıfı İş Güvenliği Uzmanı")
        case "B":
            return RDLocalization.string("localizable.profile.view.b.sinifi.is.guvenligi.uzmani.2ea7315b", table: .localizable, fallback: "B Sınıfı İş Güvenliği Uzmanı")
        case "C":
            return RDLocalization.string("localizable.profile.view.c.sinifi.is.guvenligi.uzmani.6e8ca297", table: .localizable, fallback: "C Sınıfı İş Güvenliği Uzmanı")
        case "doctor":
            return RDLocalization.string("localizable.profile.view.isyeri.hekimi.f29566df", table: .localizable, fallback: "İşyeri Hekimi")
        case "otherHealth":
            return RDLocalization.string("localizable.profile.view.diger.saglik.personeli.88d0fa73", table: .localizable, fallback: "Diğer Sağlık Personeli")
        default:
            if let title = app.profile?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                return title
            }
            return RDLocalization.string("localizable.profile.view.isg.uzmani.0fa630c7", table: .localizable, fallback: "İSG Uzmanı")
        }
    }

    private var professionalTitleLabel: String {
        professionalProgressSummary?.currentTitle.label ?? ProfessionalProgressTitle.candidate.label
    }

    private var professionalTitleIcon: String {
        switch professionalProgressSummary?.currentTitle ?? .candidate {
        case .fieldObserver:
            return "binoculars.fill"
        case .riskHunter:
            return "scope"
        case .hazardAnalyst:
            return "exclamationmark.triangle.fill"
        case .seniorRiskSpecialist:
            return "shield.checkered"
        case .safetyStrategist:
            return "flag.checkered"
        case .masterHSESpecialist:
            return "crown.fill"
        case .candidate:
            return "person.crop.circle.badge.checkmark"
        }
    }

    private var professionalTitleAccent: Color {
        switch professionalProgressSummary?.currentTitle ?? .candidate {
        case .fieldObserver:
            return Color(hex: "#9A5B00")
        case .riskHunter:
            return Color(hex: "#8F421D")
        case .hazardAnalyst:
            return Color(hex: "#8F2B13")
        case .seniorRiskSpecialist:
            return Color(hex: "#4F6F98")
        case .safetyStrategist:
            return Color.rdPlanPlusDark
        case .masterHSESpecialist:
            return Color(hex: "#102A43")
        case .candidate:
            return Color(hex: "#087C5B")
        }
    }

    // MARK: - Pro card

    private var proCard: some View {
        HStack(spacing: 12) {
            RDTierBadge(tier: app.currentTier, small: true)

            VStack(alignment: .leading, spacing: 3) {
                Text(RDLocalization.format("localizable.profile.view.1.aktif.eb025629", table: .localizable, fallback: "%1$@ aktif", arguments: [String(describing: subscriptionPaymentTitle)]))
                    .font(RDTypography.font(size: RDFontScale.size(14), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .lineLimit(1)

                Text("\(subscriptionPeriodLabel) · \(subscriptionRenewalLabel)")
                    .font(RDTypography.font(size: RDFontScale.size(12), weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 8)

            Image(systemName: "checkmark.seal.fill")
                .font(RDTypography.font(size: RDFontScale.size(18), weight: .semibold, design: .rounded))
                .foregroundStyle(app.currentTier.accentColor)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: colorScheme == .dark
                    ? [Color(hex: "#2A2416"), Color(hex: "#181A16")]
                    : [Color(hex: "#FFF7DE"), Color(hex: "#FFFDF6")],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: RDRadius.lg)
                .stroke(Color.rdPlanPlus.opacity(colorScheme == .dark ? 0.28 : 0.35), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        .profileCardDepth(colorScheme: colorScheme, accent: Color.rdPlanPlus)
        .allowsHitTesting(false)
    }

    private var upsellCard: some View {
        RDPlanUpsellCard {
            PaywallEventService.shared.beginEntry(
                at: .profileUpsellCard,
                currentTier: app.currentTier,
                targetTier: app.currentTier == .plus ? .pro : .plus
            )
            showPaywall = true
        }
    }

    // MARK: - Lists

    private var accountList: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(RDLocalization.string("localizable.profile.view.hesap.c8de18a3", table: .localizable, fallback: "Hesap"))
            VStack(spacing: 0) {
                Button {
                    showProfileEditor = true
                } label: {
                    ProfileRow(icon: "person.text.rectangle", title: RDLocalization.string("localizable.profile.view.profil.bilgileri.fb9eb38f", table: .localizable, fallback: "Profil bilgileri"))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.row.info")
                Divider().background(Color.rdLine).padding(.leading, 60)
                Button {
                    showCompanyPicker = true
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    ProfileRow(
                        icon: app.currentTier.isPaid ? "building.2" : "lock.fill",
                        title: RDLocalization.string("localizable.profile.view.firmalarim.74674628", table: .localizable, fallback: "Firmalarım"),
                        detail: app.currentTier.isPaid ? RDLocalization.string("localizable.profile.view.yonet.143b9405", table: .localizable, fallback: "Yönet") : "Plus/Pro"
                    )
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.row.companies")
                Divider().background(Color.rdLine).padding(.leading, 60)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        app.activeTab = .analyses
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    ProfileRow(icon: "doc.text", title: RDLocalization.string("localizable.profile.view.gecmis.analizler.e936d553", table: .localizable, fallback: "Geçmiş analizler"), detail: stats.map { "\($0.analysisCount)" } ?? "—")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.row.history")
                Divider().background(Color.rdLine).padding(.leading, 60)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        app.activeTab = .reports
                    }
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    ProfileRow(icon: "arrow.down.to.line", title: RDLocalization.string("localizable.profile.view.raporlarim.16715436", table: .localizable, fallback: "Raporlarım"), detail: stats.map { "\($0.reportCount)" } ?? "—")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.row.reports")
                Divider().background(Color.rdLine).padding(.leading, 60)
                Button {
                    showNotificationSettings = true
                } label: {
                    ProfileRow(icon: "bell", title: RDLocalization.string("localizable.profile.view.bildirimler.b8286da6", table: .localizable, fallback: "Bildirimler"))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.row.notifications")
            }
            .background(profileCardFill)
            .overlay(
                RoundedRectangle(cornerRadius: RDRadius.lg)
                    .stroke(profileLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
            .profileCardDepth(colorScheme: colorScheme)
        }
    }

    private var notificationStatusText: String {
        switch notifications.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return RDLocalization.string("localizable.profile.view.acik.38c11300", table: .localizable, fallback: "Açık")
        case .denied:
            return RDLocalization.string("localizable.profile.view.kapali.28e7315c", table: .localizable, fallback: "Kapalı")
        case .notDetermined:
            return RDLocalization.string("localizable.profile.view.kur.1bf320eb", table: .localizable, fallback: "Kur")
        @unknown default:
            return RDLocalization.string("localizable.profile.view.kontrol.et.50c9c5d5", table: .localizable, fallback: "Kontrol et")
        }
    }

    private func consumePendingProfileDestinationIfNeeded() {
        guard app.activeTab == .profile,
              let destination = app.pendingProfileDestination else { return }
        app.pendingProfileDestination = nil
        switch destination {
        case .preferences:
            showPreferences = true
        }
    }

    private var settingsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader(RDLocalization.string("localizable.profile.view.ayarlar.0bc78d3d", table: .localizable, fallback: "Ayarlar"))
            VStack(spacing: 0) {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    showPreferences = true
                } label: {
                    ProfileRow(icon: "gearshape", title: RDLocalization.string("localizable.profile.view.tercihler.9dc53e66", table: .localizable, fallback: "Tercihler"))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.row.preferences")
                Divider().background(Color.rdLine).padding(.leading, 60)
                Button {
                    restorePurchasesFromProfile()
                } label: {
                    ProfileRow(
                        icon: "arrow.clockwise.circle",
                        title: RDLocalization.string("localizable.profile.view.satin.alimlari.geri.yukle.3b1b795b", table: .localizable, fallback: "Satın alımları geri yükle"),
                        detail: isRestoringPurchases ? RDLocalization.string("localizable.profile.view.bekle.5095b0d1", table: .localizable, fallback: "Bekle") : app.currentTier.title
                    )
                }
                .buttonStyle(.plain)
                .disabled(isRestoringPurchases)
                .accessibilityIdentifier("profile.row.restore_purchases")
                if app.currentTier.isPaid {
                    Divider().background(Color.rdLine).padding(.leading, 60)
                    Button {
                        openURL(subscriptionManagementURL)
                        UISelectionFeedbackGenerator().selectionChanged()
                    } label: {
                        ProfileRow(
                            icon: "creditcard",
                            title: RDLocalization.string("localizable.profile.view.app.store.aboneligini.yonet.553f0a73", table: .localizable, fallback: "App Store aboneliğini yönet"),
                            detail: RDLocalization.string("localizable.profile.view.apple.40533c0b", table: .localizable, fallback: "Apple")
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile.row.manage_app_store_subscription")
                }
                Divider().background(Color.rdLine).padding(.leading, 60)
                Button {
                    showDataControls = true
                } label: {
                    ProfileRow(icon: "externaldrive.badge.checkmark", title: RDLocalization.string("localizable.profile.view.verilerim.8d24daaa", table: .localizable, fallback: "Verilerim"))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                Divider().background(Color.rdLine).padding(.leading, 60)
                Button {
                    showLegalInfo = true
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    ProfileRow(
                        icon: deviceIntegrity.isWarning ? "exclamationmark.shield.fill" : "lock",
                        title: RDLocalization.string("localizable.profile.view.guvenlik.ve.gizlilik.47d46255", table: .localizable, fallback: "Güvenlik ve gizlilik"),
                        detail: deviceIntegrity.profileDetail,
                        danger: deviceIntegrity.isWarning
                    )
                }
                .buttonStyle(.plain)
                Divider().background(Color.rdLine).padding(.leading, 60)
                Button {
                    showSupport = true
                    UISelectionFeedbackGenerator().selectionChanged()
                } label: {
                    ProfileRow(icon: "headphones", title: RDLocalization.string("localizable.profile.view.destek.745f0ecb", table: .localizable, fallback: "Destek"))
                }
                .buttonStyle(.plain)
            }
            .background(profileCardFill)
            .overlay(
                RoundedRectangle(cornerRadius: RDRadius.lg)
                    .stroke(profileLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
            .profileCardDepth(colorScheme: colorScheme)
        }
    }

    private var subscriptionManagementURL: URL {
        app.subscriptionState.managementURL
            ?? URL(string: "https://apps.apple.com/account/subscriptions")!
    }

    private func restorePurchasesFromProfile() {
        guard !isRestoringPurchases else { return }
        UISelectionFeedbackGenerator().selectionChanged()
        isRestoringPurchases = true
        logProfileRestoreTap()

        Task {
            do {
                let restoredState = try await app.restoreSubscriptions()
                await loadStats()
                restoreMessage = restoredState.tier.isPaid
                    ? RDLocalization.format("localizable.profile.view.1.aboneligin.dogrulandi.a377fb83", table: .localizable, fallback: "%1$@ aboneliğin doğrulandı.", arguments: [String(describing: restoredState.tier.title)])
                    : RDLocalization.string("localizable.profile.view.geri.yuklenecek.aktif.abonelik.bulunamadi.c7188f39", table: .localizable, fallback: "Geri yüklenecek aktif abonelik bulunamadı.")
            } catch {
                restoreMessage = error.localizedDescription
            }
            isRestoringPurchases = false
        }
    }

    private func logProfileRestoreTap() {
        PaywallEventService.shared.record(
            .restoreTap,
            funnelSessionID: UUID(),
            source: .inApp,
            variantID: "profile_subscription_restore_v1",
            segmentKey: nil,
            selectedTier: app.currentTier,
            billing: nil,
            productIdentifier: nil,
            metadata: PaywallEventMetadata(
                layout: "profile_restore",
                currentTier: app.currentTier.rawValue,
                selectedPackageID: nil,
                noticePresent: false,
                errorMessage: nil,
                contextHeadline: "profile",
                purchaseError: nil
            )
        )
    }

    private var deviceIntegrityWarningCard: some View {
        RDCard {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.shield.fill")
                    .font(RDTypography.font(size: RDFontScale.size(18), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdCriticalText)
                    .frame(width: 40, height: 40)
                    .background(Color.rdCriticalBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(RDLocalization.string("localizable.profile.view.cihaz.guvenligi.uyarisi.937fe0b5", table: .localizable, fallback: "Cihaz güvenliği uyarısı"))
                        .font(RDTypography.font(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(deviceIntegrity.userMessage)
                        .font(RDTypography.font(size: RDFontScale.size(12), weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
        }
        .accessibilityIdentifier("profile.device_integrity.warning")
    }

    private var signOutCard: some View {
        Button {
            app.signOut()
        } label: {
            ProfileRow(icon: "rectangle.portrait.and.arrow.right", title: RDLocalization.string("localizable.profile.view.cikis.yap.e00324ba", table: .localizable, fallback: "Çıkış yap"),
                       danger: true, showsChevron: false)
                .background(profileCardFill)
                .overlay(
                    RoundedRectangle(cornerRadius: RDRadius.lg)
                        .stroke(profileLine, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
                .profileCardDepth(colorScheme: colorScheme)
        }
        .buttonStyle(.plain)
    }

    private var deleteAccountCard: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            pendingDataAction = .requestAccountDeletion
        } label: {
            ProfileRow(
                icon: "person.crop.circle.badge.xmark",
                title: RDLocalization.string("localizable.profile.view.hesabimi.sil.delete.account.1494065e", table: .localizable, fallback: "Hesabımı sil / Delete Account"),
                subtitle: RDLocalization.string("localizable.profile.view.hesap.ve.uygulama.verilerini.kalici.olarak.siler.41c09bb7", table: .localizable, fallback: "Hesap ve uygulama verilerini kalıcı olarak siler."),
                danger: true
            )
            .background(profileCardFill)
            .overlay(
                RoundedRectangle(cornerRadius: RDRadius.lg)
                    .stroke(profileLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
            .profileCardDepth(colorScheme: colorScheme)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile.row.delete_account")
    }

    private var dataAlertTitle: String {
        shouldSignOutAfterDataMessageDismiss
            ? RDLocalization.string("localizable.profile.view.hesap.silindi.account.deleted.43618c3b", table: .localizable, fallback: "Hesap silindi / Account Deleted")
            : "Verilerim"
    }

    private func dismissDataMessage() {
        dataMessage = nil
        guard shouldSignOutAfterDataMessageDismiss else { return }
        shouldSignOutAfterDataMessageDismiss = false
        app.signOut()
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(RDTypography.font(size: RDFontScale.size(11), weight: .bold, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(Color.rdSlate)
            .padding(.leading, 4)
    }

    private var subscriptionPeriodLabel: String {
        switch app.profile?.subscriptionPeriod {
        case "monthly": return RDLocalization.string("localizable.profile.view.aylik.plan.5f4cc5d2", table: .localizable, fallback: "Aylık plan")
        case "yearly": return RDLocalization.string("localizable.profile.view.yillik.plan.97dd768f", table: .localizable, fallback: "Yıllık plan")
        case .some(let value): return value.capitalized
        case .none: return RDLocalization.format("localizable.profile.view.1.plan.62d8aa84", table: .localizable, fallback: "%1$@ planı", arguments: [String(describing: app.currentTier.title)])
        }
    }

    private var subscriptionPaymentTitle: String {
        "\(app.currentTier.title) plan"
    }

    private var subscriptionRenewalLabel: String {
        guard let raw = app.profile?.subscriptionRenewalAt,
              let date = parseISODate(raw)
        else {
            return RDLocalization.string("localizable.profile.view.app.store.aboneligi.aktif.20d1b110", table: .localizable, fallback: "App Store aboneliği aktif")
        }

        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .long
        return "\(formatter.string(from: date))"
    }

    private func parseISODate(_ raw: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return withFraction.date(from: raw) ?? plain.date(from: raw)
    }

    private func showProfileBadges(_ summary: ProfessionalProgressSummary) {
        profileBadgesSheet = ProfileBadgesSheetItem(summary: summary)
    }

    private func loadProfileAvatarImage() async {
        guard let path = app.profile?.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty
        else {
            profileAvatarImage = nil
            return
        }

        do {
            profileAvatarImage = try await app.auth.profileAvatarImage(path: path)
        } catch {
            profileAvatarImage = nil
        }
    }

    private func handleProfileAvatarSelection(_ item: PhotosPickerItem) async {
        isUpdatingProfileAvatar = true
        defer {
            isUpdatingProfileAvatar = false
            selectedProfileAvatarItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self),
                  let image = UIImage(data: data)
            else {
                throw NSError(
                    domain: "RiskDetected.ProfileView",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: RDLocalization.string("localizable.profile.view.fotograf.okunamadi.lutfen.farkli.bir.gorsel.sec.0ac3c3ec", table: .localizable, fallback: "Fotoğraf okunamadı. Lütfen farklı bir görsel seç.")]
                )
            }

            try await app.auth.saveProfileAvatar(image)
            await app.auth.refreshProfile()
            await loadProfileAvatarImage()
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        } catch {
            profileAvatarError = error.localizedDescription
        }
    }

    private func loadStats() async {
        guard app.auth.session != nil else { return }
        do {
            stats = try await AnalysisService.shared.profileStats()
        } catch {
            stats = nil
        }
    }

    private func loadProfessionalProgress() async {
        guard app.auth.session != nil,
              RDConfig.Features.professionalProgressEnabled,
              RDProfessionalProgressLocalizationReview.isAvailable
        else {
            professionalProgressSummary = nil
            showProfessionalTitlesFromHeader = false
            profileBadgesSheet = nil
            return
        }
        professionalProgressSummary = await ProfessionalProgressService.shared.fetchSummary()
    }

    private func loadOnboardingSummary() async {
        guard app.auth.session != nil,
              let userID = SupabaseService.shared.currentUserID
        else {
            onboardingSummary = nil
            return
        }

        do {
            let rows: [ProfileOnboardingSummary] = try await SupabaseService.shared.client
                .from("user_onboarding_answers")
                .select("certificate_class")
                .eq("user_id", value: userID.uuidString)
                .limit(1)
                .execute()
                .value
            onboardingSummary = rows.first
        } catch {
            onboardingSummary = nil
        }
    }

    private func runDataAction(_ action: ProfileDataAction) {
        guard dataActionInProgress == nil else { return }
        pendingDataAction = nil
        shouldSignOutAfterDataMessageDismiss = false
        if action == .exportData {
            cleanupExportedDataFile()
        }

        guard let userID = app.auth.session?.user.id else {
            dataMessage = AppErrorMessage.make(AnalysisService.AnalysisError.notAuthenticated, context: RDLocalization.string("localizable.profile.view.veri.islemi.yapilamadi.bb13b88e", table: .localizable, fallback: "Veri işlemi yapılamadı")).fullText
            return
        }

        dataActionInProgress = action
        let requestID = UUID().uuidString
        let supportID = AppErrorMessage.newSupportID()

        Task {
            do {
                switch action {
                case .exportData:
                    let url = try await AnalysisService.shared.exportUserData(
                        userID: userID,
                        profile: app.profile,
                        requestID: requestID,
                        supportID: supportID
                    )
                    exportedDataFile = ShareItem(url: url)
                case .deleteReports:
                    try await AnalysisService.shared.deleteAllReports(
                        requestID: requestID,
                        supportID: supportID
                    )
                    dataMessage = RDLocalization.string("localizable.profile.view.tum.pdf.raporlarin.silindi.2eec83dd", table: .localizable, fallback: "Tüm PDF raporların silindi.")
                    await loadStats()
                case .deleteAnalyses:
                    try await AnalysisService.shared.deleteAllAnalyses(
                        requestID: requestID,
                        supportID: supportID
                    )
                    dataMessage = RDLocalization.string("localizable.profile.view.tum.analizlerin.ve.iliskili.bulgular.fotograflar.0277c8eb", table: .localizable, fallback: "Tüm analizlerin ve ilişkili bulgular/fotoğraflar silindi.")
                    await loadStats()
                case .requestAccountDeletion:
                    let result = try await AnalysisService.shared.requestAccountDeletion(
                        userID: userID,
                        email: app.profile?.email,
                        requestID: requestID,
                        supportID: supportID
                    )
                    if result.shouldClearLocalSession {
                        shouldSignOutAfterDataMessageDismiss = true
                        dataMessage = result.message ?? RDLocalization.string("localizable.profile.view.hesabin.ve.uygulama.verilerin.silindi.13c9bb20", table: .localizable, fallback: "Hesabın ve uygulama verilerin silindi.")
                    } else {
                        dataMessage = result.message ?? RDLocalization.string("localizable.profile.view.hesap.silme.istegin.alindi.guvenli.silme.islemi..055e7498", table: .localizable, fallback: "Hesap silme isteğin alındı. Güvenli silme işlemi devam ediyor.")
                    }
                }
            } catch {
                shouldSignOutAfterDataMessageDismiss = false
                dataMessage = AppErrorMessage.make(
                    rawMessage: RDLocalization.format("localizable.profile.view.1.destek.kodu.2.5641b5ac", table: .localizable, fallback: "%1$@\nDestek kodu: %2$@", arguments: [String(describing: error.localizedDescription), String(describing: supportID)]),
                    context: action.errorContext,
                    fallbackTitle: action.errorContext
                ).fullText
            }
            dataActionInProgress = nil
        }
    }

    private func cleanupExportedDataFile() {
        guard let item = exportedDataFile else { return }
        AnalysisService.shared.removeUserDataExport(at: item.url)
        exportedDataFile = nil
    }
}

// MARK: - ProfileRow

private enum ProfileDataAction: Identifiable, Equatable {
    case exportData
    case deleteReports
    case deleteAnalyses
    case requestAccountDeletion

    var id: String {
        switch self {
        case .exportData: return RDLocalization.string("localizable.profile.view.exportdata.51296107", table: .localizable, fallback: "exportData")
        case .deleteReports: return RDLocalization.string("localizable.profile.view.deletereports.0f90649c", table: .localizable, fallback: "Raporları sil")
        case .deleteAnalyses: return RDLocalization.string("localizable.profile.view.deleteanalyses.15f41049", table: .localizable, fallback: "analizleri sil")
        case .requestAccountDeletion: return RDLocalization.string("localizable.profile.view.requestaccountdeletion.4e909399", table: .localizable, fallback: "Hesap Silme isteği")
        }
    }

    var confirmationTitle: String {
        switch self {
        case .exportData:
            return RDLocalization.string("localizable.profile.view.veriler.disa.aktarilsin.mi.20993cfd", table: .localizable, fallback: "Veriler dışa aktarılsın mı?")
        case .deleteReports:
            return RDLocalization.string("localizable.profile.view.tum.raporlar.silinsin.mi.c69bbe6c", table: .localizable, fallback: "Tüm raporlar silinsin mi?")
        case .deleteAnalyses:
            return RDLocalization.string("localizable.profile.view.tum.analizler.silinsin.mi.ccdb36aa", table: .localizable, fallback: "Tüm analizler silinsin mi?")
        case .requestAccountDeletion:
            return RDLocalization.string("localizable.profile.view.hesabin.ve.verilerin.silinsin.mi.0179a72b", table: .localizable, fallback: "Hesabın ve verilerin silinsin mi?")
        }
    }

    var confirmationMessage: String {
        switch self {
        case .exportData:
            return RDLocalization.string("localizable.profile.view.analiz.bulgu.fotograf.yolu.rapor.metadatasi.ve.p.07683258", table: .localizable, fallback: "Analiz, bulgu, fotoğraf yolu, rapor metadatası ve profil özetin JSON dosyası olarak hazırlanır.")
        case .deleteReports:
            return RDLocalization.string("localizable.profile.view.pdf.rapor.dosyalari.ve.rapor.arsiv.kayitlari.sil.aa136aab", table: .localizable, fallback: "PDF rapor dosyaları ve rapor arşiv kayıtları silinir. Analiz sonuçların kalır.")
        case .deleteAnalyses:
            return RDLocalization.string("localizable.profile.view.tum.analizler.bulgular.fotograf.kayitlari.ve.bu..8555a6ef", table: .localizable, fallback: "Tüm analizler, bulgular, fotoğraf kayıtları ve bu analizlere bağlı raporlar silinir. Bu işlem geri alınamaz.")
        case .requestAccountDeletion:
            return RDLocalization.string("localizable.profile.view.hesabin.profilin.analizlerin.raporlarin.ve.sakla.89fdd655", table: .localizable, fallback: "Hesabın, profilin, analizlerin, raporların ve saklanan dosyaların kalıcı olarak silinir. Silme işlemi uygulama içinde tamamlanır; e-posta, destek veya web sitesi gerekmez. Aktif App Store aboneliğin varsa iptal ve yönetim işlemleri Apple abonelik ayarlarından yapılır. Bu işlem geri alınamaz.")
        }
    }

    var confirmationButtonTitle: String {
        switch self {
        case .exportData: return RDLocalization.string("localizable.profile.view.disa.aktar.18035137", table: .localizable, fallback: "Dışa aktar")
        case .deleteReports: return RDLocalization.string("localizable.profile.view.tum.raporlari.sil.d4bd0af8", table: .localizable, fallback: "Tüm raporları sil")
        case .deleteAnalyses: return RDLocalization.string("localizable.profile.view.tum.analizleri.sil.ba2f5c47", table: .localizable, fallback: "Tüm analizleri sil")
        case .requestAccountDeletion: return RDLocalization.string("localizable.profile.view.hesabimi.sil.delete.account.488c3b9a", table: .localizable, fallback: "Hesabımı sil / Delete Account")
        }
    }

    var errorContext: String {
        switch self {
        case .exportData: return RDLocalization.string("localizable.profile.view.veri.disa.aktarimi.olusturulamadi.95d8d692", table: .localizable, fallback: "Veri dışa aktarımı oluşturulamadı")
        case .deleteReports: return RDLocalization.string("localizable.profile.view.raporlar.silinemedi.a95cf8e4", table: .localizable, fallback: "Raporlar silinemedi")
        case .deleteAnalyses: return RDLocalization.string("localizable.profile.view.analizler.silinemedi.1c906fb1", table: .localizable, fallback: "Analizler silinemedi")
        case .requestAccountDeletion: return RDLocalization.string("localizable.profile.view.hesap.silme.islemi.baslatilamadi.74db2edd", table: .localizable, fallback: "Hesap silme işlemi başlatılamadı")
        }
    }

    var role: ButtonRole? {
        switch self {
        case .deleteReports, .deleteAnalyses, .requestAccountDeletion:
            return .destructive
        case .exportData:
            return nil
        }
    }
}

private struct ProfileEditSheet: View {
    let profile: UserProfile?
    let auth: AuthService
    let appLanguage: RDLanguage
    let onSaved: () -> Void
    let onClose: () -> Void

    @State private var fullName = ""
    @State private var title = ""
    @State private var certificateNumber = ""
    @State private var companyName = ""
    @State private var phone = ""
    @State private var preferredMethod: RiskMethodWire = .fineKinney
    @State private var companyLogoPath: String?
    @State private var companyLogo: UIImage?
    @State private var selectedLogoItem: PhotosPickerItem?
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 16) {
                    logoSection
                    identitySection
                    methodSection

                    RDButton(
                        title: isSaving ? RDLocalization.string("localizable.profile.view.kaydediliyor.7948588e", table: .localizable, fallback: "Kaydediliyor...") : RDLocalization.string("localizable.profile.view.profili.kaydet.d6a55caf", table: .localizable, fallback: "Profili kaydet"),
                        style: .detect,
                        icon: isSaving ? "hourglass" : "checkmark.circle.fill",
                        height: 54
                    ) {
                        save()
                    }
                    .disabled(isSaving)
                    .opacity(isSaving ? 0.72 : 1)
                }
                .padding(20)
                .padding(.bottom, 24)
                .keyboardAdaptivePadding(extra: 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(Color.rdPaper)
            .navigationTitle(RDLocalization.string("localizable.profile.view.profil.bilgileri.54c967ae", table: .localizable, fallback: "Profil Bilgileri"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    RDModalCloseButton(action: onClose)
                }
            }
            .alert(RDLocalization.string("localizable.profile.view.profil.kaydedilemedi.496d7643", table: .localizable, fallback: "Profil kaydedilemedi"), isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button(RDLocalization.string("localizable.profile.view.tamam.fff8c2ae", table: .localizable, fallback: "Tamam"), role: .cancel) { errorMessage = nil }
            } message: {
                Text(errorMessage ?? "")
            }
        }
        .onAppear(perform: populate)
        .onChange(of: selectedLogoItem) { newItem in
            guard let newItem else { return }
            Task {
                if let data = try? await newItem.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    await MainActor.run { companyLogo = image }
                }
            }
        }
    }

    private var logoSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(RDLocalization.string("localizable.profile.view.logo.e5d1fda8", table: .localizable, fallback: "Logo"), icon: "photo.badge.plus")
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color.rdWhite)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.rdLine, lineWidth: 1)
                        )
                    if let companyLogo {
                        Image(uiImage: companyLogo)
                            .resizable()
                            .scaledToFit()
                            .padding(10)
                    } else {
                        Image(systemName: "building.2.crop.circle")
                            .font(RDTypography.font(size: RDFontScale.size(28), weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                    }
                }
                .frame(width: 78, height: 68)

                VStack(alignment: .leading, spacing: 5) {
                    Text(companyLogo == nil ? RDLocalization.string("localizable.profile.view.logo.ekle.c6da0e71", table: .localizable, fallback: "Logo ekle") : RDLocalization.string("localizable.profile.view.varsayilan.rapor.logosu.fa7bb40f", table: .localizable, fallback: "Varsayılan rapor logosu"))
                        .font(RDTypography.font(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(RDLocalization.string("localizable.profile.view.firma.veya.kisisel.logon.raporlarda.varsayilan.o.5dfc29e6", table: .localizable, fallback: "Firma veya kişisel logon raporlarda varsayılan olarak kullanılır."))
                        .font(RDTypography.font(size: RDFontScale.size(12), design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                PhotosPicker(selection: $selectedLogoItem, matching: .images) {
                    Image(systemName: companyLogo == nil ? "plus" : "arrow.triangle.2.circlepath")
                        .font(RDTypography.font(size: RDFontScale.size(15), weight: .bold, design: .rounded))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(Color.rdGreenDark)
                        .background(Color.rdGreenSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityLabel(companyLogo == nil ? RDLocalization.string("localizable.profile.view.logo.sec.4a97bac8", table: .localizable, fallback: "Logo seç") : RDLocalization.string("localizable.profile.view.logoyu.degistir.b6bc49d0", table: .localizable, fallback: "Logoyu değiştir"))
                .disabled(isSaving)
            }
            .padding(12)
            .background(Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.rdLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(
                appLanguage == .turkish ? RDLocalization.string("localizable.profile.view.kimlik.ve.firma.d8debd64", table: .localizable, fallback: "Kimlik ve firma") : RDLocalization.string("localizable.profile.view.profile.and.company.fb381c68", table: .localizable, fallback: "Profil ve şirket"),
                icon: "building.2"
            )
            VStack(spacing: 9) {
                profileField(
                    appLanguage == .turkish ? RDLocalization.string("localizable.profile.view.ad.soyad.e60c91cb", table: .localizable, fallback: "Ad soyad") : RDLocalization.string("localizable.profile.view.full.name.9ef96064", table: .localizable, fallback: "Ad Soyad"),
                    text: $fullName,
                    placeholder: appLanguage == .turkish ? RDLocalization.string("localizable.profile.view.ad.soyad.a277ae0b", table: .localizable, fallback: "Ad Soyad") : RDLocalization.string("localizable.profile.view.full.name.4d415a25", table: .localizable, fallback: "Ad Soyad"),
                    icon: "person.fill"
                )
                profileField(
                    appLanguage == .turkish ? RDLocalization.string("localizable.profile.view.unvan.belge.sinifi.07ff0723", table: .localizable, fallback: "Ünvan / belge sınıfı") : RDLocalization.string("localizable.profile.view.role.job.title.b5315a3c", table: .localizable, fallback: "Rol / İş unvanı"),
                    text: $title,
                    placeholder: appLanguage == .turkish ? RDLocalization.string("localizable.profile.view.isg.uzmani.a.sinifi.56493e61", table: .localizable, fallback: "İSG Uzmanı · A Sınıfı") : RDLocalization.string("localizable.profile.view.safety.professional.a0559094", table: .localizable, fallback: "Güvenlik uzmanı"),
                    icon: "checkmark.seal.fill"
                )
                profileField(
                    appLanguage == .turkish ? RDLocalization.string("localizable.profile.view.sertifika.no.3375cce7", table: .localizable, fallback: "Sertifika no") : RDLocalization.string("localizable.profile.view.professional.credential.or.registration.number.7c0aa931", table: .localizable, fallback: "Profesyonel kimlik bilgisi veya kayıt numarası"),
                    text: $certificateNumber,
                    placeholder: appLanguage == .turkish ? RDLocalization.string("localizable.profile.view.sertifika.numarasi.9ece8cef", table: .localizable, fallback: "Sertifika numarası") : RDLocalization.string("localizable.profile.view.optional.credential.c6e47a72", table: .localizable, fallback: "İsteğe bağlı kimlik bilgisi"),
                    icon: "number"
                )
                if appLanguage == .english {
                    Text(RDLocalization.string("localizable.profile.view.optional.enter.only.a.credential.you.are.authori.daeda8d4", table: .localizable, fallback: "İsteğe bağlı. Yalnızca kullanmaya yetkili olduğunuz bir kimlik bilgisi girin."))
                        .font(RDTypography.font(size: RDFontScale.size(11), design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
                }
                profileField(RDLocalization.string("localizable.profile.view.firma.adi.1f3200a9", table: .localizable, fallback: "Firma adı"), text: $companyName, placeholder: RDLocalization.string("localizable.profile.view.firma.adi.76933eb6", table: .localizable, fallback: "Firma adı"), icon: "building.2.fill")
                profileField(RDLocalization.string("localizable.profile.view.telefon.6c1f670a", table: .localizable, fallback: "Telefon"), text: $phone, placeholder: RDLocalization.string("localizable.profile.view.90.5xx.xxx.xx.xx.669be765", table: .localizable, fallback: "+90 5xx xxx xx xx"), icon: "phone.fill", keyboard: .phonePad)
            }
            .padding(12)
            .background(Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.rdLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private var methodSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(RDLocalization.string("localizable.profile.view.varsayilan.risk.metodu.fbba51ae", table: .localizable, fallback: "Varsayılan risk metodu"), icon: "function")
            HStack(spacing: 8) {
                methodButton(.fineKinney)
                methodButton(.matrix5x5)
            }
            .padding(12)
            .background(Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(Color.rdLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
    }

    private func methodButton(_ method: RiskMethodWire) -> some View {
        let active = preferredMethod == method
        return Button {
            preferredMethod = method
            UISelectionFeedbackGenerator().selectionChanged()
        } label: {
            VStack(spacing: 4) {
                Text(method.domain.label)
                    .font(RDTypography.font(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                Text(RDLocalization.format("localizable.profile.view.r.1.f705a409", table: .localizable, fallback: "r = %1$@", arguments: [String(describing: method.domain.formula)]))
                    .rdMono(size: 10)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(active ? Color.rdBlack : Color.rdSlate)
            .background(active ? Color.rdWhite : Color.rdFog)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(active ? Color.rdSelected : Color.rdLine, lineWidth: active ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func sectionTitle(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(RDTypography.font(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreen)
                .frame(width: 24, height: 24)
                .background(Color.rdGreenSoft)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            Text(title)
                .font(RDTypography.font(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdSlate)
        }
        .padding(.leading, 2)
    }

    private func profileField(
        _ title: String,
        text: Binding<String>,
        placeholder: String,
        icon: String,
        keyboard: UIKeyboardType = .default
    ) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(RDTypography.font(size: RDFontScale.size(14), weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdBlack.opacity(0.72))
                .frame(width: 36, height: 36)
                .background(Color.rdCloud)
                .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(RDTypography.font(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                TextField(placeholder, text: text)
                    .font(RDTypography.font(size: RDFontScale.size(15), weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .keyboardType(keyboard)
                    .textInputAutocapitalization(keyboard == .default ? .words : .never)
                    .autocorrectionDisabled(keyboard != .default)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
        .background(Color.rdCloud.opacity(0.55))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func populate() {
        fullName = profile?.fullName ?? ""
        title = profile?.title ?? ""
        certificateNumber = profile?.certificateNumber ?? ""
        companyName = profile?.companyName ?? ""
        phone = profile?.phone ?? ""
        preferredMethod = profile?.preferredMethod
            ?? (appLanguage == .english ? .matrix5x5 : .fineKinney)
        companyLogoPath = profile?.companyLogoURL

        guard companyLogo == nil, let path = profile?.companyLogoURL, !path.isEmpty else { return }
        Task {
            if let image = try? await auth.profileLogoImage(path: path) {
                await MainActor.run { companyLogo = image }
            }
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        errorMessage = nil

        Task {
            do {
                var resolvedLogoPath = companyLogoPath
                if let companyLogo {
                    resolvedLogoPath = try await auth.uploadProfileLogo(companyLogo)
                }
                try await auth.updateProfile(
                    ProfileUpdateInput(
                        fullName: fullName,
                        title: title,
                        certificateNumber: certificateNumber,
                        companyName: companyName,
                        phone: phone,
                        preferredMethod: preferredMethod,
                        companyLogoPath: resolvedLogoPath
                    )
                )
                onSaved()
            } catch {
                errorMessage = AppErrorMessage.make(
                    error,
                    context: RDLocalization.string("localizable.profile.view.profil.kaydedilemedi.a39f843a", table: .localizable, fallback: "Profil kaydedilemedi"),
                    fallbackTitle: RDLocalization.string("localizable.profile.view.profil.kaydedilemedi.6b869118", table: .localizable, fallback: "Profil kaydedilemedi")
                ).message
            }
            isSaving = false
        }
    }
}

private struct NotificationSettingsSheet: View {
    @ObservedObject var notificationService: NotificationService
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                RDCard {
                    HStack(alignment: .top, spacing: 10) {
                        statusIndicator

                        VStack(alignment: .leading, spacing: 4) {
                            Text(statusTitle)
                                .font(RDTypography.font(size: RDFontScale.size(16), weight: .bold, design: .rounded))
                                .foregroundStyle(Color.rdBlack)
                            Text(statusMessage)
                                .font(RDTypography.font(size: RDFontScale.size(12), design: .rounded))
                                .foregroundStyle(Color.rdSlate)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if !notificationService.isLoadingSettings,
                   let lastError = notificationService.lastError {
                    Text(lastError)
                        .font(RDTypography.font(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdCriticalText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !notificationService.isLoadingSettings,
                   !notificationService.settingsLoadFailed,
                   isEnabled {
                    notificationTypesCard
                    progressPreferencesCard
                }

                if notificationService.settingsLoadFailed {
                    RDButton(
                        title: RDLocalization.string(
                            "localizable.profile.notifications.retry",
                            table: .localizable,
                            fallback: "Tekrar dene"
                        ),
                        style: .detect,
                        icon: "arrow.clockwise",
                        height: 48
                    ) {
                        Task {
                            await notificationService.refreshSettings()
                        }
                    }
                } else if notificationService.isLoadingSettings {
                    EmptyView()
                } else if notificationService.authorizationStatus == .denied {
                    RDButton(
                        title: RDLocalization.string("localizable.profile.view.ayarlar.dan.ac.80b5d809", table: .localizable, fallback: "Ayarlar'dan aç"),
                        style: .primary,
                        icon: "gearshape.fill",
                        height: 48
                    ) {
                        openSystemSettings()
                    }
                } else if isEnabled {
                    RDButton(
                        title: RDLocalization.string("localizable.profile.view.bildirimleri.kapat.d98293e9", table: .localizable, fallback: "Bildirimleri kapat"),
                        style: .secondary,
                        icon: "bell.slash",
                        height: 48
                    ) {
                        notificationService.disableNotifications()
                    }
                } else {
                    RDButton(
                        title: notificationService.isRegistering ? RDLocalization.string("localizable.profile.view.bildirimler.kuruluyor.0aa10b71", table: .localizable, fallback: "Bildirimler kuruluyor...") : RDLocalization.string("localizable.profile.view.bildirimleri.ac.d2c665c7", table: .localizable, fallback: "Bildirimleri aç"),
                        style: .detect,
                        icon: notificationService.isRegistering ? "hourglass" : "bell.badge",
                        height: 48
                    ) {
                        notificationService.enableNotifications()
                    }
                    .disabled(notificationService.isRegistering)
                    .opacity(notificationService.isRegistering ? 0.72 : 1)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 18)
            .background(Color.rdPaper)
            .navigationTitle(RDLocalization.string("localizable.profile.view.bildirimler.120feec2", table: .localizable, fallback: "Bildirimler"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    RDModalCloseButton(action: onClose)
                }
            }
            .task {
                await notificationService.refreshSettings()
            }
        }
        .presentationDetents([.height(sheetHeight), .medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var sheetHeight: CGFloat {
        if notificationService.isLoadingSettings {
            return 250
        }
        if notificationService.settingsLoadFailed {
            return 300
        }
        if isEnabled {
            return notificationService.lastError == nil ? 590 : 630
        }
        if notificationService.lastError != nil {
            return 330
        }
        return notificationService.authorizationStatus == .denied ? 300 : 285
    }

    private var notificationTypesCard: some View {
        RDCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(RDLocalization.string("localizable.profile.view.aktif.bildirimler.c876e6f6", table: .localizable, fallback: "Aktif bildirimler"))
                    .font(RDTypography.font(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)

                NotificationInfoRow(icon: "sparkles", title: RDLocalization.string("localizable.profile.view.analiz.tamamlandi.b9c97000", table: .localizable, fallback: "Analiz tamamlandı"))
                NotificationInfoRow(icon: "doc.text.fill", title: RDLocalization.string("localizable.profile.view.rapor.hazir.3bd22aa3", table: .localizable, fallback: "Rapor hazır"))
                NotificationInfoRow(icon: "shield.checkered", title: RDLocalization.string("localizable.profile.view.hesap.guvenligi.c9fa84ff", table: .localizable, fallback: "Hesap güvenliği"))

                Divider()

                NotificationPreferenceToggle(
                    title: RDLocalization.string("localizable.profile.view.uygulama.bildirimleri.3be3ae96", table: .localizable, fallback: "Uygulama bildirimleri"),
                    icon: "app.badge.fill",
                    isOn: notificationService.appRemindersEnabled
                ) { isOn in
                    notificationService.setAppRemindersPreference(enabled: isOn)
                }
            }
        }
    }

    private var progressPreferencesCard: some View {
        RDCard {
            VStack(alignment: .leading, spacing: 12) {
                Text(RDLocalization.string("localizable.profile.view.mesleki.ilerleme.43c5ddd9", table: .localizable, fallback: "Mesleki ilerleme"))
                    .font(RDTypography.font(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)

                NotificationPreferenceToggle(
                    title: RDLocalization.string("localizable.profile.view.haftalik.ozet.7515b06a", table: .localizable, fallback: "Haftalık özet"),
                    icon: "calendar",
                    isOn: notificationService.progressPreferenceEnabled(.weeklySummary)
                ) { isOn in
                    notificationService.setProgressPreference(.weeklySummary, enabled: isOn)
                }

                NotificationPreferenceToggle(
                    title: RDLocalization.string("localizable.profile.view.aylik.ozet.d60e4f0b", table: .localizable, fallback: "Aylık özet"),
                    icon: "calendar.badge.clock",
                    isOn: notificationService.progressPreferenceEnabled(.monthlySummary)
                ) { isOn in
                    notificationService.setProgressPreference(.monthlySummary, enabled: isOn)
                }

                NotificationPreferenceToggle(
                    title: RDLocalization.string("localizable.profile.view.rozet.ve.unvan.8c184356", table: .localizable, fallback: "Rozet ve unvan"),
                    icon: "medal.fill",
                    isOn: notificationService.progressPreferenceEnabled(.milestones)
                ) { isOn in
                    notificationService.setProgressPreference(.milestones, enabled: isOn)
                }
            }
        }
    }

    private var isEnabled: Bool {
        notificationService.notificationsEnabled
    }

    private var statusTitle: String {
        if notificationService.isLoadingSettings {
            return RDLocalization.string(
                "localizable.profile.notifications.loading.title",
                table: .localizable,
                fallback: "Bildirim ayarları yükleniyor"
            )
        }
        if notificationService.settingsLoadFailed {
            return RDLocalization.string(
                "localizable.profile.view.bildirim.durumu.kontrol.edilemedi.15c0387d",
                table: .localizable,
                fallback: "Bildirim durumu kontrol edilemedi"
            )
        }
        if notificationService.notificationsEnabled {
            return RDLocalization.string("localizable.profile.view.bildirimler.acik.4fe9babd", table: .localizable, fallback: "Bildirimler açık")
        }
        switch notificationService.authorizationStatus {
        case .denied:
            return RDLocalization.string(
                "localizable.profile.view.bildirimler.kapali.ad5faf39",
                table: .localizable,
                fallback: "Bildirimler kapalı"
            )
        case .authorized, .provisional, .ephemeral:
            return RDLocalization.string("localizable.profile.view.bildirimler.kapali.d6a9d684", table: .localizable, fallback: "Bildirimler kapalı")
        case .notDetermined:
            return RDLocalization.string("localizable.profile.view.bildirimler.kapali.ad5faf39", table: .localizable, fallback: "Bildirimler kapalı")
        @unknown default:
            return RDLocalization.string("localizable.profile.view.bildirim.durumu.kontrol.edilemedi.15c0387d", table: .localizable, fallback: "Bildirim durumu kontrol edilemedi")
        }
    }

    private var statusMessage: String {
        if notificationService.isLoadingSettings {
            return RDLocalization.string(
                "localizable.profile.notifications.loading.message",
                table: .localizable,
                fallback: "Hesap ve cihaz bildirim tercihlerin kontrol ediliyor."
            )
        }
        if notificationService.settingsLoadFailed {
            return RDLocalization.string(
                "localizable.profile.view.bildirim.ayarlarini.yenileyip.tekrar.dene.9bbead0f",
                table: .localizable,
                fallback: "Bildirim ayarlarını yenileyip tekrar dene."
            )
        }
        if notificationService.notificationsEnabled {
            return RDLocalization.string("localizable.profile.view.analiz.sonuclari.raporlar.deneme.suresi.ve.acik..07194c0b", table: .localizable, fallback: "Analiz sonuçları, raporlar, deneme süresi ve açık uygulama hatırlatmaları için bildirim alırsın.")
        }
        switch notificationService.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return RDLocalization.string("localizable.profile.view.bildirimler.uygulama.icinde.kapali.actiginda.ana.b095b73c", table: .localizable, fallback: "Bildirimler uygulama içinde kapalı. Açtığında analiz sonuçları, raporlar, deneme süresi ve uygulama hatırlatmalarını tekrar alırsın.")
        case .denied:
            return RDLocalization.string("localizable.profile.view.actiginda.analiz.sonuclari.raporlar.deneme.sures.d9a504f3", table: .localizable, fallback: "Açtığında analiz sonuçları, raporlar, deneme süresi ve uygulama hatırlatmalarını alabilirsin.")
        case .notDetermined:
            return RDLocalization.string("localizable.profile.view.actiginda.analiz.sonuclari.raporlar.deneme.sures.f8d95411", table: .localizable, fallback: "Açtığında analiz sonuçları, raporlar, deneme süresi ve uygulama hatırlatmalarını alabilirsin.")
        @unknown default:
            return RDLocalization.string("localizable.profile.view.bildirim.ayarlarini.yenileyip.tekrar.dene.9bbead0f", table: .localizable, fallback: "Bildirim ayarlarını yenileyip tekrar dene.")
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if notificationService.isLoadingSettings {
            ProgressView()
                .tint(Color.rdGreen)
                .frame(width: 42, height: 42)
                .background(Color.rdGreen.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 13))
                .accessibilityLabel(
                    RDLocalization.string(
                        "localizable.profile.notifications.loading.title",
                        table: .localizable,
                        fallback: "Bildirim ayarları yükleniyor"
                    )
                )
        } else {
            Image(systemName: iconName)
                .font(RDTypography.font(size: RDFontScale.size(19), weight: .semibold, design: .rounded))
                .foregroundStyle(iconColor)
                .frame(width: 42, height: 42)
                .background(iconColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 13))
        }
    }

    private var iconName: String {
        isEnabled ? "bell.badge.fill" : "bell"
    }

    private var iconColor: Color {
        isEnabled ? Color.rdGreen : Color.rdSlate
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct NotificationInfoRow: View {
    let icon: String
    let title: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(RDTypography.font(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdGreen)
                .frame(width: 24, height: 24)
                .background(Color.rdGreen.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(title)
                .font(RDTypography.font(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdBlack)

            Spacer(minLength: 0)

            Text(RDLocalization.string("localizable.profile.view.acik.7af435f6", table: .localizable, fallback: "Açık"))
                .font(RDTypography.font(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreen)
        }
    }
}

private struct NotificationPreferenceToggle: View {
    let title: String
    let icon: String
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(
            get: { isOn },
            set: onChange
        )) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(RDTypography.font(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .frame(width: 24, height: 24)
                    .background(Color.rdSlate.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(title)
                    .font(RDTypography.font(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
            }
        }
        .toggleStyle(.switch)
        .tint(Color.rdGreen)
    }
}

private struct ProfileDataControlsSheet: View {
    let stats: ProfileStats?
    let actionInProgress: ProfileDataAction?
    @Binding var exportedFile: ShareItem?
    let onExport: () -> Void
    let onDeleteReports: () -> Void
    let onDeleteAnalyses: () -> Void
    let onRequestAccountDeletion: () -> Void
    let onClose: () -> Void
    @State private var presentedExportURL: URL?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    summaryCard
                    dataActionButton(
                        icon: "square.and.arrow.up",
                        title: actionInProgress == .exportData ? RDLocalization.string("localizable.profile.view.verilerin.hazirlaniyor.d55ba0a4", table: .localizable, fallback: "Verilerin hazırlanıyor...") : RDLocalization.string("localizable.profile.view.verilerimi.disa.aktar.dc7acfd7", table: .localizable, fallback: "Verilerimi dışa aktar"),
                        subtitle: actionInProgress == .exportData
                            ? RDLocalization.string("localizable.profile.view.json.dosyasi.olusturuluyor.ve.telefona.kaydedili.0072b550", table: .localizable, fallback: "JSON dosyası oluşturuluyor ve telefona kaydediliyor.")
                            : RDLocalization.string("localizable.profile.view.analiz.bulgu.rapor.ve.profil.ozetini.json.dosyas.f00cc2f4", table: .localizable, fallback: "Analiz, bulgu, rapor ve profil özetini JSON dosyası olarak al."),
                        action: .exportData,
                        onTap: onExport
                    )
                    if let exportedFile {
                        exportedFileCard(exportedFile)
                    }
                    dataActionButton(
                        icon: "doc.badge.minus",
                        title: RDLocalization.string("localizable.profile.view.tum.raporlarimi.sil.6f53b4d2", table: .localizable, fallback: "Tüm raporlarımı sil"),
                        subtitle: RDLocalization.string("localizable.profile.view.pdf.dosyalari.ve.rapor.arsiv.kayitlari.silinir.a.4c3468b2", table: .localizable, fallback: "PDF dosyaları ve rapor arşiv kayıtları silinir. Analizler kalır."),
                        action: .deleteReports,
                        danger: true,
                        onTap: onDeleteReports
                    )
                    dataActionButton(
                        icon: "trash",
                        title: RDLocalization.string("localizable.profile.view.tum.analizlerimi.sil.a1edc808", table: .localizable, fallback: "Tüm analizlerimi sil"),
                        subtitle: RDLocalization.string("localizable.profile.view.analizler.bulgular.fotograf.kayitlari.ve.bagli.r.0dde7277", table: .localizable, fallback: "Analizler, bulgular, fotoğraf kayıtları ve bağlı raporlar silinir."),
                        action: .deleteAnalyses,
                        danger: true,
                        onTap: onDeleteAnalyses
                    )
                    dataActionButton(
                        icon: "person.crop.circle.badge.xmark",
                        title: RDLocalization.string("localizable.profile.view.hesabimi.sil.delete.account.55b97b6d", table: .localizable, fallback: "Hesabımı sil / Delete Account"),
                        subtitle: RDLocalization.string("localizable.profile.view.profil.analizler.raporlar.ve.dosyalar.kalici.sil.9e71da32", table: .localizable, fallback: "Profil, analizler, raporlar ve dosyalar kalıcı silinir. E-posta, destek veya web sitesi gerekmez."),
                        action: .requestAccountDeletion,
                        danger: true,
                        onTap: onRequestAccountDeletion
                    )

                    Text(RDLocalization.string("localizable.profile.view.not.otomatik.saklama.politikasi.ayrica.calisir.f.503d8159", table: .localizable, fallback: "Not: Otomatik saklama politikası ayrıca çalışır. Free fotoğraflar 7 gün, Plus fotoğraflar 30 gün, Pro fotoğraflar sınırsız saklanır; raporlar kullanıcı silene kadar kalır."))
                        .font(RDTypography.font(size: RDFontScale.size(12), design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .background(Color.rdFog)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(20)
            }
            .background(Color.rdPaper)
            .navigationTitle(RDLocalization.string("localizable.profile.view.verilerim.5155c570", table: .localizable, fallback: "Verilerim"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    RDModalCloseButton(action: onClose)
                }
            }
        }
        .onChange(of: exportedFile?.url) { url in
            if let url {
                presentedExportURL = url
            }
        }
        .sheet(item: $exportedFile, onDismiss: cleanupPresentedExport) { item in
            DocumentPreview(url: item.url)
        }
    }

    private func cleanupPresentedExport() {
        guard let url = presentedExportURL else { return }
        AnalysisService.shared.removeUserDataExport(at: url)
        presentedExportURL = nil
        exportedFile = nil
    }

    private var summaryCard: some View {
        HStack(spacing: 8) {
            dataStat(value: stats.map { "\($0.analysisCount)" } ?? "—", label: RDLocalization.string("localizable.profile.view.analiz.9f69382f", table: .localizable, fallback: "Analiz"))
            dataStat(value: stats.map { "\($0.reportCount)" } ?? "—", label: RDLocalization.string("localizable.profile.view.rapor.2d7e4997", table: .localizable, fallback: "Rapor"))
            dataStat(value: stats.map { "\($0.weeklyAnalysisCount)" } ?? "—", label: RDLocalization.string("localizable.profile.view.bu.hafta.2b64a66a", table: .localizable, fallback: "Bu hafta"))
        }
    }

    private func dataStat(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .rdMono(size: 18, weight: .bold)
                .foregroundStyle(Color.rdBlack)
            Text(label)
                .font(RDTypography.font(size: RDFontScale.size(11), weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdSlate)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func dataActionButton(
        icon: String,
        title: String,
        subtitle: String,
        action: ProfileDataAction,
        danger: Bool = false,
        onTap: @escaping () -> Void
    ) -> some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(RDTypography.font(size: RDFontScale.size(17), weight: .semibold, design: .rounded))
                    .foregroundStyle(danger ? Color.rdCriticalText : Color.rdGreen)
                    .frame(width: 42, height: 42)
                    .background(danger ? Color.rdCriticalBg : Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(RDTypography.font(size: RDFontScale.size(15), weight: .bold, design: .rounded))
                        .foregroundStyle(danger ? Color.rdCriticalText : Color.rdBlack)
                    Text(subtitle)
                        .font(RDTypography.font(size: RDFontScale.size(12), design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if actionInProgress == action {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(RDTypography.font(size: RDFontScale.size(12), weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                }
            }
            .padding(14)
            .background(Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(danger ? Color.rdCritical.opacity(0.22) : Color.rdLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(RDPressableButtonStyle())
        .disabled(actionInProgress != nil)
    }

    private func exportedFileCard(_ item: ShareItem) -> some View {
        Button {
            exportedFile = item
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(RDTypography.font(size: RDFontScale.size(17), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreen)
                    .frame(width: 42, height: 42)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(RDLocalization.string("localizable.profile.view.telefona.kaydedildi.6de9dab3", table: .localizable, fallback: "Telefona kaydedildi"))
                        .font(RDTypography.font(size: RDFontScale.size(15), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(item.url.lastPathComponent)
                        .font(RDTypography.font(size: RDFontScale.size(12), design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "doc.text.magnifyingglass")
                    .font(RDTypography.font(size: RDFontScale.size(14), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
            }
            .padding(14)
            .background(Color.rdGreenSoft.opacity(0.45))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.rdGreen.opacity(0.28), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityLabel(RDLocalization.string("localizable.profile.view.disa.aktarilan.dosyayi.ac.c6b2b658", table: .localizable, fallback: "Dışa aktarılan dosyayı aç"))
    }
}

struct ProfileRow: View {
    @Environment(\.colorScheme) private var colorScheme

    let icon: String
    let title: String
    var subtitle: String? = nil
    var detail: String? = nil
    var danger: Bool = false
    var showsChevron: Bool = true

    private var iconFill: Color {
        if danger {
            return colorScheme == .dark ? Color.rdCritical.opacity(0.16) : Color.rdCriticalBg
        }
        return colorScheme == .dark ? Color(hex: "#1B2220") : Color.rdFog
    }

    private var iconColor: Color {
        if danger { return Color.rdCriticalText }
        return colorScheme == .dark ? Color.rdSlate : Color.rdCharcoal
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(RDTypography.font(size: RDFontScale.size(14), weight: .semibold, design: .rounded))
                .frame(width: 32, height: 32)
                .foregroundStyle(iconColor)
                .background(iconFill)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(RDTypography.font(size: RDFontScale.size(15), weight: .medium, design: .rounded))
                    .foregroundStyle(danger ? Color.rdCriticalText : Color.rdBlack)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .font(RDTypography.font(size: RDFontScale.size(12), weight: .medium, design: .rounded))
                        .foregroundStyle(danger ? Color.rdCriticalText.opacity(0.82) : Color.rdSlate)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
                .frame(maxWidth: .infinity, alignment: .leading)

            if let detail {
                Text(detail)
                    .rdMono(size: 13, weight: .medium)
                    .foregroundStyle(Color.rdSlate)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(RDTypography.font(size: RDFontScale.size(12), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
    }
}

private struct ProfilePreferencesSheet: View {
    @Environment(\.dismiss) private var dismiss
    let themePreference: RDThemePreference
    let languagePreference: RDLanguagePreference
    let safetyProfileID: RDSafetyProfileID?
    let onThemeChange: (RDThemePreference) -> Void
    let onSafetyProfileChange: (RDSafetyProfileID) -> Void

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    preferenceSection(
                        title: RDLocalization.string("localizable.profile.view.tema.80e8d059", table: .localizable, fallback: "Tema"),
                        subtitle: RDLocalization.string("localizable.profile.view.uygulamanin.gorunumunu.cihazina.veya.kendi.secim.0450bf6d", table: .localizable, fallback: "Uygulamanın görünümünü cihazına veya kendi seçimine göre ayarla.")
                    ) {
                        VStack(spacing: 10) {
                            ForEach(RDThemePreference.allCases) { preference in
                                PreferenceOptionRow(
                                    icon: preference.icon,
                                    title: preference.title,
                                    subtitle: preference.subtitle,
                                    isSelected: themePreference == preference
                                ) {
                                    onThemeChange(preference)
                                    UISelectionFeedbackGenerator().selectionChanged()
                                }
                            }
                        }
                    }

                    preferenceSection(
                        title: RDLocalization.string("localizable.profile.view.dil.5398169b", table: .localizable, fallback: "Dil"),
                        subtitle: RDLocalization.string("localizable.profile.view.uygulama.dili.ios.ayarlari.ndaki.riskdetected.bo.0f4db4b6", table: .localizable, fallback: "Uygulama dili iOS Ayarları'ndaki RiskDetected bölümünden değiştirilir.")
                    ) {
                        PreferenceOptionRow(
                            icon: "gearshape.fill",
                            title: languagePreference.title,
                            subtitle: RDLocalization.string("localizable.profile.view.ios.ayarlari.nda.uygulama.dilini.ac.10562d1d", table: .localizable, fallback: "iOS Ayarları'nda uygulama dilini aç"),
                            isSelected: true
                        ) {
                            openApplicationSettings()
                        }
                    }

                    if languagePreference == .english {
                        preferenceSection(
                            title: RDLocalization.string(
                                "safety.profile.title",
                                table: .safetyTerminology,
                                fallback: "İş güvenliği terminolojini seç"
                            ),
                            subtitle: RDLocalization.string(
                                "safety.profile.body",
                                table: .safetyTerminology,
                                fallback: "Çalışmanda kullanılan terminolojiyi seç. Bu seçim analiz ve rapor ifadelerini değiştirir; yasal uyumluluğu belgelemez."
                            )
                        ) {
                            VStack(spacing: 10) {
                                ForEach(RDSafetyProfileID.englishSelectionCases) { profileID in
                                    PreferenceOptionRow(
                                        icon: profileID.icon,
                                        title: profileID.localizedTitle,
                                        subtitle: profileID.localizedSubtitle,
                                        isSelected: safetyProfileID == profileID
                                    ) {
                                        onSafetyProfileChange(profileID)
                                        UISelectionFeedbackGenerator().selectionChanged()
                                    }
                                }
                            }
                        }

                        Text(
                            RDLocalization.string(
                                "safety.profile.footer",
                                table: .safetyTerminology,
                                fallback: "Gelecekteki analizler için bu seçimi Profil’den değiştirebilirsin."
                            )
                        )
                            .font(RDTypography.font(size: RDFontScale.size(12), design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(Color.rdPaper)
            .navigationTitle(RDLocalization.string("localizable.profile.view.tercihler.5764236d", table: .localizable, fallback: "Tercihler"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    RDModalCloseButton {
                        dismiss()
                    }
                }
            }
        }
        .preferredColorScheme(themePreference.colorScheme)
    }

    private func openApplicationSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func preferenceSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(RDTypography.font(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(Color.rdSlate)
                Text(subtitle)
                    .font(RDTypography.font(size: RDFontScale.size(13), weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)

            content()
        }
    }
}

private struct PreferenceOptionRow: View {
    let icon: String
    let title: String
    let subtitle: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(RDTypography.font(size: RDFontScale.size(15), weight: .bold, design: .rounded))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(isSelected ? Color.white : Color.rdCharcoal)
                    .background(isSelected ? Color.rdSelected : Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(RDTypography.font(size: RDFontScale.size(15), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(subtitle)
                        .font(RDTypography.font(size: RDFontScale.size(12), weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(RDTypography.font(size: RDFontScale.size(20), weight: .semibold, design: .rounded))
                    .foregroundStyle(isSelected ? Color.rdGreen : Color.rdSlate.opacity(0.55))
            }
            .padding(14)
            .background(Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(isSelected ? Color.rdGreen.opacity(0.55) : Color.rdLine, lineWidth: isSelected ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityLabel(title)
        .accessibilityIdentifier("profile.preference.\(title)")
        .accessibilityValue(isSelected ? RDLocalization.string("localizable.profile.view.secili.74479879", table: .localizable, fallback: "Seçili") : RDLocalization.string("localizable.profile.view.secili.degil.14691146", table: .localizable, fallback: "Seçili değil"))
    }
}

private struct ProfileOnboardingSummary: Decodable, Equatable {
    let certificateClass: String?

    enum CodingKeys: String, CodingKey {
        case certificateClass = "certificate_class"
    }
}

private struct ProfileBadgesSheetItem: Identifiable {
    let id = UUID()
    let summary: ProfessionalProgressSummary
}

extension View {
    func profileCardDepth(colorScheme: ColorScheme, accent: Color = Color.rdBlack) -> some View {
        rdCardShadow(colorScheme: colorScheme, accent: accent)
    }
}

#Preview {
    ProfileView()
        .environmentObject({ let s = AppState(); s.flow = .main; return s }())
}
