import SwiftUI

/// New expert shell only. The owner supplies scoped state and real destination content.
/// Not installed in the legacy MainTabView; no Auth, billing or service calls here.
struct NovaExpertShell<Content: View>: View {
    @Binding var navigation: NovaNavigationState
    let userName: String
    var hasUnread = false
    var unreadCount = 0
    var notificationItems: [NovaNotice] = []
    /// The bell's own note, shown under the list. Empty hides it.
    var noticeNote = ""
    var onReadNotice: ((String) -> Void)?
    var onDismissNotice: ((String) -> Void)?
    var onRestoreNotice: ((String) -> Void)?
    var connectionLabel = RDLocalization.string("localizable.nova.shell.connection.unknown", table: .localizable, fallback: "Bağlantı bilgisi yok")
    var onReadAll: (() -> Void)?
    var onClearNotifications: (() -> Void)?
    var onCompanyCreate: (() -> Void)?
    /// Allows the composition root to reset feature-local state when a root
    /// destination is selected (for example, leaving a company workspace).
    var onDestination: ((NovaDestination) -> Void)?
    var onLogout: (() -> Void)?
    @ViewBuilder let content: (NovaDestination) -> Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        let epoch = navigation.epoch
        let send: (NovaNavigationEvent) -> Void = { navigation.apply($0, from: epoch) }
        GeometryReader { geometry in
            ZStack {
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
                    // Keep the bar in layout: TabView resets inherited bottom insets,
                    // which otherwise puts a child screen's sticky action under the bar.
                    NovaShellTabBar(selected: navigation.selected, canOpen: navigation.canOpen, send: send,
                        onDestination: guardedDestination(onDestination, epoch: epoch))
                        .accessibilityHidden(navigation.overlay != nil)
                        .allowsHitTesting(navigation.overlay == nil)
                        .padding(.horizontal, NovaDimensionToken.layoutTabBarInset.value)
                        .padding(.top, 8)
                        .padding(.bottom, max(10 - geometry.safeAreaInsets.bottom, 0) + 16)
                }
                .allowsHitTesting(navigation.overlay == nil)
                .accessibilityHidden(navigation.overlay != nil)
                .blur(radius: navigation.overlay == .quickAdd && !reduceTransparency ? 7 : 0)

                if let panel = navigation.overlay {
                    NovaShellPanel(panel: panel, selected: navigation.current, canOpen: navigation.canOpen,
                        userName: userName, send: send, notices: notificationItems, connectionLabel: connectionLabel,
                        noticeNote: noticeNote,
                        onReadAll: guarded(onReadAll, epoch: epoch), onClear: guarded(onClearNotifications, epoch: epoch),
                        onReadNotice: guardedKey(onReadNotice, epoch: epoch),
                        onDismissNotice: guardedKey(onDismissNotice, epoch: epoch),
                        onRestoreNotice: guardedKey(onRestoreNotice, epoch: epoch),
                        onCompanyCreate: guarded(onCompanyCreate, epoch: epoch),
                        onDestination: guardedDestination(onDestination, epoch: epoch),
                        onLogout: guarded(onLogout, epoch: epoch))
                }
            }.background(NovaColorToken.canvas.color(in: scheme).ignoresSafeArea())
        }
        // Caller replaces the state on Auth/session-epoch change; local child state must not leak.
        .id(navigation.epoch)
        .environment(\.novaHasHeader, true)
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
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedDrawerGroup: String?

    var body: some View {
        VStack(spacing: 8) {
        HStack(spacing: 10) {
            icon(canGoBack ? "chevron.left" : "line.3.horizontal", label: canGoBack ? RDLocalization.string("localizable.nova.shell.back", table: .localizable, fallback: "Geri") : RDLocalization.string("localizable.nova.shell.open.menu", table: .localizable, fallback: "Menüyü aç"),
                 id: canGoBack ? "nova.back" : "nova.menu") { send(canGoBack ? .back : .open(.drawer)) }
            if typeSize.isAccessibilitySize { Spacer() } else { brand }
            icon("bell", label: hasUnread ? RDLocalization.string("localizable.nova.shell.notifications.with.new", table: .localizable, fallback: "Bildirimler, yeni bildirim var") : RDLocalization.string("localizable.nova.shell.notifications", table: .localizable, fallback: "Bildirimler"), id: "nova.notifications") {
                send(.open(.notifications))
            }
                .disabled(!notificationsAvailable).overlay(alignment: .topTrailing) { badge }
            Button { send(.select(.profile)) } label: {
                NovaIcon(symbol: "person", size: 22)
                    .foregroundStyle(NovaColorToken.text.color(in: scheme))
                    .frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel(RDLocalization.string("localizable.nova.expert.shell.hesabim.f6d2ed00", table: .localizable, fallback: "Hesabım")).accessibilityIdentifier("nova.profile")
        }
        if typeSize.isAccessibilitySize { brand }
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

    private var brand: some View {
        VStack(spacing: 1) {
            NovaText(text: RDLocalization.string("localizable.nova.expert.shell.brand", table: .localizable, fallback: "İSGADA"), style: .brand)
            NovaText(text: RDLocalization.string("localizable.nova.expert.shell.saha.denetim.asistani.192b4816", table: .localizable, fallback: "Saha denetim asistanı"), style: .meta, color: NovaColorToken.textMuted.color(in: scheme))
        }.frame(maxWidth: .infinity).multilineTextAlignment(.center)
    }

    private func icon(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Color.clear
                NovaIcon(symbol: symbol, size: 17)
                    .foregroundStyle((symbol == "bell" ? NovaColorToken.accentInk : .text).color(in: scheme))
            }.frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel(Text(verbatim: label)).accessibilityIdentifier(id)
    }
}

struct NovaShellTabBar: View {
    let selected: NovaTab
    let canOpen: (NovaDestination) -> Bool
    let send: (NovaNavigationEvent) -> Void
    var onDestination: ((NovaDestination) -> Void)? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedDrawerGroup: String?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        NovaShellTabStrip(selected: selected, canOpen: canOpen, send: send,
                            onDestination: onDestination, expanded: true)
                    }
                    .accessibilityIdentifier("nova.tabs.scroll")
                    .onAppear { proxy.scrollTo(selected.rawValue, anchor: .center) }
                    .onChange(of: selected) { value in proxy.scrollTo(value.rawValue, anchor: .center) }
                }.fixedSize(horizontal: false, vertical: true)
            } else {
                NovaShellTabStrip(selected: selected, canOpen: canOpen, send: send, onDestination: onDestination)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .frame(minHeight: NovaDimensionToken.layoutTabBarHeight.value)
        .background {
            if reduceTransparency {
                RoundedRectangle(cornerRadius: NovaDimensionToken.radiusTabBar.value).fill(NovaColorToken.surface.color(in: scheme))
            } else {
                RoundedRectangle(cornerRadius: NovaDimensionToken.radiusTabBar.value).fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: NovaDimensionToken.radiusTabBar.value).fill(NovaColorToken.glass.color(in: scheme)))
            }
        }
        .overlay(RoundedRectangle(cornerRadius: NovaDimensionToken.radiusTabBar.value).strokeBorder(NovaColorToken.glassBorder.color(in: scheme)))
        .shadow(color: .black.opacity(0.025), radius: 16, x: 0, y: 4)
    }

}

struct NovaShellTabStrip: View {
    let selected: NovaTab
    let canOpen: (NovaDestination) -> Bool
    let send: (NovaNavigationEvent) -> Void
    var onDestination: ((NovaDestination) -> Void)? = nil
    var expanded = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            tab(.home)
            tab(.findings)
            Button { send(.open(.quickAdd)) } label: {
                VStack(spacing: 2) {
                    Image(systemName: "plus").font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(NovaColorToken.text.color(in: scheme))
                        .frame(width: 42, height: 42)
                    NovaText(text: "Ekle", style: .tab, color: NovaColorToken.accent.color(in: scheme)).lineLimit(1)
                }.frame(minWidth: 44, maxWidth: expanded ? nil : .infinity, minHeight: 52)
                    .padding(.horizontal, expanded ? 12 : 0).contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel("Ekle").accessibilityIdentifier("nova.add").id("add")
            tab(.companies)
            tab(.profile)
        }
    }

    private func tab(_ tab: NovaTab) -> some View {
        Button { onDestination?(tab.root); send(.select(tab)) } label: {
            VStack(spacing: 2) {
                NovaIcon(symbol: tab.root.symbol, size: 19)
                    .frame(width: 34, height: 42)
                NovaText(text: tab.title, style: .tab, color: NovaColorToken.text.color(in: scheme))
                    .lineLimit(1).minimumScaleFactor(expanded ? 1 : 0.75)
            }.foregroundStyle(NovaColorToken.text.color(in: scheme))
                .frame(minWidth: 44, maxWidth: expanded ? nil : .infinity, minHeight: 52)
                .padding(.horizontal, expanded ? 12 : 0).contentShape(Rectangle())
                .opacity(canOpen(tab.root) ? (selected == tab ? 1 : 0.45) : 0.3)
        }.buttonStyle(.plain).disabled(!canOpen(tab.root))
            .accessibilityLabel(Text(verbatim: tab.title))
            .accessibilityAddTraits(selected == tab ? .isSelected : [])
            .accessibilityIdentifier("nova.tab.\(tab.rawValue)").id(tab.rawValue)
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
        .padding(isPopover ? 14 : 16)
        .background {
            if isPopover {
                RoundedRectangle(cornerRadius: 26).fill(.regularMaterial)
            } else { RoundedRectangle(cornerRadius: 30).fill(NovaColorToken.canvasSheet.color(in: scheme)) }
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

func novaInitials(_ name: String) -> String {
    name.split(whereSeparator: { $0.isWhitespace }).prefix(2).compactMap(\.first)
        .map(String.init).joined().uppercased(with: Locale(identifier: "tr_TR"))
}

struct NovaShellPanel: View {
    let panel: NovaOverlay
    let selected: NovaDestination
    let canOpen: (NovaDestination) -> Bool
    let userName: String
    let send: (NovaNavigationEvent) -> Void
    var notices: [NovaNotice] = []
    var connectionLabel = RDLocalization.string("localizable.nova.shell.connection.unknown", table: .localizable, fallback: "Bağlantı bilgisi yok")
    var noticeNote = ""
    var onReadAll: (() -> Void)?
    var onClear: (() -> Void)?
    var onReadNotice: ((String) -> Void)?
    var onDismissNotice: ((String) -> Void)?
    var onRestoreNotice: ((String) -> Void)?
    var onCompanyCreate: (() -> Void)?
    var onDestination: ((NovaDestination) -> Void)?
    var onLogout: (() -> Void)?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var expandedDrawerGroup: String?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: panel == .drawer ? .leading : panel == .notifications ? .top : .center) {
                (panel == .quickAdd ? Color(red: 15 / 255, green: 15 / 255, blue: 17 / 255).opacity(0.34) : NovaColorToken.scrim.color(in: scheme)).ignoresSafeArea()
                    .onTapGesture { send(.dismiss) }.accessibilityHidden(true)
                if panel == .drawer {
                    drawer
                        .frame(width: min(typeSize.isAccessibilitySize ? 360 : 290, geometry.size.width - 48))
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
        Button { send(.dismiss) } label: {
            Image(systemName: "xmark").font(.system(size: 17)).frame(width: 44, height: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
            .accessibilityLabel(RDLocalization.string("localizable.nova.expert.shell.kapat.73fe721a", table: .localizable, fallback: "Kapat")).accessibilityIdentifier("nova.panel.close")
    }

    private var drawer: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                NovaText(text: novaInitials(userName), style: .cardTitle, color: .white)
                    .frame(width: 48, height: 48)
                    .background(Color(white: 0.14), in: RoundedRectangle(cornerRadius: 16))
                VStack(alignment: .leading, spacing: 2) {
                    NovaText(text: userName, style: .sectionTitle)
                    NovaText(text: RDLocalization.string("localizable.nova.expert.shell.isg.uzmani.4d28231f", table: .localizable, fallback: "İSG Uzmanı"), style: .metaQuiet, color: NovaColorToken.textMuted.color(in: scheme))
                }
                Spacer(minLength: 0)
                close
            }.padding(.top, 16).padding(.bottom, 18)
            NovaText(text: connectionLabel, style: .meta, color: NovaColorToken.statusSuccessInk.color(in: scheme))
                .padding(.bottom, 14)
            Rectangle().fill(NovaColorToken.hairline.color(in: scheme)).frame(height: 1).padding(.bottom, 12)
            ScrollView {
                VStack(spacing: 0) {
                    drawerDestination(.home)
                    ForEach(NovaDrawerGroup.all) { group in
                        drawerGroup(group)
                    }
                    drawerDestination(.statistics)
                    drawerDestination(.notifications)
                }
            }.accessibilityIdentifier("nova.panel.scroll")
                .onAppear {
                    expandedDrawerGroup = NovaDrawerGroup.all.first { $0.destinations.contains(selected) }?.id
                }
            Button { onLogout?() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.right")
                    NovaText(text: RDLocalization.string("localizable.nova.expert.shell.cikis.yap.6a3d02af", table: .localizable, fallback: "Çıkış yap"), style: .button, color: NovaColorToken.textSecondary.color(in: scheme))
                }.frame(maxWidth: .infinity, minHeight: 46)
                    .background(NovaColorToken.surfaceMuted.color(in: scheme), in: Capsule())
            }.buttonStyle(.plain).disabled(onLogout == nil).accessibilityIdentifier("nova.logout")
                .padding(.top, 10).padding(.bottom, 14)
        }.padding(.horizontal, 20)
    }

    private func drawerGroup(_ group: NovaDrawerGroup) -> some View {
        let expanded = expandedDrawerGroup == group.id
        return VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.18)) {
                    expandedDrawerGroup = expanded ? nil : group.id
                }
            } label: {
                HStack(spacing: 12) {
                    NovaIcon(symbol: group.symbol, size: 18).frame(width: 20)
                    NovaText(text: group.title, style: .buttonSm)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .medium))
                        .rotationEffect(.degrees(expanded ? 180 : 0))
                }
                .foregroundStyle(NovaColorToken.text.color(in: scheme))
                .padding(.horizontal, 8).padding(.vertical, 6)
                .frame(minHeight: 46).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("nova.drawer.group.\(group.id)")
            .accessibilityValue(expanded ? RDLocalization.string("localizable.nova.drawer.expanded", table: .localizable, fallback: "Açık") : RDLocalization.string("localizable.nova.drawer.collapsed", table: .localizable, fallback: "Kapalı"))
            if expanded {
                VStack(spacing: 0) {
                    ForEach(group.destinations, id: \.self) { destination in
                        drawerDestination(destination, nested: true)
                    }
                }.padding(.bottom, 6)
            }
        }
    }

    private func drawerDestination(_ destination: NovaDestination, nested: Bool = false) -> some View {
        Button {
            onDestination?(destination)
            send(.navigate(destination))
        } label: {
            HStack(spacing: 12) {
                NovaIcon(symbol: destination.symbol, size: nested ? 17 : 18).frame(width: 20)
                NovaText(text: destination.title, style: nested ? .body : .buttonSm)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                if selected == destination {
                    Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                }
            }
            .foregroundStyle(NovaColorToken.text.color(in: scheme))
            .padding(.leading, nested ? 24 : 8).padding(.trailing, 8).padding(.vertical, 6)
            .frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(!canOpen(destination))
            .opacity(canOpen(destination) ? 1 : 0.4)
            .accessibilityIdentifier("nova.destination.\(destination.rawValue)")
            .accessibilityAddTraits(selected == destination ? .isSelected : [])
    }

    private var quickAdd: some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: RDLocalization.string("localizable.nova.expert.shell.ne.eklemek.istiyorsun.ee07893e", table: .localizable, fallback: "Ne eklemek istiyorsun?"), style: .sectionTitle).padding(.horizontal, 4).padding(.bottom, 4)
            ForEach(NovaDestination.quickAdd, id: \.self) { destination in
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
                        .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 20))
                }.buttonStyle(.plain).disabled(!canOpen(destination)).opacity(canOpen(destination) ? 1 : 0.4)
                    .accessibilityIdentifier("nova.destination.\(destination.rawValue)")
            }
            Button { send(.dismiss) } label: {
                HStack(spacing: 10) {
                    NovaIcon(symbol: "chevron.left", size: 14)
                    NovaText(text: RDLocalization.string("localizable.nova.expert.shell.vazgec.5f0c7644", table: .localizable, fallback: "Vazgeç"), style: .button, color: NovaColorToken.textSecondary.color(in: scheme))
                }.frame(maxWidth: .infinity, minHeight: 46)
                    .background(NovaColorToken.surfaceMuted.color(in: scheme), in: Capsule())
            }.buttonStyle(.plain).foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                .padding(.top, 2).accessibilityIdentifier("nova.panel.close")
        }
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
            }.buttonStyle(.plain).foregroundStyle(NovaColorToken.statusSuccessInk.color(in: scheme)).padding(.top, -6).padding(.bottom, -13)
                .disabled(!canOpen(.notifications)).accessibilityIdentifier("nova.notices.center")
        }.buttonStyle(.plain)
    }

    /// One notice: the whole row opens the record, and the two controls on the
    /// right mark it read or take it off the list.
    @ViewBuilder private func noticeRow(_ notice: NovaNotice) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Button {
                // Opening a notice is reading it.
                onReadNotice?(notice.id)
                send(.navigate(notice.destination))
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
            }.buttonStyle(.plain).disabled(!canOpen(notice.destination))
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
            .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 20))
            .opacity(notice.dismissed ? 0.55 : 1)
            .padding(.bottom, 7)
    }

    @ViewBuilder private func noticeAction(_ symbol: String, _ label: String, _ identifier: String,
                                           _ disabled: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            NovaIcon(symbol: symbol, size: 13)
                .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
                .frame(width: 30, height: 30).contentShape(Rectangle())
        }.buttonStyle(.plain).disabled(disabled)
            .accessibilityLabel(Text(verbatim: label)).accessibilityIdentifier(identifier)
    }
}

extension NovaDestination {
    var quickHint: String {
        switch self {
        case .newFinding: return RDLocalization.string("localizable.nova.expert.shell.bulgu.fotograf.ve.oncelik.6cb3a0fa", table: .localizable, fallback: "Bulgu, fotoğraf ve öncelik")
        case .newDocument: return RDLocalization.string("localizable.nova.expert.shell.rapor.form.veya.belge.yukle.d2d30a9a", table: .localizable, fallback: "Rapor, form veya belge yükle")
        case .newVisit: return RDLocalization.string("localizable.nova.expert.shell.yeni.saha.ziyareti.planla.dbc1aeb4", table: .localizable, fallback: "Yeni saha ziyareti planla")
        case .newTraining: return RDLocalization.string("localizable.nova.expert.shell.firma.personeline.egitim.kaydi.olustur.17b5c3df", table: .localizable, fallback: "Firma personeline eğitim kaydı oluştur")
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
    var recentFindings: [NovaRecentFinding] = []
    var summaryMessage: String? = nil
}
struct NovaRecentFinding: Identifiable {
    let id: String
    let companyName: String
    var thumbnail: Image?
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
    let onAssistant: () -> Void
    var onFinding: ((String) -> Void)?
    var trackingIdentity: NovaSessionIdentity?
    var trackingCanWrite = false
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var muted: Color { NovaColorToken.textMuted.color(in: scheme) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                welcome.padding(.horizontal, 20).padding(.bottom, 20)
                if let trackingIdentity {
                    NovaModuleTrackingCard(identity: trackingIdentity, canWrite: trackingCanWrite)
                        .padding(.horizontal, 20).padding(.bottom, 16)
                }
                HStack {
                    NovaText(text: RDLocalization.string("localizable.nova.expert.shell.ozet.79587bac", table: .localizable, fallback: "Özet"), style: .sectionTitle)
                    Spacer()
                    NovaText(text: RDLocalization.string("localizable.nova.dashboard.current", table: .localizable, fallback: "Güncel"), style: .meta, color: muted)
                }.padding(.horizontal, 20).padding(.bottom, 9)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: 8) {
                        ForEach(data.metrics) { metric in
                            Button { onNavigate(metric.destination) } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        NovaIcon(symbol: metric.symbol, size: 15).foregroundStyle(metric.tone.color(in: scheme))
                                        NovaSizedText(text: metric.value, size: 19, weight: "ExtraBold")
                                    }
                                    NovaSizedText(text: metric.label, size: 10, weight: "Medium", color: muted)
                                        .lineLimit(2).frame(maxWidth: .infinity, minHeight: 24, alignment: .topLeading)
                                    NovaSizedText(text: metric.footer, size: 9.5, weight: "Bold",
                                        color: metric.id == "open" ? metric.tone.color(in: scheme) : muted)
                                        .lineLimit(1).minimumScaleFactor(0.8)
                                }.padding(.horizontal, 10).padding(.vertical, 11)
                                    .frame(width: typeSize.isAccessibilitySize ? 160 : 86, height: typeSize.isAccessibilitySize ? nil : 86, alignment: .topLeading)
                                    .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 18))
                            }.buttonStyle(.plain).accessibilityIdentifier("nova.metric.\(metric.id)")
                        }
                    }.padding(.horizontal, 16)
                }.padding(.bottom, 18)
                capture.padding(.horizontal, 20).padding(.bottom, 22)
                Button { onNavigate(.training) } label: {
                    HStack(spacing: 12) {
                        NovaIcon(symbol: "hand.thumbsup.fill", size: 22).foregroundStyle(NovaColorToken.accent.color(in: scheme))
                        VStack(alignment: .leading, spacing: 2) {
                            NovaText(text: RDLocalization.string("localizable.nova.expert.shell.egitim.ve.takip.bc2f6a1a", table: .localizable, fallback: "Eğitim ve Takip"), style: .cardTitle)
                            NovaSizedText(text: data.trainingMessage, size: 11, weight: "Regular", color: NovaColorToken.textSecondary.color(in: scheme))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.system(size: 18)).foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                    }.padding(.horizontal, 14).padding(.vertical, 13).frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
                        .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 24))
                }.buttonStyle(.plain).padding(.horizontal, 18).padding(.bottom, 10).accessibilityIdentifier("nova.home.training")
                HStack(spacing: 10) {
                    Image(systemName: "line.3.horizontal.decrease").foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                    NovaText(text: RDLocalization.string("localizable.nova.expert.shell.son.uygunsuzluklar.6355cdea", table: .localizable, fallback: "Son Uygunsuzluklar"), style: .screenTitle)
                    Spacer(minLength: 0)
                    Button { onNavigate(.findings) } label: { NovaText(text: RDLocalization.string("localizable.nova.expert.shell.tumu.e4457af3", table: .localizable, fallback: "Tümü"), style: .meta, color: muted) }
                }.padding(.horizontal, 20)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 14) {
                        ForEach(data.recentFindings) { finding in
                            Button { onFinding?(finding.id) } label: {
                                VStack(spacing: 8) {
                                    Group {
                                        if let thumbnail = finding.thumbnail { thumbnail.resizable().scaledToFill() }
                                        else { NovaIcon(symbol: "camera", size: 22) }
                                    }.frame(width: 60, height: 60).clipShape(Circle())
                                        .padding(3).overlay(Circle().strokeBorder(NovaColorToken.statusInfoDot.color(in: scheme), lineWidth: 3))
                                    NovaText(text: finding.companyName, style: .meta, color: muted).lineLimit(1)
                                }.frame(width: 74)
                            }.buttonStyle(.plain).disabled(onFinding == nil).accessibilityIdentifier("nova.recent.\(finding.id)")
                        }
                    }.padding(.horizontal, 20).padding(.top, 14)
                }
            }.padding(.bottom, 122)
        }.background(NovaColorToken.canvas.color(in: scheme)).accessibilityIdentifier("nova.home.scroll")
    }

    private var welcome: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { greeting; assistant }
            VStack(alignment: .leading, spacing: 12) { greeting; assistant }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 22))
    }
    private var greeting: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
                NovaIcon(symbol: "helmet", size: 18)
                NovaSizedText(text: String(format: RDLocalization.string("localizable.nova.shell.greeting", table: .localizable, fallback: "Merhaba, %@"), data.firstName), size: 15.5, weight: "Bold")
            }
            NovaText(text: data.summaryMessage ?? data.openCount.map { String(format: RDLocalization.string("localizable.nova.shell.open.nonconformities.today", table: .localizable, fallback: "Bugün %@ açık uygunsuzluk var."), String($0)) } ?? RDLocalization.string("localizable.nova.shell.summary.loading", table: .localizable, fallback: "Özet yükleniyor…"),
                     style: .metaQuiet, color: muted)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var assistant: some View {
        Button(action: onAssistant) {
            HStack(spacing: 7) {
                NovaIcon(symbol: "sparkle", size: 14)
                NovaSizedText(text: RDLocalization.string("localizable.nova.expert.shell.ai.asistan.fd9d94db", table: .localizable, fallback: "AI Asistan"), size: 13.5)
            }.padding(.horizontal, 15).frame(minHeight: 44)
                .background(NovaColorToken.surfaceMuted.color(in: scheme), in: Capsule())
        }.buttonStyle(.plain).accessibilityIdentifier("nova.home.assistant")
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
        }.buttonStyle(.plain).padding(12).padding(.vertical, 3)
            .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 24))
    }
    private var capture: some View {
        VStack(spacing: 0) {
            HStack {
                NovaText(text: RDLocalization.string("localizable.nova.expert.shell.yeni.kayit.9acd3c41", table: .localizable, fallback: "Yeni kayıt"), style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(NovaColorToken.surfaceMuted.color(in: scheme), in: Capsule())
                Spacer()
                HStack(spacing: 5) {
                    ForEach([1.0, 0.45, 0.2], id: \.self) { opacity in
                        Circle().fill(NovaColorToken.accent.color(in: scheme).opacity(opacity)).frame(width: 6, height: 6)
                    }
                }.accessibilityHidden(true)
            }
            Button(action: onPhoto) {
                VStack(spacing: 9) {
                    Image("Nova_cameraLarge", bundle: Bundle(for: NovaIconBundleMarker.self)).renderingMode(.template)
                        .resizable().scaledToFit().frame(width: 22, height: 22)
                        .frame(width: 46, height: 46)
                        .overlay(alignment: .bottomTrailing) {
                            Image(systemName: "plus").font(.system(size: 12, weight: .bold))
                                .foregroundStyle(NovaColorToken.accent.color(in: scheme)).offset(x: 5, y: 5)
                        }
                    NovaText(text: RDLocalization.string("localizable.nova.expert.shell.fotograf.cek.veya.galeriden.sec.bea08bcc", table: .localizable, fallback: "Fotoğraf çek veya galeriden seç"), style: .meta, color: NovaColorToken.textTertiary.color(in: scheme))
                }.frame(maxWidth: .infinity, minHeight: 118)
                    .background { NovaPhotoBackdrop() }
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(NovaColorToken.borderStrong.color(in: scheme), style: StrokeStyle(lineWidth: 1.6, dash: [5, 4])))
            }.buttonStyle(.plain).padding(.top, 12).accessibilityIdentifier("nova.home.photo")
            Button { onNavigate(.newFinding) } label: {
                HStack(spacing: 9) {
                    Image(systemName: "arrow.right")
                    NovaSizedText(text: RDLocalization.string("localizable.nova.expert.shell.uygunsuzluk.ekle.808de642", table: .localizable, fallback: "Uygunsuzluk Ekle"), size: 15, weight: "Bold", color: .white)
                }.foregroundStyle(.white).frame(maxWidth: .infinity, minHeight: 54)
                    .background(NovaColorToken.accent.color(in: scheme), in: Capsule())
                    .shadow(color: NovaColorToken.accent.color(in: scheme).opacity(0.18), radius: 18, x: 0, y: 9)
            }.buttonStyle(.plain).padding(.top, 14).accessibilityIdentifier("nova.home.addFinding")
        }.padding(18)
            .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 26))
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
                                NovaSizedText(text: RDLocalization.string("localizable.nova.expert.shell.firma.ekle.09e0dac1", table: .localizable, fallback: "Firma Ekle"), size: 11.5, weight: "Medium")
                            }.padding(.horizontal, 15).frame(minWidth: 116, minHeight: 34)
                                .background(NovaColorToken.accent.color(in: scheme), in: Capsule())
                                .foregroundStyle(NovaColorToken.onAccent.color(in: scheme))
                        }.buttonStyle(.plain).accessibilityIdentifier("nova.pilot.company.create")
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
                    .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 16))
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
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(NovaColorToken.borderStrong.color(in: scheme))
                            }.padding(14).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
                                .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 22))
                        }.accessibilityIdentifier("nova.company.\(company.id)")
                    }
                }
            }.padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 24)
        }.buttonStyle(.plain).background(NovaColorToken.canvas.color(in: scheme))
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
