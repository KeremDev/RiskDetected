import SwiftUI

/// New expert shell only. The owner supplies scoped state and real destination content.
/// Not installed in the legacy MainTabView; no Auth, billing or service calls here.
struct NovaExpertShell<Content: View>: View {
    @Binding var navigation: NovaNavigationState
    let userName: String
    var hasUnread = false
    @ViewBuilder let content: (NovaDestination) -> Content
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let epoch = navigation.epoch
        let send: (NovaNavigationEvent) -> Void = { navigation.apply($0, from: epoch) }
        GeometryReader { geometry in
            ZStack {
                VStack(spacing: 0) {
                    NovaShellTopBar(current: navigation.current, userName: userName, hasUnread: hasUnread,
                        canGoBack: !(navigation.paths[navigation.selected] ?? []).isEmpty,
                        notificationsAvailable: navigation.canOpen(.notifications), send: send)
                    TabView(selection: Binding(get: { navigation.selected }, set: { send(.select($0)) })) {
                        ForEach(NovaTab.allCases, id: \.self) { tab in
                            NavigationStack(path: Binding(
                                get: { navigation.paths[tab] ?? [] },
                                set: { navigation.acceptBackPath($0, tab: tab, from: epoch) })) {
                                Group {
                                    if navigation.canOpen(tab.root) { content(tab.root) }
                                    else { NovaText(text: "Bu bölüm henüz kullanıma açık değil.") }
                                }
                                    .navigationDestination(for: NovaDestination.self, destination: content)
                                    .toolbar(.hidden, for: .navigationBar, .tabBar)
                            }.tag(tab)
                        }
                    }
                }
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    NovaShellTabBar(selected: navigation.selected, canOpen: navigation.canOpen, send: send)
                        .padding(.horizontal, NovaDimensionToken.layoutTabBarInset.value)
                        .padding(.top, 8)
                        .padding(.bottom, max(10 - geometry.safeAreaInsets.bottom, 0) + 16)
                }
                .allowsHitTesting(navigation.overlay == nil)
                .accessibilityHidden(navigation.overlay != nil)

                if let panel = navigation.overlay {
                    NovaShellPanel(panel: panel, selected: navigation.current, canOpen: navigation.canOpen,
                        userName: userName, send: send)
                }
            }.background(NovaColorToken.canvas.color(in: scheme).ignoresSafeArea())
        }
        // Caller replaces the state on Auth/session-epoch change; local child state must not leak.
        .id(navigation.epoch)
    }
}

struct NovaShellTopBar: View {
    let current: NovaDestination
    let userName: String
    let hasUnread: Bool
    let canGoBack: Bool
    let notificationsAvailable: Bool
    let send: (NovaNavigationEvent) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 8) {
        HStack(spacing: 10) {
            icon(canGoBack ? "chevron.left" : "line.3.horizontal", label: canGoBack ? "Geri" : "Menüyü aç",
                 id: canGoBack ? "nova.back" : "nova.menu") { send(canGoBack ? .back : .open(.drawer)) }
            if typeSize.isAccessibilitySize { Spacer() } else { brand }
            icon("bell", label: hasUnread ? "Bildirimler, yeni bildirim var" : "Bildirimler", id: "nova.notifications") {
                send(.navigate(.notifications))
            }.disabled(!notificationsAvailable).overlay(alignment: .topTrailing) {
                if hasUnread {
                    Circle().fill(NovaColorToken.statusDangerDot.color(in: scheme)).frame(width: 8, height: 8)
                        .padding(7).accessibilityHidden(true)
                }
            }
            Button { send(.select(.profile)) } label: {
                Group {
                    if typeSize.isAccessibilitySize { Image(systemName: "person.fill").foregroundStyle(.white) }
                    else { NovaText(text: String(userName.prefix(2)).uppercased(), style: .label, color: .white) }
                }.frame(width: 44, height: 44)
                    .background(LinearGradient(colors: [Color(white: 0.25), Color(white: 0.1)], startPoint: .topLeading, endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: NovaDimensionToken.radiusControl.value))
            }.buttonStyle(.plain).accessibilityLabel("Hesabım").accessibilityIdentifier("nova.profile")
        }
        if typeSize.isAccessibilitySize { brand }
        }.padding(.horizontal, NovaDimensionToken.spaceScreenX.value).padding(.top, 8).padding(.bottom, 18)
    }

    private var brand: some View {
        VStack(spacing: 1) {
            NovaText(text: "İSG Adası", style: .brand)
            NovaText(text: current.title, style: .meta, color: NovaColorToken.textMuted.color(in: scheme))
        }.frame(maxWidth: .infinity).multilineTextAlignment(.center)
    }

    private func icon(_ symbol: String, label: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold))
                .foregroundStyle(NovaColorToken.text.color(in: scheme))
                .frame(width: 44, height: 44)
                .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: NovaDimensionToken.radiusControl.value))
        }.buttonStyle(.plain).accessibilityLabel(Text(verbatim: label)).accessibilityIdentifier(id)
    }
}

struct NovaShellTabBar: View {
    let selected: NovaTab
    let canOpen: (NovaDestination) -> Bool
    let send: (NovaNavigationEvent) -> Void
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        NovaShellTabStrip(selected: selected, canOpen: canOpen, send: send, expanded: true)
                    }
                    .onAppear { proxy.scrollTo(selected.rawValue, anchor: .center) }
                    .onChange(of: selected) { value in proxy.scrollTo(value.rawValue, anchor: .center) }
                }.fixedSize(horizontal: false, vertical: true)
            } else {
                NovaShellTabStrip(selected: selected, canOpen: canOpen, send: send)
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
        .shadow(color: .black.opacity(0.16), radius: 34, x: 0, y: 12)
    }

}

struct NovaShellTabStrip: View {
    let selected: NovaTab
    let canOpen: (NovaDestination) -> Bool
    let send: (NovaNavigationEvent) -> Void
    var expanded = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            tab(.home)
            tab(.findings)
            Button { send(.open(.quickAdd)) } label: {
                VStack(spacing: 2) {
                    Image(systemName: "plus").font(.system(size: 21, weight: .semibold))
                        .foregroundStyle(Color(white: 17.0 / 255))
                        .frame(width: 42, height: 42)
                        .background(NovaColorToken.accent.color(in: scheme), in: Circle())
                    NovaText(text: "Ekle", style: .tab, color: NovaColorToken.text.color(in: scheme)).lineLimit(1)
                }.frame(maxWidth: expanded ? nil : .infinity, minHeight: 52).padding(.horizontal, expanded ? 12 : 0)
            }.buttonStyle(.plain).accessibilityLabel("Ekle").accessibilityIdentifier("nova.add").id("add")
            tab(.companies)
            tab(.profile)
        }
    }

    private func tab(_ tab: NovaTab) -> some View {
        Button { send(.select(tab)) } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.root.symbol).font(.system(size: 19))
                    .frame(width: 34, height: 42)
                NovaText(text: tab.title, style: .tab, color: NovaColorToken.text.color(in: scheme))
                    .lineLimit(1).minimumScaleFactor(expanded ? 1 : 0.75)
            }.foregroundStyle(NovaColorToken.text.color(in: scheme))
                .frame(maxWidth: expanded ? nil : .infinity, minHeight: 52).padding(.horizontal, expanded ? 12 : 0)
                .opacity(canOpen(tab.root) ? (selected == tab ? 1 : 0.7) : 0.4)
        }.buttonStyle(.plain).disabled(!canOpen(tab.root))
            .accessibilityLabel(Text(verbatim: tab.title))
            .accessibilityAddTraits(selected == tab ? .isSelected : [])
            .accessibilityIdentifier("nova.tab.\(tab.rawValue)").id(tab.rawValue)
    }
}

struct NovaShellPanel: View {
    let panel: NovaOverlay
    let selected: NovaDestination
    let canOpen: (NovaDestination) -> Bool
    let userName: String
    let send: (NovaNavigationEvent) -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: panel == .drawer ? .leading : .center) {
                NovaColorToken.scrim.color(in: scheme).ignoresSafeArea()
                    .onTapGesture { send(.dismiss) }.accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        NovaText(text: panel == .drawer ? "İSG Adası" : "Hızlı İşlem", style: .sheetTitle)
                        Spacer()
                        Button { send(.dismiss) } label: {
                            Image(systemName: "xmark").frame(width: 44, height: 44)
                        }.buttonStyle(.plain).foregroundStyle(NovaColorToken.text.color(in: scheme))
                            .accessibilityLabel("Kapat").accessibilityIdentifier("nova.panel.close")
                    }
                    if panel == .drawer { NovaText(text: userName, style: .bodyStrong) }
                    ScrollView {
                        VStack(spacing: 7) {
                            ForEach(panel == .drawer ? NovaDestination.drawer : NovaDestination.quickAdd, id: \.self) { destination in
                                Button { send(.navigate(destination)) } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: destination.symbol).frame(width: 24)
                                        VStack(alignment: .leading, spacing: 4) {
                                            NovaText(text: destination.title, style: .bodyStrong)
                                            if !canOpen(destination) { NovaText(text: "Henüz kullanıma açık değil", style: .metaQuiet) }
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "chevron.right").font(.caption)
                                    }.padding(12).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                                        .background(selected == destination ? NovaColorToken.accentSoft.color(in: scheme) : NovaColorToken.surface.color(in: scheme),
                                                    in: RoundedRectangle(cornerRadius: NovaDimensionToken.radiusControl.value))
                                }.buttonStyle(.plain).foregroundStyle(NovaColorToken.text.color(in: scheme))
                                    .disabled(!canOpen(destination)).opacity(canOpen(destination) ? 1 : 0.5)
                                    .accessibilityIdentifier("nova.destination.\(destination.rawValue)")
                            }
                        }
                    }
                }
                .padding(20)
                .frame(width: min(geometry.size.width * (panel == .drawer ? 0.9 : 0.92), panel == .drawer ? 384 : 520))
                .frame(maxHeight: max(0, geometry.size.height - 24))
                .background(NovaColorToken.canvasSheet.color(in: scheme), in: RoundedRectangle(cornerRadius: NovaDimensionToken.radiusDialog.value))
                .padding(.leading, panel == .drawer ? 8 : 0)
                .accessibilityAddTraits(.isModal)
                .accessibilityAction(.escape) { send(.dismiss) }
            }
        }
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
