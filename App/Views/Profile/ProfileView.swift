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
        .sheet(isPresented: $showDataControls) {
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
                title: "Firmalarım",
                accessTier: app.currentTier,
                selectedCompanyID: nil,
                allowNoCompany: false,
                allowsSelection: false,
                onSelect: { _ in },
                onPaywall: {
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
                onThemeChange: { app.setThemePreference($0) },
                onLanguageChange: { app.setLanguagePreference($0) }
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
                onClose: { showSupport = false }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .preferredColorScheme(preferredModalColorScheme)
        }
        .sheet(isPresented: $showProfessionalTitlesFromHeader) {
            if let professionalProgressSummary {
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
        .alert("Profil fotoğrafı güncellenemedi", isPresented: Binding(
            get: { profileAvatarError != nil },
            set: { if !$0 { profileAvatarError = nil } }
        )) {
            Button("Tamam", role: .cancel) { profileAvatarError = nil }
        } message: {
            Text(profileAvatarError ?? "")
        }
        .confirmationDialog(
            pendingDataAction?.confirmationTitle ?? "İşlem onayı",
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
            Button("Vazgeç", role: .cancel) {
                pendingDataAction = nil
            }
        } message: {
            Text(pendingDataAction?.confirmationMessage ?? "")
        }
        .alert(dataAlertTitle, isPresented: Binding(
            get: { dataMessage != nil },
            set: { if !$0 { dismissDataMessage() } }
        )) {
            Button("Tamam") { dismissDataMessage() }
        } message: {
            Text(dataMessage ?? "")
        }
        .alert("Satın alımları geri yükle", isPresented: Binding(
            get: { restoreMessage != nil },
            set: { if !$0 { restoreMessage = nil } }
        )) {
            Button("Tamam") { restoreMessage = nil }
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
                            .font(.system(size: RDFontScale.size(23), weight: .bold, design: .rounded))
                            .foregroundStyle(Color.rdBlack)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)
                            .padding(.top, 50)

                        Text(profileExpertiseLabel)
                            .font(.system(size: RDFontScale.size(13.5), weight: .medium, design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                            .lineSpacing(2)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)

                        if let professionalProgressSummary {
                            Button {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                showProfileBadges(professionalProgressSummary)
                            } label: {
                                Label("Başarılarım", systemImage: "rosette")
                                    .font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.rdGreenDark)
                            }
                            .buttonStyle(.plain)
                            .padding(.top, 6)
                            .accessibilityLabel("Başarılarım")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 24)
                    .padding(.bottom, professionalProgressSummary == nil ? 16 : 12)

                    profileHeroStatsRow
                }

                profileAvatarPicker
                    .offset(x: 28, y: 96)

                professionalTitleBadge
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 202)
                    .padding(.trailing, 16)
                    .offset(y: 172)
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
        .accessibilityLabel("Profil fotoğrafı")
        .accessibilityHint("Fotoğraf seçmek veya değiştirmek için dokun")
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
                .font(.system(size: RDFontScale.size(11), weight: .black, design: .rounded))
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
                .font(.system(size: RDFontScale.size(12), weight: .black, design: .rounded))
                .foregroundStyle(Color.rdWhite)
                .frame(width: 28, height: 28)
                .background(Color.rdPlanPlus)
                .clipShape(Circle())
                .overlay(Circle().stroke(profileCardFill, lineWidth: 3))
                .shadow(color: Color.rdPlanPlus.opacity(0.30), radius: 8, x: 0, y: 4)
        case .pro:
            Image(systemName: "star.fill")
                .font(.system(size: RDFontScale.size(12), weight: .black, design: .rounded))
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
                    .font(.system(size: RDFontScale.size(10.5), weight: .black, design: .rounded))
                    .foregroundStyle(Color.rdWhite)
                    .frame(width: 21, height: 21)
                    .background(professionalTitleAccent)
                    .clipShape(Circle())

                Text(professionalTitleLabel)
                    .font(.system(size: RDFontScale.size(11.5), weight: .bold, design: .rounded))
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
        .accessibilityLabel("Mesleki ünvan: \(professionalTitleLabel)")
        .accessibilityHint("Mesleki ilerleme penceresini açar")
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
                    .font(.system(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
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
                        .font(.system(size: RDFontScale.size(9), weight: .semibold, design: .rounded))
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
                label: "Analiz",
                icon: "waveform.path.ecg",
                color: .rdInfo
            ),
            .init(
                value: stats.map { "\($0.reportCount)" } ?? "—",
                label: "Rapor",
                icon: "doc.text.fill",
                color: .rdGreen
            ),
            .init(
                value: weeklyProfileStatValue,
                label: "Bu hafta",
                icon: "calendar.badge.checkmark",
                color: .rdPlanPlus
            ),
            .init(
                value: professionalProgressSummary.map { "\($0.profile.highFindings + $0.profile.criticalFindings)" } ?? "—",
                label: "Yüksek/\nKritik",
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
        app.profile?.displayName ?? "Kullanıcı"
    }

    private var profileExpertiseLabel: String {
        switch onboardingSummary?.certificateClass {
        case "A":
            return "A Sınıfı İş Güvenliği Uzmanı"
        case "B":
            return "B Sınıfı İş Güvenliği Uzmanı"
        case "C":
            return "C Sınıfı İş Güvenliği Uzmanı"
        case "doctor":
            return "İşyeri Hekimi"
        case "otherHealth":
            return "Diğer Sağlık Personeli"
        default:
            if let title = app.profile?.title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
                return title
            }
            return "İSG Uzmanı"
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
                Text("\(subscriptionPaymentTitle) aktif")
                    .font(.system(size: RDFontScale.size(14), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .lineLimit(1)

                Text("\(subscriptionPeriodLabel) · \(subscriptionRenewalLabel)")
                    .font(.system(size: RDFontScale.size(12), weight: .medium, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 8)

            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: RDFontScale.size(18), weight: .semibold, design: .rounded))
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
            showPaywall = true
        }
    }

    // MARK: - Lists

    private var accountList: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Hesap")
            VStack(spacing: 0) {
                Button {
                    showProfileEditor = true
                } label: {
                    ProfileRow(icon: "person.text.rectangle", title: "Profil bilgileri")
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
                        title: "Firmalarım",
                        detail: app.currentTier.isPaid ? "Yönet" : "Plus/Pro"
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
                    ProfileRow(icon: "doc.text", title: "Geçmiş analizler", detail: stats.map { "\($0.analysisCount)" } ?? "—")
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
                    ProfileRow(icon: "arrow.down.to.line", title: "Raporlarım", detail: stats.map { "\($0.reportCount)" } ?? "—")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.row.reports")
                Divider().background(Color.rdLine).padding(.leading, 60)
                Button {
                    showNotificationSettings = true
                } label: {
                    ProfileRow(icon: "bell", title: "Bildirimler")
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
            return "Açık"
        case .denied:
            return "Kapalı"
        case .notDetermined:
            return "Kur"
        @unknown default:
            return "Kontrol et"
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
            sectionHeader("Ayarlar")
            VStack(spacing: 0) {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    showPreferences = true
                } label: {
                    ProfileRow(icon: "gearshape", title: "Tercihler")
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.row.preferences")
                Divider().background(Color.rdLine).padding(.leading, 60)
                Button {
                    restorePurchasesFromProfile()
                } label: {
                    ProfileRow(
                        icon: "arrow.clockwise.circle",
                        title: "Satın alımları geri yükle",
                        detail: isRestoringPurchases ? "Bekle" : app.currentTier.title
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
                            title: "App Store aboneliğini yönet",
                            detail: "Apple"
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("profile.row.manage_app_store_subscription")
                }
                Divider().background(Color.rdLine).padding(.leading, 60)
                Button {
                    showDataControls = true
                } label: {
                    ProfileRow(icon: "externaldrive.badge.checkmark", title: "Verilerim")
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
                        title: "Güvenlik ve gizlilik",
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
                    ProfileRow(icon: "headphones", title: "Destek")
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
                    ? "\(restoredState.tier.title) aboneliğin doğrulandı."
                    : "Geri yüklenecek aktif abonelik bulunamadı."
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
                    .font(.system(size: RDFontScale.size(18), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdCriticalText)
                    .frame(width: 40, height: 40)
                    .background(Color.rdCriticalBg)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Cihaz güvenliği uyarısı")
                        .font(.system(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(deviceIntegrity.userMessage)
                        .font(.system(size: RDFontScale.size(12), weight: .medium, design: .rounded))
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
            ProfileRow(icon: "rectangle.portrait.and.arrow.right", title: "Çıkış yap",
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
                title: "Hesabımı sil / Delete Account",
                subtitle: "Hesap ve uygulama verilerini kalıcı olarak siler.",
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
            ? "Hesap silindi / Account Deleted"
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
            .font(.system(size: RDFontScale.size(11), weight: .bold, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(Color.rdSlate)
            .padding(.leading, 4)
    }

    private var subscriptionPeriodLabel: String {
        switch app.profile?.subscriptionPeriod {
        case "monthly": return "Aylık plan"
        case "yearly": return "Yıllık plan"
        case .some(let value): return value.capitalized
        case .none: return "\(app.currentTier.title) plan"
        }
    }

    private var subscriptionPaymentTitle: String {
        "\(app.currentTier.title) plan"
    }

    private var subscriptionRenewalLabel: String {
        guard let raw = app.profile?.subscriptionRenewalAt,
              let date = parseISODate(raw)
        else {
            return "App Store aboneliği aktif"
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "tr_TR")
        formatter.dateFormat = "d MMMM yyyy"
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
                    userInfo: [NSLocalizedDescriptionKey: "Fotoğraf okunamadı. Lütfen farklı bir görsel seç."]
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
        guard app.auth.session != nil, RDConfig.Features.professionalProgressEnabled else {
            professionalProgressSummary = nil
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
            exportedDataFile = nil
        }

        guard let userID = app.auth.session?.user.id else {
            dataMessage = AppErrorMessage.make(AnalysisService.AnalysisError.notAuthenticated, context: "Veri işlemi yapılamadı").fullText
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
                    dataMessage = "Tüm PDF raporların silindi."
                    await loadStats()
                case .deleteAnalyses:
                    try await AnalysisService.shared.deleteAllAnalyses(
                        requestID: requestID,
                        supportID: supportID
                    )
                    dataMessage = "Tüm analizlerin ve ilişkili bulgular/fotoğraflar silindi."
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
                        dataMessage = result.message ?? "Hesabın ve uygulama verilerin silindi."
                    } else {
                        dataMessage = result.message ?? "Hesap silme isteğin alındı. Güvenli silme işlemi devam ediyor."
                    }
                }
            } catch {
                shouldSignOutAfterDataMessageDismiss = false
                dataMessage = AppErrorMessage.make(
                    rawMessage: "\(error.localizedDescription)\nDestek kodu: \(supportID)",
                    context: action.errorContext,
                    fallbackTitle: action.errorContext
                ).fullText
            }
            dataActionInProgress = nil
        }
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
        case .exportData: return "exportData"
        case .deleteReports: return "deleteReports"
        case .deleteAnalyses: return "deleteAnalyses"
        case .requestAccountDeletion: return "requestAccountDeletion"
        }
    }

    var confirmationTitle: String {
        switch self {
        case .exportData:
            return "Veriler dışa aktarılsın mı?"
        case .deleteReports:
            return "Tüm raporlar silinsin mi?"
        case .deleteAnalyses:
            return "Tüm analizler silinsin mi?"
        case .requestAccountDeletion:
            return "Hesabın ve verilerin silinsin mi?"
        }
    }

    var confirmationMessage: String {
        switch self {
        case .exportData:
            return "Analiz, bulgu, fotoğraf yolu, rapor metadatası ve profil özetin JSON dosyası olarak hazırlanır."
        case .deleteReports:
            return "PDF rapor dosyaları ve rapor arşiv kayıtları silinir. Analiz sonuçların kalır."
        case .deleteAnalyses:
            return "Tüm analizler, bulgular, fotoğraf kayıtları ve bu analizlere bağlı raporlar silinir. Bu işlem geri alınamaz."
        case .requestAccountDeletion:
            return "Hesabın, profilin, analizlerin, raporların ve saklanan dosyaların kalıcı olarak silinir. Silme işlemi uygulama içinde tamamlanır; e-posta, destek veya web sitesi gerekmez. Aktif App Store aboneliğin varsa iptal ve yönetim işlemleri Apple abonelik ayarlarından yapılır. Bu işlem geri alınamaz."
        }
    }

    var confirmationButtonTitle: String {
        switch self {
        case .exportData: return "Dışa aktar"
        case .deleteReports: return "Tüm raporları sil"
        case .deleteAnalyses: return "Tüm analizleri sil"
        case .requestAccountDeletion: return "Hesabımı sil / Delete Account"
        }
    }

    var errorContext: String {
        switch self {
        case .exportData: return "Veri dışa aktarımı oluşturulamadı"
        case .deleteReports: return "Raporlar silinemedi"
        case .deleteAnalyses: return "Analizler silinemedi"
        case .requestAccountDeletion: return "Hesap silme işlemi başlatılamadı"
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
                        title: isSaving ? "Kaydediliyor..." : "Profili kaydet",
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
            .navigationTitle("Profil Bilgileri")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    RDModalCloseButton(action: onClose)
                }
            }
            .alert("Profil kaydedilemedi", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("Tamam", role: .cancel) { errorMessage = nil }
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
            sectionTitle("Logo", icon: "photo.badge.plus")
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
                            .font(.system(size: RDFontScale.size(28), weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                    }
                }
                .frame(width: 78, height: 68)

                VStack(alignment: .leading, spacing: 5) {
                    Text(companyLogo == nil ? "Logo ekle" : "Varsayılan rapor logosu")
                        .font(.system(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text("Firma veya kişisel logon raporlarda varsayılan olarak kullanılır.")
                        .font(.system(size: RDFontScale.size(12), design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                PhotosPicker(selection: $selectedLogoItem, matching: .images) {
                    Image(systemName: companyLogo == nil ? "plus" : "arrow.triangle.2.circlepath")
                        .font(.system(size: RDFontScale.size(15), weight: .bold, design: .rounded))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(Color.rdGreenDark)
                        .background(Color.rdGreenSoft)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .accessibilityLabel(companyLogo == nil ? "Logo seç" : "Logoyu değiştir")
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
            sectionTitle("Kimlik ve firma", icon: "building.2")
            VStack(spacing: 9) {
                profileField("Ad soyad", text: $fullName, placeholder: "Ad Soyad", icon: "person.fill")
                profileField("Ünvan / belge sınıfı", text: $title, placeholder: "İSG Uzmanı · A Sınıfı", icon: "checkmark.seal.fill")
                profileField("Sertifika no", text: $certificateNumber, placeholder: "Sertifika numarası", icon: "number")
                profileField("Firma adı", text: $companyName, placeholder: "Firma adı", icon: "building.2.fill")
                profileField("Telefon", text: $phone, placeholder: "+90 5xx xxx xx xx", icon: "phone.fill", keyboard: .phonePad)
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
            sectionTitle("Varsayılan risk metodu", icon: "function")
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
                    .font(.system(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                Text("R = \(method.domain.formula)")
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
                .font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreen)
                .frame(width: 24, height: 24)
                .background(Color.rdGreenSoft)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            Text(title)
                .font(.system(size: RDFontScale.size(14), weight: .bold, design: .rounded))
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
                .font(.system(size: RDFontScale.size(14), weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdBlack.opacity(0.72))
                .frame(width: 36, height: 36)
                .background(Color.rdCloud)
                .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                TextField(placeholder, text: text)
                    .font(.system(size: RDFontScale.size(15), weight: .medium, design: .rounded))
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
        preferredMethod = profile?.preferredMethod ?? .fineKinney
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
                    context: "Profil kaydedilemedi",
                    fallbackTitle: "Profil kaydedilemedi"
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
                        Image(systemName: iconName)
                            .font(.system(size: RDFontScale.size(19), weight: .semibold, design: .rounded))
                            .foregroundStyle(iconColor)
                            .frame(width: 42, height: 42)
                            .background(iconColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 13))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(statusTitle)
                                .font(.system(size: RDFontScale.size(16), weight: .bold, design: .rounded))
                                .foregroundStyle(Color.rdBlack)
                            Text(statusMessage)
                                .font(.system(size: RDFontScale.size(12), design: .rounded))
                                .foregroundStyle(Color.rdSlate)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                if let lastError = notificationService.lastError {
                    Text(lastError)
                        .font(.system(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdCriticalText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if isEnabled {
                    notificationTypesCard
                    progressPreferencesCard
                }

                if notificationService.authorizationStatus == .denied {
                    RDButton(
                        title: "Ayarlar'dan aç",
                        style: .primary,
                        icon: "gearshape.fill",
                        height: 48
                    ) {
                        openSystemSettings()
                    }
                } else if isEnabled {
                    RDButton(
                        title: "Bildirimleri kapat",
                        style: .secondary,
                        icon: "bell.slash",
                        height: 48
                    ) {
                        notificationService.disableNotifications()
                    }
                } else {
                    RDButton(
                        title: notificationService.isRegistering ? "Bildirimler kuruluyor..." : "Bildirimleri aç",
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
            .navigationTitle("Bildirimler")
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
                Text("Aktif bildirimler")
                    .font(.system(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)

                NotificationInfoRow(icon: "sparkles", title: "Analiz tamamlandı")
                NotificationInfoRow(icon: "doc.text.fill", title: "Rapor hazır")
                NotificationInfoRow(icon: "shield.checkered", title: "Hesap güvenliği")

                Divider()

                NotificationPreferenceToggle(
                    title: "Uygulama bildirimleri",
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
                Text("Mesleki ilerleme")
                    .font(.system(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)

                NotificationPreferenceToggle(
                    title: "Haftalık özet",
                    icon: "calendar",
                    isOn: notificationService.progressPreferenceEnabled(.weeklySummary)
                ) { isOn in
                    notificationService.setProgressPreference(.weeklySummary, enabled: isOn)
                }

                NotificationPreferenceToggle(
                    title: "Aylık özet",
                    icon: "calendar.badge.clock",
                    isOn: notificationService.progressPreferenceEnabled(.monthlySummary)
                ) { isOn in
                    notificationService.setProgressPreference(.monthlySummary, enabled: isOn)
                }

                NotificationPreferenceToggle(
                    title: "Rozet ve unvan",
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
        if notificationService.notificationsEnabled {
            return "Bildirimler açık"
        }
        switch notificationService.authorizationStatus {
        case .denied:
            return "Bildirimler kapalı"
        case .authorized, .provisional, .ephemeral:
            return "Bildirimler kapalı"
        case .notDetermined:
            return "Bildirimler kapalı"
        @unknown default:
            return "Bildirim durumu kontrol edilemedi"
        }
    }

    private var statusMessage: String {
        if notificationService.notificationsEnabled {
            return "Analiz sonuçları, raporlar, deneme süresi ve açık uygulama hatırlatmaları için bildirim alırsın."
        }
        switch notificationService.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Bildirimler uygulama içinde kapalı. Açtığında analiz sonuçları, raporlar, deneme süresi ve uygulama hatırlatmalarını tekrar alırsın."
        case .denied:
            return "Açtığında analiz sonuçları, raporlar, deneme süresi ve uygulama hatırlatmalarını alabilirsin."
        case .notDetermined:
            return "Açtığında analiz sonuçları, raporlar, deneme süresi ve uygulama hatırlatmalarını alabilirsin."
        @unknown default:
            return "Bildirim ayarlarını yenileyip tekrar dene."
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
                .font(.system(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdGreen)
                .frame(width: 24, height: 24)
                .background(Color.rdGreen.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(title)
                .font(.system(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdBlack)

            Spacer(minLength: 0)

            Text("Açık")
                .font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded))
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
                    .font(.system(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .frame(width: 24, height: 24)
                    .background(Color.rdSlate.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(title)
                    .font(.system(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
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

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    summaryCard
                    dataActionButton(
                        icon: "square.and.arrow.up",
                        title: actionInProgress == .exportData ? "Verilerin hazırlanıyor..." : "Verilerimi dışa aktar",
                        subtitle: actionInProgress == .exportData
                            ? "JSON dosyası oluşturuluyor ve telefona kaydediliyor."
                            : "Analiz, bulgu, rapor ve profil özetini JSON dosyası olarak al.",
                        action: .exportData,
                        onTap: onExport
                    )
                    if let exportedFile {
                        exportedFileCard(exportedFile)
                    }
                    dataActionButton(
                        icon: "doc.badge.minus",
                        title: "Tüm raporlarımı sil",
                        subtitle: "PDF dosyaları ve rapor arşiv kayıtları silinir. Analizler kalır.",
                        action: .deleteReports,
                        danger: true,
                        onTap: onDeleteReports
                    )
                    dataActionButton(
                        icon: "trash",
                        title: "Tüm analizlerimi sil",
                        subtitle: "Analizler, bulgular, fotoğraf kayıtları ve bağlı raporlar silinir.",
                        action: .deleteAnalyses,
                        danger: true,
                        onTap: onDeleteAnalyses
                    )
                    dataActionButton(
                        icon: "person.crop.circle.badge.xmark",
                        title: "Hesabımı sil / Delete Account",
                        subtitle: "Profil, analizler, raporlar ve dosyalar kalıcı silinir. E-posta, destek veya web sitesi gerekmez.",
                        action: .requestAccountDeletion,
                        danger: true,
                        onTap: onRequestAccountDeletion
                    )

                    Text("Not: Otomatik saklama politikası ayrıca çalışır. Free fotoğraflar 7 gün, Plus fotoğraflar 30 gün, Pro fotoğraflar sınırsız saklanır; raporlar kullanıcı silene kadar kalır.")
                        .font(.system(size: RDFontScale.size(12), design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .background(Color.rdFog)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .padding(20)
            }
            .background(Color.rdPaper)
            .navigationTitle("Verilerim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    RDModalCloseButton(action: onClose)
                }
            }
        }
        .sheet(item: $exportedFile) { item in
            DocumentPreview(url: item.url)
        }
    }

    private var summaryCard: some View {
        HStack(spacing: 8) {
            dataStat(value: stats.map { "\($0.analysisCount)" } ?? "—", label: "Analiz")
            dataStat(value: stats.map { "\($0.reportCount)" } ?? "—", label: "Rapor")
            dataStat(value: stats.map { "\($0.weeklyAnalysisCount)" } ?? "—", label: "Bu hafta")
        }
    }

    private func dataStat(value: String, label: String) -> some View {
        VStack(spacing: 3) {
            Text(value)
                .rdMono(size: 18, weight: .bold)
                .foregroundStyle(Color.rdBlack)
            Text(label)
                .font(.system(size: RDFontScale.size(11), weight: .semibold, design: .rounded))
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
                    .font(.system(size: RDFontScale.size(17), weight: .semibold, design: .rounded))
                    .foregroundStyle(danger ? Color.rdCriticalText : Color.rdGreen)
                    .frame(width: 42, height: 42)
                    .background(danger ? Color.rdCriticalBg : Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: RDFontScale.size(15), weight: .bold, design: .rounded))
                        .foregroundStyle(danger ? Color.rdCriticalText : Color.rdBlack)
                    Text(subtitle)
                        .font(.system(size: RDFontScale.size(12), design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if actionInProgress == action {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: RDFontScale.size(12), weight: .semibold, design: .rounded))
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
                    .font(.system(size: RDFontScale.size(17), weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdGreen)
                    .frame(width: 42, height: 42)
                    .background(Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text("Telefona kaydedildi")
                        .font(.system(size: RDFontScale.size(15), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(item.url.lastPathComponent)
                        .font(.system(size: RDFontScale.size(12), design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: RDFontScale.size(14), weight: .semibold, design: .rounded))
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
        .accessibilityLabel("Dışa aktarılan dosyayı aç")
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
                .font(.system(size: RDFontScale.size(14), weight: .semibold, design: .rounded))
                .frame(width: 32, height: 32)
                .foregroundStyle(iconColor)
                .background(iconFill)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: RDFontScale.size(15), weight: .medium, design: .rounded))
                    .foregroundStyle(danger ? Color.rdCriticalText : Color.rdBlack)
                    .lineLimit(2)
                    .minimumScaleFactor(0.82)
                    .fixedSize(horizontal: false, vertical: true)

                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: RDFontScale.size(12), weight: .medium, design: .rounded))
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
                    .font(.system(size: RDFontScale.size(12), weight: .semibold, design: .rounded))
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
    let onThemeChange: (RDThemePreference) -> Void
    let onLanguageChange: (RDLanguagePreference) -> Void

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    preferenceSection(
                        title: "Tema",
                        subtitle: "Uygulamanın görünümünü cihazına veya kendi seçimine göre ayarla."
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
                        title: "Dil",
                        subtitle: "Uygulama metinleri şimdilik Türkçe kalır."
                    ) {
                        VStack(spacing: 10) {
                            ForEach(RDLanguagePreference.supportedCases) { preference in
                                PreferenceOptionRow(
                                    icon: preference.icon,
                                    title: preference.title,
                                    subtitle: preference.subtitle,
                                    isSelected: languagePreference == preference
                                ) {
                                    onLanguageChange(preference)
                                    UISelectionFeedbackGenerator().selectionChanged()
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 28)
            }
            .background(Color.rdPaper)
            .navigationTitle("Tercihler")
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
        .onAppear {
            if !RDLanguagePreference.supportedCases.contains(languagePreference) {
                onLanguageChange(.turkish)
            }
        }
    }

    private func preferenceSection<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title.uppercased())
                    .font(.system(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(Color.rdSlate)
                Text(subtitle)
                    .font(.system(size: RDFontScale.size(13), weight: .medium, design: .rounded))
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
                    .font(.system(size: RDFontScale.size(15), weight: .bold, design: .rounded))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(isSelected ? Color.white : Color.rdCharcoal)
                    .background(isSelected ? Color.rdSelected : Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: RDFontScale.size(15), weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(subtitle)
                        .font(.system(size: RDFontScale.size(12), weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: RDFontScale.size(20), weight: .semibold, design: .rounded))
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
        .accessibilityValue(isSelected ? "Seçili" : "Seçili değil")
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
