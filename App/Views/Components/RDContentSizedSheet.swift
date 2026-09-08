import SwiftUI

/// Measures intrinsic content, not the scroll viewport. UIKit caps the detent
/// on smaller screens, where the content remains scrollable above the action.
struct RDContentSizedSheet<Content: View, Footer: View>: View {
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer
    @State private var heights: [Int: CGFloat] = [:]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(showsIndicators: false) {
                content()
                    .fixedSize(horizontal: false, vertical: true)
                    .background(heightReader(0))
            }
            .frame(maxHeight: heights[0])
            footer()
                .fixedSize(horizontal: false, vertical: true)
                .background(heightReader(1))
        }
        .onPreferenceChange(SheetContentHeightKey.self) { heights = $0 }
        // Custom detents already exclude the system bottom safe area.
        .presentationDetents([.height(ceil((heights[0] ?? 320) + (heights[1] ?? 72)))])
    }

    private func heightReader(_ region: Int) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(key: SheetContentHeightKey.self, value: [region: proxy.size.height])
        }
    }
}

private struct SheetContentHeightKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
    }
}
