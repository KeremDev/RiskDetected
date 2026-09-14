import SwiftUI

/// The top border of a tab that is joined to the panel below it: up the left
/// side, across the rounded top, down the right side, and no bottom edge.
struct NovaTabTopBorder: Shape {
    var radius: CGFloat = 14
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY),
                          control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius),
                          control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        return path
    }
}

/// A tab that only rounds its top corners, so it can sit flush on the panel.
private struct NovaTabTopShape: Shape {
    var radius: CGFloat = 14
    func path(in rect: CGRect) -> Path {
        Path(roundedRect: rect, cornerRadii: RectangleCornerRadii(topLeading: radius, bottomLeading: 0,
                                                                  bottomTrailing: 0, topTrailing: radius))
    }
}

/// One choice in the folder strip.
struct NovaFolderTab: Identifiable, Equatable {
    let id: String
    let title: String
    let symbol: String
    let caption: String?
}

/// Tabs joined to the panel underneath: the chosen one loses its bottom edge
/// and reads as the front of the page, the way a folder divider does.
struct NovaFolderTabs<Content: View>: View {
    let tabs: [NovaFolderTab]
    @Binding var selection: String
    var identifierPrefix = "folder.tab"
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme

    private var surface: Color { NovaColorToken.surface.color(in: scheme) }
    private var border: Color { NovaColorToken.borderStrong.color(in: scheme) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(tabs) { tab in cell(tab) }
            }
            ZStack(alignment: .top) {
                content()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(surface)
                    .overlay(Rectangle().strokeBorder(border, lineWidth: 1.2))
                    .clipShape(RoundedRectangle(cornerRadius: 0))
                // Erases the panel's top edge under the chosen tab so the two
                // read as one surface instead of two stacked cards.
                HStack(spacing: 6) {
                    ForEach(tabs) { tab in
                        Rectangle().fill(tab.id == selection ? surface : Color.clear)
                            .frame(height: 2).frame(maxWidth: .infinity)
                    }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 16).offset(y: -1))
        }
    }

    private func cell(_ tab: NovaFolderTab) -> some View {
        let isOn = tab.id == selection
        return Button { selection = tab.id } label: {
            VStack(spacing: 4) {
                NovaIcon(symbol: tab.symbol, size: 18)
                    .foregroundStyle(isOn ? NovaColorToken.accentInk.color(in: scheme)
                                          : NovaColorToken.textSecondary.color(in: scheme))
                NovaText(text: tab.title, style: .badge,
                    color: isOn ? NovaColorToken.text.color(in: scheme) : NovaColorToken.textSecondary.color(in: scheme))
                    .multilineTextAlignment(.center)
                if let caption = tab.caption {
                    NovaText(text: caption, style: .micro,
                        color: isOn ? NovaColorToken.textTertiary.color(in: scheme) : NovaColorToken.textSubtle.color(in: scheme))
                }
            }
            .frame(maxWidth: .infinity).frame(height: isOn ? 74 : 68)
            .background(isOn ? surface : NovaColorToken.statusSuccessBg.color(in: scheme),
                        in: NovaTabTopShape())
            .overlay(isOn ? AnyView(NovaTabTopBorder().stroke(border, lineWidth: 1.2)) : AnyView(EmptyView()))
        }.buttonStyle(.plain)
            .accessibilityIdentifier("\(identifierPrefix).\(tab.id)")
            .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
