import SwiftUI

struct RDUpgradeCTA: View {
    var isPro: Bool
    var action: () -> Void

    var body: some View {
        Button {
            if !isPro {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                action()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "star.fill")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                Text(isPro ? "PRO" : "PRO")
                    .font(.system(size: 10, weight: .heavy, design: .rounded))
                    .tracking(0.7)
                    .foregroundStyle(.white)
            }
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(
                        LinearGradient(colors: [Color.rdGreen, Color.rdGreenDark],
                                       startPoint: .topLeading,
                                       endPoint: .bottomTrailing)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 7)
                            .stroke(Color.rdGreen.opacity(0.18), lineWidth: 1)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .shadow(color: Color.rdGreen.opacity(0.24), radius: 8, x: 0, y: 3)
        }
        .buttonStyle(RDPressableButtonStyle())
        .accessibilityLabel(isPro ? "Pro aktif" : "Pro'ya geç")
    }
}

struct RDHeaderAccountCTA: View {
    @EnvironmentObject private var app: AppState
    @State private var showMenu = false
    var onUpgrade: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            if !app.isPro {
                RDUpgradeCTA(isPro: false, action: onUpgrade)
            }
            Button {
                withAnimation(.spring(response: 0.24, dampingFraction: 0.88)) {
                    showMenu.toggle()
                }
                UISelectionFeedbackGenerator().selectionChanged()
            } label: {
                RDAvatar(
                    initials: app.profile?.displayInitials ?? "—",
                    size: 36,
                    pro: app.isPro
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
                        isPro: app.isPro,
                        isDarkMode: app.isDarkModeEnabled,
                        onAnalyses: { select(.analyses) },
                        onReports: { select(.reports) },
                        onUpgrade: {
                            closeMenu()
                            onUpgrade()
                        },
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
        .zIndex(30)
    }

    private func select(_ tab: RDTab) {
        closeMenu()
        app.activeTab = tab
    }

    private func closeMenu() {
        withAnimation(.spring(response: 0.22, dampingFraction: 0.9)) {
            showMenu = false
        }
    }
}

private struct RDHeaderProfileMenu: View {
    let isPro: Bool
    let isDarkMode: Bool
    let onAnalyses: () -> Void
    let onReports: () -> Void
    let onUpgrade: () -> Void
    let onSignOut: () -> Void
    let onToggleTheme: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            VStack(spacing: 0) {
                menuButton(icon: "square.dashed", title: "Analizlerim", action: onAnalyses)
                Divider().background(Color.rdLine).padding(.leading, 40)
                menuButton(icon: "doc.text", title: "Raporlarım", action: onReports)
                Divider().background(Color.rdLine).padding(.leading, 40)
                if isPro {
                    menuInfo(icon: "star.fill", title: "Pro üyesiniz", tint: .rdGreen)
                } else {
                    menuButton(icon: "star.fill", title: "Plan Yükselt", tint: .rdGreen, action: onUpgrade)
                }
            }

            Divider().background(Color.rdLine)

            HStack(spacing: 8) {
                iconButton(
                    icon: "rectangle.portrait.and.arrow.right",
                    tint: .rdCriticalText,
                    background: .rdCriticalBg,
                    label: "Çıkış yap",
                    action: onSignOut
                )
                iconButton(
                    icon: isDarkMode ? "sun.max.fill" : "moon.fill",
                    tint: .rdGreen,
                    background: .rdGreenSoft,
                    label: isDarkMode ? "Aydınlık mod" : "Karanlık mod",
                    action: onToggleTheme
                )
            }
            .padding(.top, 2)
        }
        .padding(8)
        .frame(width: 190)
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
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .frame(width: 28, height: 28)
                    .foregroundStyle(tint)
                    .background(tint.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func menuInfo(icon: String, title: String, tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .frame(width: 28, height: 28)
                .foregroundStyle(tint)
                .background(tint.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Text(title)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.rdBlack)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
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
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
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
        RDUpgradeCTA(isPro: true) {}
    }
    .padding()
    .background(Color.rdPaper)
}
