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
    var features: [String]

    private var reminderDay: Int { max(1, trialDays - 2) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 14) {
                rail(circleColor: PaywallDesignColor.orange, railColor: PaywallDesignColor.orange) {
                    PaywallDesignCheckIcon(
                        size: CGSize(width: 15, height: 12),
                        lineWidth: 2,
                        color: .white
                    )
                }
                VStack(alignment: .leading, spacing: 0) {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            todayTitle
                            todayDetail.fixedSize()
                        }
                        VStack(alignment: .leading, spacing: 0) {
                            todayTitle
                            todayDetail
                        }
                    }

                    LazyVGrid(
                        columns: [
                            GridItem(.flexible(), spacing: 10, alignment: .leading),
                            GridItem(.flexible(), spacing: 10, alignment: .leading)
                        ],
                        alignment: .leading,
                        spacing: 8
                    ) {
                        ForEach(features, id: \.self) { feature in
                            HStack(spacing: 6) {
                                PaywallDesignCheckBadge(
                                    diameter: 16,
                                    checkSize: CGSize(width: 8, height: 7),
                                    checkLineWidth: 2.4,
                                    background: PaywallDesignColor.orangeSoft
                                )
                                Text(feature)
                                    .font(.system(size: 12.5))
                                    .foregroundColor(PaywallDesignColor.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }
                    .padding(.top, 10)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 16)
            }

            HStack(alignment: .top, spacing: 14) {
                rail(circleColor: PaywallDesignColor.idleMark, railColor: PaywallDesignColor.idleRail) {
                    PaywallDesignBellIcon()
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

            HStack(alignment: .top, spacing: 14) {
                rail(circleColor: PaywallDesignColor.idleMark, railColor: nil) {
                    PaywallDesignCardIcon()
                }
                step(
                    title: dayTitle(trialDays),
                    detail: RDLocalization.string(
                        "paywall.design.timeline.billing.detail",
                        table: .paywall,
                        fallback: "Aboneliğiniz başlar. İstediğiniz zaman öncesinde iptal edin."
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

    private var todayTitle: some View {
        Text(RDLocalization.string("paywall.design.timeline.today.title", table: .paywall, fallback: "Bugün"))
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(PaywallDesignColor.ink)
    }

    private var todayDetail: some View {
        Text(
            RDLocalization.format(
                "paywall.design.timeline.today.detail_format",
                table: .paywall,
                fallback: "— Tüm %1$@ özelliklerine anında erişim kazanın",
                arguments: [tierName]
            )
        )
        .font(.system(size: 13))
        .foregroundColor(PaywallDesignColor.muted)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func step(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(PaywallDesignColor.ink)
            Text(detail)
                .font(.system(size: 13.5))
                .foregroundColor(PaywallDesignColor.muted)
                .designLineHeight(13.5)
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
                .frame(width: 32, height: 32)
                .overlay(icon())
            if let railColor {
                Rectangle()
                    .fill(railColor)
                    .frame(width: 2)
                    .frame(maxHeight: .infinity)
                    .padding(.vertical, 3)
            }
        }
        .frame(width: 32)
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
    struct Column {
        let title: String
        let color: Color
        let weight: Font.Weight
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
        Text(column.title)
            .font(.system(size: 12, weight: column.weight))
            .foregroundColor(column.color)
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
                // 17pt bazi para birimlerinde ("₺2.499,99", "$49.99") kart genisligini
                // zorluyordu; 15.5pt hiyerarsiyi bozmadan nefes aldiriyor.
                .font(.system(size: 15.5, weight: .heavy))
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

            Text(
                RDLocalization.string(
                    "paywall.design.footer.auto_renew",
                    table: .paywall,
                    fallback: "Otomatik yenilenir. İstediğiniz zaman iptal edin."
                )
            )
            .font(.system(size: 11))
            .foregroundColor(PaywallDesignColor.footer)
            .designLineHeight(11)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)

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
