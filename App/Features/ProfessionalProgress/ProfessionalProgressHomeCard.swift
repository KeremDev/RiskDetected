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

    @State private var animateProgress = false
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
                        .foregroundStyle(Color.rdBlack)
                    Text("/ \(formattedNumber(nextTitleThreshold)) MDP")
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                    Spacer(minLength: 0)
                    Text("%\(titleProgressPercent)")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.rdSlate)
                }

                GeometryReader { geo in
                    let filledWidth = max(28, geo.size.width * progress)
                    let markerX = min(max(filledWidth, 26), geo.size.width - 12)

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
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            LinearGradient(
                colors: [
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
                .stroke(accent.opacity(0.24), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        .shadow(color: accent.opacity(0.10), radius: 12, x: 0, y: 6)
        .contentShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        .onTapGesture {
            onTap?()
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityAddTraits(.isButton)
        .onAppear {
            withAnimation(.snappy(duration: 0.55)) {
                animateProgress = true
            }
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

        return HStack(spacing: 12) {
            titleTile(accent: accent, accentSoft: accentSoft)

            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formattedNumber(summary.profile.totalMDP))
                            .rdMono(size: 25, weight: .bold)
                            .foregroundStyle(Color.white)
                            .shadow(color: Color.white.opacity(0.28), radius: 8, x: 0, y: 0)
                        Text("/ \(formattedNumber(nextTitleThreshold))")
                            .font(.system(size: 15, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.58))
                        Spacer(minLength: 0)
                    }
                    Text(nextTitleLabel)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.62))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                }

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.12))
                        Capsule()
                            .fill(Color.white.opacity(0.92))
                            .frame(width: max(30, geo.size.width * progress))
                            .shadow(color: Color.white.opacity(0.55), radius: 10, x: 0, y: 0)
                            .shadow(color: accent.opacity(0.35), radius: 8, x: 0, y: 0)
                    }
                }
                .frame(height: 15)

                titleLadder(accent: accent, accentText: accentText)
            }
        }
        .padding(12)
        .background {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: "#050708"),
                        Color(hex: "#101416"),
                        Color(hex: "#07090A")
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                LinearGradient(
                    colors: [
                        accent.opacity(0.20),
                        Color.clear,
                        Color.rdGreen.opacity(0.10)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: RDRadius.lg)
                .stroke(Color.white.opacity(0.09), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        .shadow(color: Color.rdOnyx.opacity(0.18), radius: 18, x: 0, y: 10)
        .shadow(color: accent.opacity(0.10), radius: 22, x: 0, y: 8)
        .contentShape(RoundedRectangle(cornerRadius: RDRadius.lg))
        .onTapGesture {
            onTap?()
        }
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityAddTraits(.isButton)
        .onAppear {
            withAnimation(.snappy(duration: 0.65)) {
                animateProgress = true
            }
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
                                accent.opacity(0.34),
                                Color(hex: "#FF6B35").opacity(0.16),
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
                    .shadow(color: accent.opacity(0.62), radius: 14, x: 0, y: 0)
                    .shadow(color: Color(hex: "#FF6B35").opacity(0.34), radius: 18, x: 0, y: 6)
            }
            .frame(height: 54)

            VStack(spacing: 1) {
                Text(summary.currentTitle.label)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white)
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
                            Color.white.opacity(0.12),
                            Color.white.opacity(0.045)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 24)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
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
                        .fill(reached ? accent : Color.white.opacity(0.08))
                        .frame(width: 23, height: 23)
                        .overlay {
                            if reached {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(Color.white)
                            } else {
                                Text("\(stage)")
                                    .font(.system(size: 9, weight: .bold, design: .rounded))
                                    .foregroundStyle(Color.white.opacity(0.28))
                            }
                        }
                        .shadow(color: reached ? accent.opacity(0.25) : Color.clear, radius: 8, x: 0, y: 0)

                    Text(stageLabel(for: title))
                        .font(.system(size: 7.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(reached ? Color.white.opacity(0.82) : Color.white.opacity(0.40))
                        .lineLimit(1)
                        .minimumScaleFactor(0.68)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.065))
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
