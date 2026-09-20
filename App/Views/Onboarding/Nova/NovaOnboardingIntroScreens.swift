#if DEBUG && NOVA_PILOT_BUILD
import SwiftUI

// MARK: - Splash

/// Mascot zooms out of the screen centre into its resting spot while the
/// wordmark fades in underneath — the prototype's `isgMascotZoom` +
/// `isgLogoReveal` pair, 3 s total.
struct NovaOBSplashScreen: View {
    @ObservedObject var controller: NovaOBController
    @State private var zoomed = true
    @State private var mascotOpacity: Double = 0
    @State private var logoVisible = false

    var body: some View {
        ZStack {
            NovaOB.surface.ignoresSafeArea()

            Image("NovaOBLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 220)
                .opacity(logoVisible ? 1 : 0)

            Image("NovaOBMascot")
                .resizable()
                .scaledToFit()
                .frame(width: 27.9, height: 26.7)
                .scaleEffect(zoomed ? 12.5 : 1)
                .offset(x: zoomed ? 0 : 44.55, y: zoomed ? 0 : 8.05)
                .opacity(mascotOpacity)
        }
        .task { await run() }
    }

    private func run() async {
        withAnimation(.linear(duration: 0.24)) { mascotOpacity = 1 }
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        withAnimation(.timingCurve(0.24, 0.9, 0.2, 1, duration: 1.26)) { zoomed = false }
        try? await Task.sleep(nanoseconds: 1_080_000_000)
        withAnimation(.linear(duration: 0.3)) { logoVisible = true }
        try? await Task.sleep(nanoseconds: 180_000_000)
        withAnimation(.linear(duration: 0.24)) { mascotOpacity = 0 }
        // Hold on the wordmark before handing over to the intro.
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        controller.go(.intro1)
    }
}

// MARK: - Intro 1–3

struct NovaOBIntroScreen: View {
    @ObservedObject var controller: NovaOBController
    let page: Int
    let onLogin: () -> Void

    private struct Spec {
        let background: Color
        let title: String
        let image: String
        let body: String
    }

    private static let specs: [Spec] = [
        Spec(
            background: NovaOB.intro1Bg,
            title: "Sana Özel \nİSG",
            image: "NovaOBIntro1",
            body: "Firmalarını, risk analizlerini, eğitimlerini ve günlük işlerini İSGADA ile tek bir çalışma alanında topla; her şeyi ihtiyaçlarına göre sen şekillendir."
        ),
        Spec(
            background: NovaOB.intro2Bg,
            title: "Net ve Kolay\nTakip",
            image: "NovaOBIntro2",
            body: "Risk analizlerini, eğitimlerini ve kontrol listelerini dağınık tablolar yerine tek bir düzende takip et; neyin ne zaman yapılacağını her an net şekilde gör."
        ),
        Spec(
            background: NovaOB.intro3Bg,
            title: "Senin\nÖnceliğin",
            image: "NovaOBIntro3",
            body: "Birkaç kısa soruyla çalışma alanını, kontrol listelerini ve asistan desteğini kendi deneyimine ve önceliklerine göre baştan kurgulayalım."
        )
    ]

    private var spec: Spec { Self.specs[page] }

    var body: some View {
        ZStack {
            spec.background.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                content
                footer
            }
            .padding(.horizontal, 24)
            .padding(.top, NovaOB.padTop(78))
            .padding(.bottom, NovaOB.padBottom(40))
        }
        .transition(.opacity)
    }

    private var header: some View {
        HStack {
            NovaOBDots(active: page)
            Spacer(minLength: 0)
            if page == 0 {
                Button(action: onLogin) {
                    Text("Tanıtımı geç")
                        .font(NovaOB.font(14))
                        .foregroundColor(NovaOB.slate)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 26)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 22) {
            Text(spec.title)
                .font(NovaOB.font(53, 800))
                .tracking(-1.8)
                .lineSpacing(NovaOB.lineSpacing(53, 1.06))
                .foregroundColor(Color(hex: 0x030303))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
            Image(spec.image)
                .resizable()
                .scaledToFit()
                .frame(width: 280, height: 280)
                .frame(maxWidth: .infinity)
            Spacer(minLength: 0)

            Text(spec.body)
                .font(NovaOB.font(16.5))
                .foregroundColor(NovaOB.inkSoft)
                .lineSpacing(NovaOB.lineSpacing(16.5, 1.5))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    @ViewBuilder private var footer: some View {
        HStack(alignment: .center, spacing: 20) {
            if page == 2 {
                NovaOBPillButton(title: "Devam Et", height: 57, fontSize: 16.5, fixedWidth: 203) {
                    controller.go(.social)
                }
                Spacer(minLength: 0)
                Text("Yanıtlarını\ndaha sonra değiştirebilirsin.")
                    .font(NovaOB.font(13))
                    .foregroundColor(NovaOB.slate)
                    .multilineTextAlignment(.trailing)
                    .lineSpacing(NovaOB.lineSpacing(13, 1.45))
            } else {
                NovaOBPillButton(title: "Devam et", height: 60, fontSize: 17, horizontalPadding: 40) {
                    controller.go(page == 0 ? .intro2 : .intro3)
                }
                Spacer(minLength: 0)
                if page == 0 {
                    Button(action: onLogin) {
                        (
                            Text("Hesabın var mı?\n").font(NovaOB.font(13.5)).foregroundColor(NovaOB.slate)
                            + Text("Giriş yap").font(NovaOB.font(13.5, 700)).foregroundColor(NovaOB.ink)
                        )
                        .multilineTextAlignment(.trailing)
                        .lineSpacing(NovaOB.lineSpacing(13.5, 1.45))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.top, 34)
    }
}

// MARK: - Social proof

struct NovaOBSocialProofScreen: View {
    @ObservedObject var controller: NovaOBController
    let onLogin: () -> Void

    struct Review: Identifiable {
        let id = UUID()
        let title: String
        let body: String
        let name: String
        let role: String
        let initials: String
    }

    static let reviews: [Review] = [
        .init(title: "Saha denetimi artık dakikalar sürüyor",
              body: "Eskiden Excel’de kaybolan kontrol listelerini telefondan doldurup anında rapora çeviriyorum.",
              name: "Mert Kaya", role: "A Sınıfı İSG Uzmanı", initials: "MK"),
        .init(title: "Eğitim takibi kendiliğinden işliyor",
              body: "Süresi dolan eğitimleri İSGADA hatırlatıyor; 14 firmada tek bir gecikme yaşamadım.",
              name: "Elif Yıldırım", role: "OSGB Koordinatörü", initials: "EY"),
        .init(title: "Risk analizi şablonları tam yerinde",
              body: "Sektöre göre gelen maddeler sayesinde yeni bir analiz hazırlamak yarım güne değil bir saate indi.",
              name: "Serkan Demir", role: "B Sınıfı İSG Uzmanı", initials: "SD"),
        .init(title: "Denetime hazır olmak rahatlatıcı",
              body: "Bakanlık denetiminde istenen tüm kayıtlar tek ekrandaydı; hiçbir dosya aramadım.",
              name: "Ayşe Tunç", role: "İSG Müdürü", initials: "AT"),
        .init(title: "Ekipteki herkes aynı sayfada",
              body: "Görev atadığımda sahadaki teknisyen bildirim alıyor, işin durumunu canlı görüyorum.",
              name: "Burak Şen", role: "İş Güvenliği Şefi", initials: "BŞ")
    ]

    var body: some View {
        ZStack {
            NovaOB.socialBg.ignoresSafeArea()
            VStack(spacing: 0) {
                header
                VStack(alignment: .leading, spacing: 22) {
                    headline
                    avatars
                    marquee
                }
                footer
            }
            .padding(.top, NovaOB.padTop(78))
            .padding(.bottom, NovaOB.padBottom(40))

            if controller.skipModal {
                NovaOBSkipModal(
                    onContinue: { controller.skipModal = false },
                    onSkip: { controller.skipModal = false; onLogin() }
                )
            }
        }
    }

    private var header: some View {
        HStack {
            NovaOBDots(active: 3)
            Spacer(minLength: 0)
            Button { controller.skipModal = true } label: {
                Text("Atla")
                    .font(NovaOB.font(14, 600))
                    .foregroundColor(NovaOB.slate)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 26)
    }

    private var headline: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 9) {
                Text("★")
                    .font(NovaOB.font(11, 800))
                    .foregroundColor(NovaOB.ink)
                    .frame(width: 24, height: 24)
                    .background(NovaOB.intro3Bg, in: Circle())
                Text("4000+ İş Güvenliği Uzmanının Tercihi")
                    .font(NovaOB.font(12, 700))
                    .tracking(0.24)
                    .foregroundColor(.white)
            }
            .padding(.leading, 5)
            .padding(.trailing, 14)
            .frame(height: 34)
            .background(NovaOB.ink, in: Capsule())

            Text("Sahada\nKanıtlanmış")
                .font(NovaOB.font(44, 800))
                .tracking(-1.6)
                .lineSpacing(NovaOB.lineSpacing(44, 1.06))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var avatars: some View {
        HStack(spacing: 14) {
            ZStack(alignment: .leading) {
                HStack(spacing: -12) {
                    ForEach([0x5C7F88, 0x9DB0A4, 0xC89B7B, 0x7E8AA0], id: \.self) { color in
                        Circle()
                            .fill(Color(hex: UInt32(color)))
                            .frame(width: 44, height: 44)
                            .overlay(Circle().strokeBorder(NovaOB.socialBg, lineWidth: 3))
                    }
                }
                .blur(radius: 2.4)
                .opacity(0.55)
                .offset(x: 34, y: -2)

                HStack(spacing: -14) {
                    avatar("MK", 0x3E6670)
                    avatar("EY", 0x8C5A3C)
                    avatar("SD", 0x4F6B4A)
                    avatar("AT", 0x6B5E8C)
                    avatar("4K+", 0x000000, size: 13)
                }
            }
            .frame(height: 74)

            Text("Uzmanlar\nİSGADA kullanıyor")
                .font(NovaOB.font(13, 500))
                .foregroundColor(NovaOB.inkSoft)
                .lineSpacing(NovaOB.lineSpacing(13, 1.4))
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func avatar(_ text: String, _ color: Int, size: CGFloat = 14) -> some View {
        Text(text)
            .font(NovaOB.font(size, text == "4K+" ? 800 : 700))
            .foregroundColor(.white)
            .frame(width: 46, height: 46)
            .background(Color(hex: UInt32(color)), in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.14), radius: 6, y: 4)
    }

    private var marquee: some View {
        NovaOBMarquee(reviews: Self.reviews)
            .frame(minHeight: 200)
            .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 20) {
            NovaOBPillButton(title: "Başlayalım", height: 57, fontSize: 16.5, fixedWidth: 203) {
                controller.startQuestions()
            }
            Spacer(minLength: 0)
            Text("Kurulum\n2 dakika sürer.")
                .font(NovaOB.font(13))
                .foregroundColor(NovaOB.slate)
                .multilineTextAlignment(.trailing)
                .lineSpacing(NovaOB.lineSpacing(13, 1.45))
        }
        .padding(.horizontal, 24)
        .padding(.top, 26)
    }
}

/// Continuously scrolling review rail (`isgMarquee`, 34 s linear).
private struct NovaOBMarquee: View {
    let reviews: [NovaOBSocialProofScreen.Review]
    @State private var offset: CGFloat = 0

    private var singleWidth: CGFloat { CGFloat(reviews.count) * 264 }

    var body: some View {
        // The rail is far wider than the screen; an overlay keeps that width
        // from propagating out and squeezing the rest of the column.
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomLeading) {
                HStack(spacing: 12) {
                    ForEach(Array((reviews + reviews).enumerated()), id: \.offset) { _, review in
                        card(review)
                    }
                }
                .fixedSize(horizontal: true, vertical: false)
                .padding(.leading, 24)
                .offset(x: offset)
            }
            .clipped()
            .onAppear {
                withAnimation(.linear(duration: 34).repeatForever(autoreverses: false)) {
                    offset = -singleWidth
                }
            }
    }

    private func card(_ review: NovaOBSocialProofScreen.Review) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("★★★★★")
                .font(NovaOB.font(12))
                .tracking(1.68)
                .foregroundColor(NovaOB.gold)
            Text(review.title)
                .font(NovaOB.font(15.5, 700))
                .tracking(-0.2)
                .lineSpacing(NovaOB.lineSpacing(15.5, 1.25))
                .fixedSize(horizontal: false, vertical: true)
            Text(review.body)
                .font(NovaOB.font(13))
                .foregroundColor(NovaOB.slate)
                .lineSpacing(NovaOB.lineSpacing(13, 1.45))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 9) {
                Text(review.initials)
                    .font(NovaOB.font(11.5, 700))
                    .foregroundColor(Color(hex: 0x3E6670))
                    .frame(width: 30, height: 30)
                    .background(Color(hex: 0xEDF3F2), in: Circle())
                VStack(alignment: .leading, spacing: 0) {
                    Text(review.name).font(NovaOB.font(12.5, 700))
                    Text(review.role).font(NovaOB.font(11)).foregroundColor(NovaOB.slate)
                }
            }
            .padding(.top, 2)
        }
        .padding(18)
        .frame(width: 252, alignment: .leading)
        .background(NovaOB.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: Color(hex: 0x142832).opacity(0.08), radius: 11, y: 8)
    }
}

/// "Bu adımı atlamak istiyor musun?" — blurred scrim plus a centred card.
struct NovaOBSkipModal: View {
    let onContinue: () -> Void
    let onSkip: () -> Void
    @State private var shown = false

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .overlay(Color(hex: 0x0E161C).opacity(0.42))
                .ignoresSafeArea()
                .onTapGesture(perform: onContinue)

            VStack(spacing: 14) {
                Image("NovaOBSkipWarning")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 168, height: 168)
                    .padding(.top, -6)
                    .padding(.bottom, -8)

                Text("Bu adımı atlamak istiyor musun?")
                    .font(NovaOB.font(21, 800))
                    .tracking(-0.4)
                    .multilineTextAlignment(.center)
                    .lineSpacing(NovaOB.lineSpacing(21, 1.2))
                    .fixedSize(horizontal: false, vertical: true)

                Text("Soruları yanıtlamazsan sana özel risk analizi önerileri, eğitim takvimi ve hatırlatmaları hazırlayamayız. Uygulama içinde her şeyi tek tek kendin kurman gerekir.")
                    .font(NovaOB.font(14.5))
                    .foregroundColor(NovaOB.slate)
                    .multilineTextAlignment(.center)
                    .lineSpacing(NovaOB.lineSpacing(14.5, 1.5))
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: 9) {
                    Button(action: onContinue) {
                        HStack(spacing: 9) {
                            NovaOBIconPath(
                                path: "circle:12,12,9.2|M8.4 14.2c.8 1.3 2.1 2 3.6 2s2.8-.7 3.6-2|M9 9.6h.01|M15 9.6h.01",
                                size: 19, color: .white, lineWidth: 1.9
                            )
                            Text("Devam et").font(NovaOB.font(16.5, 700)).foregroundColor(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(NovaOB.ink, in: Capsule())
                    }
                    .buttonStyle(.plain)

                    Button(action: onSkip) {
                        HStack(spacing: 8) {
                            NovaOBIconPath(
                                path: "circle:12,12,9.2|M8.4 16c.8-1.3 2.1-2 3.6-2s2.8.7 3.6 2|M9 9.6h.01|M15 9.6h.01",
                                size: 17, color: Color(hex: 0x5A6A6E), lineWidth: 1.9
                            )
                            Text("Yine de atla").font(NovaOB.font(15, 600)).foregroundColor(NovaOB.slate)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .padding(22)
            .frame(maxWidth: 320)
            .background(NovaOB.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: Color(hex: 0x0E161C).opacity(0.28), radius: 30, y: 22)
            .padding(.horizontal, 24)
            .scaleEffect(shown ? 1 : 0.6)
            .opacity(shown ? 1 : 0)
        }
        .onAppear {
            withAnimation(.timingCurve(0.2, 0.85, 0.25, 1, duration: 0.3)) { shown = true }
        }
    }
}
#endif
