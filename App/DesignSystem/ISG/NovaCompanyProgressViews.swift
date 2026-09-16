import SwiftUI

extension NovaCompanySection {
    var title: String {
        switch self {
        case .logo: return RDLocalization.string("localizable.nova.workspace.logo", table: .localizable, fallback: "Firma Logosu")
        case .personnel: return RDLocalization.string("localizable.nova.workspace.personnel", table: .localizable, fallback: "Personel Listesi")
        case .representative: return RDLocalization.string("localizable.nova.workspace.representative", table: .localizable, fallback: "Çalışan Temsilcisi")
        case .support: return RDLocalization.string("localizable.nova.workspace.support", table: .localizable, fallback: "Destek Elemanları")
        case .risk: return RDLocalization.string("localizable.nova.workspace.risk", table: .localizable, fallback: "Risk Analizi")
        case .emergency: return RDLocalization.string("localizable.nova.workspace.emergency", table: .localizable, fallback: "Acil Durum Eylem Planı")
        case .inspections: return RDLocalization.string("localizable.nova.workspace.inspections", table: .localizable, fallback: "Periyodik Kontroller")
        case .accidents: return RDLocalization.string("localizable.nova.workspace.accidents", table: .localizable, fallback: "İş Kazaları")
        case .board: return RDLocalization.string("localizable.nova.workspace.board", table: .localizable, fallback: "İSG Kurulu")
        case .training: return RDLocalization.string("localizable.nova.workspace.training", table: .localizable, fallback: "Eğitimler")
        case .files: return RDLocalization.string("localizable.nova.workspace.files", table: .localizable, fallback: "Dosyalarım")
        case .handover: return RDLocalization.string("localizable.nova.workspace.handover", table: .localizable, fallback: "Zimmet Formları")
        }
    }
    var symbol: String {
        switch self {
        case .logo: return "photo"
        case .personnel: return "person.2"
        case .representative: return "person.crop.rectangle"
        case .support: return "person.3"
        case .risk: return "exclamationmark.triangle"
        case .emergency: return "shield"
        case .inspections: return "wrench.and.screwdriver"
        case .accidents: return "cross.case"
        case .board: return "person.3.sequence"
        case .training: return "graduationcap"
        case .files: return "folder"
        case .handover: return "doc.text"
        }
    }
}

struct NovaCompanyScoreCard: View {
    let progress: NovaCompanyProgress
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        NovaCard(padding: 16, tint: NovaColorToken.statusSuccessBg.color(in: scheme)) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) { ring; description }
                } else {
                    HStack(spacing: 16) {
                        ring
                        description.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityIdentifier("company.score")
    }
    private var ring: some View {
        ZStack {
            Circle().stroke(NovaColorToken.accentInk.color(in: scheme).opacity(0.13), lineWidth: 9)
            Circle().trim(from: 0, to: progress.fraction ?? 0)
                .stroke(NovaColorToken.accentInk.color(in: scheme), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.35), value: progress.fraction)
            VStack(spacing: 3) {
                Image(systemName: "chart.bar").font(.system(size: 17))
                    .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                NovaText(text: progress.score.map(String.init) ?? "—", style: .screenTitle)
                NovaText(text: "/ 100", style: .metaQuiet)
            }
        }.frame(width: 116, height: 116)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(progress.score.map { String(format: RDLocalization.string("localizable.nova.workspace.score.spoken", table: .localizable, fallback: "Başarı skoru: %d / 100"), $0) } ?? RDLocalization.string("localizable.nova.workspace.unknown", table: .localizable, fallback: "Başarı skoru henüz hesaplanamıyor"))
    }
    private var description: some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: RDLocalization.string("localizable.nova.workspace.title", table: .localizable, fallback: "Firma Başarı Skoru"), style: .cardTitle)
            NovaText(text: String(format: RDLocalization.string("localizable.nova.workspace.score.count", table: .localizable, fallback: "%d/%d başlık tamamlandı"), progress.completed, progress.total), style: .metaQuiet)
            NovaText(text: progress.isKnown ? RDLocalization.string("localizable.nova.workspace.hint", table: .localizable, fallback: "Başlıklar tamamlandıkça skorunuz artar.") : RDLocalization.string("localizable.nova.workspace.score.pending", table: .localizable, fallback: "Tüm başlık verileri bağlandığında skor hesaplanacak."), style: .metaQuiet)
            NovaText(text: RDLocalization.string("localizable.nova.workspace.disclaimer", table: .localizable, fallback: "Kayıt tamamlama göstergesidir."), style: .metaQuiet)
        }
    }
}

struct NovaCompanyScoreRing: View {
    let progress: NovaCompanyProgress
    @Environment(\.colorScheme) private var scheme
    private var ink: Color { NovaColorToken.text.color(in: scheme) }
    var body: some View {
        ZStack {
            Circle().stroke(ink.opacity(0.15), lineWidth: 5)
            Circle().trim(from: 0, to: progress.fraction ?? 0)
                .stroke(ink, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 2) {
                Image(systemName: "chart.bar").font(.system(size: 12)).foregroundStyle(ink)
                Text(progress.score.map(String.init) ?? "—").font(.custom("PlusJakartaSans-Bold", size: 20))
                Text("/100").font(.custom("PlusJakartaSans-Medium", size: 9))
            }
        }.frame(width: 88, height: 88)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(progress.score.map { String(format: RDLocalization.string("localizable.nova.workspace.score.spoken", table: .localizable, fallback: "Başarı skoru: %d / 100"), $0) } ?? RDLocalization.string("localizable.nova.workspace.unknown", table: .localizable, fallback: "Başarı skoru henüz hesaplanamıyor"))
            .accessibilityIdentifier("company.score")
    }
}

struct NovaCompanyAccordion<Content: View>: View {
    let title: String
    let symbol: String
    var state: NovaCompletionState? = nil
    var identifier = "company.accordion"
    /// Nested rows (logo/personnel) keep the same interaction styling but do
    /// not add a second outline inside the already outlined parent section.
    var outlinesWhenExpanded = true
    @Binding var expanded: Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        NovaCard(padding: 10, border: expanded && outlinesWhenExpanded ? NovaColorToken.textSecondary.color(in: scheme) : .clear) {
            VStack(alignment: .leading, spacing: expanded ? 10 : 0) {
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 9) {
                        Image(systemName: symbol).font(.system(size: 17)).foregroundStyle(iconTone.color(in: scheme))
                        NovaText(text: title, style: .label)
                        Spacer(minLength: 0)
                        if let state { status(state) }
                        Image(systemName: expanded ? "chevron.up" : "chevron.down").font(.system(size: 12))
                    }.padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .background(expanded ? NovaColorToken.surfaceMuted.color(in: scheme) : .clear,
                            in: RoundedRectangle(cornerRadius: NovaDimensionToken.radiusCard.value - 2))
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier(identifier).accessibilityValue(expanded ? RDLocalization.string("localizable.nova.workspace.expanded", table: .localizable, fallback: "Açık") : RDLocalization.string("localizable.nova.workspace.collapsed", table: .localizable, fallback: "Kapalı"))
                if expanded { content().padding(.bottom, 0) }
            }
        }
    }
    private var iconTone: NovaColorToken {
        switch symbol {
        case "exclamationmark.triangle": return .statusWarningInk
        case "shield": return .statusInfoInk
        case "person.2", "person.crop.rectangle", "person.3", "person.3.sequence": return .accentInk
        case "cross.case": return .statusDangerInk
        case "wrench.and.screwdriver": return .statusWarningInk
        case "graduationcap": return .statusInfoInk
        case "folder", "doc.text": return .statusInfoInk
        default: return .text
        }
    }
    private func status(_ state: NovaCompletionState) -> some View {
        let label = state == .complete ? RDLocalization.string("localizable.nova.workspace.complete", table: .localizable, fallback: "Tamamlandı") : RDLocalization.string("localizable.nova.workspace.missing", table: .localizable, fallback: "Eksik")
        return Label(label, systemImage: state == .complete ? "checkmark" : "xmark")
            .font(.custom("PlusJakartaSans-SemiBold", size: 10)).fixedSize()
            .foregroundStyle((state == .complete ? NovaColorToken.accentInk : .statusDangerInk).color(in: scheme))
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background((state == .complete ? NovaColorToken.statusSuccessBg : .statusDangerBg).color(in: scheme), in: Capsule())
    }
}
