import SwiftUI

struct ProfileView: View {
    @EnvironmentObject var app: AppState
    @State private var showPaywall = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                RDLogo(size: 18)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 4)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    profileHeader
                    statsRow
                    if app.isPro { proCard } else { upsellCard }
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
        .fullScreenCover(isPresented: $showPaywall) {
            PaywallView(onClose: { showPaywall = false },
                        onSubscribe: {
                            app.isPro = true
                            showPaywall = false
                        })
        }
    }

    // MARK: - Header

    private var profileHeader: some View {
        HStack(spacing: 14) {
            RDAvatar(
                initials: app.profile?.displayInitials ?? "—",
                size: 64,
                pro: app.isPro
            )
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(app.profile?.displayName ?? "Kullanıcı")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(Color.rdBlack)
                    if app.isPro { RDProBadge(small: true) }
                }
                if let title = app.profile?.title {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.rdSlate)
                }
                if let email = app.profile?.email {
                    Text(email)
                        .font(.system(size: 12))
                        .foregroundStyle(Color.rdSlate)
                }
            }
            Spacer()
        }
    }

    // MARK: - Stats

    private struct Stat { let value: String; let label: String }
    private let stats: [Stat] = [
        .init(value: "128", label: "Analiz"),
        .init(value: "47",  label: "Rapor"),
        .init(value: "21",  label: "Bu hafta")
    ]

    private var statsRow: some View {
        HStack(spacing: 8) {
            ForEach(Array(stats.enumerated()), id: \.offset) { _, s in
                VStack(spacing: 2) {
                    Text(s.value)
                        .rdMono(size: 22, weight: .bold)
                        .foregroundStyle(Color.rdBlack)
                    Text(s.label)
                        .font(.system(size: 11, weight: .semibold))
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
        Button {
            showPaywall = true
        } label: {
            ZStack(alignment: .topLeading) {
                Circle()
                    .fill(Color.rdGreen.opacity(0.18))
                    .frame(width: 120, height: 120)
                    .offset(x: 230, y: -45)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        RDProBadge(small: true)
                        Text("Aktif · Yıllık plan")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.7))
                    }

                    Text("Bir sonraki ödeme")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.top, 4)

                    Text("02 Mayıs 2027 · ₺1.799,99")
                        .rdMono(size: 13, weight: .medium)
                        .foregroundStyle(.white.opacity(0.7))

                    HStack(spacing: 4) {
                        Text("Üyeliğimi yönet")
                            .font(.system(size: 13, weight: .semibold))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(Color.rdGreen)
                    .padding(.top, 10)
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.rdBlack)
            .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        }
        .buttonStyle(RDPressableButtonStyle())
    }

    private var upsellCard: some View {
        Button {
            showPaywall = true
        } label: {
            VStack(alignment: .leading, spacing: 6) {
                RDProBadge()
                Text("Pro'ya yükselt")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 8)
                Text("Sınırsız PDF rapor, gelişmiş AI canvasları ve risk matrisi.")
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.75))
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.rdBlack)
            .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        }
        .buttonStyle(RDPressableButtonStyle())
    }

    // MARK: - Lists

    private var accountList: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Hesap")
            VStack(spacing: 0) {
                ProfileRow(icon: "doc.text", title: "Geçmiş analizler", detail: "128")
                Divider().background(Color.rdLine).padding(.leading, 60)
                ProfileRow(icon: "arrow.down.to.line", title: "Raporlarım", detail: "47")
                Divider().background(Color.rdLine).padding(.leading, 60)
                ProfileRow(icon: "bell", title: "Bildirimler")
            }
            .background(Color.rdWhite)
            .overlay(
                RoundedRectangle(cornerRadius: RDRadius.lg)
                    .stroke(Color.rdLine, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        }
    }

    private var settingsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionHeader("Ayarlar")
            VStack(spacing: 0) {
                ProfileRow(icon: "gearshape", title: "Tercihler")
                Divider().background(Color.rdLine).padding(.leading, 60)
                ProfileRow(icon: "lock", title: "Güvenlik ve gizlilik")
                Divider().background(Color.rdLine).padding(.leading, 60)
                ProfileRow(icon: "headphones", title: "Destek")
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
            .font(.system(size: 11, weight: .bold))
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
}

// MARK: - ProfileRow

struct ProfileRow: View {
    let icon: String
    let title: String
    var detail: String? = nil
    var danger: Bool = false
    var showsChevron: Bool = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 32, height: 32)
                .foregroundStyle(danger ? Color.rdCriticalText : Color.rdCharcoal)
                .background(danger ? Color.rdCriticalBg : Color.rdFog)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(danger ? Color.rdCriticalText : Color.rdBlack)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let detail {
                Text(detail)
                    .rdMono(size: 13, weight: .medium)
                    .foregroundStyle(Color.rdSlate)
            }
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.rdSlate)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

#Preview {
    ProfileView()
        .environmentObject({ let s = AppState(); s.flow = .main; return s }())
}
