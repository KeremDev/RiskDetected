import SwiftUI
import UIKit

/// New expert shell only. The owner supplies scoped state and real destination content.
/// Not installed in the legacy MainTabView; no Auth, billing or service calls here.
struct NovaExpertShell<Content: View>: View {
    var notebookAvailable = false
    @Binding var navigation: NovaNavigationState
    let userName: String
    /// Optional account avatar rendered in the drawer. The initials fallback
    /// keeps the menu useful while the profile image is loading or missing.
    var profileAvatar: Image? = nil
    var menuRoleTitle = "İSG Uzmanı"
    var menuStats: [NovaMenuStat] = []
    var menuNextAction: NovaMenuNextAction? = nil
    var onInvite: (() -> Void)? = nil
    var hasUnread = false
    var unreadCount = 0
    var notificationItems: [NovaNotice] = []
    /// The bell's own note, shown under the list. Empty hides it.
    var noticeNote = ""
    var onReadNotice: ((String) -> Void)?
    var onOpenNotice: ((String) -> Void)?
    var onDismissNotice: ((String) -> Void)?
    var onRestoreNotice: ((String) -> Void)?
    var connectionLabel = RDLocalization.string("localizable.nova.shell.connection.unknown", table: .localizable, fallback: "Bağlantı bilgisi yok")
    var onReadAll: (() -> Void)?
    var onClearNotifications: (() -> Void)?
    var onCompanyCreate: (() -> Void)?
    /// OSGB manager-only shortcuts. They are deliberately callbacks instead
    /// of destinations: both actions open the existing, mutation-backed
    /// management sheets and therefore cannot bypass their scoped store.
    var isManager = false
    var onExpertCreate: (() -> Void)?
    var onAssignmentOpen: (() -> Void)?
    /// Allows the composition root to reset feature-local state when a root
    /// destination is selected (for example, leaving a company workspace).
    var onDestination: ((NovaDestination) -> Void)?
    var onLogout: (() -> Void)?
    @ViewBuilder let content: (NovaDestination) -> Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var keyboard = KeyboardObserver()

    var body: some View {
        let epoch = navigation.epoch
        let send: (NovaNavigationEvent) -> Void = { navigation.apply($0, from: epoch) }
        GeometryReader { geometry in
            ZStack {
                ZStack(alignment: .bottom) {
                    VStack(spacing: 0) {
                    NovaShellTopBar(current: navigation.current, userName: userName, hasUnread: hasUnread,
                        unreadCount: unreadCount,
                        canGoBack: !(navigation.paths[navigation.selected] ?? []).isEmpty,
                        notificationsAvailable: navigation.canOpen(.notifications), send: send)
                    TabView(selection: Binding(get: { navigation.selected }, set: { send(.select($0)) })) {
                        ForEach(NovaTab.allCases, id: \.self) { tab in
                            NavigationStack(path: Binding(
                                get: { navigation.paths[tab] ?? [] },
                                set: { navigation.acceptBackPath($0, tab: tab, from: epoch) })) {
                                NovaPageSurface {
                                    if navigation.canOpen(tab.root) { content(tab.root) }
                                    else { NovaText(text: RDLocalization.string("localizable.nova.expert.shell.bu.bolum.henuz.kullanima.acik.degil.38c52ea3", table: .localizable, fallback: "Bu bölüm henüz kullanıma açık değil.")) }
                                }
                                    .navigationDestination(for: NovaDestination.self) { destination in
                                        NovaPageSurface { content(destination) }
                                    }
                            }.tag(tab)
                        }
                    }
                    }
                    if keyboard.height == 0 {
                        NovaShellTabBar(selected: navigation.selected, current: navigation.current,
                            canOpen: navigation.canOpen, send: send,
                            onDestination: guardedDestination(onDestination, epoch: epoch))
                            .accessibilityHidden(navigation.overlay != nil)
                            .allowsHitTesting(navigation.overlay == nil)
                            .padding(.horizontal, NovaDimensionToken.layoutTabBarInset.value)
                            .padding(.top, 8)
                            .padding(.bottom, max(10, geometry.safeAreaInsets.bottom + 6))
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .allowsHitTesting(navigation.overlay == nil)
                .accessibilityHidden(navigation.overlay != nil)
                .blur(radius: navigation.overlay == .quickAdd && !reduceTransparency ? NovaPopupStyle.sourceBlur : 0)

                if let panel = navigation.overlay {
                    NovaShellPanel(panel: panel, selected: navigation.current, canOpen: navigation.canOpen,
                        userName: userName, profileAvatar: profileAvatar, menuRoleTitle: menuRoleTitle,
                        menuStats: menuStats, menuNextAction: menuNextAction, onInvite: guarded(onInvite, epoch: epoch),
                        send: send, notices: notificationItems, connectionLabel: connectionLabel,
                        noticeNote: noticeNote,
                        onReadAll: guarded(onReadAll, epoch: epoch), onClear: guarded(onClearNotifications, epoch: epoch),
                        onReadNotice: guardedKey(onReadNotice, epoch: epoch),
                        onOpenNotice: guardedKey(onOpenNotice, epoch: epoch),
                        onDismissNotice: guardedKey(onDismissNotice, epoch: epoch),
                        onRestoreNotice: guardedKey(onRestoreNotice, epoch: epoch),
                        onCompanyCreate: guarded(onCompanyCreate, epoch: epoch),
                        isManager: isManager, notebookAvailable: notebookAvailable,
                        onExpertCreate: guarded(onExpertCreate, epoch: epoch),
                        onAssignmentOpen: guarded(onAssignmentOpen, epoch: epoch),
                        onDestination: guardedDestination(onDestination, epoch: epoch),
                        onLogout: guarded(onLogout, epoch: epoch))
                }
            }.background(NovaColorToken.canvas.color(in: scheme).ignoresSafeArea())
                .animation(.easeInOut(duration: keyboard.animationDuration), value: keyboard.height == 0)
        }
        // Caller replaces the state on Auth/session-epoch change; local child state must not leak.
        .id(navigation.epoch)
        .environment(\.novaHasHeader, true)
        .environment(\.novaPresentationEpoch, epoch)
        .environment(\.novaHeaderContext, NovaHeaderContext(current: navigation.current,
            userName: userName, unreadCount: unreadCount, hasUnread: hasUnread,
            notificationsAvailable: navigation.canOpen(.notifications), send: { event in
                guard navigation.epoch == epoch else { return }
                NotificationCenter.default.post(name: Notification.Name("isgada.shell.navigate"), object: epoch)
                send(event)
            }))
    }

    private func guarded(_ action: (() -> Void)?, epoch: String) -> (() -> Void)? {
        guard let action else { return nil }
        return { guard navigation.epoch == epoch else { return }; action() }
    }

    private func guardedKey(_ action: ((String) -> Void)?, epoch: String) -> ((String) -> Void)? {
        guard let action else { return nil }
        return { key in guard navigation.epoch == epoch else { return }; action(key) }
    }

    private func guardedDestination(_ action: ((NovaDestination) -> Void)?, epoch: String) -> ((NovaDestination) -> Void)? {
        guard let action else { return nil }
        return { destination in guard navigation.epoch == epoch else { return }; action(destination) }
    }
}

struct NovaShellTopBar: View {
    let current: NovaDestination
    let userName: String
    let hasUnread: Bool
    var unreadCount = 0
    let canGoBack: Bool
    let notificationsAvailable: Bool
    let send: (NovaNavigationEvent) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedDrawerGroup: String?

    var body: some View {
        VStack(spacing: 8) {
        HStack(spacing: 10) {
            icon("line.3.horizontal", label: RDLocalization.string("localizable.nova.shell.open.menu", table: .localizable,
                fallback: "Menüyü aç"), id: "nova.menu") { send(.open(.drawer)) }
            Spacer(minLength: 0)
            icon("bell", label: hasUnread ? RDLocalization.string("localizable.nova.shell.notifications.with.new", table: .localizable, fallback: "Bildirimler, yeni bildirim var") : RDLocalization.string("localizable.nova.shell.notifications", table: .localizable, fallback: "Bildirimler"), id: "nova.notifications") {
                send(.open(.notifications))
            }
                .disabled(!notificationsAvailable).overlay(alignment: .topTrailing) { badge }
            Button { send(.select(.profile)) } label: {
                Image(systemName: "person.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Color.black)
                    .frame(width: 44, height: 44)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 14))
                    .shadow(color: Color.black.opacity(0.06), radius: 5, y: 2)
            }.buttonStyle(NovaPressStyle()).accessibilityLabel(RDLocalization.string("localizable.nova.expert.shell.hesabim.f6d2ed00", table: .localizable, fallback: "Hesabım")).accessibilityIdentifier("nova.profile")
        }
        }.padding(.horizontal, NovaDimensionToken.spaceScreenX.value).padding(.top, 8).padding(.bottom, 2)
    }

    /// A count when there is one, a plain dot when there is only a flag. Both
    /// are decoration: the label already says there is something new.
    @ViewBuilder private var badge: some View {
        if unreadCount > 0 {
            Text(verbatim: unreadCount > 99 ? "99+" : String(unreadCount))
                .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                .padding(.horizontal, 4).frame(minWidth: 16, minHeight: 16)
                .background(NovaColorToken.statusDangerDot.color(in: scheme), in: Capsule())
                .padding(4).accessibilityHidden(true)
        } else if hasUnread {
            Circle().fill(NovaColorToken.statusDangerDot.color(in: scheme)).frame(width: 8, height: 8)
                .padding(7).accessibilityHidden(true)
        }
    }

    private func icon(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.white)
                NovaIcon(symbol: symbol, size: 17)
                    .foregroundStyle(Color.black)
            }
            .frame(width: 44, height: 44)
            .shadow(color: Color.black.opacity(0.06), radius: 5, y: 2)
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(NovaPressStyle()).accessibilityLabel(Text(verbatim: label)).accessibilityIdentifier(id)
    }
}

struct NovaShellTabBar: View {
    let selected: NovaTab
    let current: NovaDestination
    let canOpen: (NovaDestination) -> Bool
    let send: (NovaNavigationEvent) -> Void
    var onDestination: ((NovaDestination) -> Void)? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if #available(iOS 26.0, *) {
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        strip
                            .padding(5)
                            .glassEffect(.regular.interactive(), in: Capsule())
                        if current != .analyses {
                            quickAdd
                                .background(Circle().fill(Color.black))
                                .glassEffect(.clear.interactive(), in: Circle())
                        }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    strip
                        .padding(5)
                        .background {
                            if reduceTransparency {
                                Capsule().fill(NovaColorToken.surface.color(in: scheme))
                            } else {
                                Capsule().fill(.ultraThinMaterial)
                                    .overlay(Capsule().fill(NovaColorToken.glass.color(in: scheme)))
                            }
                        }
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.78), lineWidth: 1))
                    if current != .analyses {
                        quickAdd
                            .background(Circle().fill(Color.black))
                            .overlay(Circle().strokeBorder(Color.white.opacity(0.35), lineWidth: 1))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 62)
        .shadow(color: .black.opacity(0.07), radius: 18, x: 0, y: 7)
    }

    private var strip: some View {
        NovaShellTabStrip(selected: selected, canOpen: canOpen, send: send,
            onDestination: onDestination)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
    }

    private var quickAdd: some View {
        Button {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            send(.open(.quickAdd))
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 24, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white)
                .frame(width: 62, height: 62)
                .contentShape(Circle())
        }
        .buttonStyle(NovaPressStyle(scale: 0.93, pressedOpacity: 0.72))
        .accessibilityLabel("Ekle")
        .accessibilityIdentifier("nova.add")
        .id("add")
    }

}

struct NovaShellTabStrip: View {
    let selected: NovaTab
    let canOpen: (NovaDestination) -> Bool
    let send: (NovaNavigationEvent) -> Void
    var onDestination: ((NovaDestination) -> Void)? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selectionHighlight

    var body: some View {
        HStack(spacing: 2) {
            tab(.home)
            tab(.companies)
            tab(.findings)
            tab(.profile)
        }
    }

    private func tab(_ tab: NovaTab) -> some View {
        let isSelected = selected == tab
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(NovaMotion.stopped(NovaMotion.momentum, reduceMotion: reduceMotion)) {
                onDestination?(tab.root)
                send(.select(tab))
            }
        } label: {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(Color.white.opacity(scheme == .dark ? 0.18 : 0.82))
                        .overlay(Capsule().strokeBorder(Color.white.opacity(0.86), lineWidth: 0.8))
                        .matchedGeometryEffect(id: "nova-tab-selection", in: selectionHighlight)
                }
                HStack(spacing: 7) {
                    Image(systemName: symbol(tab))
                        .font(.system(size: 20, weight: isSelected ? .semibold : .regular))
                        .symbolRenderingMode(.monochrome)
                    if isSelected {
                        NovaSizedText(text: tab.title, size: 12.5, weight: "Bold", color: Color.black)
                            .lineLimit(1).minimumScaleFactor(0.82)
                            .transition(.opacity.combined(with: .scale(scale: 0.92)))
                    }
                }
                .foregroundStyle(Color.black)
                .padding(.horizontal, isSelected ? 14 : 9)
            }
            .frame(width: isSelected ? 116 : 45, height: 48)
            .contentShape(Capsule())
            .opacity(canOpen(tab.root) ? 1 : 0.3)
        }.buttonStyle(NovaPressStyle(scale: 0.93, pressedOpacity: 0.72)).disabled(!canOpen(tab.root))
            .accessibilityLabel(Text(verbatim: tab.title))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("nova.tab.\(tab.rawValue)").id(tab.rawValue)
    }

    private func symbol(_ tab: NovaTab) -> String {
        switch tab {
        case .home: return "house"
        case .companies: return "building.2"
        case .findings: return "checklist"
        case .profile: return "person"
        }
    }
}

/// One reusable popup surface: compact intrinsic height, scroll fallback at large text sizes.
struct NovaPopupSurface<Content: View>: View {
    var isPopover = false
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ViewThatFits(in: .vertical) {
            content().fixedSize(horizontal: false, vertical: true)
            ScrollView { content() }.accessibilityIdentifier("nova.panel.scroll")
        }
        .environment(\.isNovaPopup, !isPopover)
        .padding(isPopover ? 14 : 16)
        .background {
            if isPopover {
                RoundedRectangle(cornerRadius: 26).fill(.regularMaterial)
            } else { RoundedRectangle(cornerRadius: 30).fill(NovaPopupStyle.background(in: scheme)) }
        }
        .overlay(RoundedRectangle(cornerRadius: isPopover ? 26 : 30).strokeBorder(NovaColorToken.glassBorder.color(in: scheme), lineWidth: isPopover ? 0 : 1))
    }
}

/// One line in the bell. The owner computes every field; the shell only draws
/// it, and `id` is the key the owner marks the notice by.
struct NovaNotice: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    /// How late it is, in words. Never a bare number the reader must decode.
    let badge: String
    let symbol: String
    let tone: NovaColorToken
    var unread = true
    var dismissed = false
    var destination: NovaDestination = .notifications
}

/// Compact, actionable summary cards shown at the top of the drawer.
struct NovaMenuStat: Identifiable {
    let id: String
    let title: String
    let value: String
    let symbol: String
    let destination: NovaDestination
}

/// The next best action is supplied by the composition root so it can reflect
/// the account's current data rather than a hard-coded onboarding state.
struct NovaMenuNextAction {
    let title: String
    let symbol: String
    let destination: NovaDestination
    let completed: Int
    let total: Int

    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}

func novaInitials(_ name: String) -> String {
    name.split(whereSeparator: { $0.isWhitespace }).prefix(2).compactMap(\.first)
        .map(String.init).joined().uppercased(with: Locale(identifier: "tr_TR"))
}

struct NovaShellPanel: View {
    let panel: NovaOverlay
    let selected: NovaDestination
    let canOpen: (NovaDestination) -> Bool
    let userName: String
    var profileAvatar: Image? = nil
    var menuRoleTitle = "İSG Uzmanı"
    var menuStats: [NovaMenuStat] = []
    var menuNextAction: NovaMenuNextAction? = nil
    var onInvite: (() -> Void)? = nil
    let send: (NovaNavigationEvent) -> Void
    var notices: [NovaNotice] = []
    var connectionLabel = RDLocalization.string("localizable.nova.shell.connection.unknown", table: .localizable, fallback: "Bağlantı bilgisi yok")
    var noticeNote = ""
    var onReadAll: (() -> Void)?
    var onClear: (() -> Void)?
    var onReadNotice: ((String) -> Void)?
    var onOpenNotice: ((String) -> Void)?
    var onDismissNotice: ((String) -> Void)?
    var onRestoreNotice: ((String) -> Void)?
    var onCompanyCreate: (() -> Void)?
    var isManager = false
    var notebookAvailable = false
    var onExpertCreate: (() -> Void)?
    var onAssignmentOpen: (() -> Void)?
    var onDestination: ((NovaDestination) -> Void)?
    var onLogout: (() -> Void)?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedDrawerGroup: String?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: panel == .drawer ? .leading : panel == .notifications ? .top : .center) {
                (panel == .quickAdd ? Color.black.opacity(NovaPopupStyle.dimOpacity) : NovaColorToken.scrim.color(in: scheme)).ignoresSafeArea()
                    .onTapGesture { send(.dismiss) }.accessibilityHidden(true)
                if panel == .drawer {
                    drawer
                        .frame(width: min(typeSize.isAccessibilitySize ? 380 : 340, geometry.size.width - 24))
                        .frame(maxHeight: .infinity)
                        .background(NovaColorToken.canvasSheet.color(in: scheme).ignoresSafeArea())
                } else {
                    NovaPopupSurface(isPopover: panel == .notifications) {
                        if panel == .quickAdd { quickAdd } else { notifications }
                    }
                    .frame(maxWidth: 440, maxHeight: max(0, geometry.size.height - (panel == .notifications ? 64 : 24)))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, panel == .notifications ? 16 : 14)
                    .padding(.top, panel == .notifications ? 56 : 0)
                }
            }
            .accessibilityAddTraits(.isModal)
            .accessibilityAction(.escape) { send(.dismiss) }
        }
    }

    private var close: some View {
        NovaPopupCloseButton(identifier: "nova.panel.close") { send(.dismiss) }
    }

    private var drawer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Group {
                    if let profileAvatar {
                        profileAvatar.resizable().scaledToFill()
                    } else {
                        NovaText(text: novaInitials(userName.isEmpty ? "Kullanıcı" : userName), style: .cardTitle, color: .white)
                    }
                }
                .frame(width: 46, height: 46)
                .background(Color(white: 0.14), in: Circle())
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(NovaColorToken.hairline.color(in: scheme), lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    NovaText(text: userName.isEmpty ? "Kullanıcı" : userName, style: .sectionTitle)
                    NovaText(text: menuRoleTitle, style: .metaQuiet, color: NovaColorToken.textMuted.color(in: scheme))
                }
                Spacer(minLength: 0)
                close
            }.padding(.top, 10).padding(.bottom, 10)

            if !menuStats.isEmpty {
                HStack(spacing: 6) {
                    ForEach(menuStats.prefix(3)) { stat in
                        menuStatCard(stat)
                    }
                }
                .padding(.bottom, 10)
            }

            Rectangle().fill(NovaColorToken.hairline.color(in: scheme)).frame(height: 1).padding(.bottom, 7)
            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    if let menuNextAction {
                        menuNextActionCard(menuNextAction)
                            .padding(.bottom, 8)
                    }
                    if isManager {
                        managerDrawer
                    } else {
                        drawerSectionLabel("Genel")
                        drawerDestination(.home)
                        drawerSectionLabel("İşlemler")
                        ForEach(NovaDrawerGroup.all) { group in
                            drawerGroup(group)
                        }
                        drawerSectionLabel("Takip")
                        drawerDestination(.training)
                        drawerDestination(.visits)
                        operationDrawer
                    }
                    if let onInvite {
                        inviteBanner(onInvite)
                            .padding(.top, 6)
                    }
                }
            }.accessibilityIdentifier("nova.panel.scroll")
                .onAppear {
                    // Start compact so the full menu fits in one screen. A
                    // section expands only when the user explicitly opens it.
                    expandedDrawerGroup = nil
                }
            HStack(spacing: 8) {
                Button {
                    onDestination?(.profile)
                    send(.navigate(.profile))
                    send(.dismiss)
                } label: {
                    NovaIcon(symbol: "gearshape", size: 18)
                        .foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                        .frame(width: 42, height: 40)
                        .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 13))
                }
                .buttonStyle(NovaRowPressStyle())
                .accessibilityLabel("Ayarlar")
                .accessibilityIdentifier("nova.settings")

                Button { onLogout?() } label: {
                    HStack(spacing: 8) {
                        NovaIcon(symbol: "rectangle.portrait.and.arrow.right", size: 17)
                        NovaText(text: RDLocalization.string("localizable.nova.expert.shell.cikis.yap.6a3d02af", table: .localizable, fallback: "Çıkış yap"), style: .body,
                                 color: NovaColorToken.statusDangerInk.color(in: scheme))
                    }
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(NovaColorToken.surfaceMuted.color(in: scheme), in: Capsule())
                }
                .buttonStyle(NovaRowPressStyle())
                .disabled(onLogout == nil)
                .opacity(onLogout == nil ? 0.4 : 1)
                .accessibilityIdentifier("nova.logout")
            }
            .padding(.top, 6).padding(.bottom, 8)
        }.padding(.horizontal, 20)
    }

    private func menuStatCard(_ stat: NovaMenuStat) -> some View {
        let enabled = canOpen(stat.destination)
        return Button {
            onDestination?(stat.destination)
            send(.navigate(stat.destination))
            send(.dismiss)
        } label: {
            VStack(alignment: .center, spacing: 3) {
                HStack(spacing: 4) {
                    NovaIcon(symbol: stat.symbol, size: 13)
                    NovaText(text: stat.value, style: .metaQuiet)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                NovaText(text: stat.title, style: .metaQuiet, color: NovaColorToken.textMuted.color(in: scheme))
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(NovaColorToken.text.color(in: scheme))
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .center)
            .padding(.horizontal, 7).padding(.vertical, 6)
            .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(NovaRowPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityIdentifier("nova.menu.stat.\(stat.id)")
    }

    private func menuNextActionCard(_ action: NovaMenuNextAction) -> some View {
        let enabled = canOpen(action.destination) && (action.destination != .newCompany || onCompanyCreate != nil)
        return Button {
            if action.destination == .newCompany { onCompanyCreate?() }
            else {
                onDestination?(action.destination)
                send(.navigate(action.destination))
            }
            send(.dismiss)
        } label: {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 10) {
                    NovaIcon(symbol: action.symbol, size: 19)
                        .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                        .frame(width: 26, height: 26)
                        .background(NovaColorToken.accent.color(in: scheme).opacity(0.16), in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        NovaText(text: "Sıradaki işin", style: .micro, color: NovaColorToken.textMuted.color(in: scheme))
                        NovaText(text: action.title, style: .body)
                    }
                    Spacer(minLength: 4)
                    NovaText(text: "\(action.completed)/\(action.total)", style: .metaQuiet, color: NovaColorToken.accentInk.color(in: scheme))
                }
                ProgressView(value: action.progress)
                    .tint(NovaColorToken.accentInk.color(in: scheme))
                    .scaleEffect(x: 1, y: 1.2, anchor: .center)
            }
            .foregroundStyle(NovaColorToken.text.color(in: scheme))
            .padding(9)
            .background(NovaColorToken.accent.color(in: scheme).opacity(0.11), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(NovaRowPressStyle())
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.45)
        .accessibilityIdentifier("nova.menu.next-action")
    }

    private func inviteBanner(_ action: @escaping () -> Void) -> some View {
        Button {
            action()
            send(.dismiss)
        } label: {
            HStack(spacing: 10) {
                NovaIcon(symbol: "gift", size: 21)
                    .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                    .frame(width: 34, height: 34)
                    .background(NovaColorToken.accent.color(in: scheme).opacity(0.16), in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    NovaText(text: "Arkadaşını Davet Et", style: .buttonSm)
                    NovaText(text: "7 Günlük Plus kazan", style: .metaQuiet, color: NovaColorToken.textMuted.color(in: scheme))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
            }
            .foregroundStyle(NovaColorToken.text.color(in: scheme))
            .padding(9)
            .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(NovaRowPressStyle())
        .accessibilityIdentifier("nova.menu.invite")
    }

    /// The OSGB authority does not need the expert's personal route catalog.
    /// Keep operations under one accordion and surface the three management
    /// actions that otherwise remained hidden behind the floating plus button.
    @ViewBuilder private var managerDrawer: some View {
        drawerSectionLabel("Genel")
        drawerDestination(.home)
        drawerDestination(.companies)
        drawerAction(title: "Uzmanlar", symbol: "person.2", identifier: "nova.manager.experts",
                     action: onExpertCreate)
        drawerSectionLabel("İşlemler")
        drawerGroup(managerAnalysisAuditGroup)
        drawerGroup(managerFormsGroup)
        drawerGroup(managerSafetyGroup)
        drawerSectionLabel("Takip")
        drawerDestination(.training)
        drawerDestination(.visits)
        operationDrawer
        Rectangle().fill(NovaColorToken.hairline.color(in: scheme)).frame(height: 1)
            .padding(.horizontal, 8).padding(.vertical, 8)
        NovaText(text: RDLocalization.string("localizable.nova.manager.section", table: .localizable,
            fallback: "Yönetim"), style: .meta, color: NovaColorToken.textMuted.color(in: scheme))
            .padding(.horizontal, 8).padding(.bottom, 3)
        drawerAction(title: "Firma ekle", symbol: "building.2.crop.circle", identifier: "nova.manager.add-company",
                     action: onCompanyCreate)
        drawerAction(title: "Uzman ekle", symbol: "person.badge.plus", identifier: "nova.manager.add-expert",
                     action: onExpertCreate)
        drawerAction(title: RDLocalization.string("localizable.nova.manager.assignment", table: .localizable,
            fallback: "Atama yap / değiştir"), symbol: "person.2.badge.gearshape", identifier: "nova.manager.assign-expert",
                     action: onAssignmentOpen)
    }

    @ViewBuilder private var operationDrawer: some View {
        drawerSectionLabel("Operasyon")
        drawerDestination(.statistics)
        drawerDestination(.reports)
        drawerDestination(.activity)
        if notebookAvailable { drawerDestination(.notebook) }
    }

    private func drawerSectionLabel(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Rectangle().fill(NovaColorToken.hairline.color(in: scheme)).frame(height: 1)
            NovaText(text: title, style: .micro, color: NovaColorToken.textMuted.color(in: scheme))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8).padding(.top, 6).padding(.bottom, 1)
    }

    private var managerAnalysisAuditGroup: NovaDrawerGroup {
        .init(id: "manager-analysis-audit", title: RDLocalization.string("localizable.nova.drawer.group.analysis.audit", table: .localizable,
              fallback: "Analiz & Denetim"), symbol: "magnifyingglass",
              destinations: [.newAnalysis, .analyses, .newFinding, .findings])
    }

    private var managerFormsGroup: NovaDrawerGroup {
        .init(id: "manager-forms", title: RDLocalization.string("localizable.nova.drawer.group.forms", table: .localizable,
              fallback: "Formlar"), symbol: "doc.text",
              destinations: [.ppeHandovers, .workPermits, .documentChecklist, .documents])
    }

    private var managerSafetyGroup: NovaDrawerGroup {
        .init(id: "manager-safety", title: RDLocalization.string("localizable.nova.manager.safety", table: .localizable,
              fallback: "İş Güvenliği"), symbol: "shield.lefthalf.filled",
              destinations: [.riskAssessments, .emergencyPlans, .appointments, .boardMeetings,
                             .annualWorkPlans, .drills, .periodicChecks, .katipContracts, .checklists])
    }

    private func drawerAction(title: String, symbol: String, identifier: String,
                              action: (() -> Void)?) -> some View {
        Button { action?(); send(.dismiss) } label: {
            HStack(spacing: 12) {
                NovaIcon(symbol: symbol, size: 16).frame(width: 18)
                NovaText(text: title, style: .body)
                Spacer(minLength: 4)
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(NovaColorToken.text.color(in: scheme))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .frame(minHeight: 34).contentShape(Rectangle())
        }.buttonStyle(NovaRowPressStyle()).disabled(action == nil).opacity(action == nil ? 0.4 : 1)
            .accessibilityIdentifier(identifier)
    }

    private func drawerGroup(_ group: NovaDrawerGroup) -> some View {
        let expanded = expandedDrawerGroup == group.id
        return VStack(spacing: 0) {
            Button {
                withAnimation(NovaMotion.gated(NovaMotion.easeOut(NovaMotion.Duration.dropdown), reduceMotion: reduceMotion)) {
                    expandedDrawerGroup = expanded ? nil : group.id
                }
            } label: {
                HStack(spacing: 12) {
                    NovaIcon(symbol: group.symbol, size: 16).frame(width: 18)
                    NovaText(text: group.title, style: .body)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .foregroundStyle(NovaColorToken.text.color(in: scheme))
                .padding(.horizontal, 8).padding(.vertical, 4)
                .frame(minHeight: 36).contentShape(Rectangle())
            }
            .buttonStyle(NovaRowPressStyle())
            .accessibilityIdentifier("nova.drawer.group.\(group.id)")
            .accessibilityValue(expanded ? RDLocalization.string("localizable.nova.drawer.expanded", table: .localizable, fallback: "Açık") : RDLocalization.string("localizable.nova.drawer.collapsed", table: .localizable, fallback: "Kapalı"))
            if expanded {
                VStack(spacing: 0) {
                    ForEach(group.destinations, id: \.self) { destination in
                        drawerDestination(destination, nested: true)
                    }
                }.padding(.bottom, 2)
                // The chevron was already turning, but the rows themselves
                // appeared and vanished on a single frame. They now grow out of
                // the group header they belong to, and collapse back into it.
                .transition(reduceMotion
                    ? .opacity
                    : .scale(scale: 0.98, anchor: .top).combined(with: .opacity))
            }
        }
    }

    private func drawerDestination(_ destination: NovaDestination, nested: Bool = false) -> some View {
        let enabled = canOpen(destination) && (destination != .newCompany || onCompanyCreate != nil)
        return Button {
            // Firma Ekle opens the company-create flow directly, same as the
            // quick-add sheet's own entry for it — it is not a pushed screen.
            if destination == .newCompany {
                onCompanyCreate?()
            } else {
                onDestination?(destination)
                send(.navigate(destination))
            }
        } label: {
            HStack(spacing: 12) {
                NovaIcon(symbol: destination.symbol, size: nested ? 15 : 16).frame(width: 18)
                NovaText(text: destination.title, style: .metaQuiet)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if selected == destination {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundStyle(NovaColorToken.text.color(in: scheme))
            .padding(.leading, nested ? 24 : 8).padding(.trailing, 8).padding(.vertical, 4)
            .frame(minHeight: 34).contentShape(Rectangle())
        }.buttonStyle(NovaRowPressStyle()).disabled(!enabled)
            .opacity(enabled ? 1 : 0.4)
            .accessibilityIdentifier("nova.destination.\(destination.rawValue)")
            .accessibilityAddTraits(selected == destination ? .isSelected : [])
    }

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: RDLocalization.string("localizable.nova.expert.shell.ne.eklemek.istiyorsun.ee07893e", table: .localizable, fallback: "Ne eklemek istiyorsun?"), style: .sectionTitle).padding(.horizontal, 4).padding(.bottom, 4)
            if isManager {
                managerQuickAction(title: "Firma ekle", detail: RDLocalization.string("localizable.nova.manager.company.add.detail", table: .localizable,
                    fallback: "Yeni firmayı ekleyin."), symbol: "building.2.crop.circle", action: onCompanyCreate)
                managerQuickAction(title: "Uzman ekle", detail: RDLocalization.string("localizable.nova.manager.expert.add.detail", table: .localizable,
                    fallback: "Ekibinize yeni bir İSG uzmanı davet edin."), symbol: "person.badge.plus", action: onExpertCreate)
                managerQuickAction(title: RDLocalization.string("localizable.nova.manager.assignment", table: .localizable,
                    fallback: "Atama yap / değiştir"), detail: RDLocalization.string("localizable.nova.manager.assignment.detail", table: .localizable,
                    fallback: "Firma erişimi ve uzman rollerini yönetin."), symbol: "person.2.badge.gearshape", action: onAssignmentOpen)
            } else {
            ForEach(NovaDestination.quickAdd.filter { $0 != .newNote || notebookAvailable }, id: \.self) { destination in
                let enabled = canOpen(destination) && (destination != .newCompany || onCompanyCreate != nil)
                Button {
                    if destination == .newCompany { onCompanyCreate?() }
                    else {
                        // The host may prepare a destination before it opens, the
                        // same way the drawer lets it; the quick-add sheet must
                        // not skip that notice.
                        onDestination?(destination)
                        send(.navigate(destination))
                    }
                } label: {
                    HStack(spacing: 12) {
                        NovaIcon(symbol: destination.quickSymbol, size: 21)
                            .foregroundStyle(destination.quickTone.color(in: scheme)).frame(width: 38, height: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            NovaSizedText(text: destination == .newFinding ? RDLocalization.string("localizable.nova.shell.add.nonconformity", table: .localizable, fallback: "Uygunsuzluk Ekle") : destination.title, size: 15, weight: "Medium")
                            NovaText(text: destination.quickHint, style: .meta, color: NovaColorToken.textMuted.color(in: scheme))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 12))
                            .foregroundStyle(NovaColorToken.borderStrong.color(in: scheme))
                    }.padding(.horizontal, 14).padding(.vertical, 13).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                        .novaControlBackground(cornerRadius: 20)
                }.buttonStyle(NovaRowPressStyle()).disabled(!enabled).opacity(enabled ? 1 : 0.4)
                    .accessibilityIdentifier("nova.destination.\(destination.rawValue)")
            }
            }
            Button { send(.dismiss) } label: {
                HStack(spacing: 10) {
                    NovaIcon(symbol: "chevron.left", size: 14)
                    NovaText(text: RDLocalization.string("localizable.nova.expert.shell.vazgec.5f0c7644", table: .localizable, fallback: "Vazgeç"), style: .button, color: NovaColorToken.textSecondary.color(in: scheme))
                }.frame(maxWidth: .infinity, minHeight: 46)
                    .background(NovaColorToken.surfaceMuted.color(in: scheme), in: Capsule())
            }.buttonStyle(NovaRowPressStyle()).foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                .padding(.top, 2).accessibilityIdentifier("nova.panel.close")
        }
    }

    private func managerQuickAction(title: String, detail: String, symbol: String,
                                    action: (() -> Void)?) -> some View {
        Button { action?(); send(.dismiss) } label: {
            HStack(spacing: 12) {
                NovaIcon(symbol: symbol, size: 21)
                    .foregroundStyle(NovaColorToken.accentInk.color(in: scheme)).frame(width: 38, height: 38)
                VStack(alignment: .leading, spacing: 2) {
                    NovaSizedText(text: title, size: 15, weight: "Medium")
                    NovaText(text: detail, style: .meta, color: NovaColorToken.textMuted.color(in: scheme))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 12))
            }.padding(.horizontal, 14).padding(.vertical, 13).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                .novaControlBackground(cornerRadius: 20)
        }.buttonStyle(NovaRowPressStyle()).disabled(action == nil).opacity(action == nil ? 0.45 : 1)
    }

    private var notifications: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                NovaText(text: RDLocalization.string("localizable.nova.shell.notifications", table: .localizable, fallback: "Bildirimler"), style: .sectionTitle)
                Spacer()
            }.frame(height: 24).padding(.horizontal, 4).overlay(alignment: .trailing) { close }
            HStack(spacing: 12) {
                Spacer(minLength: 0)
                Button { onReadAll?() } label: {
                    NovaText(text: RDLocalization.string("localizable.nova.expert.shell.tumunu.oku.8adf7334", table: .localizable, fallback: "Tümünü oku"), style: .meta, color: NovaColorToken.statusSuccessInk.color(in: scheme))
                        .frame(minHeight: 44).padding(.vertical, -3)
                }.disabled(onReadAll == nil || notices.isEmpty).accessibilityIdentifier("nova.notices.read")
                Rectangle().fill(NovaColorToken.hairline.color(in: scheme)).frame(width: 1, height: 14)
                Button { onClear?() } label: {
                    NovaText(text: RDLocalization.string("localizable.nova.expert.shell.bildirimleri.sil.8e14b659", table: .localizable, fallback: "Bildirimleri sil"), style: .meta, color: NovaColorToken.statusDangerInk.color(in: scheme))
                        .frame(minHeight: 44).padding(.vertical, -3)
                }.disabled(onClear == nil || notices.isEmpty).accessibilityIdentifier("nova.notices.clear")
            }
            if notices.isEmpty {
                Label(RDLocalization.string("localizable.nova.expert.shell.yeni.bildirim.yok.dcd7439a", table: .localizable, fallback: "Yeni bildirim yok"), systemImage: "bell").padding(16)
                    .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
            }
            ForEach(notices) { notice in
                noticeRow(notice)
            }
            if !noticeNote.isEmpty {
                // Said where the list can be emptied, because deleting here
                // deletes nothing else.
                NovaSizedText(text: noticeNote, size: 10, weight: "Regular",
                    color: NovaColorToken.textMuted.color(in: scheme))
                    .padding(.horizontal, 12).padding(.bottom, 8)
            }
            Button { send(.navigate(.notifications)) } label: {
                HStack(spacing: 4) {
                    NovaText(text: RDLocalization.string("localizable.nova.expert.shell.bildirim.merkezine.git.65adaa40", table: .localizable, fallback: "Bildirim merkezine git"), style: .meta, color: NovaColorToken.statusSuccessInk.color(in: scheme))
                    Image(systemName: "arrow.right").font(.system(size: 12))
                }.frame(minHeight: 44)
            }.buttonStyle(NovaRowPressStyle()).foregroundStyle(NovaColorToken.statusSuccessInk.color(in: scheme)).padding(.top, -6).padding(.bottom, -13)
                .disabled(!canOpen(.notifications)).accessibilityIdentifier("nova.notices.center")
        }.buttonStyle(NovaRowPressStyle())
    }

    /// One notice: the whole row opens the record, and the two controls on the
    /// right mark it read or take it off the list.
    @ViewBuilder private func noticeRow(_ notice: NovaNotice) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                // Opening a notice is reading it.
                onReadNotice?(notice.id)
                send(.navigate(notice.destination))
                send(.dismiss)
                onOpenNotice?(notice.id)
            } label: {
                HStack(alignment: .top, spacing: 10) {
                    NovaIcon(symbol: notice.symbol, size: 19)
                        .foregroundStyle(notice.tone.color(in: scheme)).frame(width: 32, height: 32)
                        .overlay(alignment: .topTrailing) {
                            if notice.unread {
                                Circle().fill(NovaColorToken.statusDangerDot.color(in: scheme))
                                    .frame(width: 5, height: 5)
                            }
                        }
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(alignment: .top, spacing: 6) {
                            NovaSizedText(text: notice.title, size: 13, weight: notice.unread ? "Bold" : "Medium")
                            Spacer(minLength: 0)
                            NovaSizedText(text: notice.badge, size: 10, weight: "Bold",
                                color: notice.tone.color(in: scheme))
                        }
                        NovaSizedText(text: notice.detail, size: 11, weight: "Regular",
                            color: NovaColorToken.textMuted.color(in: scheme))
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.buttonStyle(NovaRowPressStyle()).disabled(!canOpen(notice.destination))
                .accessibilityIdentifier("nova.notice.\(notice.id)")
            VStack(spacing: 2) {
                if notice.dismissed {
                    noticeAction("arrow.uturn.backward",
                        RDLocalization.string("localizable.nova.notice.restore", table: .localizable, fallback: "Geri al"),
                        "nova.notice.restore.\(notice.id)", onRestoreNotice == nil) { onRestoreNotice?(notice.id) }
                } else {
                    noticeAction(notice.unread ? "envelope.open" : "envelope",
                        RDLocalization.string("localizable.nova.notice.read", table: .localizable, fallback: "Okundu işaretle"),
                        "nova.notice.read.\(notice.id)", onReadNotice == nil || !notice.unread) { onReadNotice?(notice.id) }
                    noticeAction("trash",
                        RDLocalization.string("localizable.nova.notice.dismiss", table: .localizable, fallback: "Bildirimi sil"),
                        "nova.notice.dismiss.\(notice.id)", onDismissNotice == nil) { onDismissNotice?(notice.id) }
                }
            }
        }.padding(.horizontal, 12).padding(.vertical, 11).frame(maxWidth: .infinity, alignment: .leading)
            .novaControlBackground(cornerRadius: 20)
            .opacity(notice.dismissed ? 0.55 : 1)
            .padding(.bottom, 7)
    }

    @ViewBuilder private func noticeAction(_ symbol: String, _ label: String, _ identifier: String,
                                           _ disabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            NovaIcon(symbol: symbol, size: 13)
                .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
                .frame(width: 30, height: 30).contentShape(Rectangle())
        }.buttonStyle(NovaRowPressStyle()).disabled(disabled)
            .accessibilityLabel(Text(verbatim: label)).accessibilityIdentifier(identifier)
    }
}

extension NovaDestination {
    var quickHint: String {
        switch self {
        case .newNote: return RDLocalization.string("localizable.nova.expert.shell.note.private.hint", table: .localizable,
            fallback: "Yalnız size ait not ve yapılacaklar")
        case .newFinding: return RDLocalization.string("localizable.nova.expert.shell.bulgu.fotograf.ve.oncelik.6cb3a0fa", table: .localizable, fallback: "Bulgu, fotoğraf ve öncelik")
        case .newDocument: return RDLocalization.string("localizable.nova.expert.shell.rapor.form.veya.belge.yukle.d2d30a9a", table: .localizable, fallback: "Rapor, form veya belge yükle")
        case .newVisit: return RDLocalization.string("localizable.nova.expert.shell.yeni.saha.ziyareti.planla.dbc1aeb4", table: .localizable, fallback: "Yeni saha ziyareti planla")
        case .newTraining: return RDLocalization.string("localizable.nova.expert.shell.firma.personeline.egitim.kaydi.olustur.17b5c3df", table: .localizable, fallback: "Firma personeline eğitim kaydı oluştur")
        case .newCompany: return RDLocalization.string("localizable.nova.expert.shell.yeni.firma.kaydi.olustur", table: .localizable, fallback: "Yeni firma kaydı oluştur")
        case .newAnalysis: return RDLocalization.string("localizable.nova.expert.shell.fotograflardan.risk.analizi.olustur", table: .localizable, fallback: "Fotoğraflardan risk analizi oluştur")
        default: return ""
        }
    }
    var quickSymbol: String {
        switch self {
        case .newFinding: return "exclamationmark.triangle"
        case .newDocument: return "doc.text"
        case .newVisit: return "mappin"
        case .newTraining: return "graduationcap"
        default: return symbol
        }
    }
    var quickTone: NovaColorToken {
        switch self {
        case .newDocument: return .statusInfoDot
        case .newVisit: return .statusWarningDot
        default: return .statusSuccessDot
        }
    }
}

// Data-only presentation inputs. The host supplies authorized, account-scoped records and actions.
struct NovaCompanyItem: Identifiable {
    let id: String
    let name: String
    let detail: String
    var progressCompleted: Int = 0
    var progressTotal: Int = 8
}
struct NovaMetricItem: Identifiable {
    let id: String
    let value: String
    let label: String
    let footer: String
    let symbol: String
    let tone: NovaColorToken
    let destination: NovaDestination
}
struct NovaDashboardData {
    let firstName: String
    let openCount: Int?
    let metrics: [NovaMetricItem]
    let activity: String?
    let trainingMessage: String
    var recentAnalyses: [NovaRecentAnalysis] = []
    var summaryMessage: String? = nil
}
struct NovaRecentAnalysis: Identifiable {
    let id: String
    let title: String
    let companyName: String
    let createdOn: String
}


private final class NovaIconBundleMarker {}
/// Original OSGB vector paths; tint only, never an icon tile background.
struct NovaIcon: View {
    let symbol: String
    var size: CGFloat = 20
    private static let symbols = ["risk": "shield", "cameraLarge": "camera", "helmet": "person.crop.square", "sparkle": "sparkle"]
    var body: some View {
        Image(systemName: Self.symbols[symbol] ?? (symbol.hasSuffix(".fill") ? String(symbol.dropLast(5)) : symbol.replacingOccurrences(of: ".lefthalf.filled", with: "")))
            .symbolVariant(.none).symbolRenderingMode(.monochrome)
            .font(.system(size: size, weight: .regular))
            .frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// Quiet background texture for the dashboard greeting. The icons are purely
/// decorative and deliberately stay behind the readable content.
private struct NovaSafetyIconPattern: View {
    private struct Item: Identifiable {
        let id: Int
        let symbol: String
        let size: CGFloat
        let opacity: Double
        let x: CGFloat
        let y: CGFloat
    }

    private let items: [Item] = [
        .init(id: 1, symbol: "eyeglasses", size: 22, opacity: 0.20, x: 0.71, y: 0.18),
        .init(id: 2, symbol: "hardhat", size: 34, opacity: 0.15, x: 0.94, y: 0.18),
        .init(id: 3, symbol: "glove", size: 16, opacity: 0.19, x: 0.76, y: 0.72),
        .init(id: 4, symbol: "earmuffs", size: 27, opacity: 0.16, x: 0.94, y: 0.72),
        .init(id: 5, symbol: "safetyTape", size: 20, opacity: 0.17, x: 0.83, y: 0.46),
        .init(id: 6, symbol: "trafficCone", size: 15, opacity: 0.18, x: 0.69, y: 0.87),
        .init(id: 7, symbol: "exclamationmark.triangle.fill", size: 17, opacity: 0.16, x: 0.99, y: 0.46),
        .init(id: 8, symbol: "hardhat", size: 15, opacity: 0.18, x: 0.80, y: 0.12),
        .init(id: 9, symbol: "eyeglasses", size: 14, opacity: 0.15, x: 0.68, y: 0.50),
        .init(id: 10, symbol: "glove", size: 13, opacity: 0.18, x: 0.99, y: 0.90),
        .init(id: 11, symbol: "safetyTape", size: 16, opacity: 0.15, x: 0.82, y: 0.91),
        .init(id: 12, symbol: "trafficCone", size: 19, opacity: 0.16, x: 0.74, y: 0.31)
    ]

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                ForEach(items) { item in
                    NovaSafetyPPEGlyph(symbol: item.symbol, size: item.size,
                        color: NovaColorToken.textSecondary.color(in: scheme))
                        .opacity(item.opacity)
                        .position(x: geometry.size.width * item.x, y: geometry.size.height * item.y)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct NovaSizedText: View {
    let text: String
    var size: CGFloat = 15
    var weight = "SemiBold"
    var color: Color?
    @Environment(\.colorScheme) private var scheme
    private var role: NovaTypeToken {
        switch size {
        case ...10.5: return .badge
        case ...12: return .meta
        case ...13.5: return .body
        case ...16: return .cardTitle
        default: return .screenTitle
        }
    }
    var body: some View {
        Text(verbatim: text)
            .font(size > 22 ? .custom("PlusJakartaSans-\(weight)", size: size, relativeTo: .body) : NovaFont.font(role))
            .foregroundStyle(NovaFont.ink(color, role: role, scheme: scheme))
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct NovaDashboardScreen: View {
    let data: NovaDashboardData
    let onNavigate: (NovaDestination) -> Void
    let onPhoto: () -> Void
    var onAssistant: () -> Void = {}
    var analysisThumbnail: (UUID) async -> UIImage? = { await NovaAnalysisWorkspace.thumbnail(analysisID: $0) }
    var onOpenAnalysis: ((UUID) -> Void)? = nil
    var onFinding: ((String) -> Void)?
    var trackingIdentity: NovaSessionIdentity?
    var trackingCanWrite = false
    /// Optional workspace-specific controls rendered inside the same scroll
    /// surface. This keeps OSGB company selection/actions on the shared home
    /// page instead of creating a second dashboard layout.
    var footer: AnyView?
    /// Capability-gated photo capture can be removed without forking the
    /// dashboard layout.
    var showsPhotoCapture = true
    var showsAssistant = true
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var muted: Color { NovaColorToken.textMuted.color(in: scheme) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Keep the shell header visually separate from the greeting
                // card; the top bar is a control surface, not part of the
                // dashboard card stack.
                welcome.padding(.horizontal, 20).padding(.top, 10).padding(.bottom, 20)
                HStack {
                    NovaText(text: RDLocalization.string("localizable.nova.expert.shell.ozet.79587bac", table: .localizable, fallback: "Özet"), style: .sectionTitle)
                    Spacer()
                    NovaText(text: RDLocalization.string("localizable.nova.dashboard.current", table: .localizable, fallback: "Güncel"), style: .meta, color: muted)
                }.padding(.horizontal, 20).padding(.bottom, 9)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(data.metrics) { metric in
                            NovaListStat(title: metric.label, symbol: metric.symbol, value: metric.value) {
                                onNavigate(metric.destination)
                            }
                            .frame(width: typeSize.isAccessibilitySize ? 160 : 86)
                            .accessibilityIdentifier("nova.metric.\(metric.id)")
                        }
                    }.padding(.horizontal, 16)
                }.padding(.bottom, 18)
                if showsPhotoCapture {
                    capture.padding(.horizontal, 20).padding(.bottom, 22)
                }
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal.decrease").foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                    NovaText(text: "Son Analizler", style: .screenTitle)
                    Spacer(minLength: 0)
                    Button { onNavigate(.analyses) } label: { NovaText(text: RDLocalization.string("localizable.nova.expert.shell.tumu.e4457af3", table: .localizable, fallback: "Tümü"), style: .meta, color: muted) }
                }.padding(.horizontal, 20)
                if data.recentAnalyses.isEmpty {
                    Button { onNavigate(.newAnalysis) } label: {
                        HStack(spacing: 10) {
                            NovaIcon(symbol: "photo.on.rectangle.angled", size: 20)
                                .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                            NovaText(text: "Henüz analiz yok · İlk analizi oluştur", style: .meta)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right").font(.system(size: 12, weight: .semibold))
                        }
                        .padding(.horizontal, 14).frame(minHeight: 52)
                        .novaControlBackground(cornerRadius: 18)
                    }
                    .buttonStyle(NovaRowPressStyle())
                    .padding(.horizontal, 20).padding(.top, 12)
                    .accessibilityIdentifier("nova.home.analysis.empty")
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(alignment: .top, spacing: 10) {
                            ForEach(data.recentAnalyses) { analysis in
                                NovaRecentAnalysisStory(analysis: analysis,
                                    loadPhoto: analysisThumbnail,
                                    onOpen: {
                                        if let id = UUID(uuidString: analysis.id), let onOpenAnalysis {
                                            onOpenAnalysis(id)
                                        } else {
                                            onNavigate(.analyses)
                                        }
                                    })
                            }
                        }.padding(.horizontal, 20).padding(.top, 12)
                    }
                }
                if let trackingIdentity {
                    NovaModuleTrackingCard(identity: trackingIdentity, canWrite: trackingCanWrite)
                        .padding(.horizontal, 20).padding(.top, 22)
                }
                if let footer {
                    footer
                        .padding(.horizontal, 16)
                        .padding(.top, 22)
                }
            }.padding(.bottom, 122)
        }.background(NovaColorToken.canvas.color(in: scheme)).accessibilityIdentifier("nova.home.scroll")
    }

    private var welcome: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 22)
                    .fill(LinearGradient(
                        colors: [
                            NovaColorToken.surface.color(in: scheme),
                            NovaColorToken.surface.color(in: scheme).opacity(0.94),
                            NovaColorToken.accent.color(in: scheme).opacity(scheme == .dark ? 0.48 : 0.38)
                        ], startPoint: .topLeading, endPoint: .bottomTrailing))
                NovaSafetyIconPattern()
                greeting
                    .frame(width: geometry.size.width * (typeSize.isAccessibilitySize ? 0.94 : 0.78), alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            }
        }
        .frame(height: typeSize.isAccessibilitySize ? 92 : 72)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(RoundedRectangle(cornerRadius: 22)
            .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
    }
    private var greeting: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                NovaIcon(symbol: "helmet", size: 18)
                NovaSizedText(text: String(format: RDLocalization.string("localizable.nova.shell.greeting", table: .localizable, fallback: "Merhaba, %@"), data.firstName), size: 15.5, weight: "Bold")
                    .lineLimit(1).minimumScaleFactor(0.85)
            }.lineLimit(1)
            NovaText(text: data.summaryMessage ?? data.openCount.map { String(format: RDLocalization.string("localizable.nova.shell.open.nonconformities.today", table: .localizable, fallback: "Bugün %@ açık uygunsuzluk var."), String($0)) } ?? RDLocalization.string("localizable.nova.shell.summary.loading", table: .localizable, fallback: "Özet yükleniyor…"),
                     style: .metaQuiet, color: muted)
                .lineLimit(1).minimumScaleFactor(0.85)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var activity: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                NovaText(text: RDLocalization.string("localizable.nova.expert.shell.canli.akis.594c801d", table: .localizable, fallback: "Canlı Akış"), style: .sectionTitle)
                Spacer()
                Button { onNavigate(.notifications) } label: {
                    HStack(spacing: 4) {
                        NovaText(text: RDLocalization.string("localizable.nova.expert.shell.tumu.497eccb9", table: .localizable, fallback: "Tümü"), style: .meta, color: NovaColorToken.accentInk.color(in: scheme))
                        Image(systemName: "arrow.right").font(.system(size: 12))
                    }
                }.foregroundStyle(NovaColorToken.accentInk.color(in: scheme)).frame(minHeight: 28)
            }
            Button { onNavigate(.notifications) } label: {
                HStack(spacing: 10) {
                    NovaIcon(symbol: "building.2", size: 16).foregroundStyle(NovaColorToken.statusInfoDot.color(in: scheme))
                    NovaSizedText(text: data.activity ?? RDLocalization.string("localizable.nova.shell.no.recent.activity", table: .localizable, fallback: "Henüz yeni etkinlik yok."), size: 11, color: NovaColorToken.textSecondary.color(in: scheme))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                }.frame(minHeight: 30)
            }.disabled(data.activity == nil)
        }.buttonStyle(NovaRowPressStyle()).padding(12).padding(.vertical, 3)
            .novaControlBackground(cornerRadius: 24)
    }
    private var capture: some View {
        VStack(spacing: 12) {
            HStack {
                NovaText(text: RDLocalization.string("localizable.nova.expert.shell.yeni.kayit.9acd3c41", table: .localizable, fallback: "Yeni kayıt"), style: .sectionTitle)
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: "arrow.left.and.right")
                    Text("Kaydır")
                }
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
                .accessibilityHidden(true)
            }
            GeometryReader { geometry in
                let width = geometry.size.width * (typeSize.isAccessibilitySize ? 0.86 : 0.68)
                let height: CGFloat = typeSize.isAccessibilitySize ? 210 : 176
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        addActionCard(title: RDLocalization.string("localizable.nova.nonconformity.choose.photo.title", table: .localizable, fallback: "Fotoğraftan analiz"),
                            detail: RDLocalization.string("localizable.nova.home.photo.detail", table: .localizable, fallback: "Fotoğraf seç veya çek"), symbol: "camera.fill", isPhoto: true, width: width, height: height,
                            action: onPhoto, identifier: "nova.home.photo")
                        addActionCard(title: RDLocalization.string("localizable.nova.home.manual.title", table: .localizable, fallback: "Elle uygunsuzluk"),
                            detail: RDLocalization.string("localizable.nova.home.manual.detail", table: .localizable, fallback: "Bilgileri adım adım gir"), symbol: "square.and.pencil", isPhoto: false, width: width, height: height,
                            action: { onNavigate(.newFinding) }, identifier: "nova.home.addFinding")
                    }
                    .padding(.trailing, 2)
                }
                .accessibilityIdentifier("nova.home.quickActions")
            }
            .frame(height: typeSize.isAccessibilitySize ? 210 : 176)
        }
    }

    private func addActionCard(title: String, detail: String, symbol: String,
                               isPhoto: Bool, width: CGFloat, height: CGFloat,
                               action: @escaping () -> Void, identifier: String) -> some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 18)
                    .fill(NovaColorToken.surface.color(in: scheme))
                if isPhoto { NovaPhotoSafetyPattern() }
                VStack(alignment: .leading, spacing: 6) {
                    Spacer(minLength: typeSize.isAccessibilitySize ? 48 : 78)
                    NovaText(text: title, style: .bodyStrong).lineLimit(2)
                    NovaText(text: detail, style: .metaQuiet).lineLimit(2)
                    Spacer(minLength: 2)
                    HStack {
                        NovaText(text: RDLocalization.string("localizable.nova.home.start", table: .localizable, fallback: "Başla"),
                            style: .meta, color: NovaColorToken.accentInk.color(in: scheme))
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.right").font(.system(size: 12, weight: .semibold))
                    }
                }
                .padding(14)
                .overlay(alignment: .center) {
                    Image(systemName: symbol)
                        .font(.system(size: isPhoto ? 22 : 20, weight: .semibold))
                        .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                        .frame(width: isPhoto ? 52 : 48, height: isPhoto ? 52 : 48)
                        .background(NovaColorToken.accent.color(in: scheme).opacity(0.13), in: Circle())
                        .overlay(Circle().strokeBorder(NovaColorToken.accent.color(in: scheme).opacity(0.34), lineWidth: 1))
                        .offset(y: typeSize.isAccessibilitySize ? -42 : -27)
                }
            }
            .frame(width: width, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(NovaColorToken.borderStrong.color(in: scheme),
                        style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [5, 4]))
            }
            .contentShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(NovaRowPressStyle())
        .accessibilityIdentifier(identifier)
    }
}

/// Full-bleed portrait photo cards for the recent-analysis story rail.
private struct NovaRecentAnalysisStory: View {
    let analysis: NovaRecentAnalysis
    let loadPhoto: (UUID) async -> UIImage?
    let onOpen: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var photo: UIImage?

    private let diameter: CGFloat = 82
    private let ringWidth: CGFloat = 3
    private var photoDiameter: CGFloat { diameter - ringWidth * 2 }

    var body: some View {
        Button(action: onOpen) {
            ZStack {
                Circle().fill(NovaColorToken.accentSoft.color(in: scheme))
                if let photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: photoDiameter, height: photoDiameter)
                        .scaleEffect(1.55)
                        .frame(width: photoDiameter, height: photoDiameter)
                        .clipped()
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(
                            Color.white.opacity(scheme == .dark ? 0.14 : 0.82), lineWidth: 1))
                } else {
                    Circle()
                        .fill(NovaColorToken.surfaceMuted.color(in: scheme))
                        .frame(width: photoDiameter, height: photoDiameter)
                        .overlay(Circle().strokeBorder(
                            Color.white.opacity(scheme == .dark ? 0.14 : 0.82), lineWidth: 1))
                }
            }
            .frame(width: diameter, height: diameter)
            .overlay(Circle().strokeBorder(
                NovaColorToken.accent.color(in: scheme).opacity(scheme == .dark ? 0.78 : 0.60),
                lineWidth: 1.25))
            .contentShape(Circle())
        }
        .buttonStyle(NovaRowPressStyle())
        .accessibilityLabel("\(analysis.companyName), \(analysis.createdOn)")
        .accessibilityIdentifier("nova.home.analysis.\(analysis.id)")
        .task(id: analysis.id) {
            guard let id = UUID(uuidString: analysis.id) else { return }
            photo = await loadPhoto(id)
        }
    }
}

/// Light PPE glyph collage on the white photo-analysis card. The centered
/// camera badge stays on a quiet field so the primary action remains obvious.
private struct NovaPhotoSafetyPattern: View {
    private struct Item: Identifiable {
        let id: Int
        let symbol: String
        let size: CGFloat
        let x: CGFloat
        let y: CGFloat
        let rotation: Double
        let opacity: Double
    }
    private let items: [Item] = [
        .init(id: 1, symbol: "hardhat", size: 27, x: 0.11, y: 0.16, rotation: -12, opacity: 0.22),
        .init(id: 2, symbol: "eyeglasses", size: 24, x: 0.39, y: 0.11, rotation: 8, opacity: 0.19),
        .init(id: 3, symbol: "earmuffs", size: 21, x: 0.78, y: 0.15, rotation: 10, opacity: 0.22),
        .init(id: 4, symbol: "shield.fill", size: 17, x: 0.94, y: 0.32, rotation: 9, opacity: 0.18),
        .init(id: 5, symbol: "glove", size: 23, x: 0.08, y: 0.40, rotation: -8, opacity: 0.20),
        .init(id: 6, symbol: "trafficCone", size: 28, x: 0.91, y: 0.51, rotation: 7, opacity: 0.23),
        .init(id: 7, symbol: "safetyTape", size: 20, x: 0.12, y: 0.67, rotation: -8, opacity: 0.18),
        .init(id: 8, symbol: "hardhat", size: 17, x: 0.35, y: 0.58, rotation: 12, opacity: 0.16),
        .init(id: 9, symbol: "hardhat", size: 22, x: 0.61, y: 0.70, rotation: 12, opacity: 0.20),
        .init(id: 10, symbol: "eyeglasses", size: 23, x: 0.89, y: 0.84, rotation: -10, opacity: 0.18),
        .init(id: 11, symbol: "hand.raised.fill", size: 18, x: 0.66, y: 0.34, rotation: 12, opacity: 0.17),
        .init(id: 12, symbol: "exclamationmark.triangle.fill", size: 19, x: 0.39, y: 0.88, rotation: -9, opacity: 0.21),
        .init(id: 13, symbol: "earmuffs", size: 18, x: 0.54, y: 0.17, rotation: -6, opacity: 0.17),
        .init(id: 14, symbol: "safetyTape", size: 24, x: 0.73, y: 0.91, rotation: 8, opacity: 0.18),
        .init(id: 15, symbol: "trafficCone", size: 17, x: 0.10, y: 0.91, rotation: -7, opacity: 0.17),
        .init(id: 16, symbol: "shield.fill", size: 16, x: 0.52, y: 0.49, rotation: 4, opacity: 0.14),
        .init(id: 17, symbol: "glove", size: 19, x: 0.91, y: 0.08, rotation: 10, opacity: 0.17),
        .init(id: 18, symbol: "hardhat", size: 18, x: 0.20, y: 0.27, rotation: -9, opacity: 0.16)
    ]
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        GeometryReader { geometry in
            ForEach(items) { item in
                NovaSafetyPPEGlyph(symbol: item.symbol, size: item.size,
                    color: NovaColorToken.textTertiary.color(in: scheme))
                    .opacity(item.opacity)
                    .rotationEffect(.degrees(item.rotation))
                    .position(x: geometry.size.width * item.x, y: geometry.size.height * item.y)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Small native PPE glyphs for the background collage, with no external art
/// assets or platform-specific SF Symbol requirements.
private struct NovaSafetyPPEGlyph: View {
    let symbol: String
    let size: CGFloat
    let color: Color

    @ViewBuilder var body: some View {
        switch symbol {
        case "hardhat": hardhat
        case "earmuffs": earmuffs
        case "trafficCone": trafficCone
        case "safetyTape": safetyTape
        case "glove": Image(systemName: "hand.raised.fill").font(.system(size: size, weight: .medium)).foregroundStyle(color)
        default: Image(systemName: symbol).font(.system(size: size, weight: .medium)).foregroundStyle(color)
        }
    }

    private var lineWidth: CGFloat { max(1.2, size * 0.055) }

    private var hardhat: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: width * 0.14, y: height * 0.66))
                    path.addLine(to: CGPoint(x: width * 0.86, y: height * 0.66))
                    path.addLine(to: CGPoint(x: width * 0.82, y: height * 0.54))
                    path.addCurve(to: CGPoint(x: width * 0.18, y: height * 0.54),
                        control1: CGPoint(x: width * 0.74, y: height * 0.12),
                        control2: CGPoint(x: width * 0.26, y: height * 0.12))
                    path.closeSubpath()
                }
                .fill(color.opacity(0.12))
                Path { path in
                    path.move(to: CGPoint(x: width * 0.14, y: height * 0.66))
                    path.addLine(to: CGPoint(x: width * 0.86, y: height * 0.66))
                    path.move(to: CGPoint(x: width * 0.50, y: height * 0.22))
                    path.addLine(to: CGPoint(x: width * 0.50, y: height * 0.60))
                    path.move(to: CGPoint(x: width * 0.08, y: height * 0.73))
                    path.addLine(to: CGPoint(x: width * 0.92, y: height * 0.73))
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
            }
        }
        .frame(width: size, height: size)
    }

    private var earmuffs: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: width * 0.19, y: height * 0.69))
                    path.addCurve(to: CGPoint(x: width * 0.81, y: height * 0.69),
                        control1: CGPoint(x: width * 0.12, y: height * 0.02),
                        control2: CGPoint(x: width * 0.88, y: height * 0.02))
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                RoundedRectangle(cornerRadius: size * 0.1)
                    .fill(color.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.1).stroke(color, lineWidth: lineWidth))
                    .frame(width: width * 0.24, height: height * 0.38)
                    .position(x: width * 0.19, y: height * 0.65)
                RoundedRectangle(cornerRadius: size * 0.1)
                    .fill(color.opacity(0.14))
                    .overlay(RoundedRectangle(cornerRadius: size * 0.1).stroke(color, lineWidth: lineWidth))
                    .frame(width: width * 0.24, height: height * 0.38)
                    .position(x: width * 0.81, y: height * 0.65)
            }
        }
        .frame(width: size, height: size)
    }

    private var trafficCone: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: width * 0.47, y: height * 0.12))
                    path.addLine(to: CGPoint(x: width * 0.56, y: height * 0.12))
                    path.addLine(to: CGPoint(x: width * 0.78, y: height * 0.78))
                    path.addLine(to: CGPoint(x: width * 0.22, y: height * 0.78))
                    path.closeSubpath()
                }
                .fill(color.opacity(0.12))
                Path { path in
                    path.move(to: CGPoint(x: width * 0.47, y: height * 0.12))
                    path.addLine(to: CGPoint(x: width * 0.56, y: height * 0.12))
                    path.addLine(to: CGPoint(x: width * 0.78, y: height * 0.78))
                    path.addLine(to: CGPoint(x: width * 0.22, y: height * 0.78))
                    path.closeSubpath()
                    path.move(to: CGPoint(x: width * 0.34, y: height * 0.52))
                    path.addLine(to: CGPoint(x: width * 0.66, y: height * 0.52))
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round))
                Path { path in
                    path.addRoundedRect(in: CGRect(x: width * 0.12, y: height * 0.81,
                        width: width * 0.76, height: height * 0.12), cornerSize: CGSize(width: 2, height: 2))
                }
                .fill(color.opacity(0.2))
                .overlay {
                    Path { path in
                        path.move(to: CGPoint(x: width * 0.12, y: height * 0.93))
                        path.addLine(to: CGPoint(x: width * 0.88, y: height * 0.93))
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                }
            }
        }
        .frame(width: size, height: size)
    }

    private var safetyTape: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let height = proxy.size.height
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: width * 0.16, y: height * 0.12))
                    path.addLine(to: CGPoint(x: width * 0.16, y: height * 0.88))
                    path.move(to: CGPoint(x: width * 0.84, y: height * 0.12))
                    path.addLine(to: CGPoint(x: width * 0.84, y: height * 0.88))
                    path.move(to: CGPoint(x: width * 0.16, y: height * 0.36))
                    path.addLine(to: CGPoint(x: width * 0.39, y: height * 0.57))
                    path.addLine(to: CGPoint(x: width * 0.61, y: height * 0.39))
                    path.addLine(to: CGPoint(x: width * 0.84, y: height * 0.57))
                }
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round, dash: [size * 0.11, size * 0.07]))
            }
        }
        .frame(width: size, height: size)
    }
}

/// Same icon-collage layout as OSGB's PhotoBackdrop.tsx, using native icon glyphs.
struct NovaPhotoBackdrop: View {
    @Environment(\.colorScheme) private var scheme
    private let motifs: [(CGFloat, Double, CGFloat, CGFloat, Double, String)] = [
        (30, 0.06, 16, 12, -14, "photo"), (20, 0.075, 62, 62, 8, "camera"),
        (40, 0.045, 24, 66, 6, "camera"), (22, 0.07, 108, 16, 12, "photo"),
        (16, 0.085, 148, 74, -8, "camera"), (34, 0.05, 210, 20, -10, "photo"),
        (24, 0.07, 262, 66, 14, "camera"), (18, 0.075, 300, 22, -6, "photo"),
        (28, 0.05, 246, 8, 18, "photo"), (20, 0.06, 186, 76, -16, "photo")
    ]
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                NovaColorToken.canvasSheet.color(in: scheme)
                ForEach(motifs.indices, id: \.self) { index in
                    let m = motifs[index]
                    Image("Nova_backdrop_\(m.5)", bundle: Bundle(for: NovaIconBundleMarker.self)).renderingMode(.template)
                        .resizable().scaledToFit().frame(width: m.0, height: m.0)
                        .foregroundStyle(NovaColorToken.text.color(in: scheme).opacity(m.1))
                        .rotationEffect(.degrees(m.4))
                        .offset(x: m.2 / 326 * geometry.size.width, y: m.3 / 118 * geometry.size.height)
                }
            }
        }.accessibilityHidden(true).allowsHitTesting(false)
    }
}

struct NovaCompaniesScreen: View {
    let companies: [NovaCompanyItem]
    var isLoading = false
    var error: String?
    var isOwnedList = false
    let onSelect: (String) -> Void
    let onBack: () -> Void
    let onRetry: () -> Void
    var onCreate: (() -> Void)? = nil
    @State private var search = ""
    @Environment(\.colorScheme) private var scheme
    private var filtered: [NovaCompanyItem] {
        let locale = Locale(identifier: "tr_TR")
        let needle = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(with: locale)
        return needle.isEmpty ? companies : companies.filter { "\($0.name) \($0.detail)".lowercased(with: locale).contains(needle) }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    NovaBackButton(action: onBack)
                    VStack(alignment: .leading, spacing: 2) {
                        NovaSizedText(text: "Firmalar", size: 20, weight: "ExtraBold")
                        NovaText(text: isOwnedList ? String(format: RDLocalization.string("localizable.nova.shell.company.count", table: .localizable, fallback: "%@ firma"), String(filtered.count)) : String(format: RDLocalization.string("localizable.nova.shell.assigned.company.count", table: .localizable, fallback: "%@ atanmış firma"), String(filtered.count)), style: .metaQuiet, color: NovaColorToken.textMuted.color(in: scheme))
                    }
                    Spacer(minLength: 0)
                    if let onCreate {
                        Button(action: onCreate) {
                            HStack(spacing: 5) {
                                Image(systemName: "plus").font(.system(size: 12, weight: .medium))
                                Text(verbatim: RDLocalization.string("localizable.nova.expert.shell.firma.ekle.09e0dac1", table: .localizable, fallback: "Firma Ekle"))
                                    .font(NovaFont.font(.bodyStrong))
                            }.padding(.horizontal, 15).frame(minWidth: 116, minHeight: 34)
                                .background(NovaColorToken.accent.color(in: scheme), in: Capsule())
                                .foregroundStyle(NovaColorToken.onAccent.color(in: scheme))
                        }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier("nova.pilot.company.create")
                    }
                }
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").font(.system(size: 14)).foregroundStyle(NovaColorToken.textPlaceholder.color(in: scheme))
                    TextField(RDLocalization.string("localizable.nova.expert.shell.firma.ara.c12d1792", table: .localizable, fallback: "Firma ara..."), text: $search).font(NovaFont.font(.body))
                        .autocorrectionDisabled().accessibilityIdentifier("nova.companies.search")
                    if !search.isEmpty {
                        Button { search = "" } label: { Image(systemName: "xmark").frame(width: 44, height: 44) }.accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.shell.clear.search", table: .localizable, fallback: "Aramayı temizle")))
                            .accessibilityLabel(RDLocalization.string("localizable.nova.expert.shell.aramayi.temizle.e3d82e8b", table: .localizable, fallback: "Aramayı temizle")).accessibilityIdentifier("nova.companies.clear")
                    }
                }.padding(.horizontal, 14).frame(minHeight: 44)
                    .novaControlBackground(cornerRadius: 16)
                if isLoading {
                    Label(RDLocalization.string("localizable.nova.expert.shell.firmalar.yukleniyor.af61acb2", table: .localizable, fallback: "Firmalar yükleniyor"), systemImage: "hourglass").padding(14)
                } else if let error {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(RDLocalization.string("localizable.nova.expert.shell.firmalar.alinamadi.6886c13c", table: .localizable, fallback: "Firmalar alınamadı"), systemImage: "exclamationmark.triangle")
                        NovaText(text: error, style: .metaQuiet)
                        Button(action: onRetry) { Label(RDLocalization.string("localizable.nova.expert.shell.tekrar.dene.f1867f5e", table: .localizable, fallback: "Tekrar dene"), systemImage: "arrow.clockwise") }.frame(minHeight: 44)
                    }.padding(14)
                } else if filtered.isEmpty {
                    Label(search.isEmpty ? (isOwnedList ? RDLocalization.string("localizable.nova.shell.no.company.added", table: .localizable, fallback: "Henüz firma eklenmedi.") : RDLocalization.string("localizable.nova.shell.no.company.assigned", table: .localizable, fallback: "Hesabına atanmış firma yok.")) : RDLocalization.string("localizable.nova.shell.company.not.found", table: .localizable, fallback: "Firma bulunamadı"), systemImage: "building.2")
                        .padding(14)
                } else {
                    ForEach(filtered) { company in
                        Button { onSelect(company.id) } label: {
                            HStack(spacing: 11) {
                                NovaText(text: novaInitials(company.name), style: .cardTitle, color: .white)
                                    .frame(width: 38, height: 38)
                                    .background(LinearGradient(colors: [Color(red: 1, green: 0.42, blue: 0.37), Color(red: 0.89, green: 0.2, blue: 0.16)],
                                                              startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 13))
                                VStack(alignment: .leading, spacing: 3) {
                                    NovaText(text: company.name, style: .cardTitle)
                                    NovaText(text: company.detail, style: .meta, color: NovaColorToken.textMuted.color(in: scheme))
                                    HStack(spacing: 8) {
                                        GeometryReader { proxy in
                                            Capsule()
                                                .fill(NovaColorToken.surfaceMuted.color(in: scheme))
                                                .overlay(alignment: .leading) {
                                                    Capsule()
                                                        .fill(NovaColorToken.accent.color(in: scheme))
                                                        .frame(width: proxy.size.width * CGFloat(min(max(company.progressCompleted, 0), max(company.progressTotal, 1))) / CGFloat(max(company.progressTotal, 1)))
                                                }
                                        }
                                        .frame(height: 5)
                                        NovaText(text: "\(min(max(company.progressCompleted, 0), max(company.progressTotal, 1)))/\(max(company.progressTotal, 1))", style: .micro,
                                                 color: NovaColorToken.textMuted.color(in: scheme))
                                            .fixedSize()
                                    }
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(NovaColorToken.borderStrong.color(in: scheme))
                            }.padding(14).frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
                                .novaControlBackground(cornerRadius: 22)
                        }.accessibilityIdentifier("nova.company.\(company.id)")
                    }
                }
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
        }.buttonStyle(NovaRowPressStyle()).background(NovaColorToken.canvas.color(in: scheme))
            .novaEdgeBackGesture(action: onBack)
    }
}

#if DEBUG
struct NovaExpertShellDemo: View {
    @State private var navigation = NovaNavigationState(epoch: "preview-only", available: Set(NovaDestination.allCases))
    var body: some View {
        NovaExpertShell(navigation: $navigation, userName: "Örnek Uzman") { destination in
            ScrollView {
                NovaCard {
                    VStack(alignment: .leading, spacing: 14) {
                        NovaText(text: destination.title, style: .screenTitle)
                        NovaText(text: "Gezinme önizlemesi. Canlı veriye bağlı değil; bu modülün iş akışı henüz bağlanmadı.")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.padding(20)
            }
        }
    }
}
struct NovaExpertShell_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            NovaExpertShellDemo().preferredColorScheme(.light)
            NovaExpertShellDemo().preferredColorScheme(.dark)
        }
    }
}
#endif
