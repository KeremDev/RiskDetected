import SwiftUI

struct OBPlanSummaryView: View {
    @ObservedObject var state: OnboardingV2State
    let onNext: () -> Void

    @State private var checkScale: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            OBTopBar(showBack: false, step: 6, total: 5, trailingLabel: "HAZIR", trailingDone: true)

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    // Centered hero block
                    VStack(spacing: 12) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 16).fill(Color.rdGreen)
                            Image(systemName: "checkmark")
                                .font(.system(size: 24, weight: .heavy))
                                .foregroundStyle(.white)
                        }
                        .frame(width: 52, height: 52)
                        .scaleEffect(checkScale)
                        .shadow(color: Color.rdGreen.opacity(0.32), radius: 16, y: 6)
                        .onAppear {
                            withAnimation(.spring(response: 0.6, dampingFraction: 0.5)) {
                                checkScale = 1
                            }
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { OBHaptic.success() }
                        }

                        Text("Hazırsın.")
                            .font(.system(size: 26, weight: .semibold))
                            .tracking(-0.6)
                            .foregroundStyle(Color.rdOnyx)
                            .multilineTextAlignment(.center)
                            .obStage(delay: 0.2)

                        VStack(spacing: 3) {
                            Text("İşte senin için hazırladığımız:")
                                .font(.system(size: 17, weight: .semibold))
                                .tracking(-0.3)
                                .foregroundStyle(Color.rdOnyx)
                                .multilineTextAlignment(.center)
                            Text("\(state.certificateLabel) · \(state.hazardsLabel) · \(state.primarySectorLabel)")
                                .font(.system(size: 13))
                                .foregroundStyle(Color.rdSlate)
                                .multilineTextAlignment(.center)
                                .lineLimit(1)
                                .minimumScaleFactor(0.85)
                        }
                        .obStage(delay: 0.32)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 14)

                    Rectangle()
                        .fill(Color.rdLine)
                        .frame(height: 1)
                        .padding(.top, 22)
                        .obStage(delay: 0.4)

                    // Plan cards section
                    VStack(spacing: 12) {
                        planCard(
                            icon: "doc.text.fill",
                            big: "47",
                            headline: "risk değerlendirme şablonu",
                            sub: "Fine-Kinney ve 5×5 hazır",
                            showBadge: true
                        )
                        .obStage(delay: 0.5)

                        planCard(
                            icon: "checklist",
                            big: nil,
                            headline: "\(state.primarySectorLabel) sektörüne özel checklist'ler",
                            sub: "İskele, KKD, yüksekte çalışma",
                            showBadge: true
                        )
                        .obStage(delay: 0.6)

                        planCard(
                            icon: "doc.richtext.fill",
                            big: nil,
                            headline: "\(state.certificateLabel) raporlama formatı",
                            sub: "PDF + Excel · Mevzuat referanslı",
                            showBadge: true
                        )
                        .obStage(delay: 0.7)
                    }
                    .padding(.top, 22)

                    social
                        .padding(.top, 18)
                        .obStage(delay: 0.86)

                    Spacer(minLength: 16)
                }
                .padding(.horizontal, 24)
            }

            OBFooter {
                OBPrimaryButton(title: "Hesabımı Oluştur") { onNext() }
                    .obStage(delay: 0.96)
            }
        }
        .background(Color.rdPaper)
    }

    private func planCard(icon: String, big: String?, headline: String, sub: String, showBadge: Bool) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Color.rdOnyx)
                .frame(width: 40, height: 40)

            VStack(alignment: .leading, spacing: 4) {
                if showBadge { saneOzelBadge }

                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if let big {
                        Text(big)
                            .font(.system(size: 20, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.rdOnyx)
                    }
                    Text(headline)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.rdOnyx)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }

                Text(sub)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.rdSlate)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 14)
        .background(Color.rdWhite)
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.rdOnyx.opacity(0.06), lineWidth: 1))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }

    private var saneOzelBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "sparkles")
                .font(.system(size: 9, weight: .bold))
            Text("SANA ÖZEL")
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
        }
        .foregroundStyle(Color.rdGreenDark)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(Color.rdGreenSoft)
        .overlay(
            Capsule().stroke(Color.rdGreen.opacity(0.22), lineWidth: 1)
        )
        .clipShape(Capsule())
    }

    private var social: some View {
        HStack(spacing: 10) {
            ZStack {
                avatar("MK", bg: Color(hex: "#4F86E0")).offset(x: -12)
                avatar("EY", bg: Color(hex: "#FFB300"))
                avatar("BD", bg: Color.rdGreen).offset(x: 12)
            }
            .frame(width: 48)

            (Text("Türkiye'nin İSG asistanı").bold().foregroundColor(Color.rdOnyx)
             + Text(" — OSGB'ler ve uzmanlar için.").foregroundColor(Color.rdGraphite))
                .font(.system(size: 13))
        }
        .padding(.horizontal, 14).padding(.vertical, 12)
        .background(Color.rdFog)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func avatar(_ initials: String, bg: Color) -> some View {
        ZStack {
            Circle().fill(bg)
            Circle().stroke(Color.rdFog, lineWidth: 2)
            Text(initials).font(.system(size: 9, weight: .semibold)).foregroundStyle(.white)
        }
        .frame(width: 22, height: 22)
    }
}
