import SwiftUI

/// The hand-entered record, asked one step at a time. Every step is revisitable,
/// a finished step carries a green tick, and the bar counts exactly the steps
/// that are finished — never a step that was merely opened.
struct NovaManualNonconformityScreen: View {
    let workplaces: [NovaNonconformityWorkplace]
    let save: (NovaManualDraft) async -> String?
    let onBack: () -> Void
    var isImprovementAllowed = true
    @Environment(\.colorScheme) private var scheme
    @State private var draft = NovaManualDraft()
    @State private var open: NovaManualStep? = nil
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    progress
                    ForEach(NovaManualStep.allCases) { step in
                        accordion(step)
                    }
                    if let error {
                        NovaCard(padding: 14) {
                            NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme))
                        }
                    }
                    saveButton
                }.padding(20).padding(.bottom, novaTabBarInset)
            }
        }.background(NovaKeyboardDismissArea())
    }

    private var header: some View {
        HStack(spacing: 10) {
            NovaBackButton(isEnabled: !saving) { onBack() }
            VStack(alignment: .leading, spacing: 2) {
                NovaText(text: RDLocalization.string("localizable.nova.manual.title", table: .localizable, fallback: "Elle Uygunsuzluk"), style: .screenTitle)
                NovaText(text: RDLocalization.string("localizable.nova.manual.subtitle", table: .localizable,
                    fallback: "Yapay zekâ kullanılmaz; bilgileri siz girersiniz."), style: .metaQuiet)
            }
            Spacer(minLength: 0)
        }
    }

    private var progress: some View {
        NovaCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    NovaText(text: String(format: RDLocalization.string("localizable.nova.manual.progress", table: .localizable,
                        fallback: "%1$d/%2$d başlık tamamlandı"), draft.completedCount, NovaManualStep.allCases.count), style: .label)
                    Spacer(minLength: 0)
                    if draft.canSave {
                        NovaStatusPill(label: RDLocalization.string("localizable.nova.manual.ready", table: .localizable, fallback: "Kaydedilebilir"), status: .success)
                    } else {
                        NovaStatusPill(label: RDLocalization.string("localizable.nova.manual.pending", table: .localizable, fallback: "Zorunlu alan eksik"), status: .warning)
                    }
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NovaColorToken.borderMuted.color(in: scheme))
                        Capsule().fill(NovaColorToken.accent.color(in: scheme))
                            .frame(width: max(0, proxy.size.width * draft.progress))
                    }
                }.frame(height: 6)
                NovaText(text: RDLocalization.string("localizable.nova.manual.progress.hint", table: .localizable,
                    fallback: "Mevzuat, sorumlu ve skorlama isteğe bağlıdır; girildiğinde tamamlandı sayılır."), style: .metaQuiet)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityElement(children: .combine)
            .accessibilityIdentifier("manual.progress")
    }

    @ViewBuilder private func accordion(_ step: NovaManualStep) -> some View {
        NovaCompanyAccordion(title: title(step), symbol: symbol(step),
            state: draft.isComplete(step) ? .complete : .missing,
            identifier: "manual.step.\(step.rawValue)",
            expanded: Binding(get: { open == step }, set: { open = $0 ? step : nil })) {
            VStack(alignment: .leading, spacing: 10) {
                switch step {
                case .company: companyStep
                case .hazard: hazardStep
                case .scoring: NovaRiskScoreEditor(score: $draft.score)
                case .legislation:
                    area(RDLocalization.string("localizable.nova.manual.legislation.hint", table: .localizable,
                        fallback: "İlgili madde, yönetmelik veya standart"), $draft.legislation, id: "legislation")
                case .responsible:
                    field(RDLocalization.string("localizable.nova.manual.responsible.hint", table: .localizable,
                        fallback: "Firmadaki sorumlu kişi"), $draft.responsible, id: "responsible")
                    NovaText(text: RDLocalization.string("localizable.nova.manual.responsible.note", table: .localizable,
                        fallback: "Bu kişi bir uygulama kullanıcısı değildir; yalnız kayıtta görünür."), style: .metaQuiet)
                }
                advance(step)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A finished step offers the next unfinished one instead of leaving the
    /// expert to find it.
    @ViewBuilder private func advance(_ step: NovaManualStep) -> some View {
        if draft.isComplete(step), let next = draft.nextIncomplete(after: step) {
            NovaButton(label: String(format: RDLocalization.string("localizable.nova.manual.next", table: .localizable,
                fallback: "Sıradaki: %@"), title(next)), symbol: "chevron.down", variant: .surface) { open = next }
                .accessibilityIdentifier("manual.next.\(step.rawValue)")
        }
    }

    @ViewBuilder private var companyStep: some View {
        if workplaces.isEmpty {
            NovaText(text: RDLocalization.string("localizable.nova.bridge.no.workplace", table: .localizable,
                fallback: "Bu firmada kayıt açılacak bir işyeri yok."), style: .metaQuiet)
        } else {
            ForEach(workplaces) { place in
                Button { draft.workplaceID = place.id } label: {
                    HStack(spacing: 8) {
                        Image(systemName: draft.workplaceID == place.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(draft.workplaceID == place.id ? NovaColorToken.accentInk.color(in: scheme)
                                                                           : NovaColorToken.borderStrong.color(in: scheme))
                        NovaText(text: place.name)
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain)
                    .accessibilityIdentifier("manual.workplace.\(place.id.uuidString.lowercased())")
            }
        }
    }

    @ViewBuilder private var hazardStep: some View {
        field(RDLocalization.string("localizable.nova.manual.hazard.title", table: .localizable, fallback: "Tehlike başlığı"), $draft.title, id: "title")
        area(RDLocalization.string("localizable.nova.manual.hazard.description", table: .localizable, fallback: "Açıklama"), $draft.hazardDescription, id: "description")
        area(RDLocalization.string("localizable.nova.manual.hazard.measure", table: .localizable, fallback: "Önlem"), $draft.controlMeasure, id: "measure")
        VStack(alignment: .leading, spacing: 4) {
            NovaText(text: RDLocalization.string("localizable.nova.nonconformity.field.severity", table: .localizable, fallback: "Önem derecesi"), style: .label,
                color: NovaColorToken.textTertiary.color(in: scheme))
            Picker("", selection: $draft.severity) {
                ForEach(NovaNonconformitySeverity.allCases) { value in
                    Text(verbatim: NovaNonconformityWords.severity(value)).tag(value)
                }
            }.pickerStyle(.segmented).accessibilityIdentifier("manual.field.severity")
        }
        if isImprovementAllowed {
            VStack(alignment: .leading, spacing: 4) {
                NovaText(text: RDLocalization.string("localizable.nova.analysis.file.kind", table: .localizable, fallback: "Kayıt türü"), style: .label,
                    color: NovaColorToken.textTertiary.color(in: scheme))
                Picker("", selection: $draft.recordKind) {
                    ForEach(NovaNonconformityRecordKind.allCases) { value in
                        Text(verbatim: NovaNonconformityWords.recordKind(value)).tag(value)
                    }
                }.pickerStyle(.segmented).accessibilityIdentifier("manual.field.kind")
            }
        }
    }

    private func field(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextField(label, text: text).font(.custom("PlusJakartaSans-Medium", size: 14))
                .frame(minHeight: 36).accessibilityIdentifier("manual.field.\(id)")
        }
    }
    private func area(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextEditor(text: text).font(.custom("PlusJakartaSans-Medium", size: 14))
                .frame(minHeight: 72).scrollContentBackground(.hidden)
                .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("manual.field.\(id)")
        }
    }

    private var saveButton: some View {
        NovaButton(label: RDLocalization.string("localizable.nova.manual.save", table: .localizable, fallback: "Kaydı aç"),
            symbol: "checkmark", isEnabled: draft.canSave && !saving, isLoading: saving) {
            Task {
                saving = true; error = nil
                error = await save(draft)
                saving = false
            }
        }.accessibilityIdentifier("manual.save")
    }

    private func title(_ step: NovaManualStep) -> String {
        switch step {
        case .company: return RDLocalization.string("localizable.nova.manual.step.company", table: .localizable, fallback: "İşyeri")
        case .hazard: return RDLocalization.string("localizable.nova.manual.step.hazard", table: .localizable, fallback: "Uygunsuzluk")
        case .scoring: return RDLocalization.string("localizable.nova.manual.step.scoring", table: .localizable, fallback: "Risk metodu ve skorlama")
        case .legislation: return RDLocalization.string("localizable.nova.manual.step.legislation", table: .localizable, fallback: "Mevzuat bilgisi")
        case .responsible: return RDLocalization.string("localizable.nova.manual.step.responsible", table: .localizable, fallback: "Firma sorumlusu")
        }
    }
    private func symbol(_ step: NovaManualStep) -> String {
        switch step {
        case .company: return "building.2"
        case .hazard: return "exclamationmark.triangle"
        case .scoring: return "chart.bar"
        case .legislation: return "doc.text"
        case .responsible: return "person.crop.rectangle"
        }
    }
}
