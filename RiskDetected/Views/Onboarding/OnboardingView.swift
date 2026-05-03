import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var app: AppState
    @State private var step: Int = 0

    private let slides: [OnboardingSlide] = [
        .init(title: "Fotoğrafla uygunsuzluk tespiti",
              body: "Sahadaki fotoğrafı yükle. Yapay zeka, iş güvenliği uygunsuzluklarını saniyeler içinde tespit etsin.",
              art: .photo),
        .init(title: "AI odaklı analiz canvasları",
              body: "Genel, KKD, sektör veya acil risk analizi seç. Her canvas, alanına özel uzman bir gözle çalışır.",
              art: .canvas),
        .init(title: "Fine-Kinney & 5×5 risk skoru",
              body: "Her bulgu için Olasılık × Frekans × Şiddet ya da 5×5 matris hesabıyla saha standardına uygun risk skoru üretilir.",
              art: .method),
        .init(title: "Risk seviyeleri ve önlemler",
              body: "Tespit edilen her tehlike için risk seviyesi, açıklama ve alınması gereken önlem net şekilde sunulur.",
              art: .risk),
        .init(title: "PDF & Excel rapor",
              body: "Bulguları tek dokunuşla Fine-Kinney veya 5×5 metoduna göre denetim hazır PDF/Excel rapora dönüştür.",
              art: .pdf)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                RDLogo(size: 18)
                Spacer()
                Button("Atla") { app.finishOnboarding() }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Color.rdSlate)
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)

            Spacer(minLength: 0)

            VStack(spacing: 36) {
                OnboardingArt(kind: slides[step].art)
                    .frame(height: 280)
                    .id(step)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))

                VStack(spacing: 14) {
                    Text(slides[step].title)
                        .font(.system(size: 28, weight: .bold))
                        .tracking(-0.6)
                        .foregroundStyle(Color.rdBlack)
                        .multilineTextAlignment(.center)
                    Text(slides[step].body)
                        .font(.system(size: 16))
                        .foregroundStyle(Color.rdSlate)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .frame(maxWidth: 320)
                }
                .id("text\(step)")
                .transition(.opacity)
            }
            .padding(.horizontal, 24)
            .animation(.easeInOut(duration: 0.32), value: step)

            Spacer(minLength: 0)

            VStack(spacing: 22) {
                HStack(spacing: 6) {
                    ForEach(0..<slides.count, id: \.self) { i in
                        Capsule()
                            .fill(i == step ? Color.rdBlack : Color.rdLine)
                            .frame(width: i == step ? 22 : 6, height: 6)
                            .animation(.easeInOut(duration: 0.24), value: step)
                    }
                }

                RDButton(title: step == slides.count - 1 ? "Başlayalım" : "Devam",
                         style: .primary,
                         trailingIcon: "arrow.right") {
                    if step < slides.count - 1 {
                        withAnimation { step += 1 }
                    } else {
                        app.finishOnboarding()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.rdPaper)
    }
}

struct OnboardingSlide {
    let title: String
    let body: String
    let art: OnboardingArtKind
}

enum OnboardingArtKind { case photo, canvas, method, risk, pdf }

struct OnboardingArt: View {
    let kind: OnboardingArtKind

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 32)
                .fill(Color.rdCloud)
                .overlay(RoundedRectangle(cornerRadius: 32).stroke(Color.rdLine, lineWidth: 1))

            switch kind {
            case .photo: photoArt
            case .canvas: canvasArt
            case .method: methodArt
            case .risk: riskArt
            case .pdf: pdfArt
            }
        }
        .frame(width: 280, height: 280)
    }

    @ViewBuilder
    private var photoArt: some View {
        ZStack {
            RDPlaceholderPhoto(label: "Saha · Fotoğraf", cornerRadius: 18)
                .padding(24)
            // detection ring
            ZStack {
                Circle()
                    .stroke(Color.rdGreen, lineWidth: 2)
                    .frame(width: 80, height: 80)
                    .background(Circle().stroke(Color.rdGreen.opacity(0.25), lineWidth: 6))
                Circle()
                    .stroke(Color.rdGreen.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: 100, height: 100)
            }
            .position(x: 120, y: 130)

            // detected badge
            HStack(spacing: 6) {
                Image(systemName: "sparkles").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.rdGreen)
                Text("Tehlike tespit edildi").font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .shadow(color: .black.opacity(0.08), radius: 14, y: 4)
            .position(x: 200, y: 100)
        }
    }

    @ViewBuilder
    private var canvasArt: some View {
        let cards: [(icon: String, title: String, color: Color, isActive: Bool)] = [
            ("sparkles", "Genel", .rdBlack, false),
            ("hardhat.fill", "KKD", .rdGreen, true),
            ("pencil", "İşaretleme", .rdGraphite, false),
            ("building.2.fill", "Sektör", .rdCharcoal, false)
        ]
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            ForEach(0..<cards.count, id: \.self) { i in
                let c = cards[i]
                VStack(alignment: .leading) {
                    Image(systemName: c.icon)
                        .font(.system(size: 20))
                        .foregroundStyle(c.color)
                    Spacer()
                    Text(c.title)
                        .font(.system(size: 13, weight: .semibold))
                }
                .padding(14)
                .frame(height: 100)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(c.isActive ? Color.rdGreen : Color.rdLine, lineWidth: c.isActive ? 2 : 1)
                )
            }
        }
        .padding(22)
    }

    @ViewBuilder
    private var methodArt: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("RİSK HESAPLAMASI")
                .font(.system(size: 11, weight: .bold))
                .tracking(1)
                .foregroundStyle(Color.rdSlate)

            methodRow(score: "1440", label: "F-KINNEY", scoreColor: Color.rdCritical,
                      title: "Fine-Kinney", formula: "R = O × F × Ş",
                      params: [("O", 6), ("F", 6), ("Ş", 40)])
            methodRow(score: "20", label: "5×5", scoreColor: Color.rdHigh,
                      title: "5×5 L-Tipi Matris", formula: "R = O × Ş",
                      params: [("O", 4), ("Ş", 5)])

            // band scale
            HStack(spacing: 0) {
                ForEach([Color.rdLow, Color(hex: "#A4B30C"), Color.rdMedium, Color.rdHigh, Color.rdCritical], id: \.self) { c in
                    Rectangle().fill(c)
                }
            }
            .frame(height: 6)
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.rdLine, lineWidth: 1))
        .padding(22)
    }

    private func methodRow(score: String, label: String, scoreColor: Color,
                           title: String, formula: String,
                           params: [(String, Int)]) -> some View {
        HStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(score).font(.system(size: 16, weight: .heavy, design: .monospaced))
                Text(label).font(.system(size: 7, weight: .bold)).opacity(0.85)
            }
            .frame(width: 48, height: 48)
            .background(scoreColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .bold))
                Text(formula).font(.system(size: 10, design: .monospaced)).foregroundStyle(Color.rdSlate)
                HStack(spacing: 4) {
                    ForEach(0..<params.count, id: \.self) { i in
                        Text("\(params[i].0)·\(params[i].1)")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.white)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.rdFog)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var riskArt: some View {
        let rows: [(level: RiskLevel, text: String)] = [
            (.critical, "Kayma riski"),
            (.high, "KKD eksikliği"),
            (.medium, "Yetersiz aydınlatma")
        ]
        VStack(alignment: .leading, spacing: 10) {
            Text("TESPİT EDİLEN RİSKLER")
                .font(.system(size: 11, weight: .semibold))
                .tracking(1)
                .foregroundStyle(Color.rdSlate)
            ForEach(0..<rows.count, id: \.self) { i in
                HStack(spacing: 10) {
                    RDRiskDot(level: rows[i].level)
                    Text(rows[i].text)
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    RDChip(level: rows[i].level)
                }
                .padding(.vertical, 6)
                if i < rows.count - 1 {
                    Divider().background(Color.rdLine)
                }
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.rdLine, lineWidth: 1))
        .padding(22)
    }

    @ViewBuilder
    private var pdfArt: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    RDLogo(size: 11)
                    Spacer()
                    Text("Rapor #2841").font(.system(size: 8)).foregroundStyle(Color.rdSlate)
                }
                Rectangle().fill(Color.rdFog).frame(height: 6).clipShape(Capsule())
                Rectangle().fill(Color.rdFog).frame(width: 140, height: 4).clipShape(Capsule())
                HStack(spacing: 4) {
                    Rectangle().fill(Color.rdCriticalBg).frame(height: 32).clipShape(RoundedRectangle(cornerRadius: 6))
                    Rectangle().fill(Color.rdHighBg).frame(height: 32).clipShape(RoundedRectangle(cornerRadius: 6))
                    Rectangle().fill(Color.rdLowBg).frame(height: 32).clipShape(RoundedRectangle(cornerRadius: 6))
                }
                ForEach(0..<4, id: \.self) { _ in
                    HStack(spacing: 4) {
                        Circle().fill(Color.rdLine).frame(width: 6, height: 6)
                        Rectangle().fill(Color.rdFog).frame(height: 4).clipShape(Capsule())
                    }
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.rdLine, lineWidth: 1))
            .shadow(color: .black.opacity(0.08), radius: 30, y: 14)
            .padding(.horizontal, 60)
            .padding(.top, 32)
            .padding(.bottom, 60)

            ZStack {
                RoundedRectangle(cornerRadius: 14)
                    .fill(Color.rdGreen)
                    .frame(width: 48, height: 48)
                    .shadow(color: Color.rdGreen.opacity(0.4), radius: 20, y: 8)
                Image(systemName: "arrow.down.to.line").font(.system(size: 20, weight: .bold)).foregroundStyle(.white)
            }
            .padding(.trailing, 30).padding(.bottom, 36)
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}
