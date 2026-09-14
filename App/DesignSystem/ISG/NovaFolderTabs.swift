import SwiftUI

/// One choice in the section tile row.
struct NovaFolderTab: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let caption: String?
}

/// Compact section navigation. Each section is a quiet tile on the canvas so
/// the content below can stay focused on the findings themselves.
struct NovaFolderTabs<Content: View>: View {
    let tabs: [NovaFolderTab]
    @Binding var selection: String
    var identifierPrefix = "folder.tab"
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.novaCanvasStyle) private var canvasStyle

    private var canvas: Color { canvasStyle.color(in: scheme) }
    private var surface: Color { NovaColorToken.surface.color(in: scheme) }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(tabs) { tab in cell(tab) }
            }
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 2)
                .padding(.bottom, 2)
                .background(canvas)
        }
    }

    private func cell(_ tab: NovaFolderTab) -> some View {
        let isOn = tab.id == selection
        return Button { selection = tab.id } label: {
            VStack(spacing: 5) {
                tabIcon(tab)
                    .foregroundStyle(NovaColorToken.text.color(in: scheme))
                    .frame(width: 30, height: 30)
                NovaText(text: tab.title, style: .badge,
                    color: NovaColorToken.text.color(in: scheme))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                if let caption = tab.caption {
                    NovaText(text: caption, style: .micro,
                        color: NovaColorToken.text.color(in: scheme))
                }
            }
            .padding(.horizontal, 4).padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 96)
            .background(surface, in: RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(.plain)
            .accessibilityIdentifier("\(identifierPrefix).\(tab.id)")
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    @ViewBuilder private func tabIcon(_ tab: NovaFolderTab) -> some View {
        if tab.symbol == "graduationcap" {
            Image(systemName: tab.symbol).font(.system(size: 16, weight: .medium))
        } else {
            NovaIcon(symbol: tab.symbol, size: 16)
        }
    }
}
