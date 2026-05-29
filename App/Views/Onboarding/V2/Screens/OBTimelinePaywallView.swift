import SwiftUI

// Timeline paywall — trust-building trial flow.
// Top: dark gradient banner with hardhat hero.
// Bottom: white card with title + plan toggle + 3-step timeline + CTA.
//
// Hooks:
//   onStart   — start trial / purchase
//   onRestore — restore purchases
//   onTerms   — open terms URL
//   onPrivacy — open privacy URL
//   onDismiss — close paywall (× button)
//
// Standalone for now; codex will wire to flow + IAP after approval.

struct OBTimelinePaywallView: View {
    let onStart: (OBPlan) -> Void
    let onRestore: () -> Void
    let onTerms: () -> Void
    let onPrivacy: () -> Void
    let onDismiss: () -> Void

    @State private var selectedPlan: OBPlan = .yearly
    @State private var swingAngle: Double = -10

    private var priceLine: String {
        switch selectedPlan {
        case .yearly:  return OBTrialPriceCopy.yearlyPaywallLine
        case .monthly: return OBTrialPriceCopy.monthlyPaywallLine
        }
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                banner
                contentCard
            }

            // Close button top-right over banner
            HStack {
                Spacer()
                Button {
                    OBHaptic.light(); onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.rdSlate)
                        .frame(width: 36, height: 36)
                        .background(Color.rdFog)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.rdLine, lineWidth: 1))
                }
                .buttonStyle(OBPressStyle())
                .padding(.top, 56)
                .padding(.trailing, 16)
                .accessibilityIdentifier("onboarding.timeline_paywall.close")
            }
        }
        .ignoresSafeArea()
        .accessibilityIdentifier("onboarding.timeline_paywall")
    }

    // MARK: - Banner (white with premium helmet icon)

    private var banner: some View {
        ZStack(alignment: .top) {
            Color.white
            helmetHero
        }
        .frame(height: 280)
        .clipped()
        .onAppear { animateBanner() }
    }

    private var helmetHero: some View {
        // Pendulum: rope + helmet as a single rotating stack, anchored at the
        // top so it swings naturally like hanging on a hook.
        VStack(spacing: 0) {
            // Hook at top (small dark anchor point)
            ZStack {
                Capsule()
                    .fill(Color(hex: "#2E2014"))
                    .frame(width: 10, height: 5)
                Circle()
                    .fill(Color(hex: "#1A0F08"))
                    .frame(width: 3, height: 3)
            }

            RealisticRope(length: 50)

            Image("Hardhat")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 210, height: 170)
                .shadow(color: Color.rdGreen.opacity(0.30), radius: 24, y: 12)
                .shadow(color: Color.black.opacity(0.18), radius: 12, y: 8)
        }
        .rotationEffect(.degrees(swingAngle), anchor: .top)
        .padding(.top, 8)
    }

    // MARK: - Content card

    private var contentCard: some View {
        VStack(spacing: 0) {
            Text("Ücretsiz Deneme Nasıl Çalışır?")
                .font(.system(size: 22, weight: .semibold))
                .tracking(-0.6)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.rdOnyx)
                .padding(.horizontal, 24)
                .padding(.top, -4)
                .obStage(delay: 0.05)

            HStack(spacing: 6) {
                if selectedPlan == .yearly {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.rdGreen)
                }
                Text(priceLine)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.rdSlate)
                    .multilineTextAlignment(.center)
            }
            .padding(.top, 6)
            .padding(.horizontal, 24)
            .obStage(delay: 0.12)
            .animation(.obSpring, value: selectedPlan)

            planToggle
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .obStage(delay: 0.18)

            Spacer(minLength: 12)

            timeline
                .padding(.horizontal, 24)

            Button {
                OBHaptic.light(); onRestore()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.counterclockwise.circle")
                        .font(.system(size: 13, weight: .medium))
                    Text("Geri Yükle")
                        .font(.system(size: 13, weight: .medium))
                }
                .foregroundStyle(Color.rdGreenDark)
            }
            .buttonStyle(OBPressStyle())
            .padding(.top, 12)
            .obStage(delay: 0.5)

            Spacer(minLength: 12)

            OBPrimaryButton(title: selectedPlan == .yearly ? "Devam Et" : "Aboneliği başlat", style: .onyx, accessibilityID: "onboarding.timeline_paywall.cta") {
                onStart(selectedPlan)
            }
            .padding(.horizontal, 24)
            .obStage(delay: 0.58)

            HStack(spacing: 12) {
                Button {
                    OBHaptic.soft(); onTerms()
                } label: {
                    Text("Kullanım Şartları")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.rdSlate)
                }
                Circle().fill(Color.rdSlate.opacity(0.5)).frame(width: 3, height: 3)
                Button {
                    OBHaptic.soft(); onPrivacy()
                } label: {
                    Text("Gizlilik Politikası")
                        .font(.system(size: 11))
                        .foregroundStyle(Color.rdSlate)
                }
            }
            .padding(.top, 12)
            .padding(.bottom, 24)
            .obStage(delay: 0.66)
        }
        .padding(.top, 6)
        .background(Color.white)
    }

    // MARK: - Plan toggle

    private var planToggle: some View {
        VStack(spacing: 6) {
            HStack(spacing: 0) {
                planPill(.yearly, label: "Yıllık")
                planPill(.monthly, label: "Aylık")
            }
            .padding(4)
            .background(Color.rdFog)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.rdLine, lineWidth: 1))
            .frame(maxWidth: 240)

            // Discount caption — only visible when yearly is selected
            Text("%16 indirim")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color.rdGreenDark)
                .opacity(selectedPlan == .yearly ? 1 : 0)
                .animation(.obSpring, value: selectedPlan)
        }
    }

    private func planPill(_ plan: OBPlan, label: String) -> some View {
        let selected = selectedPlan == plan
        return Button {
            OBHaptic.light()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.78)) {
                selectedPlan = plan
            }
        } label: {
            Text(label)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(selected ? .white : Color.rdOnyx)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(
                    Capsule().fill(selected ? Color.rdGreen : Color.clear)
                        .shadow(color: selected ? Color.rdGreen.opacity(0.3) : .clear, radius: 8, y: 3)
                )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("onboarding.timeline_paywall.plan.\(plan.rawValue)")
    }

    // MARK: - Timeline

    @ViewBuilder
    private var timeline: some View {
        if selectedPlan == .yearly {
            yearlyTimeline
        } else {
            monthlyTimeline
        }
    }

    private var yearlyTimeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            timelineStep(
                index: 0,
                icon: "lock.shield.fill",
                accent: Color(hex: "#F0A400"),
                day: "Bugün",
                detail: "",
                extraBadge: plusBadge,
                isLast: false
            )
            timelineStep(
                index: 1,
                icon: "bell.fill",
                accent: Color(hex: "#F0A400"),
                day: "5. Gün",
                detail: "Denemen bitmeden sana hatırlatma göndeririz.",
                isLast: false
            )
            timelineStep(
                index: 2,
                icon: "trophy.fill",
                accent: Color.rdGreen,
                day: "7. Gün",
                detail: "Yıllık plan başlar — 2 ay bedava avantajıyla. İstediğin zaman iptal edebilirsin.",
                isLast: true
            )
        }
        .frame(maxWidth: 280)
        .frame(maxWidth: .infinity)
    }

    private var monthlyTimeline: some View {
        VStack(alignment: .leading, spacing: 0) {
            timelineStep(
                index: 0,
                icon: "lock.shield.fill",
                accent: Color(hex: "#F0A400"),
                day: "Bugün",
                detail: "Tüm özellikler hemen aktif olur, ödeme başlar.",
                isLast: false
            )
            timelineStep(
                index: 1,
                icon: "calendar.badge.checkmark",
                accent: Color.rdGreen,
                day: "Her ay",
                detail: "₺499 otomatik yenilenir. İstediğin zaman iptal edebilirsin.",
                isLast: true
            )
        }
        .frame(maxWidth: 280)
        .frame(maxWidth: .infinity)
    }

    private func timelineStep(index: Int, icon: String, accent: Color, day: String, detail: String, extraBadge: AnyView? = nil, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .stroke(accent, lineWidth: 1.6)
                        .frame(width: 36, height: 36)
                    Circle()
                        .fill(accent.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
                }

                if !isLast {
                    Rectangle()
                        .fill(accent.opacity(0.55))
                        .frame(width: 1.5, height: 42)
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(day)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Color.rdOnyx)
                if let extraBadge {
                    extraBadge
                }
                if !detail.isEmpty {
                    Text(detail)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.rdSlate)
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.top, 4)
            .padding(.bottom, isLast ? 0 : 12)
        }
        .obStage(delay: 0.24 + Double(index) * 0.08)
    }

    private var plusBadge: AnyView {
        AnyView(
            HStack(spacing: 6) {
                Image(systemName: "crown.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color(hex: "#F0A400"))
                Text("PLUS üyeliğini tüm özellikleriyle kullan")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.rdSlate)
                    .fixedSize(horizontal: false, vertical: true)
            }
        )
    }

    // MARK: - Animations

    private func animateBanner() {
        // Pendulum swing: ease-in-out symmetric loop
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            swingAngle = 10
        }
    }
}

// Banner bottom: organic wavy edge with subtle bumps — softer than wedges,
// blends gradient into white area smoothly.
private struct BannerWedgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        p.move(to: CGPoint(x: 0, y: 0))
        p.addLine(to: CGPoint(x: w, y: 0))
        p.addLine(to: CGPoint(x: w, y: h - 24))

        // Wavy bottom edge — 3 humps via successive quadratic curves.
        // Control points alternate above/below to create organic dips.
        p.addQuadCurve(
            to: CGPoint(x: w * 0.74, y: h - 12),
            control: CGPoint(x: w * 0.90, y: h + 8)
        )
        p.addQuadCurve(
            to: CGPoint(x: w * 0.50, y: h - 30),
            control: CGPoint(x: w * 0.62, y: h - 52)
        )
        p.addQuadCurve(
            to: CGPoint(x: w * 0.26, y: h - 14),
            control: CGPoint(x: w * 0.38, y: h + 8)
        )
        p.addQuadCurve(
            to: CGPoint(x: 0, y: h - 32),
            control: CGPoint(x: w * 0.12, y: h - 50)
        )
        p.closeSubpath()
        return p
    }
}

// MARK: - Helmet shapes (built from scratch, no SF Symbol dependency)

private struct HelmetShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        // Dome top
        p.move(to: CGPoint(x: w * 0.18, y: h * 0.72))
        p.addQuadCurve(
            to: CGPoint(x: w * 0.82, y: h * 0.72),
            control: CGPoint(x: w * 0.50, y: h * 0.05)
        )
        // Right side curve down
        p.addQuadCurve(
            to: CGPoint(x: w * 0.96, y: h * 0.78),
            control: CGPoint(x: w * 0.92, y: h * 0.74)
        )
        // Brim bottom right
        p.addLine(to: CGPoint(x: w * 0.96, y: h * 0.86))
        p.addQuadCurve(
            to: CGPoint(x: w * 0.78, y: h * 0.94),
            control: CGPoint(x: w * 0.90, y: h * 0.94)
        )
        // Brim across bottom
        p.addLine(to: CGPoint(x: w * 0.22, y: h * 0.94))
        p.addQuadCurve(
            to: CGPoint(x: w * 0.04, y: h * 0.86),
            control: CGPoint(x: w * 0.10, y: h * 0.94)
        )
        p.addLine(to: CGPoint(x: w * 0.04, y: h * 0.78))
        p.addQuadCurve(
            to: CGPoint(x: w * 0.18, y: h * 0.72),
            control: CGPoint(x: w * 0.08, y: h * 0.74)
        )
        p.closeSubpath()
        return p
    }
}

private struct HelmetHighlightShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        // Crescent highlight on top dome
        p.move(to: CGPoint(x: w * 0.26, y: h * 0.40))
        p.addQuadCurve(
            to: CGPoint(x: w * 0.74, y: h * 0.40),
            control: CGPoint(x: w * 0.50, y: h * 0.10)
        )
        p.addQuadCurve(
            to: CGPoint(x: w * 0.30, y: h * 0.46),
            control: CGPoint(x: w * 0.50, y: h * 0.28)
        )
        p.closeSubpath()
        return p
    }
}

private struct HelmetRidgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let w = rect.width
        let h = rect.height
        // Center ridge line from front to back of dome
        p.move(to: CGPoint(x: w * 0.50, y: h * 0.08))
        p.addQuadCurve(
            to: CGPoint(x: w * 0.50, y: h * 0.74),
            control: CGPoint(x: w * 0.50, y: h * 0.40)
        )
        // Brim seam
        p.move(to: CGPoint(x: w * 0.06, y: h * 0.82))
        p.addLine(to: CGPoint(x: w * 0.94, y: h * 0.82))
        return p
    }
}

#Preview {
    OBTimelinePaywallView(
        onStart: { _ in },
        onRestore: {},
        onTerms: {},
        onPrivacy: {},
        onDismiss: {}
    )
}

// MARK: - Hardhat vector (Canvas-rendered, reliable across iOS versions)

private struct HardhatVector: View {
    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height

            // ── Color palette ─────────────────────────────────────
            let lightGreen = Color(hex: "#6FE99A")
            let midGreen = Color.rdGreen
            let darkGreen = Color(hex: "#007D1F")
            let veryDark = Color(hex: "#004B12")
            let shadowGreen = Color(hex: "#003A0D")

            // ── Brim under-shadow (inside lip visible under brim) ─
            var underShadow = Path()
            underShadow.addEllipse(in: CGRect(
                x: w * 0.06, y: h * 0.84,
                width: w * 0.88, height: h * 0.08
            ))
            ctx.fill(underShadow, with: .color(veryDark.opacity(0.55)))

            // ── Brim — wide flat oval base with subtle front curve ─
            var brim = Path()
            brim.move(to: CGPoint(x: w * 0.02, y: h * 0.82))
            brim.addQuadCurve(
                to: CGPoint(x: w * 0.98, y: h * 0.82),
                control: CGPoint(x: w * 0.50, y: h * 0.78)
            )
            brim.addQuadCurve(
                to: CGPoint(x: w * 0.92, y: h * 0.92),
                control: CGPoint(x: w * 0.98, y: h * 0.90)
            )
            brim.addQuadCurve(
                to: CGPoint(x: w * 0.08, y: h * 0.92),
                control: CGPoint(x: w * 0.50, y: h * 0.96)
            )
            brim.addQuadCurve(
                to: CGPoint(x: w * 0.02, y: h * 0.82),
                control: CGPoint(x: w * 0.02, y: h * 0.86)
            )
            brim.closeSubpath()
            ctx.fill(
                brim,
                with: .linearGradient(
                    Gradient(colors: [midGreen, darkGreen, veryDark]),
                    startPoint: CGPoint(x: w * 0.5, y: h * 0.80),
                    endPoint: CGPoint(x: w * 0.5, y: h * 0.92)
                )
            )

            // Brim top highlight (catches light)
            var brimHL = Path()
            brimHL.move(to: CGPoint(x: w * 0.16, y: h * 0.825))
            brimHL.addQuadCurve(
                to: CGPoint(x: w * 0.84, y: h * 0.825),
                control: CGPoint(x: w * 0.50, y: h * 0.805)
            )
            ctx.stroke(brimHL, with: .color(lightGreen.opacity(0.55)), lineWidth: 1.6)

            // Brim front-edge shadow under dome
            var brimShadow = Path()
            brimShadow.move(to: CGPoint(x: w * 0.10, y: h * 0.81))
            brimShadow.addQuadCurve(
                to: CGPoint(x: w * 0.90, y: h * 0.81),
                control: CGPoint(x: w * 0.50, y: h * 0.83)
            )
            ctx.stroke(brimShadow, with: .color(shadowGreen.opacity(0.45)), lineWidth: 2.2)

            // ── Dome — main body with proper hardhat curvature ─
            var dome = Path()
            // Start at left base, sweep up and over
            dome.move(to: CGPoint(x: w * 0.14, y: h * 0.78))
            // Left side curve up
            dome.addCurve(
                to: CGPoint(x: w * 0.50, y: h * 0.08),
                control1: CGPoint(x: w * 0.10, y: h * 0.55),
                control2: CGPoint(x: w * 0.20, y: h * 0.14)
            )
            // Right side curve down
            dome.addCurve(
                to: CGPoint(x: w * 0.86, y: h * 0.78),
                control1: CGPoint(x: w * 0.80, y: h * 0.14),
                control2: CGPoint(x: w * 0.90, y: h * 0.55)
            )
            // Right flank to brim
            dome.addQuadCurve(
                to: CGPoint(x: w * 0.94, y: h * 0.82),
                control: CGPoint(x: w * 0.90, y: h * 0.81)
            )
            // Across bottom
            dome.addLine(to: CGPoint(x: w * 0.06, y: h * 0.82))
            // Left flank back up
            dome.addQuadCurve(
                to: CGPoint(x: w * 0.14, y: h * 0.78),
                control: CGPoint(x: w * 0.10, y: h * 0.81)
            )
            dome.closeSubpath()

            // Fill dome with vertical gradient (light top → dark bottom)
            ctx.fill(
                dome,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: lightGreen, location: 0.0),
                        .init(color: midGreen, location: 0.35),
                        .init(color: darkGreen, location: 0.85),
                        .init(color: veryDark, location: 1.0)
                    ]),
                    startPoint: CGPoint(x: w * 0.5, y: h * 0.05),
                    endPoint: CGPoint(x: w * 0.5, y: h * 0.82)
                )
            )

            // Left-side ambient shadow (gives 3D feel)
            var leftShade = Path()
            leftShade.move(to: CGPoint(x: w * 0.14, y: h * 0.78))
            leftShade.addCurve(
                to: CGPoint(x: w * 0.50, y: h * 0.08),
                control1: CGPoint(x: w * 0.10, y: h * 0.55),
                control2: CGPoint(x: w * 0.20, y: h * 0.14)
            )
            leftShade.addCurve(
                to: CGPoint(x: w * 0.30, y: h * 0.78),
                control1: CGPoint(x: w * 0.36, y: h * 0.20),
                control2: CGPoint(x: w * 0.24, y: h * 0.50)
            )
            leftShade.closeSubpath()
            ctx.fill(leftShade, with: .color(shadowGreen.opacity(0.18)))

            // ── Specular highlight (upper-right) ─
            var spec = Path()
            spec.move(to: CGPoint(x: w * 0.42, y: h * 0.18))
            spec.addQuadCurve(
                to: CGPoint(x: w * 0.78, y: h * 0.42),
                control: CGPoint(x: w * 0.78, y: h * 0.16)
            )
            spec.addQuadCurve(
                to: CGPoint(x: w * 0.46, y: h * 0.28),
                control: CGPoint(x: w * 0.58, y: h * 0.38)
            )
            spec.closeSubpath()
            ctx.fill(spec, with: .color(Color.white.opacity(0.42)))

            // Secondary highlight band
            var hl2 = Path()
            hl2.move(to: CGPoint(x: w * 0.30, y: h * 0.55))
            hl2.addQuadCurve(
                to: CGPoint(x: w * 0.40, y: h * 0.50),
                control: CGPoint(x: w * 0.34, y: h * 0.50)
            )
            ctx.stroke(hl2, with: .color(lightGreen.opacity(0.65)), lineWidth: 2.5)

            // ── Center ridge (top crown line) ─
            var ridge = Path()
            ridge.move(to: CGPoint(x: w * 0.50, y: h * 0.09))
            ridge.addQuadCurve(
                to: CGPoint(x: w * 0.50, y: h * 0.78),
                control: CGPoint(x: w * 0.50, y: h * 0.45)
            )
            ctx.stroke(ridge, with: .color(darkGreen.opacity(0.40)), lineWidth: 1.8)

            // Ridge highlight
            var ridgeHL = Path()
            ridgeHL.move(to: CGPoint(x: w * 0.515, y: h * 0.12))
            ridgeHL.addQuadCurve(
                to: CGPoint(x: w * 0.515, y: h * 0.45),
                control: CGPoint(x: w * 0.515, y: h * 0.30)
            )
            ctx.stroke(ridgeHL, with: .color(Color.white.opacity(0.45)), lineWidth: 1)

            // ── Side air vents (rectangular slots, more anatomical) ─
            for vx in [w * 0.28, w * 0.68] {
                let slot = Path(roundedRect: CGRect(x: vx - 5, y: h * 0.50, width: 10, height: 16),
                                cornerRadius: 2.5)
                ctx.fill(slot, with: .color(shadowGreen.opacity(0.55)))
                // inner shadow
                let inner = Path(roundedRect: CGRect(x: vx - 4, y: h * 0.51, width: 8, height: 13),
                                 cornerRadius: 2)
                ctx.fill(inner, with: .color(Color.black.opacity(0.30)))
            }

            // ── Front logo plate (subtle, white) ─
            let plateRect = CGRect(x: w * 0.43, y: h * 0.60, width: w * 0.14, height: h * 0.08)
            ctx.fill(
                Path(roundedRect: plateRect, cornerRadius: 2.5),
                with: .linearGradient(
                    Gradient(colors: [Color.white.opacity(0.95), Color.white.opacity(0.75)]),
                    startPoint: CGPoint(x: plateRect.midX, y: plateRect.minY),
                    endPoint: CGPoint(x: plateRect.midX, y: plateRect.maxY)
                )
            )

            // ── Rim outline (crisp edge for definition) ─
            ctx.stroke(dome, with: .color(shadowGreen.opacity(0.32)), lineWidth: 0.8)
        }
    }
}

// MARK: - Realistic rope

private struct RealisticRope: View {
    let length: CGFloat
    private let thickness: CGFloat = 6

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height

            // Base shape — cylindrical rope (rounded rect, full height)
            let ropePath = Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                                cornerRadius: w * 0.5)

            // Fill with horizontal gradient — darker at edges, lighter center,
            // creates cylindrical depth illusion.
            ctx.fill(
                ropePath,
                with: .linearGradient(
                    Gradient(stops: [
                        .init(color: Color(hex: "#5A3F22"), location: 0.0),
                        .init(color: Color(hex: "#A07A4E"), location: 0.45),
                        .init(color: Color(hex: "#C49968"), location: 0.55),
                        .init(color: Color(hex: "#6E4D2A"), location: 1.0)
                    ]),
                    startPoint: CGPoint(x: 0, y: h * 0.5),
                    endPoint: CGPoint(x: w, y: h * 0.5)
                )
            )

            // Clip subsequent draws to rope shape — twist lines stay inside
            var stripes = ctx
            stripes.clip(to: ropePath)

            // Twist pattern — diagonal stripes mimicking braided fibers
            let step: CGFloat = 5
            for y in stride(from: -w * 2, through: h + w * 2, by: step) {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: w, y: y + w * 1.4))
                stripes.stroke(line, with: .color(Color.black.opacity(0.22)),
                               style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
            }

            // Lighter highlight stripes interleaved (offset half-step)
            for y in stride(from: -w * 2 + step / 2, through: h + w * 2, by: step) {
                var line = Path()
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: w, y: y + w * 1.4))
                stripes.stroke(line, with: .color(Color.white.opacity(0.12)),
                               style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
            }

            // Rim edge stroke for definition
            ctx.stroke(ropePath, with: .color(Color(hex: "#3A2510").opacity(0.55)),
                       lineWidth: 0.6)
        }
        .frame(width: thickness, height: length)
    }
}
