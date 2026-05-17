import SwiftUI
import PhotosUI
import UIKit
import UserNotifications

struct ProfileView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var notifications = NotificationService.shared
    @State private var showPaywall = false
    @State private var showProfileEditor = false
    @State private var showNotificationSettings = false
    @State private var showDataControls = false
    @State private var showPreferences = false
    @State private var showLegalInfo = false
    @State private var showSupport = false
    @State private var stats: ProfileStats? = nil
    @State private var dataActionInProgress: ProfileDataAction?
    @State private var pendingDataAction: ProfileDataAction?
    @State private var dataMessage: String?
    @State private var shareItem: ShareItem?
    private var preferredModalColorScheme: ColorScheme {
        app.themePreference.colorScheme ?? colorScheme
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                RDLogo(size: 18)
                Spacer()
                RDHeaderAccountCTA {
                    showPaywall = true
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 4)
            .zIndex(100)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    profileHeader
                    statsRow
                    if app.currentTier.isPaid { proCard } else { upsellCard }
                    accountList
                    settingsList
                    signOutCard
                    versionFootnote
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 110)
            }
        }
        .background(Color.rdPaper)
        .task {
            await loadStats()
        }
        .onChange(of: app.auth.session?.user.id) { _ in
            Task { await loadStats() }
        }
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(onClose: { showPaywall = false },
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
        .sheet(isPresented: $showNotificationSettings) {
            NotificationSettingsSheet(
                notificationService: notifications,
                onClose: { showNotificationSettings = false }
            )
            .presentationDetents([.medium])
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
        .sheet(item: $shareItem) { item in
            ShareSheet(items: [item.url])
                .preferredColorScheme(preferredModalColorScheme)
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
        .alert("Verilerim", isPresented: Binding(
            get: { dataMessage != nil },
            set: { if !$0 { dataMessage = nil } }
        )) {
            Button("Tamam") { dataMessage = nil }
        } message: {
            Text(dataMessage ?? "")
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        HStack(spacing: 14) {
            RDAvatar(
                initials: app.profile?.displayInitials ?? "—",
                size: 64,
                tier: app.currentTier
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(app.profile?.displayName ?? "Kullanıcı")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                if let title = app.profile?.title {
                    Text(title)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                }
                if let email = app.profile?.email {
                    Text(email)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                }
            }
            Spacer()
        }
    }

    // MARK: - Stats

    private struct Stat { let value: String; let label: String }
    private var statCards: [Stat] {
        [
            .init(value: stats.map { "\($0.analysisCount)" } ?? "—", label: "Analiz"),
            .init(value: stats.map { "\($0.reportCount)" } ?? "—", label: "Rapor"),
            .init(value: stats.map { "\($0.weeklyAnalysisCount)" } ?? "—", label: "Bu hafta")
        ]
    }

    private var statsRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(statCards.enumerated()), id: \.offset) { _, s in
                VStack(spacing: 2) {
                    Text(s.value)
                        .rdMono(size: 22, weight: .bold)
                        .foregroundStyle(Color.rdBlack)
                    Text(s.label)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: RDRadius.lg)
                        .fill(Color.rdWhite)
                        .overlay(
                            RoundedRectangle(cornerRadius: RDRadius.lg)
                                .stroke(Color.rdLine, lineWidth: 1)
                        )
                )
            }
        }
    }

    // MARK: - Pro card

    private var proCard: some View {
        ZStack(alignment: .topLeading) {
            Circle()
                .fill(app.currentTier.accentColor.opacity(0.18))
                .frame(width: 120, height: 120)
                .offset(x: 230, y: -45)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    RDTierBadge(tier: app.currentTier, small: true)
                    Text("Aktif · \(subscriptionPeriodLabel)")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.7))
                }

                Text(subscriptionPaymentTitle)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.top, 4)

                Text(subscriptionRenewalLabel)
                    .rdMono(size: 13, weight: .medium)
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.rdOnyx)
        .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        .allowsHitTesting(false)
    }

    private var upsellCard: some View {
        Button {
            showPaywall = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(Color.rdPlanPlus.opacity(0.18))
                    .frame(width: 132, height: 132)
                    .offset(x: 48, y: -58)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        RDTierBadge(tier: .plus)
                        RDTierBadge(tier: .pro)
                    }
                    Text("Plus veya Pro'ya yükselt")
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.top, 8)
                    Text("Günlük daha yüksek analiz hakkı, detaylı analiz, gelişmiş raporlama, gelişmiş canvas kullanımı, Fine-Kinney ve 5*5 Matris risk analiz methodları, özelleştirilmiş PDF ve Excel rapor çıktıları ve daha fazlası...")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [Color.rdOnyx, Color.rdOnyx.opacity(0.94), Color.rdPlanPlus.opacity(0.14), Color.rdGreen.opacity(0.12)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: RDRadius.lg)
                    .stroke(Color.rdPlanPlus.opacity(0.28), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
            .shadow(color: Color.rdPlanPlus.opacity(0.14), radius: 18, x: 0, y: 10)
        }
        .buttonStyle(RDPressableButtonStyle())
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
                Divider().background(Color.rdLine).padding(.leading, 60)
                Button {
                    showNotificationSettings = true
                } label: {
                    ProfileRow(icon: "bell", title: "Bildirimler")
                }
                .buttonStyle(.plain)
            }
            .background(Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: RDRadius.lg)
                    .stroke(Color.rdLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
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
                    ProfileRow(icon: "lock", title: "Güvenlik ve gizlilik")
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
            .background(Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: RDRadius.lg)
                    .stroke(Color.rdLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        }
    }

    private var signOutCard: some View {
        Button {
            app.signOut()
        } label: {
            ProfileRow(icon: "rectangle.portrait.and.arrow.right", title: "Çıkış yap",
                       danger: true, showsChevron: false)
                .background(Color.rdWhite)
                .overlay(
                    RoundedRectangle(cornerRadius: RDRadius.lg)
                        .stroke(Color.rdLine, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .bold, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(Color.rdSlate)
            .padding(.leading, 4)
    }

    private var versionFootnote: some View {
        Text("v1.4.0 · build 2841")
            .rdMono(size: 11)
            .foregroundStyle(Color.rdSlate)
            .frame(maxWidth: .infinity)
            .padding(.top, 6)
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
            return "Yenileme bilgisi bekleniyor"
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

    private func loadStats() async {
        guard app.auth.session != nil else { return }
        do {
            stats = try await AnalysisService.shared.profileStats()
        } catch {
            stats = nil
        }
    }

    private func runDataAction(_ action: ProfileDataAction) {
        guard dataActionInProgress == nil else { return }
        pendingDataAction = nil

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
                    shareItem = ShareItem(url: url)
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
                    try await AnalysisService.shared.requestAccountDeletion(
                        userID: userID,
                        email: app.profile?.email,
                        requestID: requestID,
                        supportID: supportID
                    )
                    dataMessage = "Hesap silme talebin kaydedildi. İşlem güvenli silme kuyruğunda tamamlanacak."
                }
            } catch {
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
            return "Hesap silme talebi oluşturulsun mu?"
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
            return "Talep kaydedilir. Hesap silme işlemi yetkili sunucu akışıyla tamamlanır."
        }
    }

    var confirmationButtonTitle: String {
        switch self {
        case .exportData: return "Dışa aktar"
        case .deleteReports: return "Tüm raporları sil"
        case .deleteAnalyses: return "Tüm analizleri sil"
        case .requestAccountDeletion: return "Talep oluştur"
        }
    }

    var errorContext: String {
        switch self {
        case .exportData: return "Veri dışa aktarımı oluşturulamadı"
        case .deleteReports: return "Raporlar silinemedi"
        case .deleteAnalyses: return "Analizler silinemedi"
        case .requestAccountDeletion: return "Hesap silme talebi kaydedilemedi"
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
                    Button("Kapat", action: onClose)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
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
                            .font(.system(size: 28, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                    }
                }
                .frame(width: 78, height: 68)

                VStack(alignment: .leading, spacing: 5) {
                    Text(companyLogo == nil ? "Logo ekle" : "Varsayılan rapor logosu")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text("Firma veya kişisel logon raporlarda varsayılan olarak kullanılır.")
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                PhotosPicker(selection: $selectedLogoItem, matching: .images) {
                    Image(systemName: companyLogo == nil ? "plus" : "arrow.triangle.2.circlepath")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
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
                    .font(.system(size: 13, weight: .bold, design: .rounded))
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
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Color.rdGreen)
                .frame(width: 24, height: 24)
                .background(Color.rdGreenSoft)
                .clipShape(RoundedRectangle(cornerRadius: 7))
            Text(title)
                .font(.system(size: 14, weight: .bold, design: .rounded))
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
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdBlack.opacity(0.72))
                .frame(width: 36, height: 36)
                .background(Color.rdCloud)
                .clipShape(RoundedRectangle(cornerRadius: 11))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                TextField(placeholder, text: text)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
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
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: iconName)
                            .font(.system(size: 22, weight: .semibold, design: .rounded))
                            .foregroundStyle(iconColor)
                            .frame(width: 48, height: 48)
                            .background(iconColor.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 14))

                        VStack(alignment: .leading, spacing: 6) {
                            Text(statusTitle)
                                .font(.system(size: 18, weight: .bold, design: .rounded))
                                .foregroundStyle(Color.rdBlack)
                            Text(statusMessage)
                                .font(.system(size: 13, design: .rounded))
                                .foregroundStyle(Color.rdSlate)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                VStack(spacing: 10) {
                    notificationRow(icon: "checkmark.seal", title: "Analiz tamamlandı", subtitle: "Uzun süren analizlerde sonucu kaçırma.")
                    notificationRow(icon: "doc.richtext", title: "Rapor hazır", subtitle: "PDF arşivleme ve paylaşım akışlarında haber ver.")
                    notificationRow(icon: "person.crop.circle.badge.checkmark", title: "Hesap ve güvenlik", subtitle: "Oturum, profil ve önemli hesap durumları.")
                }

                if let lastError = notificationService.lastError {
                    Text(lastError)
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdCriticalText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)

                if notificationService.authorizationStatus == .denied {
                    RDButton(
                        title: "Ayarlar'dan aç",
                        style: .primary,
                        icon: "gearshape.fill",
                        height: 52
                    ) {
                        openSystemSettings()
                    }
                } else if isEnabled {
                    RDButton(
                        title: "Bildirimleri kapat",
                        style: .secondary,
                        icon: "bell.slash",
                        height: 52
                    ) {
                        notificationService.disableNotifications()
                    }
                } else {
                    RDButton(
                        title: notificationService.isRegistering ? "Bildirimler kuruluyor..." : "Bildirimleri aç",
                        style: .detect,
                        icon: notificationService.isRegistering ? "hourglass" : "bell.badge.fill",
                        height: 52
                    ) {
                        notificationService.requestPermissionAndRegister()
                    }
                    .disabled(notificationService.isRegistering)
                    .opacity(notificationService.isRegistering ? 0.72 : 1)
                }
            }
            .padding(20)
            .background(Color.rdPaper)
            .navigationTitle("Bildirimler")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Kapat", action: onClose)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                }
            }
            .task {
                await notificationService.refreshSettings()
            }
        }
    }

    private var isEnabled: Bool {
        switch notificationService.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private var statusTitle: String {
        switch notificationService.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Bildirimler açık"
        case .denied:
            return "Bildirim izni kapalı"
        case .notDetermined:
            return "Bildirimleri kur"
        @unknown default:
            return "Bildirim durumu kontrol edilemedi"
        }
    }

    private var statusMessage: String {
        switch notificationService.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return "Cihaz kaydı Supabase ile eşleştiğinde analiz ve rapor durumları için bildirim alabileceksin."
        case .denied:
            return "iOS bildirim izni kapalı. RiskDetected bildirimlerini cihaz ayarlarından tekrar açabilirsin."
        case .notDetermined:
            return "Önemli analiz, rapor ve hesap durumlarını kaçırmamak için cihaz bildirim iznini aç."
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

    private func notificationRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdGreenDark)
                .frame(width: 38, height: 38)
                .background(Color.rdGreenSoft)
                .clipShape(RoundedRectangle(cornerRadius: 11))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                Text(subtitle)
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(Color.rdSlate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct ProfileDataControlsSheet: View {
    let stats: ProfileStats?
    let actionInProgress: ProfileDataAction?
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
                        title: "Verilerimi dışa aktar",
                        subtitle: "Analiz, bulgu, rapor ve profil özetini JSON dosyası olarak al.",
                        action: .exportData,
                        onTap: onExport
                    )
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
                        title: "Hesabımı silme talebi",
                        subtitle: "Talep kaydı oluşturulur; hesap silme güvenli sunucu sürecinde tamamlanır.",
                        action: .requestAccountDeletion,
                        danger: true,
                        onTap: onRequestAccountDeletion
                    )

                    Text("Not: Otomatik saklama politikası ayrıca çalışır. Free fotoğraflar 7 gün, Plus fotoğraflar 30 gün, Pro fotoğraflar sınırsız saklanır; raporlar kullanıcı silene kadar kalır.")
                        .font(.system(size: 12, design: .rounded))
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
                    Button("Kapat", action: onClose)
                }
            }
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
                .font(.system(size: 11, weight: .semibold, design: .rounded))
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
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(danger ? Color.rdCriticalText : Color.rdGreen)
                    .frame(width: 42, height: 42)
                    .background(danger ? Color.rdCriticalBg : Color.rdGreenSoft)
                    .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(danger ? Color.rdCriticalText : Color.rdBlack)
                    Text(subtitle)
                        .font(.system(size: 12, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if actionInProgress == action {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
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
}

struct ProfileRow: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var danger: Bool = false
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .frame(width: 32, height: 32)
                .foregroundStyle(danger ? Color.rdCriticalText : Color.rdCharcoal)
                .background(danger ? Color.rdCriticalBg : Color.rdFog)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(danger ? Color.rdCriticalText : Color.rdBlack)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let detail {
                Text(detail)
                    .rdMono(size: 13, weight: .medium)
                    .foregroundStyle(Color.rdSlate)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
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
                    Button("Kapat") { dismiss() }
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
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
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .tracking(0.6)
                    .foregroundStyle(Color.rdSlate)
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
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
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(isSelected ? Color.white : Color.rdCharcoal)
                    .background(isSelected ? Color.rdSelected : Color.rdFog)
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
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
        .accessibilityValue(isSelected ? "Seçili" : "Seçili değil")
    }
}

#Preview {
    ProfileView()
        .environmentObject({ let s = AppState(); s.flow = .main; return s }())
}
