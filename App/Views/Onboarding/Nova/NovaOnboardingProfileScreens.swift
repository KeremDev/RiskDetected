#if DEBUG && NOVA_PILOT_BUILD
import SwiftUI

// MARK: - Profile preparation

struct NovaOBPrepScreen: View {
    @ObservedObject var controller: NovaOBController

    private static let bounds = [25, 50, 75, 100]

    private var stepLabels: [String] {
        let answers = controller.answers
        return [
            "Çalışma tercihlerin düzenlendi.",
            controller.skipped.contains("exp") || (answers.exp == nil && !answers.expLess)
                ? "Deneyim bilgisi daha sonra eklenecek." : "Deneyim bilgilerin işlendi.",
            controller.skipped.contains("assist") || answers.assist.isEmpty
                ? "Destek tercihleri daha sonra seçilecek." : "Destek tercihlerin düzenlendi.",
            "Profil kartın hazırlandı."
        ]
    }

    var body: some View {
        VStack(spacing: 36) {
            Text("Sana özel profil hazırlanıyor")
                .font(NovaOB.font(27, 700))
                .tracking(-0.3)
                .multilineTextAlignment(.center)
                .lineSpacing(NovaOB.lineSpacing(27, 1.2))
                .frame(maxWidth: .infinity)

            ring

            VStack(spacing: 10) {
                ForEach(Array(stepLabels.enumerated()), id: \.offset) { index, label in
                    stepRow(label, done: controller.prepPercent >= Self.bounds[index])
                }
            }

            if controller.prepDone {
                NovaOBPrimaryButton(title: "Profilimi gör") { controller.toCard() }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 96)
        .padding(.bottom, 40)
        .background(NovaOB.surface.ignoresSafeArea())
    }

    private var ring: some View {
        ZStack {
            Circle()
                .stroke(NovaOB.line, lineWidth: 10)
            Circle()
                .trim(from: 0, to: CGFloat(controller.prepPercent) / 100)
                .stroke(NovaOB.ink, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 6) {
                Text("\(controller.prepPercent)%")
                    .font(NovaOB.font(46, 700))
                    .monospacedDigit()
                    .tracking(-1.5)
                NovaOBIconPath(
                    path: "M7 24c0-8.3 7.6-15 17-15s17 6.7 17 15|M4 24h40",
                    size: 30, color: NovaOB.line2, lineWidth: 1.8, viewBox: 48
                )
                .frame(width: 30, height: 20)
            }
        }
        .frame(width: 196, height: 196)
    }

    private func stepRow(_ label: String, done: Bool) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(done ? NovaOB.ink : NovaOB.surface)
                .overlay(Circle().strokeBorder(done ? NovaOB.ink : NovaOB.line2, lineWidth: 1.5))
                .frame(width: 22, height: 22)
                .overlay {
                    if done {
                        NovaOBIconPath(path: "M2 7.5l3.4 3.4L12 3.5", size: 12, color: .white,
                                       lineWidth: 2.4, viewBox: 14)
                    }
                }
            Text(label)
                .font(NovaOB.font(15))
                .foregroundColor(done ? NovaOB.ink : NovaOB.muted)
                .lineSpacing(NovaOB.lineSpacing(15, 1.3))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            if done {
                Text("Tamamlandı").font(NovaOB.font(12.5)).foregroundColor(NovaOB.ink)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
        .background(done ? NovaOB.surface : Color(hex: 0xF5F5F5),
                    in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(done ? NovaOB.line : Color(hex: 0xE8E8E8), lineWidth: 1)
        )
    }
}

// MARK: - Profile card

struct NovaOBProfileCardScreen: View {
    @ObservedObject var controller: NovaOBController

    private var thanksLine: String {
        let name = controller.answers.name.novaTrimmed
        return name.isEmpty ? "Cevapların için teşekkürler" : "Cevapların için teşekkürler \(name)"
    }

    var body: some View {
        ZStack {
            NovaOB.surface.ignoresSafeArea()
            NovaOBConfettiLayer()
                .allowsHitTesting(false)

            VStack(spacing: 22) {
                Spacer(minLength: 0)
                Image("NovaOBProfileReady")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 214, height: 214)
                VStack(spacing: 12) {
                    Text("Hepsi Tamam,\nSana özel profilini kaydettik.")
                        .font(NovaOB.font(31, 800))
                        .tracking(-1)
                        .multilineTextAlignment(.center)
                        .lineSpacing(NovaOB.lineSpacing(31, 1.14))
                        .fixedSize(horizontal: false, vertical: true)
                    Text(thanksLine)
                        .font(NovaOB.font(17.5))
                        .foregroundColor(NovaOB.muted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(NovaOB.lineSpacing(17.5, 1.45))
                }
                Spacer(minLength: 0)
                NovaOBPillButton(title: "Devam et", showsArrow: true) {
                    controller.auth.saveDraft(controller.answers)
                    controller.go(.signup)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 72)
            .padding(.bottom, 34)
        }
    }
}

/// Falling confetti and floating balloons (`isgFall` / `isgFloat` / `isgSway`).
private struct NovaOBConfettiLayer: View {
    private struct Piece {
        let leftRatio: Double
        let width: CGFloat
        let height: CGFloat
        let radius: CGFloat
        let color: Color
        let isBalloon: Bool
        let duration: Double
        let delay: Double
        let sway: Double
    }

    private static let colors: [UInt32] = [0x000000, 0x555555, 0xE8B733, 0xD4453C, 0x999999, 0xF2E7C9, 0x000000]

    private static let pieces: [Piece] = (0..<26).map { index in
        var generator = SystemRandomNumberGenerator()
        let balloon = index % 6 == 0
        let size = balloon ? Double.random(in: 14...22, using: &generator) : Double.random(in: 6...11, using: &generator)
        return Piece(
            leftRatio: Double.random(in: 0.02...0.94, using: &generator),
            width: size,
            height: balloon ? size * 1.25 : Double.random(in: 9...16, using: &generator),
            radius: balloon ? 99 : (index % 3 == 0 ? 2 : 99),
            color: Color(hex: colors[index % colors.count]),
            isBalloon: balloon,
            duration: Double.random(in: 3.4...6.2, using: &generator),
            delay: Double.random(in: 0...4, using: &generator),
            sway: Double.random(in: 1.8...3.4, using: &generator)
        )
    }

    var body: some View {
        GeometryReader { proxy in
            TimelineView(.animation) { timeline in
                let now = timeline.date.timeIntervalSinceReferenceDate
                ZStack(alignment: .topLeading) {
                    ForEach(Array(Self.pieces.enumerated()), id: \.offset) { _, piece in
                        let cycle = ((now - piece.delay) / piece.duration).truncatingRemainder(dividingBy: 1)
                        let progress = cycle < 0 ? cycle + 1 : cycle
                        let travel = proxy.size.height + 160
                        let swayPhase = sin(now / piece.sway * .pi)
                        RoundedRectangle(cornerRadius: piece.radius, style: .continuous)
                            .fill(piece.color)
                            .frame(width: piece.width, height: piece.height)
                            .rotationEffect(.degrees(piece.isBalloon ? 0 : progress * 680))
                            .opacity(opacity(progress))
                            .offset(
                                x: proxy.size.width * piece.leftRatio + swayPhase * 16,
                                y: -80 + progress * travel
                            )
                    }
                }
            }
        }
    }

    private func opacity(_ progress: Double) -> Double {
        switch progress {
        case ..<0.08: return progress / 0.08
        case 0.92...: return max(0, (1 - progress) / 0.08)
        default: return 0.9
        }
    }
}

// MARK: - Edit summary

struct NovaOBEditSummaryScreen: View {
    @ObservedObject var controller: NovaOBController

    private static let rows: [(label: String, id: String, index: Int)] = [
        ("İSİM", "name", 0),
        ("SERTİFİKA", "cert", 1),
        ("ÇALIŞMA ŞEKLİ", "work", 2),
        ("POZİSYON", "role", 3),
        ("DENEYİM", "exp", 4),
        ("SEKTÖRLER", "sectors", 5),
        ("EĞİTİMLER", "trainings", 6),
        ("YÖNETİM YAKLAŞIMI", "approach", 7),
        ("BAKANLIK TEFTİŞİ", "inspections", 8),
        ("GELİŞİM ALANLARI", "growth", 9),
        ("ASİSTAN DESTEĞİ", "assist", 10)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                NovaOBBackButton { controller.toCard() }.padding(.leading, -12)
                Text("Bilgilerini düzenle").font(NovaOB.font(22, 700))
            }
            Text("Değiştirmek istediğin satıra dokun; yalnızca o soruya dönersin.")
                .font(NovaOB.font(14.5))
                .foregroundColor(NovaOB.muted)
                .lineSpacing(NovaOB.lineSpacing(14.5, 1.45))

            ScrollView {
                VStack(spacing: 8) {
                    ForEach(Self.rows, id: \.id) { row in
                        summaryRow(label: row.label, value: controller.summaryValue(row.id), index: row.index)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 70)
        .padding(.bottom, 34)
        .background(NovaOB.surface.ignoresSafeArea())
    }

    private func summaryRow(label: String, value: String, index: Int) -> some View {
        let empty = value.hasPrefix("Henüz") || value == "Yanıtlanmadı"
        return Button { controller.editQuestion(index) } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(NovaOB.font(12))
                        .tracking(0.96)
                        .foregroundColor(NovaOB.muted)
                    Text(value)
                        .font(NovaOB.font(15.5))
                        .foregroundColor(empty ? NovaOB.muted : NovaOB.ink)
                        .lineSpacing(NovaOB.lineSpacing(15.5, 1.3))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                NovaOBChevronRight()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .background(NovaOB.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(NovaOB.line, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
#endif
