import SwiftUI

/// Shared chrome for long, consequential create/edit tasks. The individual
/// feature owns its data and validation; this layer keeps progress, recovery
/// and primary actions consistent across the product.
struct NovaTaskHeader: View {
    let title: String
    let step: Int
    let total: Int
    let stepTitle: String
    let onClose: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                NovaBackButton(action: onClose)
                NovaText(text: title, style: .screenTitle)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline) {
                    NovaText(text: "\(step) / \(total)", style: .label)
                    Spacer(minLength: 10)
                    NovaText(text: stepTitle, style: .metaQuiet)
                }
                ProgressView(value: Double(step), total: Double(max(1, total)))
                    .tint(NovaColorToken.accent.color(in: scheme))
                    .accessibilityLabel("İlerleme")
                    .accessibilityValue("\(step) / \(total), \(stepTitle)")
            }
        }
    }
}

struct NovaTaskErrorSummary: View {
    let message: String
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(NovaColorToken.statusDangerInk.color(in: scheme))
                .frame(width: 22, height: 22)
            VStack(alignment: .leading, spacing: 3) {
                NovaText(text: "Bu adımı kontrol edin", style: .bodyStrong)
                NovaText(text: message, style: .meta)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NovaColorToken.statusDangerBg.color(in: scheme),
                    in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isStaticText)
    }
}

/// Keeps legal or explanatory copy out of the primary task path. The short
/// label remains visible, while the long rationale is available on demand.
/// This is intentionally a small component so every module uses the same
/// progressive-disclosure language and spacing.
struct NovaWhyDisclosure<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    init(label: String = "Neden?", @ViewBuilder content: @escaping () -> Content) {
        self.label = label
        self.content = content
    }

    var body: some View {
        DisclosureGroup(label) {
            content()
                .padding(.top, 6)
        }
        .font(NovaFont.font(.meta))
        .padding(12)
        .novaControlBackground(cornerRadius: 14)
        .accessibilityIdentifier("nova.why.disclosure")
    }
}

struct NovaTaskStickyActions: View {
    let primaryTitle: String
    var primarySymbol = "arrow.right"
    var isWorking = false
    var canGoBack = true
    let onBack: () -> Void
    let onPrimary: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) { buttons }
            } else {
                HStack(spacing: 10) { buttons }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 3)
        .background(NovaColorToken.surface.color(in: scheme)
            .shadow(.drop(color: Color.black.opacity(0.08), radius: 10, y: -3)))
    }

    @ViewBuilder private var buttons: some View {
        if canGoBack {
            NovaButton(label: "Geri", symbol: "chevron.left", variant: .surface, action: onBack)
                .frame(maxWidth: 118)
        }
        NovaButton(label: isWorking ? "Kaydediliyor…" : primaryTitle,
                   symbol: isWorking ? "hourglass" : primarySymbol,
                   isEnabled: !isWorking,
                   action: onPrimary)
            .frame(maxWidth: .infinity)
    }
}

struct NovaTaskSuccessView: View {
    let title: String
    let message: String
    var nextTitle: String? = nil
    var onNext: (() -> Void)? = nil
    let doneTitle: String
    let onDone: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 54, weight: .semibold))
                        .foregroundStyle(NovaColorToken.accent.color(in: scheme))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 8) {
                        NovaText(text: title, style: .screenTitle)
                        NovaText(text: message, style: .body)
                    }
                    if let nextTitle, let onNext {
                        NovaCard(padding: 15, tint: NovaColorToken.statusSuccessBg.color(in: scheme)) {
                            VStack(alignment: .leading, spacing: 9) {
                                NovaText(text: "Sıradaki önerilen işlem", style: .metaQuiet)
                                NovaText(text: nextTitle, style: .bodyStrong)
                                NovaCompactActionButton(title: nextTitle, symbol: "arrow.right",
                                                        prominent: true, action: onNext)
                            }
                        }
                    }
                    NovaButton(label: doneTitle, symbol: "checkmark", action: onDone)
                }
                .padding(20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

struct NovaMetricStripItem: Identifiable {
    let id: String
    let value: String
    let label: String
    let symbol: String
    let status: NovaStatus
}

struct NovaMetricStrip: View {
    let items: [NovaMetricStripItem]
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(items) { item in
                    HStack(spacing: 6) {
                        Image(systemName: item.symbol).font(.system(size: 12, weight: .semibold))
                        NovaText(text: item.value, style: .bodyStrong)
                        NovaText(text: item.label, style: .metaQuiet)
                    }
                    .padding(.horizontal, 11)
                    .frame(minHeight: 38)
                    .background(background(item.status), in: Capsule())
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func background(_ status: NovaStatus) -> Color {
        switch status {
        case .success: return NovaColorToken.statusSuccessBg.color(in: scheme)
        case .warning: return NovaColorToken.statusWarningBg.color(in: scheme)
        case .danger: return NovaColorToken.statusDangerBg.color(in: scheme)
        case .info: return NovaColorToken.statusInfoBg.color(in: scheme)
        case .neutral: return NovaColorToken.surfaceMuted.color(in: scheme)
        }
    }
}
