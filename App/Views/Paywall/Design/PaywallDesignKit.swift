import SwiftUI

// Claude Design → SwiftUI birebir port.
// Kaynak: Claude Design plan-toggle ve PRO dosyaları (393×852 çerçeve).
// CSS px değerleri 1:1 SwiftUI pt olarak korunur; ekran güvenli alanları yok sayılır
// çünkü tasarım çerçevesinde durum çubuğu ve home indicator içeriğin üstüne biner.

// MARK: - Palet

enum PaywallDesignColor {
    static let ink = Color(hex: "16232E")
    static let muted = Color(hex: "8A94A6")
    static let orange = Color(hex: "FF9500")
    static let orangeSoft = Color(hex: "FF9500").opacity(0.55)
    static let idleMark = Color(hex: "C7CDD6")
    static let idleRail = Color(hex: "D9DEE5")
    static let cardBorder = Color(hex: "E5E7EB")
    static let orangeCardBg = Color(hex: "FFF7ED")
    static let green = Color(hex: "1FAA59")
    static let greenCardBg = Color(hex: "F0FAF4")
    static let amber = Color(hex: "FFB800")
    static let amberCardBg = Color(hex: "FFFAEB")
    static let amberInk = Color(hex: "B8860B")
    static let footer = Color(hex: "9AA3B2")
    static let ruleStrong = Color(hex: "EEEEEE")
    static let rule = Color(hex: "F2F2F2")
    /// Kayan özellik şeridi etiketleri: vurgu rengi göz yorduğu için nötr gri zemin.
    static let chipBg = Color(hex: "F4F5F7")
    static let chipBorder = Color(hex: "E3E6EB")
}

// MARK: - Ölçüler

enum PaywallDesignMetric {
    static let screenPadding: CGFloat = 20
    static let heroHeight: CGFloat = 300
    static let heroImageTop: CGFloat = 44
    /// half-face.png → 1448 × 1086
    static let heroImageAspect: CGFloat = 1448.0 / 1086.0
    static let socialProofBox = CGSize(width: 188, height: 56)
    /// social-proof.png → 1672 × 941
    static let socialProofImageWidth: CGFloat = 198.4
    static let socialProofImageAspect: CGFloat = 1672.0 / 941.0
    static let markColumnWidth: CGFloat = 52
    static let cardRadius: CGFloat = 16
}

/// CSS `line-height` bloğunu birebir taklit eder: satır aralığını büyütür ve
/// artan boşluğun yarısını üstte/altta bırakır (half-leading).
private struct PaywallDesignLineHeight: ViewModifier {
    let fontSize: CGFloat
    let multiple: CGFloat

    func body(content: Content) -> some View {
        let systemLineHeight = UIFont.systemFont(ofSize: fontSize).lineHeight
        let extra = max(0, fontSize * multiple - systemLineHeight)
        return content
            .lineSpacing(extra)
            .padding(.vertical, extra / 2)
    }
}

private extension View {
    func designLineHeight(_ fontSize: CGFloat, multiple: CGFloat = 1.4) -> some View {
        modifier(PaywallDesignLineHeight(fontSize: fontSize, multiple: multiple))
    }
}

// MARK: - Vektör ikonlar (SVG path'lerin birebir karşılığı)

struct PaywallDesignVector: Shape {
    var viewBox: CGSize
    var build: @Sendable (inout Path) -> Void

    func path(in rect: CGRect) -> Path {
        var path = Path()
        build(&path)
        let transform = CGAffineTransform(
            scaleX: rect.width / viewBox.width,
            y: rect.height / viewBox.height
        )
        return path.applying(transform).offsetBy(dx: rect.minX, dy: rect.minY)
    }
}

private func paywallStrokeScale(_ viewBox: CGSize, _ size: CGSize) -> CGFloat {
    sqrt((size.width / viewBox.width) * (size.height / viewBox.height))
}

/// Tik işareti — viewBox 15×12
struct PaywallDesignCheckIcon: View {
    var size: CGSize
    var lineWidth: CGFloat
    var color: Color

    private let viewBox = CGSize(width: 15, height: 12)

    var body: some View {
        PaywallDesignVector(viewBox: viewBox) { path in
            path.move(to: CGPoint(x: 1, y: 6))
            path.addLine(to: CGPoint(x: 5.5, y: 10.5))
            path.addLine(to: CGPoint(x: 14, y: 1))
        }
        .stroke(
            color,
            style: StrokeStyle(
                lineWidth: lineWidth * paywallStrokeScale(viewBox, size),
                lineCap: .round,
                lineJoin: .round
            )
        )
        .frame(width: size.width, height: size.height)
    }
}

/// Çarpı — viewBox `side`×`side`, path 1..(side - 1)
struct PaywallDesignCrossIcon: View {
    var size: CGSize
    var viewBoxSide: CGFloat
    var lineWidth: CGFloat
    var color: Color

    var body: some View {
        let viewBox = CGSize(width: viewBoxSide, height: viewBoxSide)
        let far = viewBoxSide - 1
        return PaywallDesignVector(viewBox: viewBox) { path in
            path.move(to: CGPoint(x: 1, y: 1))
            path.addLine(to: CGPoint(x: far, y: far))
            path.move(to: CGPoint(x: far, y: 1))
            path.addLine(to: CGPoint(x: 1, y: far))
        }
        .stroke(
            color,
            style: StrokeStyle(
                lineWidth: lineWidth * paywallStrokeScale(viewBox, size),
                lineCap: .round
            )
        )
        .frame(width: size.width, height: size.height)
    }
}

/// Zil — viewBox 14×15
struct PaywallDesignBellIcon: View {
    var size = CGSize(width: 14, height: 15)
    var color: Color = .white

    private let viewBox = CGSize(width: 14, height: 15)

    var body: some View {
        let scale = paywallStrokeScale(viewBox, size)
        return ZStack {
            PaywallDesignVector(viewBox: viewBox) { path in
                path.move(to: CGPoint(x: 7, y: 1))
                path.addCurve(
                    to: CGPoint(x: 3, y: 5.2),
                    control1: CGPoint(x: 4.5, y: 1),
                    control2: CGPoint(x: 3, y: 2.8)
                )
                path.addLine(to: CGPoint(x: 3, y: 7.5))
                path.addLine(to: CGPoint(x: 1.5, y: 10))
                path.addLine(to: CGPoint(x: 12.5, y: 10))
                path.addLine(to: CGPoint(x: 11, y: 7.5))
                path.addLine(to: CGPoint(x: 11, y: 5.2))
                path.addCurve(
                    to: CGPoint(x: 7, y: 1),
                    control1: CGPoint(x: 11, y: 2.8),
                    control2: CGPoint(x: 9.5, y: 1)
                )
                path.closeSubpath()
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.4 * scale, lineJoin: .round))

            PaywallDesignVector(viewBox: viewBox) { path in
                path.addArc(
                    center: CGPoint(x: 7, y: 12.5),
                    radius: 1.7,
                    startAngle: .degrees(0),
                    endAngle: .degrees(180),
                    clockwise: false
                )
            }
            .stroke(color, style: StrokeStyle(lineWidth: 1.4 * scale, lineCap: .round))
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Kart — viewBox 15×12
struct PaywallDesignCardIcon: View {
    var size = CGSize(width: 15, height: 12)
    var color: Color = .white

    private let viewBox = CGSize(width: 15, height: 12)

    var body: some View {
        let scale = paywallStrokeScale(viewBox, size)
        return ZStack {
            PaywallDesignVector(viewBox: viewBox) { path in
                path.addRoundedRect(
                    in: CGRect(x: 1, y: 1, width: 13, height: 10),
                    cornerSize: CGSize(width: 1.5, height: 1.5)
                )
            }
            .stroke(color, lineWidth: 1.4 * scale)

            PaywallDesignVector(viewBox: viewBox) { path in
                path.addRect(CGRect(x: 1, y: 3.4, width: 13, height: 2))
            }
            .fill(color)
        }
        .frame(width: size.width, height: size.height)
    }
}

/// Yıldız — viewBox 24×24, dolu
struct PaywallDesignStarIcon: View {
    var size = CGSize(width: 18, height: 18)
    var color: Color

    var body: some View {
        PaywallDesignVector(viewBox: CGSize(width: 24, height: 24)) { path in
            path.move(to: CGPoint(x: 12, y: 2))
            path.addLine(to: CGPoint(x: 15.09, y: 8.26))
            path.addLine(to: CGPoint(x: 22, y: 9.27))
            path.addLine(to: CGPoint(x: 17, y: 14.14))
            path.addLine(to: CGPoint(x: 18.18, y: 21.02))
            path.addLine(to: CGPoint(x: 12, y: 17.77))
            path.addLine(to: CGPoint(x: 5.82, y: 21.02))
            path.addLine(to: CGPoint(x: 7, y: 14.14))
            path.addLine(to: CGPoint(x: 2, y: 9.27))
            path.addLine(to: CGPoint(x: 8.91, y: 8.26))
            path.closeSubpath()
        }
        .fill(color)
        .frame(width: size.width, height: size.height)
    }
}

/// Taç — viewBox 24×20, dolu
struct PaywallDesignCrownIcon: View {
    var size = CGSize(width: 20, height: 18)
    var color: Color

    var body: some View {
        PaywallDesignVector(viewBox: CGSize(width: 24, height: 20)) { path in
            path.move(to: CGPoint(x: 2, y: 6))
            path.addLine(to: CGPoint(x: 6.5, y: 9))
            path.addLine(to: CGPoint(x: 12, y: 2))
            path.addLine(to: CGPoint(x: 17.5, y: 9))
            path.addLine(to: CGPoint(x: 22, y: 6))
            path.addLine(to: CGPoint(x: 20, y: 18))
            path.addLine(to: CGPoint(x: 4, y: 18))
            path.closeSubpath()
        }
        .fill(color)
        .frame(width: size.width, height: size.height)
    }
}

/// Chevron — viewBox 8×14
struct PaywallDesignChevronIcon: View {
    var size = CGSize(width: 8, height: 14)
    var color: Color

    private let viewBox = CGSize(width: 8, height: 14)

    var body: some View {
        PaywallDesignVector(viewBox: viewBox) { path in
            path.move(to: CGPoint(x: 1, y: 1))
            path.addLine(to: CGPoint(x: 7, y: 7))
            path.addLine(to: CGPoint(x: 1, y: 13))
        }
        .stroke(
            color,
            style: StrokeStyle(
                lineWidth: 2 * paywallStrokeScale(viewBox, size),
                lineCap: .round,
                lineJoin: .round
            )
        )
        .frame(width: size.width, height: size.height)
    }
}

/// Dolu daire içinde tik (karşılaştırma tablosu + zaman çizelgesi rozeti)
struct PaywallDesignCheckBadge: View {
    var diameter: CGFloat
    var checkSize: CGSize
    var checkLineWidth: CGFloat
    var background: Color

    var body: some View {
        Circle()
            .fill(background)
            .frame(width: diameter, height: diameter)
            .overlay(
                PaywallDesignCheckIcon(size: checkSize, lineWidth: checkLineWidth, color: .white)
            )
    }
}

// MARK: - Hero

struct PaywallDesignHero: View {
    var label: String
    var onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            Color.white

            Image("PaywallHeroFace")
                .resizable()
                .aspectRatio(PaywallDesignMetric.heroImageAspect, contentMode: .fit)
                .frame(maxWidth: .infinity)
                .offset(y: PaywallDesignMetric.heroImageTop)

            LinearGradient(
                colors: [Color.white.opacity(0.85), Color.white.opacity(0)],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .offset(y: PaywallDesignMetric.heroImageTop)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LinearGradient(
                    colors: [Color.white.opacity(0), Color.white],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 34)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                Text(label)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundColor(PaywallDesignColor.ink)
                    .padding(.vertical, 5)
                    .padding(.horizontal, 14)
                    .background(Capsule().fill(Color.white.opacity(0.78)))
                    .padding(.bottom, 10)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Button(action: onClose) {
                        Circle()
                            .fill(Color.white.opacity(0.6))
                            .frame(width: 32, height: 32)
                            .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                            .overlay(
                                PaywallDesignCrossIcon(
                                    size: CGSize(width: 13, height: 13),
                                    viewBoxSide: 13,
                                    lineWidth: 1.8,
                                    color: PaywallDesignColor.ink
                                )
                            )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(RDLocalization.string("paywall.in.app.paywall.view.paywall.ekranini.kapat.92144bcc", table: .paywall, fallback: "Paywall ekranını kapat"))
                    .padding(.trailing, 16)
                }
                .padding(.top, 56)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: PaywallDesignMetric.heroHeight, alignment: .topLeading)
        .clipped()
    }
}

// MARK: - Sosyal kanıt

struct PaywallDesignSocialProof: View {
    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            Image("PaywallSocialProof")
                .resizable()
                .frame(
                    width: PaywallDesignMetric.socialProofImageWidth,
                    height: PaywallDesignMetric.socialProofImageWidth / PaywallDesignMetric.socialProofImageAspect
                )
                .offset(x: -5.7, y: -24.2)
                .frame(
                    width: PaywallDesignMetric.socialProofBox.width,
                    height: PaywallDesignMetric.socialProofBox.height,
                    alignment: .topLeading
                )
                .clipped()
                .accessibilityLabel(RDLocalization.string("paywall.design.social_proof.accessibility", table: .paywall, fallback: "10.000+ kullanıcı, İSG uzmanlarının tercihi"))
            Spacer(minLength: 0)
        }
        .padding(.top, 6)
        .padding(.horizontal, PaywallDesignMetric.screenPadding)
    }
}

// MARK: - Ücretsiz deneme zaman çizelgesi

struct PaywallDesignTrialTimeline: View {
    /// Deneme gün sayısı App Store teklifinden gelir (ör. 7).
    var trialDays: Int
    /// Aktif paket adı (PLUS / PRO); bugün satırındaki erişim cümlesinde kullanılır.
    var tierName: String
    /// Paket vurgu rengi; bugün satırındaki taç ikonu ve paket adı bu renkle çizilir.
    var accent: Color

    private var reminderDay: Int { max(1, trialDays - 2) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                rail(circleColor: PaywallDesignColor.orange, railColor: PaywallDesignColor.orange) {
                    PaywallDesignCheckIcon(
                        size: CGSize(width: 13, height: 10.5),
                        lineWidth: 2,
                        color: .white
                    )
                }
                // Diğer basamaklarla aynı biçim: başlık üstte, açıklama altında.
                todayStep
                    // Bağlantı çizgisinin görünmesi için diğer satırlarla eşit yükseklik.
                    .padding(.bottom, 22)
            }

            HStack(alignment: .top, spacing: 12) {
                rail(circleColor: PaywallDesignColor.idleMark, railColor: PaywallDesignColor.idleRail) {
                    PaywallDesignBellIcon(size: CGSize(width: 12.5, height: 13.5))
                }
                step(
                    title: dayTitle(reminderDay),
                    detail: RDLocalization.string(
                        "paywall.design.timeline.reminder.detail",
                        table: .paywall,
                        fallback: "Deneme süreniz bitmeden size hatırlatacağız"
                    )
                )
                .padding(.bottom, 22)
            }

            HStack(alignment: .top, spacing: 12) {
                rail(circleColor: PaywallDesignColor.idleMark, railColor: nil) {
                    PaywallDesignCardIcon(size: CGSize(width: 13, height: 10.5))
                }
                step(
                    title: dayTitle(trialDays),
                    detail: RDLocalization.string(
                        "paywall.design.timeline.billing.detail",
                        table: .paywall,
                        fallback: "Aboneliğiniz başlar. İstediğiniz zaman iptal edebilirsiniz."
                    )
                )
            }
        }
        .padding(.top, 16)
        .padding(.horizontal, PaywallDesignMetric.screenPadding)
        .accessibilityIdentifier("in_app_paywall.trial_timeline")
    }

    private func dayTitle(_ day: Int) -> String {
        RDLocalization.format(
            "paywall.design.timeline.day_format",
            table: .paywall,
            fallback: "%1$@. Gün",
            arguments: [String(day)]
        )
    }

    private var todayTitle: String {
        RDLocalization.string("paywall.design.timeline.today.title", table: .paywall, fallback: "Bugün")
    }

    private var todayDetail: String {
        RDLocalization.format(
            "paywall.design.timeline.today.detail_format",
            table: .paywall,
            fallback: "Tüm %1$@ özelliklerine anında erişim kazanın",
            arguments: [tierName]
        )
    }

    /// Bugün satırı: açıklamanın başında taç ikonu, paket adı vurgu renginde.
    private var todayStep: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(todayTitle)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundColor(PaywallDesignColor.ink)
            todayDetailText
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Paket adı cümlenin içinde geçtiği yerde vurgulanır; çeviri sırası değişse de
    /// yer tutucunun karşılığı aranarak bulunur, sabit bir ön/son ek varsayılmaz.
    private var todayDetailText: Text {
        let detail = todayDetail
        let body = Font.system(size: 12.5)
        guard let range = detail.range(of: tierName) else {
            return Text(detail).font(body).foregroundColor(PaywallDesignColor.muted)
        }
        // Taç paket adının hemen soluna, metnin içine yerleşir: satır kaydığında
        // ikon da adla birlikte taşınır. Satır içi görsel için sistem sembolü
        // kullanılıyor; `Text` yalnızca `Image` kabul eder, çizilen vektörü değil.
        let crown = Text(Image(systemName: "crown.fill"))
            .font(.system(size: 10.5))
            .foregroundColor(accent)
        return Text(String(detail[detail.startIndex..<range.lowerBound]))
            .font(body)
            .foregroundColor(PaywallDesignColor.muted)
            + crown
            + Text(" ")
            + Text(tierName)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundColor(accent)
            + Text(String(detail[range.upperBound...]))
                .font(body)
                .foregroundColor(PaywallDesignColor.muted)
    }

    private func step(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundColor(PaywallDesignColor.ink)
            Text(detail)
                .font(.system(size: 12.5))
                .foregroundColor(PaywallDesignColor.muted)
                .designLineHeight(12.5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func rail<Icon: View>(
        circleColor: Color,
        railColor: Color?,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        VStack(spacing: 0) {
            Circle()
                .fill(circleColor)
                .frame(width: 28, height: 28)
                .overlay(icon())
            if let railColor {
                Rectangle()
                    .fill(railColor)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 3)
            }
        }
        .frame(width: 28)
    }
}

// MARK: - Şerit ikonları

/// Şerit etiketlerinin çizgisel ikonları. Hepsi 20×20 viewBox üzerine çizilir ve
/// yalnızca kontur olarak boyanır — tasarım kararı: içi dolu ikon yok.
enum PaywallDesignFeatureGlyph: String, Equatable, Sendable {
    /// Kalkan + tik — risk analizi
    case shield
    /// Sütun grafik — detaylı analiz
    case chart
    /// Üst üste iki kare + ufuk çizgisi — çoklu fotoğraf
    case photos
    /// Bina — firma yönetimi
    case building
    /// Gösterge kadranı — Fine-Kinney risk puanlaması
    case gauge
    /// Izgara — 5x5 matris
    case grid
    /// Büyüteç — derin araştırma
    case magnifier
    /// Ayar sürgüleri — rapor özelleştirme
    case sliders
    /// Kapaklı kutu — arşiv yönetimi
    case archive
    /// Kişi + tik — sorumlu atama
    case assignee
    /// Nişangâh — odaklı analiz
    case target
}

/// Şerit etiketi: metin ve ona ait ikon birlikte taşınır; ikon seçimi çeviriye değil
/// içerik tanımına bağlıdır (bkz. `PaywallDesignCopy.timelineFeatures`).
struct PaywallDesignFeature: Equatable, Identifiable, Sendable {
    var title: String
    var glyph: PaywallDesignFeatureGlyph

    var id: String { title }
}

struct PaywallDesignFeatureIcon: View {
    var glyph: PaywallDesignFeatureGlyph
    var size: CGFloat
    var color: Color
    var lineWidth: CGFloat = 1.5

    private let viewBox = CGSize(width: 20, height: 20)

    var body: some View {
        PaywallDesignVector(viewBox: viewBox) { path in
            switch glyph {
            case .shield: PaywallDesignFeatureIcon.shield(&path)
            case .chart: PaywallDesignFeatureIcon.chart(&path)
            case .photos: PaywallDesignFeatureIcon.photos(&path)
            case .building: PaywallDesignFeatureIcon.building(&path)
            case .gauge: PaywallDesignFeatureIcon.gauge(&path)
            case .grid: PaywallDesignFeatureIcon.grid(&path)
            case .magnifier: PaywallDesignFeatureIcon.magnifier(&path)
            case .sliders: PaywallDesignFeatureIcon.sliders(&path)
            case .archive: PaywallDesignFeatureIcon.archive(&path)
            case .assignee: PaywallDesignFeatureIcon.assignee(&path)
            case .target: PaywallDesignFeatureIcon.target(&path)
            }
        }
        .stroke(
            color,
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
        .frame(width: size, height: size)
    }

    private static func shield(_ path: inout Path) {
        path.move(to: CGPoint(x: 10, y: 2.4))
        path.addLine(to: CGPoint(x: 16.4, y: 5))
        path.addLine(to: CGPoint(x: 16.4, y: 9.8))
        path.addQuadCurve(to: CGPoint(x: 10, y: 17.6), control: CGPoint(x: 16.4, y: 14.8))
        path.addQuadCurve(to: CGPoint(x: 3.6, y: 9.8), control: CGPoint(x: 3.6, y: 14.8))
        path.addLine(to: CGPoint(x: 3.6, y: 5))
        path.closeSubpath()
        path.move(to: CGPoint(x: 7.3, y: 9.9))
        path.addLine(to: CGPoint(x: 9.3, y: 11.9))
        path.addLine(to: CGPoint(x: 12.8, y: 8))
    }

    private static func chart(_ path: inout Path) {
        path.move(to: CGPoint(x: 3.4, y: 3))
        path.addLine(to: CGPoint(x: 3.4, y: 16.4))
        path.addLine(to: CGPoint(x: 16.8, y: 16.4))
        path.move(to: CGPoint(x: 7, y: 16.4))
        path.addLine(to: CGPoint(x: 7, y: 11.6))
        path.move(to: CGPoint(x: 10.6, y: 16.4))
        path.addLine(to: CGPoint(x: 10.6, y: 8.4))
        path.move(to: CGPoint(x: 14.2, y: 16.4))
        path.addLine(to: CGPoint(x: 14.2, y: 5.2))
    }

    private static func photos(_ path: inout Path) {
        path.addRoundedRect(
            in: CGRect(x: 6.6, y: 2.4, width: 11, height: 11),
            cornerSize: CGSize(width: 2.4, height: 2.4)
        )
        path.addRoundedRect(
            in: CGRect(x: 2.4, y: 6.6, width: 11, height: 11),
            cornerSize: CGSize(width: 2.4, height: 2.4)
        )
        path.addEllipse(in: CGRect(x: 4.5, y: 8.7, width: 2.2, height: 2.2))
        path.move(to: CGPoint(x: 3.2, y: 15.4))
        path.addLine(to: CGPoint(x: 6.6, y: 11.8))
        path.addLine(to: CGPoint(x: 9.2, y: 14.4))
        path.addLine(to: CGPoint(x: 10.8, y: 12.9))
        path.addLine(to: CGPoint(x: 12.9, y: 15))
    }

    private static func building(_ path: inout Path) {
        path.move(to: CGPoint(x: 4, y: 17))
        path.addLine(to: CGPoint(x: 4, y: 3.4))
        path.addLine(to: CGPoint(x: 12.2, y: 3.4))
        path.addLine(to: CGPoint(x: 12.2, y: 17))
        path.move(to: CGPoint(x: 12.2, y: 8.6))
        path.addLine(to: CGPoint(x: 16.4, y: 8.6))
        path.addLine(to: CGPoint(x: 16.4, y: 17))
        path.move(to: CGPoint(x: 2.6, y: 17))
        path.addLine(to: CGPoint(x: 17.6, y: 17))
        path.move(to: CGPoint(x: 6.7, y: 6.6))
        path.addLine(to: CGPoint(x: 9.5, y: 6.6))
        path.move(to: CGPoint(x: 6.7, y: 9.8))
        path.addLine(to: CGPoint(x: 9.5, y: 9.8))
        path.move(to: CGPoint(x: 6.7, y: 13))
        path.addLine(to: CGPoint(x: 9.5, y: 13))
        path.move(to: CGPoint(x: 14, y: 11.6))
        path.addLine(to: CGPoint(x: 14.8, y: 11.6))
        path.move(to: CGPoint(x: 14, y: 14.2))
        path.addLine(to: CGPoint(x: 14.8, y: 14.2))
    }

    private static func gauge(_ path: inout Path) {
        path.addArc(
            center: CGPoint(x: 10, y: 13.2),
            radius: 6.8,
            startAngle: .degrees(180),
            endAngle: .degrees(0),
            clockwise: false
        )
        // İbre: sağ üst çeyreğe bakar (yüksek risk skoru okuması).
        path.move(to: CGPoint(x: 9.4, y: 13.6))
        path.addLine(to: CGPoint(x: 14.2, y: 8.2))
        path.move(to: CGPoint(x: 3.2, y: 15.6))
        path.addLine(to: CGPoint(x: 16.8, y: 15.6))
    }

    private static func grid(_ path: inout Path) {
        path.addRoundedRect(
            in: CGRect(x: 2.8, y: 2.8, width: 14.4, height: 14.4),
            cornerSize: CGSize(width: 2.4, height: 2.4)
        )
        for offset in [7.6, 12.4] {
            path.move(to: CGPoint(x: offset, y: 2.8))
            path.addLine(to: CGPoint(x: offset, y: 17.2))
            path.move(to: CGPoint(x: 2.8, y: offset))
            path.addLine(to: CGPoint(x: 17.2, y: offset))
        }
    }

    private static func magnifier(_ path: inout Path) {
        path.addEllipse(in: CGRect(x: 3, y: 3, width: 11.2, height: 11.2))
        path.move(to: CGPoint(x: 12.6, y: 12.6))
        path.addLine(to: CGPoint(x: 17.2, y: 17.2))
    }

    private static func sliders(_ path: inout Path) {
        let rows: [(y: CGFloat, knob: CGFloat)] = [(5.6, 13.2), (10, 7.2), (14.4, 14)]
        for row in rows {
            path.move(to: CGPoint(x: 3, y: row.y))
            path.addLine(to: CGPoint(x: 17, y: row.y))
            path.addEllipse(
                in: CGRect(x: row.knob - 1.8, y: row.y - 1.8, width: 3.6, height: 3.6)
            )
        }
    }

    private static func archive(_ path: inout Path) {
        path.addRoundedRect(
            in: CGRect(x: 2.6, y: 3.2, width: 14.8, height: 4),
            cornerSize: CGSize(width: 1.2, height: 1.2)
        )
        path.move(to: CGPoint(x: 4.2, y: 7.2))
        path.addLine(to: CGPoint(x: 4.2, y: 15))
        path.addQuadCurve(to: CGPoint(x: 5.8, y: 16.6), control: CGPoint(x: 4.2, y: 16.6))
        path.addLine(to: CGPoint(x: 14.2, y: 16.6))
        path.addQuadCurve(to: CGPoint(x: 15.8, y: 15), control: CGPoint(x: 15.8, y: 16.6))
        path.addLine(to: CGPoint(x: 15.8, y: 7.2))
        path.move(to: CGPoint(x: 8, y: 10.6))
        path.addLine(to: CGPoint(x: 12, y: 10.6))
    }

    private static func assignee(_ path: inout Path) {
        path.addEllipse(in: CGRect(x: 5.2, y: 3.4, width: 6.4, height: 6.4))
        path.move(to: CGPoint(x: 2.2, y: 17))
        path.addQuadCurve(to: CGPoint(x: 12.2, y: 17), control: CGPoint(x: 7.2, y: 11))
        path.move(to: CGPoint(x: 13.4, y: 11.4))
        path.addLine(to: CGPoint(x: 15.1, y: 13.1))
        path.addLine(to: CGPoint(x: 18.4, y: 9.4))
    }

    private static func target(_ path: inout Path) {
        path.addEllipse(in: CGRect(x: 3.4, y: 3.4, width: 13.2, height: 13.2))
        path.addEllipse(in: CGRect(x: 7.6, y: 7.6, width: 4.8, height: 4.8))
        path.move(to: CGPoint(x: 10, y: 1.2))
        path.addLine(to: CGPoint(x: 10, y: 3.2))
        path.move(to: CGPoint(x: 10, y: 16.8))
        path.addLine(to: CGPoint(x: 10, y: 18.8))
        path.move(to: CGPoint(x: 1.2, y: 10))
        path.addLine(to: CGPoint(x: 3.2, y: 10))
        path.move(to: CGPoint(x: 16.8, y: 10))
        path.addLine(to: CGPoint(x: 18.8, y: 10))
    }
}

// MARK: - Kayan özellik şeridi

private struct PaywallDesignMarqueeWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

/// Zaman çizelgesinin altındaki sürekli sola kayan özellik etiketleri.
/// Şerit iki özdeş kopyadan oluşur; ilk kopya tam genişliği kadar kayınca
/// başa döner, böylece dikiş yeri görünmeden sonsuz akar.
struct PaywallDesignFeatureMarquee: View {
    var features: [PaywallDesignFeature]
    var accent: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var rowWidth: CGFloat = 0
    @State private var rowHeight: CGFloat = 31
    @State private var offset: CGFloat = 0

    private let spacing: CGFloat = 8
    /// Saniyede ~34pt: okunacak kadar yavaş, duruyor izlenimi vermeyecek kadar canlı.
    private var duration: Double { max(6, Double(rowWidth + spacing) / 34) }

    var body: some View {
        // Kaydırılan içerik `overlay` içinde durur: ekrandan geniş olduğu için doğrudan
        // yerleştirilseydi kendi genişliğini ebeveyne dayatır ve tüm sayfayı yana kaydırırdı.
        // `Color.clear` ölçüyü verir, overlay yalnızca çizer.
        Color.clear
            .frame(height: rowHeight)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .leading) {
                HStack(spacing: spacing) {
                    row
                        .background(
                            GeometryReader { geometry in
                                Color.clear.preference(
                                    key: PaywallDesignMarqueeWidthKey.self,
                                    value: geometry.size.width
                                )
                            }
                        )
                    // İkinci kopya yalnızca görsel süreklilik için; ekran okuyucu tekrar etmesin.
                    row.accessibilityHidden(true)
                }
                .offset(x: offset)
                .fixedSize()
            }
            .clipped()
            .padding(.top, 12)
            .onPreferenceChange(PaywallDesignMarqueeWidthKey.self) { width in
                guard width > 0, abs(width - rowWidth) > 0.5 else { return }
                rowWidth = width
                restartAnimation()
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("in_app_paywall.feature_marquee")
    }

    private var row: some View {
        HStack(spacing: spacing) {
            ForEach(features) { feature in
                chip(feature)
            }
        }
    }

    private func chip(_ feature: PaywallDesignFeature) -> some View {
        HStack(spacing: 6) {
            PaywallDesignFeatureIcon(glyph: feature.glyph, size: 15, color: accent)
            Text(feature.title)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundColor(PaywallDesignColor.ink)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.vertical, 7)
        .padding(.horizontal, 12)
        .background(
            GeometryReader { geometry in
                Capsule()
                    .fill(PaywallDesignColor.chipBg)
                    .onAppear { rowHeight = max(rowHeight, geometry.size.height) }
            }
        )
        .overlay(
            Capsule().strokeBorder(PaywallDesignColor.chipBorder, lineWidth: 1)
        )
    }

    private func restartAnimation() {
        // Hareket azaltma açıksa şerit sabit kalır; içerik yine tamamen okunur.
        guard !reduceMotion else {
            offset = 0
            return
        }
        offset = 0
        withAnimation(.linear(duration: duration).repeatForever(autoreverses: false)) {
            offset = -(rowWidth + spacing)
        }
    }
}

// MARK: - Karşılaştırma tablosu

enum PaywallDesignMark: Equatable {
    case cross
    case check(Color)
    case text(String, Color)
}

struct PaywallDesignComparisonRow: Equatable {
    let title: String
    let left: PaywallDesignMark
    let right: PaywallDesignMark

    init(title: String, left: PaywallDesignMark, right: PaywallDesignMark) {
        self.title = title
        self.left = left
        self.right = right
    }
}

struct PaywallDesignComparisonTable: View {
    /// Sütun başlığında paket adının solunda duran işaret.
    enum Emblem: Equatable {
        case none
        case crown
        case star
    }

    struct Column {
        let title: String
        let color: Color
        let weight: Font.Weight
        var emblem: Emblem = .none
    }

    var left: Column
    var right: Column
    var rows: [PaywallDesignComparisonRow]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                header(left)
                header(right)
            }
            .padding(.bottom, 10)

            Rectangle()
                .fill(PaywallDesignColor.ruleStrong)
                .frame(height: 1)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                HStack(spacing: 0) {
                    Text(row.title)
                        .font(.system(size: 13.5))
                        .foregroundColor(PaywallDesignColor.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    mark(row.left)
                    mark(row.right)
                }
                .padding(.vertical, 6)

                if index < rows.count - 1 {
                    Rectangle()
                        .fill(PaywallDesignColor.rule)
                        .frame(height: 1)
                }
            }
        }
        .padding(.top, 16)
        .padding(.horizontal, PaywallDesignMetric.screenPadding)
    }

    private func header(_ column: Column) -> some View {
        HStack(spacing: 3) {
            switch column.emblem {
            case .none:
                EmptyView()
            case .crown:
                PaywallDesignCrownIcon(
                    size: CGSize(width: 11, height: 9.9),
                    color: PaywallDesignColor.orange
                )
            case .star:
                PaywallDesignStarIcon(
                    size: CGSize(width: 10.5, height: 10.5),
                    color: PaywallDesignColor.green
                )
            }
            Text(column.title)
                .font(.system(size: 12, weight: column.weight))
                .foregroundColor(column.color)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .frame(width: PaywallDesignMetric.markColumnWidth)
    }

    @ViewBuilder
    private func mark(_ mark: PaywallDesignMark) -> some View {
        Group {
            switch mark {
            case .cross:
                PaywallDesignCrossIcon(
                    size: CGSize(width: 10, height: 10),
                    viewBoxSide: 12,
                    lineWidth: 1.8,
                    color: PaywallDesignColor.idleMark
                )
            case let .check(color):
                PaywallDesignCheckBadge(
                    diameter: 15,
                    checkSize: CGSize(width: 7, height: 6),
                    checkLineWidth: 2.4,
                    background: color
                )
            case let .text(value, color):
                Text(value)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .frame(width: PaywallDesignMetric.markColumnWidth)
    }
}

// MARK: - Plan kartları

struct PaywallDesignPlanCard: View {
    var title: String
    var price: String
    var caption: String
    var trialNote: String?
    var badge: (label: String, discount: String)?
    var accent: Color
    var selectedBackground: Color
    var isSelected: Bool
    var accessibilityIdentifier: String
    var onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Circle()
                    .strokeBorder(isSelected ? accent : PaywallDesignColor.idleMark, lineWidth: 2)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Group {
                            if isSelected {
                                Circle()
                                    .fill(accent)
                                    .frame(width: 9, height: 9)
                            }
                        }
                    )
                Text(title)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(PaywallDesignColor.ink)
            }
            .padding(.bottom, 10)

            Text(price)
                // Fiyat kartin en agir ogesi olmamali; 14.5pt yari kalin, plan adiyla
                // ayni agirlikta durup goze batmadan okunuyor. Kalinlik ayrica bazi
                // para birimlerinde ("₺2.499,99", "$49.99") karti zorluyordu.
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundColor(PaywallDesignColor.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.85)

            Text(caption)
                .font(.system(size: 12))
                .foregroundColor(PaywallDesignColor.muted)
                .padding(.top, 2)

            if let trialNote {
                Text(trialNote)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(accent)
                    .padding(.top, 7)
            }
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: PaywallDesignMetric.cardRadius, style: .continuous)
                .fill(isSelected ? selectedBackground : Color.white)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PaywallDesignMetric.cardRadius, style: .continuous)
                .strokeBorder(isSelected ? accent : PaywallDesignColor.cardBorder, lineWidth: 1.5)
        )
        .overlay(alignment: .topTrailing) {
            if let badge {
                VStack(spacing: 2) {
                    Text(badge.label)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.vertical, 3)
                        .padding(.horizontal, 9)
                        .background(Capsule().fill(accent))
                        .fixedSize()
                    Text(badge.discount)
                        .font(.system(size: 9, weight: .heavy))
                        .foregroundColor(accent)
                        .fixedSize()
                }
                .offset(x: -12, y: -10)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: PaywallDesignMetric.cardRadius, style: .continuous))
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue([price, caption, trialNote].compactMap { $0 }.joined(separator: ", "))
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - Çapraz satış kartı

struct PaywallDesignUpsellCard<Icon: View>: View {
    var icon: Icon
    var borderColor: Color
    var background: Color
    var text: Text
    var chevronColor: Color
    var accessibilityIdentifier: String
    var onTap: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            icon
            text
                .font(.system(size: 13))
                .foregroundColor(PaywallDesignColor.ink)
                .designLineHeight(13)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            PaywallDesignChevronIcon(color: chevronColor)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: PaywallDesignMetric.cardRadius, style: .continuous)
                .fill(background)
        )
        .overlay(
            RoundedRectangle(cornerRadius: PaywallDesignMetric.cardRadius, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 1.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: PaywallDesignMetric.cardRadius, style: .continuous))
        .onTapGesture(perform: onTap)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(accessibilityIdentifier)
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Uyarı kartı

struct PaywallDesignNotice: View {
    var text: String
    var isError: Bool

    var body: some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundColor(isError ? Color(hex: "B3261E") : PaywallDesignColor.ink)
            .designLineHeight(12)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isError ? Color(hex: "FDECEA") : PaywallDesignColor.orangeCardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        (isError ? Color(hex: "B3261E") : PaywallDesignColor.orange).opacity(0.25),
                        lineWidth: 1
                    )
            )
            .accessibilityIdentifier(isError ? "in_app_paywall.error" : "in_app_paywall.notice")
    }
}

// MARK: - Alt aksiyon barı

struct PaywallDesignFooter: View {
    var ctaTitle: String
    var ctaAccessibilityIdentifier: String
    var isLoading: Bool
    var isDisabled: Bool
    var accent: Color
    var notice: String?
    var errorMessage: String?
    /// Seçili planın mağazadan gelen yenileme fiyatı, dönem ekiyle birlikte.
    /// Fiyat yüklenmediyse nil olur ve satır yalnızca otomatik yenileme cümlesini gösterir.
    var renewalPrice: String?
    var onCTA: () -> Void
    var onRestore: () -> Void
    var onTerms: () -> Void
    var onPrivacy: () -> Void
    var onManageSubscription: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            if let errorMessage {
                PaywallDesignNotice(text: errorMessage, isError: true)
                    .padding(.bottom, 10)
            } else if let notice {
                PaywallDesignNotice(text: notice, isError: false)
                    .padding(.bottom, 10)
            }

            Button(action: onCTA) {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(ctaTitle)
                        .font(.system(size: 17, weight: .bold))
                        .kerning(0.2)
                        .foregroundColor(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(
                    RoundedRectangle(cornerRadius: PaywallDesignMetric.cardRadius, style: .continuous)
                        .fill(isDisabled ? PaywallDesignColor.idleMark : accent)
                )
                .shadow(
                    color: isDisabled ? .clear : accent.opacity(0.35),
                    radius: 11,
                    x: 0,
                    y: 10
                )
            }
            .buttonStyle(.plain)
            .disabled(isDisabled)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(ctaAccessibilityIdentifier)

            autoRenewText
                .font(.system(size: 11))
                .foregroundColor(PaywallDesignColor.footer)
                .designLineHeight(11)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 10)
                .accessibilityIdentifier("in_app_paywall.auto_renew")

            HStack(spacing: 8) {
                link(
                    RDLocalization.string("paywall.design.footer.restore", table: .paywall, fallback: "Geri Yükle"),
                    identifier: "in_app_paywall.restore",
                    action: onRestore
                )
                separator
                link(
                    RDLocalization.string("paywall.design.footer.terms", table: .paywall, fallback: "Koşullar"),
                    identifier: "in_app_paywall.terms",
                    action: onTerms
                )
                separator
                link(
                    RDLocalization.string("paywall.design.footer.privacy", table: .paywall, fallback: "Gizlilik"),
                    identifier: "in_app_paywall.privacy",
                    action: onPrivacy
                )
                separator
                link(
                    RDLocalization.string("paywall.design.footer.manage", table: .paywall, fallback: "İptal Hakkı"),
                    identifier: "in_app_paywall.manage",
                    action: onManageSubscription
                )
            }
            .padding(.top, 8)
        }
        .padding(.top, 14)
        .padding(.horizontal, PaywallDesignMetric.screenPadding)
        .padding(.bottom, 30)
        .background(
            Color.white
                .shadow(color: Color.black.opacity(0.05), radius: 12, x: 0, y: -8)
        )
    }

    /// Otomatik yenileme cümlesi ve arkasına seçili planın fiyatı.
    private var autoRenewText: Text {
        let sentence = Text(
            RDLocalization.string(
                "paywall.design.footer.auto_renew",
                table: .paywall,
                fallback: "Otomatik yenilenir. İstediğiniz zaman iptal edin."
            )
        )
        guard let renewalPrice else { return sentence }
        return sentence + Text(" ") + Text(renewalPrice).fontWeight(.semibold)
    }

    private var separator: some View {
        Text(verbatim: "·")
            .font(.system(size: 11))
            .foregroundColor(PaywallDesignColor.footer)
            .accessibilityHidden(true)
    }

    private func link(_ title: String, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .foregroundColor(PaywallDesignColor.footer)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
