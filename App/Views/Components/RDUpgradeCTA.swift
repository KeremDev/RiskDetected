import SwiftUI
import UIKit

struct RDUpgradeCTA: View {
    var tier: SubscriptionTier
    var isActive: Bool
    var title: String?
    var icon: String?
    var action: () -> Void

    init(isPro: Bool, action: @escaping () -> Void) {
        self.tier = .pro
        self.isActive = isPro
        self.title = nil
        self.icon = nil
        self.action = action
    }

    init(
        tier: SubscriptionTier,
        isActive: Bool = false,
        title: String? = nil,
        icon: String? = nil,
        action: @escaping () -> Void
    ) {
        self.tier = tier
        self.isActive = isActive
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button {
            if !isActive {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: icon ?? tier.badgeIcon)
                    .font(RDTypography.font(size: RDFontScale.size(10), weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(title ?? tier.badgeLabel)
                    .font(RDTypography.font(size: RDFontScale.size(10), weight: .heavy, design: .rounded))
                    .tracking(title == nil ? 0.7 : 0.1)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, title == nil ? 8 : 10)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(colors: [tier.accentColor, tier.accentTextColor],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(tier.accentColor.opacity(0.18), lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .shadow(color: tier.accentColor.opacity(0.24), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityLabel(isActive ? "\(tier.title) aktif" : (title ?? RDLocalization.format("localizable.rdupgrade.cta.1.a.gec.9c575241", table: .localizable, fallback: "%1$@'a geç", arguments: [String(describing: tier.title)])))
    }
}

struct RDHeaderAccountCTA: View {
    @EnvironmentObject private var app: AppState
    @State private var showMenu = false
    @State private var avatarImage: UIImage?
    let directEntryPoint: PaywallEntryPoint
    let menuEntryPoint: PaywallEntryPoint
    var analysisID: UUID? = nil
    var onUpgrade: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if !app.isPro {
                RDUpgradeCTA(
                    tier: app.currentTier == .plus ? .pro : .plus,
                    title: RDLocalization.string("localizable.rdupgrade.cta.yukselt.72b0d588", table: .localizable, fallback: "Yükselt"),
                    icon: "arrow.up.circle.fill",
                    action: {
                        beginUpgradeEntry(at: directEntryPoint)
                        onUpgrade()
                    }
                )
            }
            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    showMenu.toggle()
                }
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                RDAvatar(
                    initials: app.profile?.displayInitials ?? "—",
                    image: avatarImage,
                    size: 36,
                    tier: app.currentTier
                )
            }
            .buttonStyle(RDPressableButtonStyle())
        }
        .overlay(alignment: .topTrailing) {
            if showMenu {
                ZStack(alignment: .topTrailing) {
                    Color.black.opacity(0.001)
                        .frame(width: 900, height: 1200)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            closeMenu()
                        }
                        .gesture(
                            DragGesture(minimumDistance: 1)
                                .onChanged { _ in closeMenu() }
                        )
                        .accessibilityHidden(true)

                    RDHeaderProfileMenu(
                        currentTier: app.currentTier,
                        isDarkMode: app.isDarkModeEnabled,
                        onAnalyses: { select(.analyses) },
                        onReports: { select(.reports) },
                        onUpgrade: {
                            closeMenu()
                            beginUpgradeEntry(at: menuEntryPoint)
                            onUpgrade()
                        },
                        onSettings: openProfilePreferences,
                        onSignOut: {
                            closeMenu()
                            app.signOut()
                        },
                        onToggleTheme: {
                            app.setDarkMode(!app.isDarkModeEnabled)
                            UISelectionFeedbackGenerator().selectionChanged()
                        }
                    )
                    .offset(y: 44)
                    .transition(.scale(scale: 0.94, anchor: .topTrailing).combined(with: .opacity))
                }
            }
        }
        .task(id: app.profile?.avatarURL) {
            await loadAvatarImage()
        }
        .zIndex(30)
    }

    private func select(_ tab: RDTab) {
        closeMenu()
        app.activeTab = tab
    }

    private func beginUpgradeEntry(at entryPoint: PaywallEntryPoint) {
        PaywallEventService.shared.beginEntry(
            at: entryPoint,
            currentTier: app.currentTier,
            targetTier: app.currentTier == .plus ? .pro : .plus,
            analysisID: analysisID
        )
    }

    private func openProfilePreferences() {
        closeMenu()
        app.requestProfileDestination(.preferences)
    }

    private func closeMenu() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
            showMenu = false
        }
    }

    private func loadAvatarImage() async {
        guard let path = app.profile?.avatarURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !path.isEmpty
        else {
            avatarImage = nil
            return
        }

        do {
            avatarImage = try await app.auth.profileAvatarImage(path: path)
        } catch {
            avatarImage = nil
        }
    }
}

private struct RDHeaderProfileMenu: View {
    let currentTier: SubscriptionTier
    let isDarkMode: Bool
    let onAnalyses: () -> Void
    let onReports: () -> Void
    let onUpgrade: () -> Void
    let onSettings: () -> Void
    let onSignOut: () -> Void
    let onToggleTheme: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 0) {
                menuButton(icon: "square.dashed", title: RDLocalization.string("localizable.rdupgrade.cta.analizlerim.51ca6988", table: .localizable, fallback: "Analizlerim"), action: onAnalyses)
                Divider().background(Color.rdLine).padding(.leading, 40)
                menuButton(icon: "doc.text", title: RDLocalization.string("localizable.rdupgrade.cta.raporlarim.1115ba4f", table: .localizable, fallback: "Raporlarım"), action: onReports)
                Divider().background(Color.rdLine).padding(.leading, 40)
                if currentTier.isPaid {
                    menuInfo(
                        icon: currentTier.badgeIcon,
                        title: RDLocalization.format("localizable.rdupgrade.cta.1.uyesiniz.d6d4c039", table: .localizable, fallback: "%1$@ üyesiniz", arguments: [String(describing: currentTier.title)]),
                        tint: currentTier.accentColor
                    )
                } else {
                    menuButton(icon: SubscriptionTier.plus.badgeIcon, title: RDLocalization.string("localizable.rdupgrade.cta.plan.yukselt.023472ba", table: .localizable, fallback: "Plan Yükselt"), tint: .rdPlanPlus, action: onUpgrade)
                }
            }

            Divider().background(Color.rdLine)

            HStack(spacing: 8) {
                iconButton(
                    icon: "rectangle.portrait.and.arrow.right",
                    tint: .rdCriticalText,
                    background: .rdCriticalBg,
                    label: RDLocalization.string("localizable.rdupgrade.cta.cikis.yap.7bffbf5f", table: .localizable, fallback: "Çıkış yap"),
                    action: onSignOut
                )
                iconButton(
                    icon: "gearshape.fill",
                    tint: .rdCharcoal,
                    background: .rdFog,
                    label: RDLocalization.string("localizable.rdupgrade.cta.ayarlar.97d7daa0", table: .localizable, fallback: "Ayarlar"),
                    action: onSettings
                )
                iconButton(
                    icon: isDarkMode ? "sun.max.fill" : "moon.fill",
                    tint: .rdGreen,
                    background: .rdGreenSoft,
                    label: isDarkMode ? RDLocalization.string("localizable.rdupgrade.cta.aydinlik.mod.fe8c009c", table: .localizable, fallback: "Aydınlık mod") : RDLocalization.string("localizable.rdupgrade.cta.karanlik.mod.07170435", table: .localizable, fallback: "Karanlık mod"),
                    action: onToggleTheme
                )
            }
            .padding(.top, 2)
        }
        .padding(8)
        .frame(width: 174)
        .background(Color.rdWhite)
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .stroke(Color.rdLine, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .shadow(color: Color.rdOnyx.opacity(0.16), radius: 22, x: 0, y: 12)
    }

    private func menuButton(icon: String, title: String, tint: Color = .rdBlack, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(RDTypography.font(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                    .frame(width: 27, height: 27)
                    .foregroundStyle(tint)
                    .background(tint.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(title)
                    .font(RDTypography.font(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func menuInfo(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(RDTypography.font(size: RDFontScale.size(13), weight: .bold, design: .rounded))
                .frame(width: 27, height: 27)
                .foregroundStyle(tint)
                .background(tint.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(title)
                .font(RDTypography.font(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdBlack)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 8)
        .accessibilityLabel(title)
    }

    private func iconButton(
        icon: String,
        tint: Color,
        background: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(RDTypography.font(size: RDFontScale.size(14), weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 36)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

#Preview {
    HStack(spacing: 16) {
        RDUpgradeCTA(isPro: false) {}
        RDUpgradeCTA(tier: .plus) {}
        RDUpgradeCTA(isPro: true) {}
    }
    .padding()
    .background(Color.rdPaper)
}
