import SwiftUI

/// One persisted string array, presented as individually editable numbered rows.
/// The parent retains the existing newline/array wire format for old records.
struct NovaNumberedItemsEditor: View {
    let title: String
    @Binding var value: String
    private var lines: [String] { value.isEmpty ? [""] : value.components(separatedBy: "\n") }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(lines.indices, id: \.self) { index in
                HStack(alignment: .top, spacing: 8) {
                    NovaText(text: "\(index + 1).", style: .label).frame(width: 24)
                    TextField("Madde \(index + 1)", text: Binding(
                        get: { index < lines.count ? lines[index] : "" },
                        set: { text in
                            var next = lines
                            guard next.indices.contains(index) else { return }
                            next[index] = text.replacingOccurrences(of: "\n", with: " ")
                            value = next.joined(separator: "\n")
                        }), axis: .vertical).lineLimit(1...6)
                        .accessibilityLabel(RDLocalization.format("localizable.nova.numbered.items.editor.1.madde.2.5429b500", table: .localizable, fallback: "%1$@, madde %2$@", arguments: [String(describing: title), String(describing: index + 1)]))
                    Button {
                        var next = lines
                        guard next.indices.contains(index) else { return }
                        next.remove(at: index)
                        value = next.joined(separator: "\n")
                    } label: { NovaIcon(symbol: "minus.circle", size: 18).frame(width: 44, height: 44) }
                    .buttonStyle(NovaRowPressStyle()).accessibilityLabel(RDLocalization.format("localizable.nova.numbered.items.editor.madde.1.sil.f4cd4b70", table: .localizable, fallback: "Madde %1$@ sil", arguments: [String(describing: index + 1)]))
                }
            }
            Button {
                value = (lines + [""]).joined(separator: "\n")
            } label: { Label(RDLocalization.string("localizable.nova.numbered.items.editor.madde.ekle.74913715", table: .localizable, fallback: "Madde ekle"), systemImage: "plus").font(NovaFont.font(.buttonSm)).frame(minHeight: 44) }
                .buttonStyle(NovaRowPressStyle())
        }
    }
}
