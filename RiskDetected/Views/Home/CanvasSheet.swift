import SwiftUI

/// AI Odaklı Analiz canvas seçim sheet'i — 3×2 grid, PRO kartlar ayrıca vurgulu.
struct CanvasSheet: View {
    @Binding var selected: AnalysisCanvas
    var isUserPro: Bool = false
    var onConfirm: () -> Void
    var onUpgradeRequested: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 3
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Başlık
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Odaklı Analiz")
                    .font(.system(size: 22, weight: .bold))
                    .tracking(-0.4)
                    .foregroundStyle(Color.rdBlack)
                    .padding(.top, 6)
                Text("Analiz türünü seç. Her canvas, kendi alanı için özelleştirilmiş bir AI promptu kullanır.")
                    .font(.system(size: 14))
                    .foregroundStyle(Color.rdSlate)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Grid
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(AnalysisCanvas.all) { canvas in
                    CanvasCard(
                        canvas: canvas,
                        isActive: selected == canvas
                    ) {
                        if canvas.isPro && !isUserPro {
                            onUpgradeRequested()
                        } else {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                selected = canvas
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            // Onay butonu
            RDButton(title: "Onayla ve devam et", style: .primary) {
                onConfirm()
                dismiss()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .padding(.top, 8)
        .background(Color.rdPaper)
    }
}

// MARK: - CanvasCard

private struct CanvasCard: View {
    let canvas: AnalysisCanvas
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                if canvas.isPro {
                    // sağ üst köşe yeşil halo
                    Circle()
                        .fill(Color.rdGreen.opacity(0.18))
                        .frame(width: 48, height: 48)
                        .offset(x: 16, y: -16)
                }

                VStack(alignment: .leading, spacing: 6) {
                    iconBadge
                    Text(canvas.title)
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(canvas.short)
                        .font(.system(size: 10))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(secondaryTextColor)
                }
                .padding(10)
                .frame(maxWidth: .infinity, minHeight: 108, alignment: .topLeading)

                if canvas.isPro {
                    proBadge
                        .padding(.top, 8)
                        .padding(.trailing, 8)
                }
            }
            .foregroundStyle(textColor)
            .background(
                RoundedRectangle(cornerRadius: 14)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .stroke(borderColor, lineWidth: 1)
                    )
            )
            .shadow(color: shadowColor, radius: 14, x: 0, y: 4)
        }
        .buttonStyle(RDPressableButtonStyle())
    }

    private var iconBadge: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8)
                .fill(iconBg)
            Image(systemName: canvas.icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(iconColor)
        }
        .frame(width: 28, height: 28)
    }

    private var proBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill")
                .font(.system(size: 7))
            Text("PRO")
                .font(.system(size: 8, weight: .heavy))
                .tracking(0.6)
        }
        .padding(.horizontal, 5)
        .frame(height: 16)
        .foregroundStyle(.white)
        .background(Color.rdGreen)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    // MARK: - Style helpers

    private var backgroundColor: Color {
        if isActive { return Color.rdBlack }
        if canvas.isPro { return Color(hex: "#0B0D0E") }
        return Color.rdWhite
    }

    private var textColor: Color {
        if isActive || canvas.isPro { return .white }
        return Color.rdBlack
    }

    private var secondaryTextColor: Color {
        if isActive { return Color.white.opacity(0.7) }
        if canvas.isPro { return Color.white.opacity(0.65) }
        return Color.rdSlate
    }

    private var borderColor: Color {
        if isActive { return Color.rdBlack }
        if canvas.isPro { return Color(hex: "#0B0D0E") }
        return Color.rdLine
    }

    private var iconBg: Color {
        if isActive { return Color.rdGreen }
        if canvas.isPro { return Color.rdGreen }
        return Color.rdFog
    }

    private var iconColor: Color {
        if isActive || canvas.isPro { return .white }
        return Color.rdBlack
    }

    private var shadowColor: Color {
        if canvas.isPro && !isActive {
            return Color.rdGreen.opacity(0.18)
        }
        return .clear
    }
}

#Preview {
    StatefulPreviewWrapper(AnalysisCanvas.general) { binding in
        CanvasSheet(
            selected: binding,
            isUserPro: false,
            onConfirm: {}
        )
        .presentationDetents([.medium, .large])
    }
}

private struct StatefulPreviewWrapper<Value, Content: View>: View {
    @State var value: Value
    var content: (Binding<Value>) -> Content
    init(_ initial: Value, @ViewBuilder content: @escaping (Binding<Value>) -> Content) {
        _value = State(initialValue: initial)
        self.content = content
    }
    var body: some View { content($value) }
}
