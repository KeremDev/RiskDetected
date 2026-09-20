#if DEBUG && NOVA_PILOT_BUILD
import SwiftUI

// MARK: - Trial offer

struct NovaOBTrialScreen: View {
    @ObservedObject var controller: NovaOBController

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0xF6B06A), location: 0),
                    .init(color: Color(hex: 0xF8CFA4), location: 0.24),
                    .init(color: Color(hex: 0xF3E7DC), location: 0.52),
                    .init(color: Color(hex: 0xF1F1EF), location: 0.74),
                    .init(color: Color(hex: 0xEDEDEB), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    NovaOBCloseButton { controller.go(.push) }
                }
                // The prototype reserves 400 pt for the absolutely-placed mock;
                // native text metrics run a touch taller, so the block gets the
                // few extra points it needs to stay clear of the headline.
                NovaOBTrialMockup()
                    .frame(height: 424, alignment: .top)
                    .padding(.horizontal, -4)
                    .padding(.top, 6)

                VStack(spacing: 14) {
                    Spacer(minLength: 0)
                    Text("İSGADA’yı 7 gün ücretsiz denemenizi istiyoruz")
                        .font(NovaOB.font(31, 800))
                        .tracking(-1.1)
                        .multilineTextAlignment(.center)
                        .lineSpacing(NovaOB.lineSpacing(31, 1.14))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Tüm özellikler açık, şuan ödeme alınmaz. Deneme bitmeden hatırlatırız.")
                        .font(NovaOB.font(14.5))
                        .foregroundColor(NovaOB.muted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(NovaOB.lineSpacing(14.5, 1.45))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 296)
                    NovaOBPillButton(title: "İncele", showsArrow: true, background: Color(hex: 0x111111)) {
                        controller.go(.trialHow)
                    }
                }
                .padding(.top, 10)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .padding(.horizontal, 22)
            .padding(.top, 54)
            .padding(.bottom, 34)
        }
    }
}

struct NovaOBCloseButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            NovaOBIconPath(path: "M6 6l12 12|M18 6L6 18", size: 15,
                           color: Color(hex: 0x2C2320), lineWidth: 2.3)
                .frame(width: 36, height: 36)
                .background(Color.white.opacity(0.72), in: Circle())
                .shadow(color: Color(hex: 0x784614).opacity(0.14), radius: 4, y: 2)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
    }
}

/// The layered "Saha Rutini" app mock behind the trial offer.
struct NovaOBTrialMockup: View {
    private let tags = ["Risk analizi", "Eğitim", "Denetim", "Kontrol listesi", "EKİP takibi", "Ramak kala", "İSG kurulu"]

    var body: some View {
        ZStack(alignment: .topLeading) {
            mainCard
                .padding(.horizontal, 8)

            shiftCard
                .frame(width: 236)
                .rotationEffect(.degrees(-2.4))
                .offset(x: 0, y: 270)

            statusChip(
                icon: "M12 2.5A9.5 9.5 0 1021.5 12A9.5 9.5 0 0012 2.5m-.7 13.4l-3.6-3.6 1.5-1.5 2.1 2.1 4.8-5 1.5 1.5z",
                iconColor: NovaOB.ink, label: "Tamamlanan:", value: "%68", valueColor: NovaOB.ink
            )
            .rotationEffect(.degrees(3))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 2)
            .offset(y: 298)

            statusChip(
                icon: "M12 2.5A9.5 9.5 0 1021.5 12A9.5 9.5 0 0012 2.5m1 14.6h-2v-2h2zm0-3.6h-2V7h2z",
                iconColor: Color(hex: 0xC0564B), label: "Kritik:", value: "3 kayıt", valueColor: Color(hex: 0xC0564B)
            )
            .rotationEffect(.degrees(-1.6))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, 16)
            .offset(y: 346)
        }
    }

    private var mainCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Saha Rutini").font(NovaOB.font(18, 700)).tracking(-0.3)
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    NovaOBIconPath(path: "M4 20h4l10-10-4-4L4 16z", size: 12, color: NovaOB.muted, lineWidth: 2)
                    Text("Düzenle").font(NovaOB.font(12.5, 600)).foregroundColor(NovaOB.muted)
                }
                .padding(.horizontal, 11)
                .frame(height: 28)
                .background(NovaOB.fill2, in: Capsule())
            }

            HStack(spacing: 4) {
                Text("Bugün")
                    .font(NovaOB.font(13, 700))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 31)
                    .background(Color(hex: 0x111111), in: Capsule())
                Text("Yaklaşan")
                    .font(NovaOB.font(13, 600))
                    .foregroundColor(NovaOB.muted2)
                    .frame(maxWidth: .infinity)
                    .frame(height: 31)
            }
            .padding(3)
            .background(NovaOB.fill2, in: Capsule())

            HStack(spacing: 11) {
                NovaOBIconPath(path: "M12 2.6l8.4 3.6v5.5c0 4.9-3.4 9.1-8.4 10.7-5-1.6-8.4-5.8-8.4-10.7V6.2z",
                               size: 17, color: Color(hex: 0xE8853C), lineWidth: 0, filled: true)
                    .frame(width: 31, height: 31)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text("Hedefin: saha denetimi").font(NovaOB.font(13.5, 700)).foregroundColor(.white)
                    Text("Vardiya başında kontrol listesi, risk kaydı ve eksik EKİP takibi tek akışta.")
                        .font(NovaOB.font(11))
                        .foregroundColor(.white.opacity(0.9))
                        .lineSpacing(NovaOB.lineSpacing(11, 1.4))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(13)
            .background(
                LinearGradient(colors: [Color(hex: 0xF0A44F), Color(hex: 0xE8853C)],
                               startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: 18, style: .continuous)
            )

            NovaOBFlowLayout(spacing: 5, lineSpacing: 5) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(NovaOB.font(10.5, 600))
                        .foregroundColor(Color(hex: 0x8A6B50))
                        .padding(.horizontal, 10)
                        .frame(height: 22)
                        .background(Color(hex: 0xF5EDE6), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 17)
        .padding(.top, 18)
        .padding(.bottom, 16)
        .background(NovaOB.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: Color(hex: 0x965F23).opacity(0.16), radius: 17, y: 14)
    }

    private var shiftCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                NovaOBIconPath(
                    path: "circle:12,12,4.6|M12 1.5v3.2M12 19.3v3.2M1.5 12h3.2M19.3 12h3.2M4.6 4.6l2.3 2.3M17.1 17.1l2.3 2.3M19.4 4.6l-2.3 2.3M6.9 17.1l-2.3 2.3",
                    size: 13, color: Color(hex: 0xE8853C), lineWidth: 2
                )
                Text("Sabah vardiyası").font(NovaOB.font(11.5, 700)).foregroundColor(NovaOB.muted)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("Vardiya başı saha turu").font(NovaOB.font(12, 700))
                Text("07:15 · 12 dk").font(NovaOB.font(10, 600)).foregroundColor(NovaOB.gold)
                Text("Günün ilk kontrol listesini tamamla.")
                    .font(NovaOB.font(10))
                    .foregroundColor(NovaOB.muted2)
                    .lineSpacing(NovaOB.lineSpacing(10, 1.4))
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0xFDF4EC), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 12)
        .background(NovaOB.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: Color(hex: 0x965F23).opacity(0.18), radius: 16, y: 16)
    }

    private func statusChip(icon: String, iconColor: Color, label: String, value: String, valueColor: Color) -> some View {
        HStack(spacing: 8) {
            NovaOBIconPath(path: icon, size: 15, color: iconColor, lineWidth: 0, filled: true)
            Text(label).font(NovaOB.font(12.5, 700)).foregroundColor(NovaOB.ink)
            Text(value).font(NovaOB.font(12.5, 800)).foregroundColor(valueColor)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 9)
        .background(NovaOB.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: Color(hex: 0x965F23).opacity(0.2), radius: 13, y: 12)
    }
}

/// Minimal wrapping stack for the tag row.
struct NovaOBFlowLayout: Layout {
    var spacing: CGFloat = 5
    var lineSpacing: CGFloat = 5

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + lineSpacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}

// MARK: - How the trial works

struct NovaOBTrialHowScreen: View {
    @ObservedObject var controller: NovaOBController

    private struct Step {
        let title: String
        let desc: String
        let done: Bool
        let icon: String
    }

    private static let check = "M12 2.4A9.6 9.6 0 1021.6 12A9.6 9.6 0 0012 2.4m-1.1 14.2l-4.1-4.1 1.7-1.7 2.4 2.4 5.6-5.6 1.7 1.7z"

    private static let steps: [Step] = [
        .init(title: "Uygulamayı indir", desc: "İSGADA’yı indirip açtın.", done: true, icon: check),
        .init(title: "Deneyimini kişiselleştir", desc: "Kişiselleştirme sorularının tamamını yanıtladın.", done: true, icon: check),
        .init(title: "Bugün: anında erişim", desc: "7 günlük ücretsiz PLUS denemen tüm özelliklerle başlıyor.", done: false,
              icon: "M12 1.8l8.4 3.6v5.9c0 5-3.5 9.3-8.4 10.9-4.9-1.6-8.4-5.9-8.4-10.9V5.4zm-1 13.9l5.4-5.4-1.6-1.6-3.8 3.8-1.9-1.9-1.6 1.6z"),
        .init(title: "5. gün: hatırlatma", desc: "Deneme bitmeden haber veririz; istediğin an iptal edebilirsin.", done: false,
              icon: "M12 2.4a5.4 5.4 0 00-5.4 5.4c0 4-1 5.4-2.2 6.9-.5.6 0 1.5.8 1.5h13.6c.8 0 1.3-.9.8-1.5-1.2-1.5-2.2-2.9-2.2-6.9A5.4 5.4 0 0012 2.4m-2.6 15.4a2.7 2.7 0 005.2 0z"),
        .init(title: "7. gün: deneme sona erer", desc: "İptal etmezsen 2499 TL/yıl üzerinden otomatik yenilenir.İptal edebilirsin.", done: false,
              icon: "M12 2.3l2.9 6 6.6.9-4.8 4.7 1.1 6.6L12 17.3l-5.8 3.2 1.1-6.6L2.5 9.2l6.6-.9z")
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                stops: [
                    .init(color: Color(hex: 0xF6C79A), location: 0),
                    .init(color: Color(hex: 0xF8DDC2), location: 0.22),
                    .init(color: Color(hex: 0xF5EDE4), location: 0.46),
                    .init(color: Color(hex: 0xFFFFFF), location: 0.70),
                    .init(color: Color(hex: 0xFFFFFF), location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 16) {
                header
                intro
                timeline
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, 22)
            .padding(.top, 54)
            .padding(.bottom, 30)
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            HStack(spacing: 5) {
                Capsule().fill(NovaOB.gold).frame(height: 4)
                Capsule().fill(NovaOB.ink.opacity(0.12)).frame(height: 4)
            }
            NovaOBCloseButton { controller.go(.push) }
        }
    }

    private var intro: some View {
        VStack(spacing: 10) {
            HStack(spacing: 7) {
                NovaOBIconPath(path: "M12 2.2l2.9 6 6.6.9-4.8 4.6 1.1 6.6L12 17.2 6.2 20.3l1.1-6.6L2.5 9.1l6.6-.9z",
                               size: 13, color: Color(hex: 0xF0A44F), lineWidth: 0, filled: true)
                Text("7 GÜN ÜCRETSİZ · ŞUAN ÖDEME YOK")
                    .font(NovaOB.font(11.5, 700))
                    .tracking(0.345)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .background(Color(hex: 0x111111), in: Capsule())

            Text("Ücretsiz deneme nasıl çalışır?")
                .font(NovaOB.font(26, 800))
                .tracking(-1.2)
                .multilineTextAlignment(.center)
                .lineSpacing(NovaOB.lineSpacing(26, 1.1))
                .fixedSize(horizontal: false, vertical: true)

            Text("Bugün tam erişimle başlıyorsun. 7 gün boyunca hiçbir ücret alınmaz.")
                .font(NovaOB.font(15))
                .foregroundColor(NovaOB.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(NovaOB.lineSpacing(15, 1.45))
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300)
        }
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            ForEach(Array(Self.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 14) {
                    VStack(spacing: 0) {
                        NovaOBIconPath(path: step.icon, size: 23, color: iconColor(index, step), lineWidth: 0, filled: true)
                            .frame(width: 46, height: 46)
                            .background(dotBackground(index, step), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                            .shadow(
                                color: index == 2 ? Color(hex: 0xC86E28).opacity(0.32)
                                    : (step.done ? .clear : Color(hex: 0x785028).opacity(0.12)),
                                radius: index == 2 ? 10 : 8, y: index == 2 ? 8 : 6
                            )
                        if index != Self.steps.count - 1 {
                            Rectangle()
                                .fill(step.done ? Color(hex: 0xF0D9C2) : Color(hex: 0xF0D6BF))
                                .frame(width: 3)
                                .frame(minHeight: 10)
                                .clipShape(Capsule())
                        }
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(step.title)
                            .font(NovaOB.font(18.5, 800))
                            .tracking(-0.4)
                            .foregroundColor(step.done ? Color(hex: 0x9A948E) : NovaOB.ink)
                            .strikethrough(step.done, color: Color(hex: 0x9A948E))
                        Text(step.desc)
                            .font(NovaOB.font(14))
                            .foregroundColor(step.done ? Color(hex: 0xA8A29C) : NovaOB.muted)
                            .lineSpacing(NovaOB.lineSpacing(14, 1.45))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 18)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func dotBackground(_ index: Int, _ step: Step) -> Color {
        if step.done { return Color(hex: 0xF7DCC0) }
        return index == 2 ? Color(hex: 0xE8853C) : NovaOB.surface
    }

    private func iconColor(_ index: Int, _ step: Step) -> Color {
        if step.done { return Color(hex: 0xD08A44) }
        return index == 2 ? .white : Color(hex: 0xE8853C)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            NovaOBPillButton(title: "7 günlük ücretsiz denemeyi başlat", fontSize: 17.5,
                             background: Color(hex: 0x111111)) {
                controller.go(.push)
            }
            HStack(spacing: 10) {
                Button { controller.go(.trial) } label: {
                    HStack(spacing: 7) {
                        NovaOBIconPath(path: "M20 12H5|M11 6l-6 6 6 6", size: 17, color: NovaOB.muted, lineWidth: 2)
                        Text("Geri").font(NovaOB.font(15)).foregroundColor(NovaOB.muted)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                }
                .buttonStyle(.plain)

                Rectangle().fill(NovaOB.ink.opacity(0.14)).frame(width: 1, height: 18)

                Button { controller.go(.push) } label: {
                    HStack(spacing: 7) {
                        Text("Şimdilik Ücretsiz Devam Et")
                            .font(.custom("PlusJakartaSans-Regular", size: 15).italic())
                            .foregroundColor(Color(hex: 0x999998))
                        NovaOBIconPath(path: "M4 12h15|M13 6l6 6-6 6", size: 17, color: NovaOB.gold, lineWidth: 2)
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Push permission

struct NovaOBPushScreen: View {
    @ObservedObject var controller: NovaOBController
    @State private var working = false

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 24) {
                Spacer(minLength: 0)
                Image("NovaOBNotification")
                    .resizable().scaledToFit()
                    .frame(width: 214, height: 214)
                VStack(spacing: 12) {
                    Text("Bildirimleri anında alın.")
                        .font(NovaOB.font(30, 800))
                        .tracking(-1)
                        .multilineTextAlignment(.center)
                        .lineSpacing(NovaOB.lineSpacing(30, 1.14))
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Raporların, analizlerin, periyodik kontroller ve firma takipleri için bildirim izninizi istiyoruz.")
                        .font(NovaOB.font(16))
                        .foregroundColor(NovaOB.muted)
                        .multilineTextAlignment(.center)
                        .lineSpacing(NovaOB.lineSpacing(16, 1.5))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            VStack(spacing: 6) {
                NovaOBPillButton(title: "Bildirimleri Aç", showsArrow: true) {
                    guard !working else { return }
                    working = true
                    Task {
                        await controller.auth.requestPush()
                        controller.finish()
                    }
                }
                Button { controller.finish() } label: {
                    Text("Şimdi değil")
                        .font(NovaOB.font(15.5))
                        .foregroundColor(NovaOB.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 78)
        .padding(.bottom, 34)
        .background(NovaOB.surface.ignoresSafeArea())
    }
}
#endif
