import SwiftUI

struct ProfessionalProgressHomeCard: View {
    enum DisplayStyle {
        case compactStrip
        case showcase
    }

    let summary: ProfessionalProgressSummary
    var accessibilityIdentifier = "professionalProgress.home.card"
    var displayStyle: DisplayStyle = .compactStrip
    var onTap: (() -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var animateProgress = true
    @State private var animateStripMarker = false

    @ViewBuilder
    var body: some View {
        switch displayStyle {
        case .compactStrip:
            compactStrip
        case .showcase:
            showcaseCard
        }
    }

    private var compactStrip: some View {
        let progress = animateProgress ? summary.titleProgress : 0
        let accent = Color.rdPlanPlus
        let accentSoft = Color.rdPlanPlusSoft
        let isDarkMode = colorScheme == .dark
        let primaryText = isDarkMode ? Color.white : Color.rdBlack
        let secondaryText = isDarkMode ? Color.white.opacity(0.66) : Color.rdSlate

        return HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(accent.opacity(0.20))
                    .frame(width: 38, height: 38)
                Image(systemName: "flame.fill")
                    .font(.system(size: 21, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [Color(hex: "#FFE08A"), accent, Color(hex: "#FF6B35")],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: accent.opacity(0.24), radius: 8, x: 0, y: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(formattedNumber(summary.profile.totalMDP))
                        .rdMono(size: 14, weight: .bold)
                        .foregroundStyle(primaryText)
                    Text("/ \(formattedNumber(nextTitleThreshold)) MDP")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(secondaryText)
                    Spacer(minLength: 0)
                    Text("%\(titleProgressPercent)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(secondaryText)
                }

                GeometryReader { geo in
                    let fillProgress = titleProgressPercent > 0 ? progress : 0
                    let filledWidth = geo.size.width * fillProgress
                    let markerX = min(max(filledWidth, 9), geo.size.width - 9)

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(accent.opacity(0.16))
                            .frame(height: 10)
                        Capsule()
                            .fill(accent)
                            .frame(width: filledWidth, height: 10)
                            .shadow(color: accent.opacity(0.24), radius: 7, x: 0, y: 2)
                        Image(systemName: "arrowtriangle.right.fill")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(Color.white)
                            .frame(width: 18, height: 18)
                            .background(accent)
                            .clipShape(Circle())
                            .shadow(color: accent.opacity(0.30), radius: 7, x: 0, y: 2)
                            .offset(x: markerX + (animateStripMarker ? 4 : -2) - 9)
                            .animation(
                                .easeInOut(duration: 0.82).repeatForever(autoreverses: true),
                                value: animateStripMarker
                            )
                    }
                }
                .frame(height: 18)

                HStack(spacing: 4) {
                    Image(systemName: "arrow.up.right.circle.fill")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                    Text("Kıdemini yükselt")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    if let nextTitle = summary.nextTitle {
                        Text("· \(nextTitle.label)")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(secondaryText)
                            .lineLimit(1)
                    }
                }
                .foregroundStyle(accent)
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background {
            LinearGradient(
                colors: isDarkMode
                    ? [
                        Color(hex: "#292416"),
                        Color(hex: "#1E211E"),
                        Color(hex: "#17231B")
                    ]
                    : [
                        accentSoft.opacity(0.86),
                        Color(hex: "#FFF9EA"),
                        Color.rdGreenSoft.opacity(0.32)
                    ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
        .overlay(
            RoundedRectangle(cornerRadius: RDRadius.lg)
                .stroke(accent.opacity(isDarkMode ? 0.36 : 0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        .rdCardShadow(colorScheme: colorScheme, accent: accent, radius: 5, x: 6, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        .onTapGesture {
            onTap?()
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityAddTraits(.isButton)
        .onAppear {
            animateProgress = true
            animateStripMarker = true
        }
        .onChange(of: summary.profile.totalMDP) { _ in
            animateProgress = false
            animateStripMarker = false
            withAnimation(.snappy(duration: 0.55)) {
                animateProgress = true
            }
            animateStripMarker = true
        }
    }

    private var showcaseCard: some View {
        let progress = animateProgress ? summary.titleProgress : 0
        let accent = Color.rdPlanPlus
        let accentText = Color.rdPlanPlusDark
        let accentSoft = Color.rdPlanPlusSoft
        let ink = Color.rdBlack

        return HStack(spacing: 12) {
            titleTile(accent: accent, accentSoft: accentSoft)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formattedNumber(summary.profile.totalMDP))
                            .rdMono(size: 25, weight: .bold)
                            .foregroundStyle(ink)
                        Text("/ \(formattedNumber(nextTitleThreshold))")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.rdSlate)
                        Spacer(minLength: 0)
                    }
                    Text(nextTitleLabel)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                GeometryReader { geo in
                    let fillProgress = titleProgressPercent > 0 ? progress : 0

                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.rdBlack.opacity(0.10))
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(hex: "#050607"),
                                        Color(hex: "#202426"),
                                        Color(hex: "#050607")
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * fillProgress)
                            .overlay(alignment: .top) {
                                Capsule()
                                    .fill(Color.white.opacity(0.34))
                                    .frame(height: 5)
                                    .padding(.horizontal, 3)
                                    .padding(.top, 2)
                            }
                            .shadow(color: Color.rdBlack.opacity(0.32), radius: 8, x: 0, y: 2)
                            .shadow(color: Color.white.opacity(0.22), radius: 8, x: 0, y: 0)
                    }
                }
                .frame(height: 15)

                titleLadder(accent: accent, accentText: accentText)
            }
        }
        .padding(12)
        .background {
            ZStack {
                Color.rdWhite
                RadialGradient(
                    colors: [
                        Color.rdPlanPlusSoft.opacity(0.34),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 16,
                    endRadius: 180
                )
                RadialGradient(
                    colors: [
                        Color.rdGreenSoft.opacity(0.22),
                        Color.clear
                    ],
                    center: .bottomLeading,
                    startRadius: 10,
                    endRadius: 160
                )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: RDRadius.lg)
                .stroke(Color.rdBlack, lineWidth: 1.6)
        )
        .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        .rdCardShadow(colorScheme: colorScheme, accent: accent, radius: 5, x: 6, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        .onTapGesture {
            onTap?()
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityAddTraits(.isButton)
        .onAppear {
            animateProgress = true
        }
        .onChange(of: summary.profile.totalMDP) { _ in
            animateProgress = false
            withAnimation(.snappy(duration: 0.65)) {
                animateProgress = true
            }
        }
    }

    private var currentTitleStage: Int {
        (ProfessionalProgressTitle.allCases.firstIndex(of: summary.currentTitle) ?? 0) + 1
    }

    private var nextTitleThreshold: Int {
        summary.nextTitle?.threshold ?? summary.currentTitle.threshold
    }

    private var titleProgressPercent: Int {
        Int((summary.titleProgress * 100).rounded())
    }

    private var nextTitleLabel: String {
        if let nextTitle = summary.nextTitle {
            return "Hedef: \(nextTitle.label) · \(formattedNumber(summary.nextTitleRemaining)) MDP kaldı"
        }
        return "En üst RiskDetected ünvanındasın"
    }

    private func titleTile(accent: Color, accentSoft: Color) -> some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                accent.opacity(0.26),
                                Color(hex: "#FF8A3D").opacity(0.12),
                                Color.clear
                            ],
                            center: .center,
                            startRadius: 4,
                            endRadius: 34
                        )
                    )
                    .frame(width: 70, height: 70)
                    .blur(radius: 3)

                Image(systemName: "flame.fill")
                    .font(.system(size: 39, weight: .black, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color(hex: "#FFE08A"),
                                accent,
                                Color(hex: "#FF6B35")
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .shadow(color: accent.opacity(0.42), radius: 10, x: 0, y: 0)
                    .shadow(color: Color(hex: "#FF6B35").opacity(0.20), radius: 14, x: 0, y: 5)
            }
            .frame(height: 54)

            VStack(spacing: 1) {
                Text(summary.currentTitle.label)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.rdBlack)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.72)
            }
        }
        .frame(width: 105)
        .frame(minHeight: 124)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 24)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.rdFog.opacity(0.70),
                            Color.rdWhite
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.rdBlack.opacity(0.14), lineWidth: 1)
                )
        }
    }

    private func titleLadder(accent: Color, accentText: Color) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(ProfessionalProgressTitle.allCases.enumerated()), id: \.element.id) { index, title in
                let stage = index + 1
                let reached = stage <= currentTitleStage
                VStack(spacing: 4) {
                    Circle()
                        .fill(reached ? accent : Color.rdFog)
                        .frame(width: 23, height: 23)
                        .overlay {
                            if reached {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(Color.white)
                            } else {
                                Text("\(stage)")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.rdSlate.opacity(0.70))
                            }
                        }
                        .shadow(color: reached ? accent.opacity(0.25) : Color.clear, radius: 8, x: 0, y: 0)

                    Text(stageLabel(for: title))
                        .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(reached ? Color.rdBlack.opacity(0.78) : Color.rdSlate.opacity(0.74))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.rdFog.opacity(0.76))
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }

    private func stageLabel(for title: ProfessionalProgressTitle) -> String {
        switch title {
        case .candidate: return "Aday"
        case .fieldObserver: return "Saha"
        case .riskHunter: return "Risk"
        case .hazardAnalyst: return "Analiz"
        case .seniorRiskSpecialist: return "Kıd."
        case .safetyStrategist: return "Str."
        case .masterHSESpecialist: return "Usta"
        }
    }

    private func formattedNumber(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.decimalSeparator = ","
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
