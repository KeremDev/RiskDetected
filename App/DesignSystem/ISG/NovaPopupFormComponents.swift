import SwiftUI

/// Shared visual language for company selection, form headings and compact values.
struct NovaPopupHeading: View {
    let text: String
    var symbol: String = "square.and.pencil"
    var subtitle: String? = nil
    var body: some View {
        HStack(alignment: .top, spacing: 11) {
            Image(systemName: symbol).font(.system(size: 22, weight: .regular))
                .frame(width: 28, height: 28).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                NovaText(text: text, style: .sheetTitle).fixedSize(horizontal: false, vertical: true)
                if let subtitle { NovaText(text: subtitle, style: .metaQuiet) }
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct NovaPopupOption: View {
    let title: String
    let symbol: String
    var subtitle: String? = nil
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 20, weight: .regular))
                    .frame(width: 26).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    NovaText(text: title, style: .buttonSm).fixedSize(horizontal: false, vertical: true)
                    if let subtitle { NovaText(text: subtitle, style: .metaQuiet).fixedSize(horizontal: false, vertical: true) }
                }
                Spacer(minLength: 6)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .medium)).accessibilityHidden(true)
            }
            .foregroundStyle(NovaColorToken.text.color(in: scheme))
            .padding(14).frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .novaControlBackground(cornerRadius: 16)
            .contentShape(RoundedRectangle(cornerRadius: 16))
        }.buttonStyle(NovaRowPressStyle())
    }
}

/// Labels and compact controls share one row; accessibility sizes can grow vertically.
struct NovaFormValueRow<Content: View>: View {
    let label: String
    var symbol: String = "calendar"
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize
    private var caption: some View {
        HStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: 15, weight: .regular)).accessibilityHidden(true)
            NovaText(text: label, style: .label).fixedSize(horizontal: false, vertical: true)
        }
    }
    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) { caption; content() }
            } else {
                HStack(spacing: 10) { caption; Spacer(minLength: 0); content().fixedSize(horizontal: true, vertical: false) }
            }
        }
        .padding(12).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .novaControlBackground(cornerRadius: 14)
    }
}
