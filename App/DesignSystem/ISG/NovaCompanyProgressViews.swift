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

enum NovaCompanyReadinessStatus: String, CaseIterable {
    case complete, needsReview, missing, unknown

    var title: String {
        switch self {
        case .complete: return RDLocalization.string("localizable.nova.company.progress.status.complete", table: .localizable, fallback: "Tamamlandı")
        case .needsReview: return RDLocalization.string("localizable.nova.company.progress.status.review", table: .localizable, fallback: "Kontrol gerekli")
        case .missing: return RDLocalization.string("localizable.nova.company.progress.status.missing", table: .localizable, fallback: "Eksik")
        case .unknown: return RDLocalization.string("localizable.nova.company.progress.status.waiting", table: .localizable, fallback: "Veri bekleniyor")
        }
    }

    func color(in scheme: ColorScheme) -> Color {
        switch self {
        case .complete: return NovaColorToken.accent.color(in: scheme)
        case .needsReview: return Color(red: 0.70, green: 0.62, blue: 0.94)
        case .missing: return Color(red: 1.00, green: 0.38, blue: 0.20)
        case .unknown: return NovaColorToken.border.color(in: scheme)
        }
    }
}

struct NovaCompanyReadinessItem: Identifiable, Equatable {
    let id: String
    let title: String
    let detail: String
    let status: NovaCompanyReadinessStatus
}

/// Ten operational headings, presented with the same segmented-ring model as
/// the selected reference. A tap selects one segment on phones; pointer hover
/// provides the same detail on iPad and Mac without changing the score.
struct NovaCompanyReadinessCard: View {
    let items: [NovaCompanyReadinessItem]
    @State private var selectedID: String?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var completed: Int { items.filter { $0.status == .complete }.count }
    private var selected: NovaCompanyReadinessItem? {
        items.first { $0.id == selectedID } ?? suggestedSelection
    }
    private var suggestedSelection: NovaCompanyReadinessItem? {
        items.first { $0.status == .needsReview }
            ?? items.first { $0.status == .missing }
            ?? items.first { $0.status == .unknown }
            ?? items.first
    }
    private var legendStatuses: [NovaCompanyReadinessStatus] {
        NovaCompanyReadinessStatus.allCases.filter { status in
            status != .unknown || items.contains { $0.status == .unknown }
        }
    }

    var body: some View {
        NovaCard(padding: 16) {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .center, spacing: 10) {
                    NovaText(text: RDLocalization.string("localizable.nova.company.progress.title", table: .localizable,
                        fallback: "Firma İlerlemesi"), style: .sectionTitle)
                    Spacer(minLength: 4)
                    Text(String(format: RDLocalization.string("localizable.nova.company.progress.heading.count", table: .localizable,
                        fallback: "%d başlık"), items.count))
                        .font(.custom("PlusJakartaSans-SemiBold", size: 11))
                        .foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                        .padding(.horizontal, 12).frame(minHeight: 38)
                        .background(NovaColorToken.surface.color(in: scheme), in: Capsule())
                        .overlay(Capsule().strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
                }

                if let selected { selectionBubble(selected) }

                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .center, spacing: 18) {
                            segmentedRing.frame(maxWidth: .infinity)
                            legend.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        HStack(spacing: 18) {
                            segmentedRing
                            legend.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(red: 0.29, green: 0.20, blue: 0.77))
                        .accessibilityHidden(true)
                    NovaText(text: summaryText, style: .meta,
                        color: NovaColorToken.textSecondary.color(in: scheme))
                }
                .padding(.horizontal, 13).padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
                .background(NovaColorToken.surfaceMuted.color(in: scheme),
                    in: RoundedRectangle(cornerRadius: 18))
            }
        }
        .accessibilityIdentifier("company.progress")
        .onAppear { if selectedID == nil { selectedID = suggestedSelection?.id } }
        .onChange(of: items) { value in
            if !value.contains(where: { $0.id == selectedID }) { selectedID = suggestedSelection?.id }
        }
    }

    private var segmentedRing: some View {
        ZStack {
            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                Button {
                    withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { selectedID = item.id }
                } label: {
                    NovaCompanyRingSegment(index: index, count: max(items.count, 1), gapDegrees: 2.8)
                        .fill(item.status.color(in: scheme))
                        .scaleEffect(selected?.id == item.id ? 1.035 : 1)
                        .contentShape(NovaCompanyRingSegment(index: index, count: max(items.count, 1), gapDegrees: 2.8))
                }
                .buttonStyle(.plain)
                .onHover { hovering in if hovering { selectedID = item.id } }
                .accessibilityIdentifier("company.progress.segment.\(item.id)")
                .accessibilityLabel("\(item.title), \(item.status.title)")
                .accessibilityHint(item.detail)
            }
            VStack(spacing: 1) {
                Text("\(completed)/\(items.count)")
                    .font(.custom("PlusJakartaSans-Bold", size: 27))
                    .foregroundStyle(NovaColorToken.text.color(in: scheme))
                NovaText(text: RDLocalization.string("localizable.nova.company.progress.completed", table: .localizable,
                    fallback: "tamamlandı"), style: .micro,
                    color: NovaColorToken.textMuted.color(in: scheme))
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .frame(width: 142, height: 142)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(format: RDLocalization.string("localizable.nova.company.progress.spoken", table: .localizable,
            fallback: "Firma ilerlemesi, %1$d / %2$d başlık tamamlandı"), completed, items.count))
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 13) {
            ForEach(legendStatuses, id: \.rawValue) { status in
                HStack(spacing: 8) {
                    Circle().fill(status.color(in: scheme)).frame(width: 9, height: 9)
                    NovaText(text: status.title, style: .metaQuiet)
                    Spacer(minLength: 4)
                    Text(String(items.filter { $0.status == status }.count))
                        .font(.custom("PlusJakartaSans-SemiBold", size: 14))
                        .foregroundStyle(NovaColorToken.text.color(in: scheme))
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    if let item = items.first(where: { $0.status == status }) { selectedID = item.id }
                }
            }
        }
    }

    private func selectionBubble(_ item: NovaCompanyReadinessItem) -> some View {
        HStack(spacing: 8) {
            Circle().fill(item.status.color(in: scheme)).frame(width: 8, height: 8)
            Text("\(item.title) · \(item.status.title)")
                .font(.custom("PlusJakartaSans-SemiBold", size: 11))
                .lineLimit(1).minimumScaleFactor(0.72)
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 13).frame(minHeight: 36)
        .background(Color(red: 0.04, green: 0.035, blue: 0.09), in: Capsule())
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.title), \(item.status.title). \(item.detail)")
    }

    private var summaryText: String {
        let missing = items.filter { $0.status == .missing }
        let review = items.filter { $0.status == .needsReview }
        let unknown = items.filter { $0.status == .unknown }
        if missing.isEmpty && review.isEmpty && unknown.isEmpty {
            return RDLocalization.string("localizable.nova.company.progress.summary.complete", table: .localizable,
                fallback: "Tüm firma başlıkları tamamlandı ve güncel görünüyor.")
        }
        var parts: [String] = []
        if !missing.isEmpty {
            let names = missing.prefix(2).map(\.title).joined(separator: " ve ")
            parts.append(missing.count > 2
                ? String(format: RDLocalization.string("localizable.nova.company.progress.summary.missing.many", table: .localizable,
                    fallback: "%1$@ dahil %2$d başlık eksik"), names, missing.count)
                : String(format: RDLocalization.string("localizable.nova.company.progress.summary.missing.named", table: .localizable,
                    fallback: "%@ eksik"), names))
        }
        if !review.isEmpty {
            parts.append(String(format: RDLocalization.string("localizable.nova.company.progress.summary.review", table: .localizable,
                fallback: "%d başlığın tarihi veya durumu kontrol edilmeli"), review.count))
        }
        if !unknown.isEmpty {
            parts.append(String(format: RDLocalization.string("localizable.nova.company.progress.summary.waiting", table: .localizable,
                fallback: "%d başlık için veri bekleniyor"), unknown.count))
        }
        return parts.joined(separator: ". ") + "."
    }
}

private struct NovaCompanyRingSegment: Shape {
    let index: Int
    let count: Int
    let gapDegrees: Double

    func path(in rect: CGRect) -> Path {
        let total = 360.0 / Double(max(count, 1))
        let start = -90.0 + Double(index) * total + gapDegrees / 2
        let end = -90.0 + Double(index + 1) * total - gapDegrees / 2
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.66
        var path = Path()
        path.addArc(center: center, radius: outer,
            startAngle: .degrees(start), endAngle: .degrees(end), clockwise: false)
        path.addArc(center: center, radius: inner,
            startAngle: .degrees(end), endAngle: .degrees(start), clockwise: true)
        path.closeSubpath()
        return path
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
                }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier(identifier).accessibilityValue(expanded ? RDLocalization.string("localizable.nova.workspace.expanded", table: .localizable, fallback: "Açık") : RDLocalization.string("localizable.nova.workspace.collapsed", table: .localizable, fallback: "Kapalı"))
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
