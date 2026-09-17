import SwiftUI

/// One workplace's whole record: the document that stands, what is open on top
/// of it, and every version behind it. A finalised version is never edited here
/// because it is never editable anywhere.
struct NovaRiskDetailSheet: View {
    let row: NovaRiskRow
    var canWrite: Bool = true
    let onNewVersion: () -> Void
    var onEdit: ((NovaRiskVersion) -> Void)?
    var onCancelDraft: (() -> Void)?
    let onFinalize: (Int) -> Void
    let onClose: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        NovaPopupHeading(text: row.workplaceName ?? RDLocalization.string(
                            "localizable.nova.risk.row.workplace", table: .localizable, fallback: "İşyeri"), symbol: "checkmark.shield")
                        if let company = row.companyName {
                            NovaText(text: company, style: .meta,
                                color: NovaColorToken.textSecondary.color(in: scheme))
                        }
                        NovaText(text: NovaRiskWords.explain(row), style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                    }
                    facts
                    if row.hasOpenDraft { draftCard }
                    if canWrite { actions }
                    history
                }
                .padding(20).novaPopupContentSize()
            }
        }
        .accessibilityIdentifier("nova.risk.detail")
    }

    @ViewBuilder private var facts: some View {
        NovaCard(padding: 14) {
            let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                cell("calendar", RDLocalization.string("localizable.nova.risk.fact.assessment",
                    table: .localizable, fallback: "Değerlendirme tarihi"),
                    row.currentAssessmentOn ?? unset)
                cell("calendar.badge.clock", RDLocalization.string("localizable.nova.risk.fact.until",
                    table: .localizable, fallback: "Geçerlilik"), row.validUntil ?? unset)
                cell("clock.arrow.circlepath", RDLocalization.string("localizable.nova.risk.fact.period",
                    table: .localizable, fallback: "Süre"),
                    row.periodYears.map { String(format: RDLocalization.string(
                        "localizable.nova.risk.row.years", table: .localizable, fallback: "%d yıl"), $0) } ?? unset,
                    detail: row.periodSource?.title ?? "")
                cell("number", RDLocalization.string("localizable.nova.risk.fact.version",
                    table: .localizable, fallback: "Yürürlükteki sürüm"),
                    row.currentVersion > 0 ? "v\(row.currentVersion)" : unset,
                    detail: row.currentKind?.title ?? "")
            }
            NovaHelpHint(text: RDLocalization.string("localizable.nova.risk.period.attribution",
                table: .localizable,
                fallback: "Süre kaynağı her satırda yazılıdır. Uzmanın kendi belirlediği süre mevzuat gereği olarak sunulmaz."))
            if row.sourceDrift {
                NovaHelpHint(text: row.driftNote ?? RDLocalization.string("localizable.nova.risk.fact.drift",
                    table: .localizable,
                    fallback: "Kaynak analiz bu belge hazırlandıktan sonra değişti. Belge değiştirilmedi."))
            }
        }
    }

    @ViewBuilder private var draftCard: some View {
        NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 6) {
                NovaText(text: RDLocalization.string("localizable.nova.risk.draft.title", table: .localizable,
                    fallback: "Açık taslak"), style: .cardTitle)
                NovaText(text: (row.draftKind?.title ?? "") + " · v\(row.draftVersion ?? 0)", style: .meta,
                    color: NovaColorToken.textSecondary.color(in: scheme))
                if let reason = row.draftReason, !reason.isEmpty {
                    NovaText(text: reason, style: .body)
                }
                NovaText(text: RDLocalization.string("localizable.nova.risk.draft.note", table: .localizable,
                    fallback: "Taslak belge değildir. Tamamlanana kadar yürürlükteki sürüm değişmez."),
                    style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                if canWrite, let version = row.draftVersion {
                    if let draft = row.versions.first(where: { $0.version == version }), let onEdit {
                        NovaButton(label: "Taslağı düzenle", symbol: "pencil", variant: .surface) { onEdit(draft) }
                    }
                    if let onCancelDraft { NovaButton(label: "Taslağı iptal et", symbol: "xmark", variant: .surface, action: onCancelDraft) }
                    NovaButton(label: RDLocalization.string("localizable.nova.risk.draft.finalize",
                        table: .localizable, fallback: "Taslağı tamamla"),
                        symbol: "checkmark.seal", variant: .primary) { onFinalize(version) }
                }
            }
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !row.hasOpenDraft {
                NovaButton(label: RDLocalization.string("localizable.nova.risk.action.new", table: .localizable,
                    fallback: "Yeni sürüm başlat"), symbol: "plus.circle", variant: .primary, action: onNewVersion)
            }
            NovaText(text: NovaRiskWords.analysisNotAssessment, style: .meta,
                color: NovaColorToken.textSecondary.color(in: scheme))
        }
    }

    @ViewBuilder private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: RDLocalization.string("localizable.nova.risk.history", table: .localizable,
                fallback: "Sürüm geçmişi"), style: .cardTitle)
            if row.versions.isEmpty {
                NovaText(text: RDLocalization.string("localizable.nova.risk.history.empty", table: .localizable,
                    fallback: "Henüz sürüm yok."), style: .meta,
                    color: NovaColorToken.textMuted.color(in: scheme))
            }
            ForEach(row.versions) { version in
                NovaCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            NovaText(text: "v\(version.version) · " + version.kind.title, style: .cardTitle)
                            Spacer(minLength: 0)
                            NovaStatusPill(label: stateWord(version.state),
                                status: version.isFinal ? .success
                                    : version.isDraft ? .info : .neutral)
                        }
                        NovaText(text: version.kind.explain, style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                        HStack(spacing: 10) {
                            NovaSizedText(text: RDLocalization.string("localizable.nova.risk.fact.assessment",
                                table: .localizable, fallback: "Değerlendirme tarihi") + ": " + version.assessmentOn,
                                size: 10.5, weight: "Medium")
                            if let until = version.validUntil {
                                NovaSizedText(text: RDLocalization.string("localizable.nova.risk.fact.until",
                                    table: .localizable, fallback: "Geçerlilik") + ": " + until,
                                    size: 10.5, weight: "Medium")
                            }
                        }
                        if let reason = version.reason, !reason.isEmpty {
                            NovaText(text: reason, style: .meta,
                                color: NovaColorToken.textSecondary.color(in: scheme))
                        }
                        if let note = version.cancellationNote, !note.isEmpty {
                            NovaText(text: "İptal gerekçesi: " + note, style: .body)
                        }
                        if !version.scope.isEmpty {
                            NovaText(text: RDLocalization.string("localizable.nova.risk.scope", table: .localizable,
                                fallback: "Kapsam") + ": " + version.scope.joined(separator: ", "),
                                style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                        }
                        if !version.sources.isEmpty {
                            NovaAnalysisTag(symbol: "arrow.down.doc",
                                text: String(format: RDLocalization.string(
                                    "localizable.nova.risk.sources", table: .localizable,
                                    fallback: "%d analiz bulgusu aktarıldı"), version.sources.count),
                                status: .info)
                        }
                        ForEach(version.impacts) { impact in
                            NovaAnalysisTag(symbol: "arrow.triangle.branch",
                                text: impact.targetRef + " · " + impact.actionTitle, status: .warning)
                        }
                        if let source = version.periodSource {
                            NovaAnalysisTag(symbol: source.needsReview ? "exclamationmark.circle" : "checkmark.seal",
                                text: source.title, status: source.needsReview ? .warning : .success)
                        }
                    }
                }
            }
        }
    }

    private var unset: String {
        RDLocalization.string("localizable.nova.risk.unset", table: .localizable, fallback: "Belirtilmedi")
    }
    private func stateWord(_ value: String) -> String {
        switch value {
        case "cancelled": return "İptal edildi"
        case "draft": return RDLocalization.string("localizable.nova.risk.version.draft", table: .localizable, fallback: "Taslak")
        case "final": return RDLocalization.string("localizable.nova.risk.version.final", table: .localizable, fallback: "Yürürlükte")
        default: return RDLocalization.string("localizable.nova.risk.version.superseded", table: .localizable, fallback: "Geçmiş")
        }
    }
    @ViewBuilder private func cell(_ symbol: String, _ label: String, _ value: String,
                                   detail: String = "") -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
                .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
            VStack(alignment: .leading, spacing: 1) {
                NovaSizedText(text: label, size: 9, weight: "Medium",
                    color: NovaColorToken.textMuted.color(in: scheme))
                NovaSizedText(text: value, size: 12, weight: "Bold")
                if !detail.isEmpty {
                    NovaSizedText(text: detail, size: 9.5, weight: "Medium",
                        color: NovaColorToken.textSecondary.color(in: scheme))
                }
            }
            Spacer(minLength: 0)
        }
    }
}

/// Opening a new version. The kind is chosen first, because the kind decides
/// which dates the form may even ask for.
struct NovaRiskVersionSheet: View {
    @State var draft: NovaRiskVersionDraft
    let catalogue: NovaRiskCatalogue?
    let onSave: (NovaRiskVersionDraft) async -> String?
    let onClose: () -> Void
    @State private var failure: String?
    @State private var saving = false
    @State private var choosingKind = false
    @State private var scopeEntry = ""
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NovaPopupHeading(text: draft.versionToEdit != nil ? "Taslağı düzenle" : RDLocalization.string("localizable.nova.risk.version.title",
                        table: .localizable, fallback: "Yeni sürüm"), symbol: "checkmark.shield")
                    NovaFileChooserButton(
                        label: RDLocalization.string("localizable.nova.risk.version.kind",
                            table: .localizable, fallback: "Sürüm türü"),
                        value: draft.kind.title, isOpen: choosingKind,
                        identifier: "nova.risk.version.kind") { choosingKind.toggle() }
                        .disabled(draft.versionToEdit != nil)
                    if choosingKind {
                        NovaFileChooserPanel(
                            options: NovaRiskKind.allCases.filter { $0 != .rescan }.map { .init(id: $0.rawValue, title: $0.title) },
                            selected: draft.kind.rawValue,
                            identifier: "nova.risk.version.kind.panel") { value in
                            if let value, let kind = NovaRiskKind(rawValue: value) { draft.kind = kind }
                            choosingKind = false
                        }
                    }
                    NovaHelpHint(text: draft.kind.explain)

                    // Only a renewal carries a date of its own; the others keep
                    // the original legal date, so the field is not offered.
                    if draft.kind.carriesAssessmentDate {
                        NovaDayField(label: RDLocalization.string("localizable.nova.risk.fact.assessment",
                            table: .localizable, fallback: "Değerlendirme tarihi"),
                            value: $draft.assessmentOn, identifier: "nova.risk.version.assessed")
                    } else {
                        NovaHelpHint(text: RDLocalization.string("localizable.nova.risk.version.keepdate",
                            table: .localizable,
                            fallback: "Bu tür, belgenin özgün değerlendirme tarihini korur."))
                    }
                    NovaDayField(label: RDLocalization.string("localizable.nova.risk.version.revision",
                        table: .localizable, fallback: "Revizyon tarihi"),
                        value: $draft.revisionOn, identifier: "nova.risk.version.revised", isClearable: true)

                    if draft.kind.needsScope { scopeField }
                    if draft.kind.needsReason {
                        VStack(alignment: .leading, spacing: 4) {
                            NovaText(text: RDLocalization.string("localizable.nova.risk.version.reason",
                                table: .localizable, fallback: "Gerekçe"), style: .label)
                            TextEditor(text: $draft.reason)
                                .frame(minHeight: 70)
                                .accessibilityIdentifier("nova.risk.version.reason")
                        }
                    }
                    if let failure {
                        NovaText(text: failure, style: .meta,
                            color: NovaColorToken.statusDangerInk.color(in: scheme))
                    }
                    HStack(spacing: 10) {
                        NovaButton(label: RDLocalization.string("localizable.nova.risk.cancel",
                            table: .localizable, fallback: "Vazgeç"), symbol: "xmark",
                            variant: .surface, action: onClose)
                        NovaButton(label: RDLocalization.string("localizable.nova.risk.version.save",
                            table: .localizable, fallback: "Taslağı aç"), symbol: "checkmark",
                            variant: .primary) {
                            Task { saving = true; failure = await onSave(draft); saving = false }
                        }
                        .disabled(saving)
                    }
                }
                .padding(20).novaPopupContentSize()
            }
        }
        .preference(key: NovaPopupBusyKey.self, value: saving)
        .accessibilityIdentifier("nova.risk.version.sheet")
    }

    @ViewBuilder private var scopeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            NovaText(text: RDLocalization.string("localizable.nova.risk.scope", table: .localizable,
                fallback: "Kapsam"), style: .label)
            HStack(spacing: 8) {
                TextField(RDLocalization.string("localizable.nova.risk.scope.add", table: .localizable,
                    fallback: "Bölüm adı"), text: $scopeEntry)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("nova.risk.version.scope.entry")
                NovaButton(label: RDLocalization.string("localizable.nova.risk.scope.button",
                    table: .localizable, fallback: "Ekle"), symbol: "plus", variant: .surface) {
                    let value = scopeEntry.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !value.isEmpty, draft.scope.count < 50 else { return }
                    draft.scope.append(value); scopeEntry = ""
                }
            }
            ForEach(draft.scope, id: \.self) { entry in
                HStack(spacing: 6) {
                    NovaAnalysisTag(symbol: "square.dashed", text: entry, status: .info)
                    Button { draft.scope.removeAll { $0 == entry } } label: {
                        Image(systemName: "xmark.circle").font(.system(size: 12))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

/// Making a version the document that stands. Only a renewal asks for a period,
/// and the expert's own number is stored and shown as the expert's.
struct NovaRiskFinalizeSheet: View {
    @State var draft: NovaRiskFinalizeDraft
    let catalogue: NovaRiskCatalogue?
    let onSave: (NovaRiskFinalizeDraft) async -> String?
    let onClose: () -> Void
    @State private var failure: String?
    @State private var saving = false
    @State private var choosingRule = false
    @Environment(\.colorScheme) private var scheme

    private var expertOption: String {
        RDLocalization.string("localizable.nova.risk.period.own", table: .localizable, fallback: "Kendi belirlediğim süre")
    }

    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NovaPopupHeading(text: RDLocalization.string("localizable.nova.risk.finalize.title",
                        table: .localizable, fallback: "Sürümü tamamla"), symbol: "checkmark.shield")
                    NovaHelpHint(text: RDLocalization.string("localizable.nova.risk.finalize.note",
                        table: .localizable,
                        fallback: "Tamamlanan sürüm yürürlüğe girer ve bir daha değiştirilemez. Doğrulama sizin beyanınızdır."))

                    if draft.kind == .full {
                    if let catalogue, !catalogue.rules.isEmpty {
                        NovaFileChooserButton(
                            label: RDLocalization.string("localizable.nova.risk.finalize.source",
                                table: .localizable, fallback: "Süre kaynağı"),
                            value: draft.ruleCode.isEmpty ? expertOption : draft.ruleCode,
                            isOpen: choosingRule,
                            identifier: "nova.risk.finalize.rule") { choosingRule.toggle() }
                        if choosingRule {
                            NovaFileChooserPanel(
                                options: [.init(id: nil, title: expertOption)]
                                    + catalogue.rules.map { .init(id: $0.ruleCode, title: $0.ruleCode) },
                                selected: draft.ruleCode.isEmpty ? nil : draft.ruleCode,
                                identifier: "nova.risk.finalize.rule.panel") { value in
                                draft.ruleCode = value ?? ""
                                choosingRule = false
                            }
                        }
                    } else if let years = draft.suggestedYears {
                        NovaHelpHint(text: String(format: RDLocalization.string("localizable.nova.risk.finalize.hazard.hint",
                            table: .localizable,
                            fallback: "İşyerinin tehlike sınıfına göre %d yıl otomatik dolduruldu. Gerekirse değiştirebilirsiniz."), years))
                    } else {
                        // The honest answer while nothing is approved and the
                        // workplace has no hazard class on file either.
                        NovaHelpHint(text: RDLocalization.string("localizable.nova.risk.finalize.norules",
                            table: .localizable,
                            fallback: "Onaylanmış bir süre kataloğu yok. Gireceğiniz süre \"uzman tarafından belirlenen\" olarak kaydedilir."))
                    }

                    if draft.ruleCode.isEmpty {
                        NovaFormValueRow(label: "Geçerlilik süresi", symbol: "clock") {
                            HStack(spacing: 6) {
                                TextField("", text: $draft.periodYears).keyboardType(.numberPad)
                                    .font(NovaFont.font(.body)).multilineTextAlignment(.trailing).frame(width: 46).frame(minHeight: 36)
                                    .accessibilityLabel("Geçerlilik süresi, yıl")
                                    .accessibilityIdentifier("nova.risk.finalize.years")
                                NovaText(text: "yıl", style: .meta)
                            }
                        }
                    }
                    } else {
                        NovaHelpHint(text: "Bu revizyon mevcut değerlendirme tarihini ve süre kaynağını korur.")
                    }
                    if let failure {
                        NovaText(text: failure, style: .meta,
                            color: NovaColorToken.statusDangerInk.color(in: scheme))
                    }
                    HStack(spacing: 10) {
                        NovaButton(label: RDLocalization.string("localizable.nova.risk.cancel",
                            table: .localizable, fallback: "Vazgeç"), symbol: "xmark",
                            variant: .surface, action: onClose)
                        NovaButton(label: RDLocalization.string("localizable.nova.risk.finalize.save",
                            table: .localizable, fallback: "Tamamla"), symbol: "checkmark.seal",
                            variant: .primary) {
                            Task { saving = true; failure = await onSave(draft); saving = false }
                        }
                        .disabled(saving)
                    }
                }
                .padding(20).novaPopupContentSize()
            }
        }
        .preference(key: NovaPopupBusyKey.self, value: saving)
        .accessibilityIdentifier("nova.risk.finalize.sheet")
    }
}


struct NovaRiskCancelDraftSheet: View {
    let onConfirm: (String) async -> String?
    @State private var reason = ""
    @State private var busy = false
    @State private var failure: String?
    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NovaPopupHeading(text: "Taslağı iptal et", symbol: "checkmark.shield")
                    NovaText(text: "Taslak geçmişte korunur. Yürürlükteki sürüm ve tarihleri değişmez.", style: .body)
                    TextField("İptal gerekçesi (en az 10 karakter)", text: $reason, axis: .vertical).lineLimit(3...6)
                    if let failure { NovaText(text: failure, style: .meta) }
                    NovaButton(label: "Taslağı iptal et", symbol: "xmark", isEnabled: !busy && reason.trimmingCharacters(in: .whitespacesAndNewlines).count >= 10) {
                        Task { busy = true; failure = await onConfirm(reason.trimmingCharacters(in: .whitespacesAndNewlines)); busy = false }
                    }
                }.padding(20).novaPopupContentSize().disabled(busy)
            }
        }.preference(key: NovaPopupBusyKey.self, value: busy)
    }
}
