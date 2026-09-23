import SwiftUI

/// One drill: what it rehearsed, when, who was there and what came out of it.
struct NovaDrillDetailSheet: View {
    let drill: NovaDrill
    var canWrite: Bool = true
    let onRecord: () -> Void
    let onCancel: (String) async -> String?
    let onClose: () -> Void
    @State private var reason = ""
    @State private var askingCancel = false
    @State private var failure: String?
    @State private var working = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        NovaPopupHeading(text: drill.planScope ?? RDLocalization.string(
                            "localizable.nova.drill.row.plan", table: .localizable, fallback: "Acil durum planı"), symbol: "figure.walk")
                        NovaText(text: [drill.workplaceName, drill.companyName]
                            .compactMap { $0 }.joined(separator: " · "), style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                        NovaText(text: NovaDrillWords.explain(drill), style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                    }
                    facts
                    if drill.performed { outcome }
                    if drill.performed { participants }
                    if let failure {
                        NovaText(text: failure, style: .meta,
                            color: NovaColorToken.statusDangerInk.color(in: scheme))
                    }
                    if canWrite && !drill.performed && drill.state != .cancelled { actions }
                }
                .padding(20).novaPopupContentSize()
            }
        }
        .accessibilityIdentifier("nova.drill.detail")
    }

    @ViewBuilder private var facts: some View {
        NovaCard(padding: 14) {
            let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                cell("calendar", RDLocalization.string("localizable.nova.drill.row.planned",
                    table: .localizable, fallback: "Planlanan"), drill.plannedOn)
                cell("checkmark.circle", RDLocalization.string("localizable.nova.drill.row.performed",
                    table: .localizable, fallback: "Yapılan"),
                    drill.performedOn ?? RDLocalization.string("localizable.nova.drill.unset",
                        table: .localizable, fallback: "Yapılmadı"))
                cell("doc.text", RDLocalization.string("localizable.nova.drill.row.version",
                    table: .localizable, fallback: "Plan sürümü"), "v\(drill.planVersion)",
                    detail: drill.planVersionSuperseded
                        ? RDLocalization.string("localizable.nova.drill.detail.superseded",
                            table: .localizable, fallback: "sonradan güncellendi") : "")
                cell("person.2", RDLocalization.string("localizable.nova.drill.detail.participants",
                    table: .localizable, fallback: "Katılımcı"), "\(drill.participantCount)")
            }
            NovaHelpHint(text: NovaDrillWords.pinnedNote)
        }
    }

    @ViewBuilder private var outcome: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let observation = drill.observation, !observation.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    NovaText(text: RDLocalization.string("localizable.nova.drill.detail.observation",
                        table: .localizable, fallback: "Gözlem"), style: .label)
                    NovaText(text: observation, style: .body)
                }
            }
            if let improvement = drill.improvement, !improvement.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    NovaText(text: RDLocalization.string("localizable.nova.drill.detail.improvement",
                        table: .localizable, fallback: "İyileştirme"), style: .label)
                    NovaText(text: improvement, style: .body)
                }
            }
        }
    }

    @ViewBuilder private var participants: some View {
        VStack(alignment: .leading, spacing: 6) {
            NovaText(text: RDLocalization.string("localizable.nova.drill.detail.participants",
                table: .localizable, fallback: "Katılımcı"), style: .cardTitle)
            ForEach(drill.participants) { person in
                HStack(spacing: 8) {
                    Image(systemName: "person").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
                    NovaText(text: person.fullName, style: .body)
                    Spacer(minLength: 0)
                }
            }
            if drill.participantsSnapshotted {
                NovaText(text: NovaDrillWords.snapshotNote, style: .meta,
                    color: NovaColorToken.textSecondary.color(in: scheme))
            }
        }
    }

    @ViewBuilder private var actions: some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaButton(label: RDLocalization.string("localizable.nova.drill.detail.record",
                table: .localizable, fallback: "Tatbikat kaydı gir"), symbol: "square.and.pencil",
                variant: .primary, action: onRecord)
            if askingCancel {
                TextField(RDLocalization.string("localizable.nova.drill.detail.reason",
                    table: .localizable, fallback: "İptal gerekçesi"), text: $reason)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("nova.drill.detail.reason")
                NovaButton(label: RDLocalization.string("localizable.nova.drill.detail.confirmcancel",
                    table: .localizable, fallback: "İptali onayla"), symbol: "xmark.circle",
                    variant: .surface) {
                    let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    Task { working = true; failure = await onCancel(trimmed); working = false }
                }
                .disabled(working)
            } else {
                NovaButton(label: RDLocalization.string("localizable.nova.drill.detail.cancel",
                    table: .localizable, fallback: "Tatbikatı iptal et"), symbol: "xmark.circle",
                    variant: .surface) { askingCancel = true }
            }
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

/// Planning a drill. The plan is chosen; its version is not offered, because
/// the server pins the one in force.
struct NovaDrillPlanSheet: View {
    @State var draft: NovaDrillPlanDraft
    let catalogue: NovaDrillCatalogue?
    let onSave: (NovaDrillPlanDraft) async -> String?
    let onClose: () -> Void
    @State private var failure: String?
    @State private var saving = false
    @State private var choosingPlan = false
    @State private var step = 0
    @State private var saved = false
    @Environment(\.colorScheme) private var scheme

    private var chosen: NovaDrillPlanOption? {
        catalogue?.plans.first { $0.planID == draft.planID }
    }

    var body: some View {
        Group {
            if saved {
                NovaTaskSuccessView(title: RDLocalization.string("localizable.nova.drill.sheets.tatbikat.planlandi.8e418f49", table: .localizable, fallback: "Tatbikat planlandı"),
                    message: RDLocalization.string("localizable.nova.drill.sheets.plan.tarihi.ve.prova.edilecek.acil.durum.plani.f.d5ad4af4", table: .localizable, fallback: "Plan tarihi ve prova edilecek acil durum planı firma kaydına eklendi."),
                    doneTitle: "Tatbikatlara dön", onDone: onClose)
            } else {
                NovaPageSurface(onEdgeBack: goBack) {
                    VStack(spacing: 0) {
                        NovaTaskHeader(title: RDLocalization.string("localizable.nova.drill.sheets.tatbikat.planla.95102735", table: .localizable, fallback: "Tatbikat planla"), step: step + 1, total: 3,
                            stepTitle: ["Plan seçimi", "Tarih", "Kontrol"][step], onClose: goBack)
                            .padding(.horizontal, 18).padding(.top, 10)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                if step == 0 { planStep }
                                else if step == 1 { dateStep }
                                else { reviewStep }
                                if let failure { NovaTaskErrorSummary(message: failure) }
                            }.padding(20).padding(.bottom, 18)
                        }
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            NovaTaskStickyActions(primaryTitle: step == 2 ? "Tatbikatı planla" : "Devam",
                                primarySymbol: step == 2 ? "checkmark" : "arrow.right", isWorking: saving,
                                canGoBack: true, onBack: goBack, onPrimary: advance)
                        }
                    }
                }
            }
        }
        .preference(key: NovaPopupBusyKey.self, value: saving)
        .accessibilityIdentifier("nova.drill.form")
    }

    private var planStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaHelpHint(text: RDLocalization.string("localizable.nova.drill.sheets.prova.edilecek.plani.secin.plan.surumu.arka.plan.ef1b8e16", table: .localizable, fallback: "Prova edilecek planı seçin. Plan sürümü arka planda sabitlenir ve sonraki adımlara taşınır."))
                    if catalogue?.plans.isEmpty ?? true {
                        NovaHelpHint(text: RDLocalization.string("localizable.nova.drill.empty.noplan",
                            table: .localizable,
                            fallback: "Önce bir acil durum planı yayımlayın; tatbikat bir plan sürümünü prova eder."))
                    } else {
                        NovaFileChooserButton(
                            label: RDLocalization.string("localizable.nova.drill.form.plan",
                                table: .localizable, fallback: "Prova edilecek plan"),
                            value: chosen.map { $0.scope + " · " + $0.workplaceName }
                                ?? RDLocalization.string("localizable.nova.drill.form.pickplan",
                                    table: .localizable, fallback: "Plan seçin"),
                            isOpen: choosingPlan,
                            identifier: "nova.drill.form.plan") { choosingPlan.toggle() }
                        if choosingPlan {
                            NovaFileChooserPanel(
                                options: (catalogue?.plans ?? []).map {
                                    .init(id: $0.planID.uuidString,
                                          title: $0.scope + " · " + $0.workplaceName) },
                                selected: draft.planID?.uuidString,
                                identifier: "nova.drill.form.plan.panel") { value in
                                draft.planID = value.flatMap(UUID.init(uuidString:))
                                choosingPlan = false
                            }
                        }
                        if let chosen {
                            NovaWhyDisclosure {
                                NovaText(text: String(format: RDLocalization.string(
                                    "localizable.nova.drill.form.version", table: .localizable,
                                    fallback: "Planın yürürlükteki %d. sürümü prova edilecek."), chosen.version), style: .metaQuiet)
                            }
                        }
                    }
        }
    }

    private var dateStep: some View {
        VStack(alignment: .leading, spacing: 12) {
                    NovaDayField(label: RDLocalization.string("localizable.nova.drill.row.planned",
                        table: .localizable, fallback: "Planlanan"),
                        value: $draft.plannedOn, identifier: "nova.drill.form.planned")
                    NovaText(text: NovaDrillWords.planningIsNotPerforming, style: .meta,
                        color: NovaColorToken.textSecondary.color(in: scheme))
        }
    }

    private var reviewStep: some View {
        NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                NovaText(text: RDLocalization.string("localizable.nova.drill.sheets.tatbikat.ozeti.78e1a85b", table: .localizable, fallback: "Tatbikat özeti"), style: .bodyStrong)
                NovaText(text: chosen.map { $0.scope + " · " + $0.workplaceName } ?? "Plan seçilmedi", style: .body)
                NovaText(text: draft.plannedOn, style: .metaQuiet)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func goBack() { failure = nil; if step > 0 { step -= 1 } else { onClose() } }
    private func advance() {
        failure = nil
        if step == 0 && draft.planID == nil { failure = "Prova edilecek planı seçin."; return }
        if step < 2 { step += 1; return }
        Task {
            saving = true; let result = await onSave(draft); saving = false
            if let result { failure = result } else { saved = true }
        }
    }
}

/// Recording what happened. Participants are picked from the company's own
/// register and frozen as they are named now.
struct NovaDrillResultSheet: View {
    @State var draft: NovaDrillResultDraft
    let catalogue: NovaDrillCatalogue?
    let onSave: (NovaDrillResultDraft) async -> String?
    let onClose: () -> Void
    @State private var failure: String?
    @State private var saving = false
    @State private var step = 0
    @State private var saved = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Group {
            if saved {
                NovaTaskSuccessView(title: RDLocalization.string("localizable.nova.drill.sheets.tatbikat.kaydedildi.a75bb560", table: .localizable, fallback: "Tatbikat kaydedildi"),
                    message: RDLocalization.string("localizable.nova.drill.sheets.tarih.katilimcilar.gozlem.ve.iyilestirme.bilgile.bdd0b7eb", table: .localizable, fallback: "Tarih, katılımcılar, gözlem ve iyileştirme bilgileri firma kaydına eklendi."),
                    doneTitle: "Tatbikatlara dön", onDone: onClose)
            } else {
                NovaPageSurface(onEdgeBack: goBack) {
                    VStack(spacing: 0) {
                        NovaTaskHeader(title: RDLocalization.string("localizable.nova.drill.sheets.tatbikat.kaydi.3104551f", table: .localizable, fallback: "Tatbikat kaydı"), step: step + 1, total: 4,
                            stepTitle: ["Tarih", "Katılımcılar", "Sonuçlar", "Kontrol"][step], onClose: goBack)
                            .padding(.horizontal, 18).padding(.top, 10)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                resultStep
                                if let failure { NovaTaskErrorSummary(message: failure) }
                            }.padding(20).padding(.bottom, 18)
                        }
                        .safeAreaInset(edge: .bottom, spacing: 0) {
                            NovaTaskStickyActions(primaryTitle: step == 3 ? "Tatbikatı kaydet" : "Devam",
                                primarySymbol: step == 3 ? "checkmark" : "arrow.right", isWorking: saving,
                                canGoBack: true, onBack: goBack, onPrimary: advance)
                        }
                    }
                }
            }
        }
        .accessibilityIdentifier("nova.drill.result")
    }

    @ViewBuilder private var resultStep: some View {
        switch step {
        case 0:
            if !draft.planScope.isEmpty { NovaText(text: draft.planScope, style: .bodyStrong) }
            NovaDayField(label: RDLocalization.string("localizable.nova.drill.sheets.yapilan.771108cc", table: .localizable, fallback: "Yapılan"), value: $draft.performedOn,
                identifier: "nova.drill.result.performed")
        case 1:
            participants
        case 2:
            VStack(alignment: .leading, spacing: 5) {
                NovaText(text: RDLocalization.string("localizable.nova.drill.sheets.gozlem.0c0e69cc", table: .localizable, fallback: "Gözlem"), style: .label)
                TextEditor(text: $draft.observation).frame(minHeight: 100)
                    .accessibilityIdentifier("nova.drill.result.observation")
            }
            VStack(alignment: .leading, spacing: 5) {
                NovaText(text: RDLocalization.string("localizable.nova.drill.sheets.iyilestirme.62fb4fea", table: .localizable, fallback: "İyileştirme"), style: .label)
                TextEditor(text: $draft.improvement).frame(minHeight: 100)
                    .accessibilityIdentifier("nova.drill.result.improvement")
            }
        default:
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 8) {
                    NovaText(text: RDLocalization.string("localizable.nova.drill.sheets.tatbikat.ozeti.cbde121b", table: .localizable, fallback: "Tatbikat özeti"), style: .bodyStrong)
                    NovaText(text: draft.planScope, style: .body)
                    NovaText(text: RDLocalization.format("localizable.nova.drill.sheets.1.2.katilimci.9e46c92e", table: .localizable, fallback: "%1$@ · %2$@ katılımcı", arguments: [String(describing: draft.performedOn), String(describing: draft.participants.count)]), style: .metaQuiet)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func goBack() { failure = nil; if step > 0 { step -= 1 } else { onClose() } }
    private func advance() {
        failure = nil
        if step == 1 && draft.participants.isEmpty { failure = "En az bir katılımcı seçin."; return }
        if step < 3 { step += 1; return }
        Task {
            saving = true; let result = await onSave(draft); saving = false
            if let result { failure = result } else { saved = true }
        }
    }

    @ViewBuilder private var participants: some View {
        VStack(alignment: .leading, spacing: 6) {
            NovaText(text: RDLocalization.string("localizable.nova.drill.detail.participants",
                table: .localizable, fallback: "Katılımcı"), style: .label)
            if catalogue?.employees.isEmpty ?? true {
                NovaText(text: RDLocalization.string("localizable.nova.drill.result.nopeople",
                    table: .localizable, fallback: "Bu firmada aktif personel kaydı yok."),
                    style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
            }
            // Only this company's own people are offered; the server refuses
            // anyone else anyway.
            ForEach(catalogue?.employees ?? []) { person in
                Button {
                    if draft.participants.contains(person.id) { draft.participants.remove(person.id) }
                    else { draft.participants.insert(person.id) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: draft.participants.contains(person.id)
                            ? "checkmark.square.fill" : "square")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(draft.participants.contains(person.id)
                                ? NovaColorToken.accentInk.color(in: scheme)
                                : NovaColorToken.textMuted.color(in: scheme))
                        NovaText(text: person.fullName, style: .body)
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(NovaRowPressStyle())
                .accessibilityIdentifier("nova.drill.result.person.\(person.id.uuidString)")
            }
            NovaText(text: NovaDrillWords.snapshotNote, style: .meta,
                color: NovaColorToken.textSecondary.color(in: scheme))
        }
    }
}
