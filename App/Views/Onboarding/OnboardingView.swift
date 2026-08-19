import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var app: AppState
    @State private var step: Int = 0

    private let slides: [OnboardingSlide] = [
        .init(title: RDLocalization.string("onboarding.onboarding.view.fotografla.uygunsuzluk.tespiti.64bd9fdb", table: .onboarding, fallback: "Fotoğrafla uygunsuzluk tespiti"),
              body: RDLocalization.string("onboarding.onboarding.view.sahadaki.fotografi.yukle.yapay.zeka.is.guvenligi.a0ff6f4b", table: .onboarding, fallback: "Sahadaki fotoğrafı yükle. Yapay zeka, iş güvenliği uygunsuzluklarını saniyeler içinde tespit etsin."),
              art: .photo),
        .init(title: RDLocalization.string("onboarding.onboarding.view.ai.odakli.analiz.canvaslari.7e21d6e7", table: .onboarding, fallback: "AI odaklı analiz canvasları"),
              body: RDLocalization.string("onboarding.onboarding.view.genel.kkd.sektor.veya.acil.risk.analizi.sec.her..b11ffd57", table: .onboarding, fallback: "Genel, KKD, sektör veya acil risk analizi seç. Her canvas, alanına özel uzman bir gözle çalışır."),
              art: .canvas),
        .init(title: RDLocalization.string("onboarding.onboarding.view.fine.kinney.5.5.risk.skoru.37dfd9ef", table: .onboarding, fallback: "Fine-Kinney & 5×5 risk skoru"),
              body: RDLocalization.string("onboarding.onboarding.view.her.bulgu.icin.olasilik.frekans.siddet.ya.da.5.5.b8d4dbbd", table: .onboarding, fallback: "Her bulgu için Olasılık × Frekans × Şiddet ya da 5×5 matris hesabıyla saha standardına uygun risk skoru üretilir."),
              art: .method),
        .init(title: RDLocalization.string("onboarding.onboarding.view.risk.seviyeleri.ve.onlemler.3214990a", table: .onboarding, fallback: "Risk seviyeleri ve önlemler"),
              body: RDLocalization.string("onboarding.onboarding.view.tespit.edilen.her.tehlike.icin.risk.seviyesi.aci.2f8fb473", table: .onboarding, fallback: "Tespit edilen her tehlike için risk seviyesi, açıklama ve alınması gereken önlem net şekilde sunulur."),
              art: .risk),
        .init(title: RDLocalization.string("onboarding.onboarding.view.pdf.excel.rapor.adbe8847", table: .onboarding, fallback: "PDF & Excel rapor"),
              body: RDLocalization.string("onboarding.onboarding.view.bulgulari.tek.dokunusla.fine.kinney.veya.5.5.met.9f646051", table: .onboarding, fallback: "Bulguları tek dokunuşla Fine-Kinney veya 5×5 metoduna göre denetim hazır PDF/Excel rapora dönüştür."),
              art: .pdf)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                RDLogo(size: 18)
                Spacer()
                Button(RDLocalization.string("onboarding.onboarding.view.atla.e25539b1", table: .onboarding, fallback: "Atla")) { app.finishOnboarding() }
                    .font(.system(size: RDFontScale.size(15), weight: .medium, design: .rounded))
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
                        .font(.system(size: RDFontScale.size(28), weight: .bold, design: .rounded))
                        .tracking(-0.6)
                        .foregroundStyle(Color.rdBlack)
                        .multilineTextAlignment(.center)
                    Text(slides[step].body)
                        .font(.system(size: RDFontScale.size(16), design: .rounded))
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

                RDButton(title: step == slides.count - 1 ? RDLocalization.string("onboarding.onboarding.view.baslayalim.b166d890", table: .onboarding, fallback: "Başlayalım") : RDLocalization.string("onboarding.onboarding.view.devam.a5bee993", table: .onboarding, fallback: "Devam"),
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
            RDPlaceholderPhoto(label: RDLocalization.string("onboarding.onboarding.view.saha.fotograf.e741ee23", table: .onboarding, fallback: "Saha · Fotoğraf"), cornerRadius: 18)
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
                Image(systemName: "sparkles").font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded)).foregroundStyle(Color.rdGreen)
                Text(RDLocalization.string("onboarding.onboarding.view.tehlike.tespit.edildi.7fe2db41", table: .onboarding, fallback: "Tehlike tespit edildi")).font(.system(size: RDFontScale.size(11), weight: .semibold, design: .rounded))
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
            ("sparkles", RDLocalization.string("onboarding.onboarding.view.genel.39cd056c", table: .onboarding, fallback: "Genel"), .rdBlack, false),
            ("hardhat.fill", "KKD", .rdGreen, true),
            ("pencil", RDLocalization.string("onboarding.onboarding.view.isaretleme.6be848bf", table: .onboarding, fallback: "İşaretleme"), .rdGraphite, false),
            ("building.2.fill", RDLocalization.string("onboarding.onboarding.view.sektor.41cc804c", table: .onboarding, fallback: "Sektör"), .rdCharcoal, false)
        ]
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
            ForEach(0..<cards.count, id: \.self) { i in
                let c = cards[i]
                VStack(alignment: .leading) {
                    Image(systemName: c.icon)
                        .font(.system(size: RDFontScale.size(20), design: .rounded))
                        .foregroundStyle(c.color)
                    Spacer()
                    Text(c.title)
                        .font(.system(size: RDFontScale.size(13), weight: .semibold, design: .rounded))
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
            Text(RDLocalization.string("onboarding.onboarding.view.risk.hesaplamasi.91234ce8", table: .onboarding, fallback: "RİSK HESAPLAMASI"))
                .font(.system(size: RDFontScale.size(11), weight: .bold, design: .rounded))
                .tracking(1)
                .foregroundStyle(Color.rdSlate)

            methodRow(score: "1440", label: RDLocalization.string("onboarding.onboarding.view.f.kinney.7955a88b", table: .onboarding, fallback: "F-KINNEY"), scoreColor: Color.rdCritical,
                      title: RDLocalization.string("onboarding.onboarding.view.fine.kinney.36094f7d", table: .onboarding, fallback: "Fine-Kinney"), formula: RDLocalization.string("onboarding.onboarding.view.r.o.f.s.c031ebce", table: .onboarding, fallback: "R = O × F × Ş"),
                      params: [("O", 6), ("F", 6), (RDLocalization.string("onboarding.onboarding.view.s.1a3e180d", table: .onboarding, fallback: "Ş"), 40)])
            methodRow(score: "20", label: RDLocalization.string("onboarding.onboarding.view.5.5.c56e30aa", table: .onboarding, fallback: "5×5"), scoreColor: Color.rdHigh,
                      title: RDLocalization.string("onboarding.onboarding.view.5.5.l.tipi.matris.3525cecd", table: .onboarding, fallback: "5×5 L-Tipi Matris"), formula: RDLocalization.string("onboarding.onboarding.view.r.o.s.0fc90694", table: .onboarding, fallback: "R = O × Ş"),
                      params: [("O", 4), (RDLocalization.string("onboarding.onboarding.view.s.89da2339", table: .onboarding, fallback: "Ş"), 5)])

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
                Text(score).font(.system(size: RDFontScale.size(16), weight: .heavy, design: .monospaced))
                Text(label).font(.system(size: RDFontScale.size(7), weight: .bold, design: .rounded)).opacity(0.85)
            }
            .frame(width: 48, height: 48)
            .background(scoreColor)
            .foregroundStyle(.white)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: RDFontScale.size(12), weight: .bold, design: .rounded))
                Text(formula).font(.system(size: RDFontScale.size(10), design: .monospaced)).foregroundStyle(Color.rdSlate)
                HStack(spacing: 4) {
                    ForEach(0..<params.count, id: \.self) { i in
                        Text("\(params[i].0)·\(params[i].1)")
                            .font(.system(size: RDFontScale.size(9), weight: .bold, design: .monospaced))
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
            (.critical, RDLocalization.string("onboarding.onboarding.view.kayma.riski.5fc04da2", table: .onboarding, fallback: "Kayma riski")),
            (.high, RDLocalization.string("onboarding.onboarding.view.kkd.eksikligi.8a363c64", table: .onboarding, fallback: "KKD eksikliği")),
            (.medium, RDLocalization.string("onboarding.onboarding.view.yetersiz.aydinlatma.39df16b2", table: .onboarding, fallback: "Yetersiz aydınlatma"))
        ]
        VStack(alignment: .leading, spacing: 10) {
            Text(RDLocalization.string("onboarding.onboarding.view.tespit.edilen.riskler.2a8f4423", table: .onboarding, fallback: "TESPİT EDİLEN RİSKLER"))
                .font(.system(size: RDFontScale.size(11), weight: .semibold, design: .rounded))
                .tracking(1)
                .foregroundStyle(Color.rdSlate)
            ForEach(0..<rows.count, id: \.self) { i in
                HStack(spacing: 10) {
                    RDRiskDot(level: rows[i].level)
                    Text(rows[i].text)
                        .font(.system(size: RDFontScale.size(14), weight: .medium, design: .rounded))
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
                    Text(RDLocalization.string("onboarding.onboarding.view.rapor.2841.7db67f95", table: .onboarding, fallback: "Rapor #2841")).font(.system(size: RDFontScale.size(8), design: .rounded)).foregroundStyle(Color.rdSlate)
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
                Image(systemName: "arrow.down.to.line").font(.system(size: RDFontScale.size(20), weight: .bold, design: .rounded)).foregroundStyle(.white)
            }
            .padding(.trailing, 30).padding(.bottom, 36)
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
}
