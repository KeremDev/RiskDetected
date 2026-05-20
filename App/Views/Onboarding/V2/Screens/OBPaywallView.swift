import SwiftUI

struct OBPaywallView: View {
    @ObservedObject var state: OnboardingV2State
    let onStartTrial: () -> Void
    let onDismiss: () -> Void

    private let benefits: [(icon: String, title: String, sub: String)] = [
        ("photo.fill", "Sınırsız fotoğraf analizi", "Fine-Kinney · 5×5 · L×Ş"),
        ("doc.text.fill", "PDF + Excel dışa aktarım", "Mevzuat referansları ile"),
        ("person.2.fill", "Ekip ile paylaş ve yorumla", "5 kullanıcıya kadar"),
        ("bubble.left.fill", "Öncelikli destek", "Türkçe · 24 saat içinde yanıt")
    ]

    var body: some View {
        ZStack(alignment: .topTrailing) {
            LinearGradient(colors: [Color(hex: "#161819"), Color(hex: "#0B0D0E")],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        pill
                            .padding(.top, 56)
                            .obStage(delay: 0.08)

                        Text(titleAttr)
                            .font(.system(size: 30, weight: .semibold))
                            .tracking(-0.96)
                            .lineSpacing(2)
                            .padding(.top, 18)
                            .obStage(delay: 0.16)

                        trialPill
                            .padding(.top, 12)
                            .obStage(delay: 0.24)

                        benefitsCard
                            .padding(.top, 24)
                            .obStage(delay: 0.34)

                        VStack(spacing: 10) {
                            planCard(.yearly)
                                .obStage(delay: 0.46)
                            planCard(.monthly)
                                .obStage(delay: 0.54)
                        }
                        .padding(.top, 16)

                        Spacer(minLength: 32)
                    }
                    .padding(.horizontal, 24)
                }

                VStack(spacing: 10) {
                    Button {
                        OBHaptic.medium(); onStartTrial()
                    } label: {
                        HStack(spacing: 8) {
                            Text("Ücretsiz denemeyi başlat")
                                .font(.system(size: 16, weight: .semibold))
                            Image(systemName: "arrow.right")
                                .font(.system(size: 15, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity).frame(height: 58)
                        .background(Color.rdGreen)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .shadow(color: Color.rdGreen.opacity(0.32), radius: 16, y: 6)
                    }
                    .buttonStyle(OBPressStyle())
                    .obStage(delay: 0.68)

                    finePrint
                        .obStage(delay: 0.76)
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 28)
                .background(
                    LinearGradient(colors: [.clear, Color(hex: "#0B0D0E").opacity(0.6), Color(hex: "#0B0D0E")],
                                   startPoint: .top, endPoint: .bottom)
                )
            }

            Button {
                OBHaptic.light(); onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                    .frame(width: 36, height: 36)
                    .background(.white.opacity(0.1))
                    .clipShape(Circle())
            }
            .buttonStyle(OBPressStyle())
            .padding(.top, 64)
            .padding(.trailing, 16)
        }
    }

    private var titleAttr: AttributedString {
        var s = AttributedString("Sahadaki her gözlemi ")
        var accent = AttributedString("rapora")
        accent.foregroundColor = Color(hex: "#4FE07E")
        s.append(accent)
        s.append(AttributedString(" dönüştür."))
        s.foregroundColor = .white
        return s
    }

    private var pill: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: "#00E03A")).frame(width: 5, height: 5)
            Text("\(state.primarySectorLabel.uppercased()) UZMANLARI İÇİN HAZIRLANDI")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
        }
        .foregroundStyle(Color(hex: "#4FE07E"))
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.rdGreen.opacity(0.16))
        .overlay(Capsule().stroke(Color.rdGreen.opacity(0.32), lineWidth: 1))
        .clipShape(Capsule())
    }

    private var trialPill: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: "#4FE07E")).frame(width: 5, height: 5)
                .shadow(color: Color(hex: "#4FE07E"), radius: 4)
            Text("Planın hazır · 7 gün ücretsiz dene")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.78))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }

    private var benefitsCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(benefits.enumerated()), id: \.offset) { i, b in
                HStack(spacing: 14) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 10).fill(Color.rdGreen.opacity(0.18))
                        Image(systemName: b.icon)
                            .font(.system(size: 14))
                            .foregroundStyle(Color(hex: "#4FE07E"))
                    }
                    .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(b.title)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.92))
                        Text(b.sub)
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.55))
                    }
                    Spacer()
                }
                .padding(.vertical, 10)
                if i < benefits.count - 1 {
                    Rectangle().fill(.white.opacity(0.06)).frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 8)
        .background(.white.opacity(0.04))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func planCard(_ plan: OBPlan) -> some View {
        let selected = state.selectedPlan == plan
        let isYearly = plan == .yearly
        return Button {
            OBHaptic.light()
            withAnimation(.obSpring) { state.selectedPlan = plan }
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .stroke(selected ? Color(hex: "#4FE07E") : .white.opacity(0.25), lineWidth: 1.5)
                    if selected {
                        Circle().fill(Color(hex: "#4FE07E")).padding(4)
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .frame(width: 22, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(isYearly ? "Yıllık" : "Aylık")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white)
                        if isYearly {
                            Text("%60 TASARRUF")
                                .font(.system(size: 10, weight: .semibold))
                                .tracking(0.4)
                                .foregroundStyle(Color.rdOnyx)
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color(hex: "#4FE07E"))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                    Text(isYearly ? "İlk 7 gün ücretsiz · sonra ₺199 / ay" : "İlk 7 gün ücretsiz")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(isYearly ? "₺2.388" : "₺499")
                        .font(.system(size: 17, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text(isYearly ? "/yıl" : "/ay")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .background(selected ? Color.rdGreen.opacity(0.10) : Color.white.opacity(0.04))
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(selected ? Color(hex: "#4FE07E") : Color.white.opacity(0.1),
                            lineWidth: selected ? 2 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(OBPressStyle())
    }

    private var finePrint: some View {
        VStack(spacing: 4) {
            Text("İstediğin zaman iptal · App Store üzerinden faturalandırılır")
            HStack(spacing: 0) {
                Text("Şartlar").underline()
                dot
                Text("Gizlilik").underline()
                dot
                Text("Satın alımları geri yükle").underline()
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.white.opacity(0.45))
        .lineSpacing(3)
        .frame(maxWidth: .infinity)
    }

    private var dot: some View {
        Circle().fill(.white.opacity(0.3))
            .frame(width: 3, height: 3)
            .padding(.horizontal, 5)
    }
}
