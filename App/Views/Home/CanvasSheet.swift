import SwiftUI

/// AI Odaklı Analiz canvas seçim sheet'i — 3×2 grid, PRO kartlar ayrıca vurgulu.
struct CanvasSheet: View {
    @Binding var selected: Set<AnalysisCanvas>
    @Binding var userPrompt: String
    var isUserPro: Bool = false
    var onConfirm: () -> Void
    var onUpgradeRequested: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    private let promptLimit = 100

    private let columns: [GridItem] = Array(
        repeating: GridItem(.flexible(), spacing: 8),
        count: 3
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Başlık
            VStack(alignment: .leading, spacing: 4) {
                Text("AI Odaklı Analiz")
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .tracking(-0.4)
                    .foregroundStyle(Color.rdBlack)
                    .padding(.top, 6)
                Text("Analiz türünü seç. Her canvas, kendi alanı için özelleştirilmiş bir AI promptu kullanır.")
                    .font(.system(size: 14, design: .rounded))
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
                        isActive: selected.contains(canvas)
                    ) {
                        if canvas.isPro && !isUserPro {
                            onUpgradeRequested()
                        } else {
                            UISelectionFeedbackGenerator().selectionChanged()
                            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
                                if selected.contains(canvas) {
                                    if selected.count > 1 { selected.remove(canvas) }
                                } else {
                                    selected.insert(canvas)
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 12)

            promptInput

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

    private var promptInput: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Özel analiz notu")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                Spacer()
                Text("\(userPrompt.count)/\(promptLimit)")
                    .rdMono(size: 10, weight: .semibold)
                    .foregroundStyle(userPrompt.count >= promptLimit ? Color.rdHigh : Color.rdSlate)
            }

            TextEditor(text: $userPrompt)
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(Color.rdBlack)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(height: 64)
                .background(Color.rdWhite)
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(Color.rdLine, lineWidth: 1)
                )
                .overlay(alignment: .topLeading) {
                    if userPrompt.isEmpty {
                        Text("Örn: sadece araç kasasında yolcu taşıma risklerine bak")
                            .font(.system(size: 13, design: .rounded))
                            .foregroundStyle(Color.rdSlate.opacity(0.72))
                            .padding(.horizontal, 15)
                            .padding(.vertical, 16)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: userPrompt) { newValue in
                    if newValue.count > promptLimit {
                        userPrompt = String(newValue.prefix(promptLimit))
                    }
                }

            Text("Bu alanda ne istediğini belirtirsen daha net cevaplar alabilirsin.")
                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                .foregroundStyle(Color.rdSlate)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 10)
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
                VStack(alignment: .leading, spacing: 6) {
                    iconBadge
                    Text(canvas.title)
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(canvas.short)
                        .font(.system(size: 10, design: .rounded))
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
                            .stroke(borderColor, lineWidth: borderWidth)
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
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(iconColor)
        }
        .frame(width: 28, height: 28)
    }

    private var proBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill")
                .font(.system(size: 7, design: .rounded))
            Text("PRO")
                .font(.system(size: 8, weight: .heavy, design: .rounded))
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
        isActive ? Color.rdSelected : Color.rdWhite
    }

    private var textColor: Color {
        isActive ? .white : Color.rdBlack
    }

    private var secondaryTextColor: Color {
        isActive ? Color.white.opacity(0.7) : Color.rdSlate
    }

    private var borderColor: Color {
        if isActive { return Color.rdSelected }
        if canvas.isPro { return Color.rdGreen.opacity(0.55) }
        return Color.rdLine
    }

    private var borderWidth: CGFloat {
        canvas.isPro && !isActive ? 1.5 : 1
    }

    private var iconBg: Color {
        if isActive { return Color.rdGreen }
        if canvas.isPro { return Color.rdGreenSoft }
        return Color.rdFog
    }

    private var iconColor: Color {
        if isActive { return .white }
        if canvas.isPro { return Color.rdGreenDark }
        return Color.rdBlack
    }

    private var shadowColor: Color {
        if isActive { return Color.black.opacity(0.12) }
        if canvas.isPro { return Color.rdGreen.opacity(0.14) }
        return .clear
    }
}

#Preview {
    StatefulPreviewWrapper(Set([AnalysisCanvas.general])) { binding in
        CanvasSheet(
            selected: binding,
            userPrompt: .constant(""),
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
