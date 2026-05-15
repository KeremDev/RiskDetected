import SwiftUI

/// Odaklı Analiz canvas seçim sheet'i — 2 satırlı yatay seçim rayı.
struct CanvasSheet: View {
    @Binding var selected: Set<AnalysisCanvas>
    var userTier: SubscriptionTier = .free
    var onConfirm: () -> Void
    var onUpgradeRequested: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    private let rows: [GridItem] = Array(
        repeating: GridItem(.fixed(82), spacing: 8),
        count: 2
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Başlık
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Odaklı Analiz")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .tracking(-0.4)
                        .foregroundStyle(Color.rdBlack)
                        .padding(.top, 6)
                    Text(userTier.isPaid ? "Bir veya birden fazla analiz odağı seçebilirsin." : "Bir analiz odağı seçebilirsin.")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdBlack)
                        .frame(width: 38, height: 38)
                        .background(Color.rdWhite)
                        .clipShape(Circle())
                        .shadow(color: Color.rdOnyx.opacity(0.10), radius: 8, x: 0, y: 4)
                }
                .buttonStyle(RDPressableButtonStyle())
                .accessibilityLabel("Kapat")
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)

            // Yatay seçim rayı: ilk bakışta 6 kart görünür, sağda diğer seçeneklerden iz kalır.
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHGrid(rows: rows, spacing: 8) {
                    ForEach(AnalysisCanvas.all) { canvas in
                        CanvasCard(
                            canvas: canvas,
                            isActive: selected.contains(canvas),
                            isLocked: canvas.isPaid && !userTier.includes(canvas.minTier),
                            userTier: userTier
                        ) {
                            select(canvas)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 1)
            }
            .padding(.bottom, 12)

            // Onay butonu
            RDButton(title: "Onayla ve devam et", style: .detect) {
                onConfirm()
                dismiss()
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .padding(.top, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color.rdPaper.ignoresSafeArea())
    }

    private func select(_ canvas: AnalysisCanvas) {
        if canvas.isPaid && !userTier.includes(canvas.minTier) {
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            onUpgradeRequested()
            return
        }

        UISelectionFeedbackGenerator().selectionChanged()
        withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) {
            if !userTier.isPaid {
                selected = [canvas]
            } else if selected.contains(canvas) {
                if selected.count > 1 {
                    selected.remove(canvas)
                }
            } else {
                selected.insert(canvas)
            }
        }
    }
}

// MARK: - CanvasCard

private struct CanvasCard: View {
    let canvas: AnalysisCanvas
    let isActive: Bool
    let isLocked: Bool
    let userTier: SubscriptionTier
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                VStack(alignment: .leading, spacing: 7) {
                    iconBadge
                    Text(canvas.title)
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                .padding(9)
                .frame(width: 106, height: 82, alignment: .topLeading)

                if canvas.isPaid {
                    VStack(alignment: .trailing, spacing: 4) {
                        tierBadge
                        if isLocked {
                            lockedBadge
                        }
                    }
                    .padding(.top, 6)
                    .padding(.trailing, 6)
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
            .opacity(isLocked ? 0.86 : 1)
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

    private var tierBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: canvas.minTier.badgeIcon)
                .font(.system(size: 7, design: .rounded))
            Text(canvas.minTier.badgeLabel)
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .tracking(0.6)
        }
        .padding(.horizontal, 5)
        .frame(height: 16)
        .foregroundStyle(.white)
        .background(canvas.minTier.accentColor)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }

    private var lockedBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "lock.fill")
                .font(.system(size: 6.5, design: .rounded))
            Text("KİLİTLİ")
                .font(.system(size: 6.8, weight: .heavy, design: .rounded))
                .tracking(0.35)
        }
        .padding(.horizontal, 5)
        .frame(height: 15)
        .foregroundStyle(Color(hex: "#8A6500"))
        .background(Color(hex: "#FFF1B8"))
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
        if canvas.isPaid { return canvas.minTier.accentColor.opacity(0.55) }
        return Color.rdLine
    }

    private var borderWidth: CGFloat {
        canvas.isPaid && !isActive ? 1.5 : 1
    }

    private var iconBg: Color {
        if isActive { return Color.rdGreen }
        if canvas.isPaid { return canvas.minTier.accentSoftColor }
        return Color.rdFog
    }

    private var iconColor: Color {
        if isActive { return .white }
        if canvas.isPaid { return canvas.minTier.accentTextColor }
        return Color.rdBlack
    }

    private var shadowColor: Color {
        if isActive { return Color.black.opacity(0.12) }
        if canvas.isPaid { return canvas.minTier.accentColor.opacity(0.14) }
        return .clear
    }
}

#Preview {
    StatefulPreviewWrapper(Set([AnalysisCanvas.general])) { binding in
        CanvasSheet(
            selected: binding,
            userTier: .free,
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
