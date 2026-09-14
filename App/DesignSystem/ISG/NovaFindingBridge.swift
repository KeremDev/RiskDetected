import SwiftUI

/// One finding out of a completed photo analysis, reduced to what opening a
/// nonconformity needs. The analysis row itself is never copied or rewritten.
struct NovaAnalysisFinding: Equatable, Identifiable {
    let id: UUID
    let ordinal: Int
    let title: String
    let category: String?
    /// The legacy band: low, medium, high, critical - or unknown, which the
    /// server refuses to map on its own.
    let band: String
    let methodLabel: String
    var isUnreadable: Bool { !["low", "medium", "high", "critical"].contains(band) }
}

/// What happened to one finding after the expert pressed open.
enum NovaFindingOutcome: Equatable {
    case untouched
    case opened
    case alreadyOpen
    case failed(String)
}

struct NovaFindingSelectionScreen: View {
    let findings: [NovaAnalysisFinding]
    let workplaces: [NovaNonconformityWorkplace]
    let open: (NovaAnalysisFinding, UUID, NovaNonconformitySeverity?) async -> NovaFindingOutcome
    let onBack: () -> Void
    let onFinished: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var selected: Set<UUID> = []
    @State private var chosenSeverity: [UUID: NovaNonconformitySeverity] = [:]
    @State private var outcomes: [UUID: NovaFindingOutcome] = [:]
    @State private var workplace: UUID?
    @State private var running = false
    @State private var finished = false

    /// A finding whose band cannot be read is only selectable once the expert
    /// has chosen a severity for it. Nothing is guessed on their behalf.
    private func isReady(_ finding: NovaAnalysisFinding) -> Bool {
        !finding.isUnreadable || chosenSeverity[finding.id] != nil
    }
    private var openable: [NovaAnalysisFinding] {
        findings.filter { selected.contains($0.id) && isReady($0) }
    }

    var body: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    if workplaces.isEmpty {
                        NovaCard(padding: 20) {
                            NovaText(text: RDLocalization.string("localizable.nova.bridge.no.workplace", table: .localizable,
                                fallback: "Bu firmada kayıt açılacak bir işyeri yok."), style: .metaQuiet)
                        }
                    } else {
                        workplacePicker
                        ForEach(findings) { finding in row(finding) }
                        footer
                    }
                }.padding(20)
            }
        }
    }

    @ViewBuilder private var header: some View {
        HStack {
            Button(action: onBack) { NovaIcon(symbol: "chevron.left", size: 22).frame(width: 44, height: 44) }
                .disabled(running)
                .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.shell.back", table: .localizable, fallback: "Geri")))
                .accessibilityIdentifier("bridge.back")
            NovaText(text: RDLocalization.string("localizable.nova.bridge.title", table: .localizable,
                fallback: "Bulgulardan uygunsuzluk"), style: .screenTitle)
        }
        NovaText(text: RDLocalization.string("localizable.nova.bridge.detail", table: .localizable,
            fallback: "Analiz kaydı olduğu gibi kalır. Seçtiğiniz bulgular için ayrı uygunsuzluk açılır."), style: .metaQuiet)
    }

    @ViewBuilder private var workplacePicker: some View {
        NovaCard(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                NovaText(text: RDLocalization.string("localizable.nova.nonconformity.field.workplace", table: .localizable, fallback: "İşyeri"), style: .metaQuiet)
                ForEach(workplaces) { place in
                    Button { workplace = place.id } label: {
                        HStack {
                            NovaIcon(symbol: workplace == place.id ? "checkmark.circle" : "circle", size: 20)
                            NovaText(text: place.name)
                        }.frame(minHeight: 44)
                    }.buttonStyle(.plain).disabled(running)
                        .accessibilityIdentifier("bridge.workplace.\(place.id.uuidString.lowercased())")
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.onAppear { if workplace == nil { workplace = workplaces.first?.id } }
    }

    private func row(_ finding: NovaAnalysisFinding) -> some View {
        NovaCard(padding: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    if selected.contains(finding.id) { selected.remove(finding.id) } else { selected.insert(finding.id) }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        NovaIcon(symbol: selected.contains(finding.id) ? "checkmark.circle" : "circle", size: 20)
                        VStack(alignment: .leading, spacing: 4) {
                            NovaText(text: finding.title, style: .cardTitle)
                            if let category = finding.category { NovaText(text: category, style: .metaQuiet) }
                        }
                        Spacer()
                    }.frame(minHeight: 44)
                }.buttonStyle(.plain).disabled(running || !isReady(finding))
                    .accessibilityIdentifier("bridge.finding.\(finding.id.uuidString.lowercased())")
                HStack(spacing: 8) {
                    NovaStatusPill(label: bandLabel(finding.band), status: bandStatus(finding.band))
                    NovaText(text: finding.methodLabel, style: .metaQuiet)
                }
                if finding.isUnreadable { unreadable(finding) }
                if let outcome = outcomes[finding.id] { outcomeLine(outcome) }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func unreadable(_ finding: NovaAnalysisFinding) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NovaText(text: RDLocalization.string("localizable.nova.bridge.band.unreadable", table: .localizable,
                fallback: "Bu bulgunun risk bandı okunamadı. Önem derecesini siz seçin."), style: .metaQuiet)
            Picker("", selection: Binding(get: { chosenSeverity[finding.id] ?? .medium },
                                          set: { chosenSeverity[finding.id] = $0 })) {
                ForEach(NovaNonconformitySeverity.allCases) { value in
                    Text(verbatim: severityLabel(value)).tag(value)
                }
            }.pickerStyle(.segmented).disabled(running)
                .accessibilityIdentifier("bridge.severity.\(finding.id.uuidString.lowercased())")
        }
    }

    @ViewBuilder private func outcomeLine(_ outcome: NovaFindingOutcome) -> some View {
        switch outcome {
        case .untouched: EmptyView()
        case .opened:
            NovaText(text: RDLocalization.string("localizable.nova.bridge.outcome.opened", table: .localizable,
                fallback: "Uygunsuzluk açıldı"), style: .metaQuiet)
        case .alreadyOpen:
            NovaText(text: RDLocalization.string("localizable.nova.bridge.outcome.existing", table: .localizable,
                fallback: "Bu bulgunun uygunsuzluğu zaten vardı"), style: .metaQuiet)
        case .failed(let reason):
            NovaText(text: reason, style: .metaQuiet)
        }
    }

    @ViewBuilder private var footer: some View {
        VStack(alignment: .leading, spacing: 10) {
            if finished {
                // Never a blanket success: the per-row lines above are the answer.
                NovaText(text: RDLocalization.string("localizable.nova.bridge.finished", table: .localizable,
                    fallback: "İşlem bitti. Her bulgunun sonucu kendi satırında yazıyor."), style: .metaQuiet)
                NovaButton(label: RDLocalization.string("localizable.nova.bridge.done", table: .localizable, fallback: "Listeye dön"), symbol: "list.bullet", variant: .surface) { onFinished() }
                    .accessibilityIdentifier("bridge.done")
            } else {
                NovaButton(label: RDLocalization.string("localizable.nova.bridge.open.selected", table: .localizable, fallback: "Seçilenleri aç"), symbol: "checkmark",
                    isEnabled: !running && workplace != nil && !openable.isEmpty, isLoading: running) { Task { await run() } }
                    .accessibilityIdentifier("bridge.open")
            }
        }
    }

    private func run() async {
        guard let target = workplace else { return }
        running = true
        for finding in openable {
            // The finding id is the mutation key, so pressing open twice for the
            // same finding replays instead of opening a second record.
            let outcome = await open(finding, target, chosenSeverity[finding.id])
            outcomes[finding.id] = outcome
        }
        running = false
        finished = true
    }

    private func bandStatus(_ band: String) -> NovaStatus {
        switch band {
        case "critical", "high": return .danger
        case "medium": return .warning
        case "low": return .neutral
        default: return .info
        }
    }
    private func bandLabel(_ band: String) -> String {
        switch band {
        case "critical": return RDLocalization.string("localizable.nova.nonconformity.severity.critical", table: .localizable, fallback: "Kritik")
        case "high": return RDLocalization.string("localizable.nova.nonconformity.severity.high", table: .localizable, fallback: "Yüksek")
        case "medium": return RDLocalization.string("localizable.nova.nonconformity.severity.medium", table: .localizable, fallback: "Orta")
        case "low": return RDLocalization.string("localizable.nova.nonconformity.severity.low", table: .localizable, fallback: "Düşük")
        default: return RDLocalization.string("localizable.nova.bridge.band.unknown", table: .localizable, fallback: "Bilinmiyor")
        }
    }
    private func severityLabel(_ value: NovaNonconformitySeverity) -> String {
        switch value {
        case .critical: return RDLocalization.string("localizable.nova.nonconformity.severity.critical", table: .localizable, fallback: "Kritik")
        case .high: return RDLocalization.string("localizable.nova.nonconformity.severity.high", table: .localizable, fallback: "Yüksek")
        case .medium: return RDLocalization.string("localizable.nova.nonconformity.severity.medium", table: .localizable, fallback: "Orta")
        case .low: return RDLocalization.string("localizable.nova.nonconformity.severity.low", table: .localizable, fallback: "Düşük")
        }
    }
}
