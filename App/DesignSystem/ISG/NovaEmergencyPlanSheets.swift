import SwiftUI

/// One plan: the version that stands, and every version behind it with its own
/// team, dates and scope. Nothing here edits a published version.
struct NovaEmergencyDetailSheet: View {
    let plan: NovaEmergencyPlan
    var canWrite: Bool = true
    let fileClient: NovaFileLibraryClient
    let onRenew: () -> Void
    let onClose: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var opened: URL?
    @State private var openFailure: String?
    @State private var opening = false

    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        NovaPopupHeading(text: plan.scope, symbol: "shield")
                        NovaText(text: [plan.workplaceName, plan.companyName]
                            .compactMap { $0 }.joined(separator: " · "), style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                        NovaText(text: NovaEmergencyWords.explain(plan), style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                    }
                    facts
                    if plan.assetDownload != nil { fileRow }
                    team(plan.team, title: RDLocalization.string("localizable.nova.emergency.detail.team",
                        table: .localizable, fallback: "Ekip"))
                    if canWrite {
                        VStack(alignment: .leading, spacing: 8) {
                            NovaButton(label: RDLocalization.string("localizable.nova.emergency.detail.renew",
                                table: .localizable, fallback: "Yeni sürüm yayımla"),
                                symbol: "arrow.triangle.2.circlepath", variant: .primary, action: onRenew)
                        }
                    }
                    history
                }
                .padding(20).novaPopupContentSize()
            }
        }
        .accessibilityIdentifier("nova.emergency.detail")
        .sheet(item: $opened) { url in NovaFileShareSheet(url: url) }
    }

    @ViewBuilder private var fileRow: some View {
        NovaCard(padding: 12) {
            HStack(spacing: 10) {
                Image(systemName: "doc.fill").font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(NovaColorToken.statusSuccessInk.color(in: scheme))
                VStack(alignment: .leading, spacing: 1) {
                    NovaText(text: RDLocalization.string("localizable.nova.emergency.form.file.attached",
                        table: .localizable, fallback: "Dosya ekli"), style: .cardTitle)
                    if let openFailure {
                        NovaText(text: openFailure, style: .metaQuiet,
                            color: NovaColorToken.statusDangerInk.color(in: scheme))
                    }
                }
                Spacer(minLength: 0)
                NovaButton(label: RDLocalization.string("localizable.nova.file.open", table: .localizable,
                    fallback: "Dosyayı aç"), symbol: "arrow.up.right.square", variant: .surface,
                    isEnabled: !opening, isLoading: opening) { open() }
                    .accessibilityIdentifier("nova.emergency.detail.file.open")
            }
        }
    }

    private func open() {
        guard let download = plan.assetDownload else { return }
        opening = true; openFailure = nil
        Task {
            do {
                let data = try await fileClient.download(download.bucket, download.path)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString, isDirectory: true)
                    .appendingPathComponent(download.path.components(separatedBy: "/").last ?? "belge")
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                         withIntermediateDirectories: true)
                try data.write(to: url, options: .completeFileProtection)
                opened = url
            } catch {
                openFailure = RDLocalization.string("localizable.nova.file.failure.unavailable", table: .localizable,
                    fallback: "Dosya servisi şu anda kullanılamıyor.")
            }
            opening = false
        }
    }

    @ViewBuilder private var facts: some View {
        NovaCard(padding: 14) {
            let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]
            LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                cell("calendar", RDLocalization.string("localizable.nova.emergency.row.prepared",
                    table: .localizable, fallback: "Hazırlanma"), plan.preparedOn)
                cell("calendar.badge.clock", RDLocalization.string("localizable.nova.emergency.row.until",
                    table: .localizable, fallback: "Geçerlilik"),
                    plan.validUntil ?? RDLocalization.string("localizable.nova.emergency.unset",
                        table: .localizable, fallback: "Belirtilmedi"),
                    detail: RDLocalization.string("localizable.nova.emergency.period.expert",
                        table: .localizable, fallback: "uzmanın kararı"))
                cell("number", RDLocalization.string("localizable.nova.emergency.row.version",
                    table: .localizable, fallback: "Sürüm"), "v\(plan.version)",
                    detail: String(format: RDLocalization.string("localizable.nova.emergency.detail.total",
                        table: .localizable, fallback: "%d sürüm"), plan.versionsTotal))
                cell("person.2", RDLocalization.string("localizable.nova.emergency.row.team",
                    table: .localizable, fallback: "Ekip"), "\(plan.teamSize)")
            }
        }
    }

    @ViewBuilder private func team(_ members: [NovaEmergencyMember], title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NovaText(text: title, style: .cardTitle)
            ForEach(members) { member in
                HStack(spacing: 8) {
                    Image(systemName: member.role.symbol).font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
                    VStack(alignment: .leading, spacing: 1) {
                        NovaText(text: member.fullName, style: .body)
                        NovaSizedText(text: member.role.title
                            + (member.contact.map { " · " + $0 } ?? ""), size: 10.5, weight: "Medium",
                            color: NovaColorToken.textSecondary.color(in: scheme))
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder private var history: some View {
        VStack(alignment: .leading, spacing: 8) {
            NovaText(text: RDLocalization.string("localizable.nova.emergency.detail.history", table: .localizable,
                fallback: "Sürüm geçmişi"), style: .cardTitle)
            // Each version keeps its own team, dates and scope; renewing never
            // rewrote what came before, and the history shows it.
            ForEach(plan.versions) { version in
                NovaCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            NovaText(text: RDLocalization.format("localizable.nova.emergency.plan.sheets.v.1.3bd7c83c", table: .localizable, fallback: "v%1$@ · ", arguments: [String(describing: version.version)]) + version.scope, style: .cardTitle)
                            Spacer(minLength: 0)
                            NovaStatusPill(label: version.isActive
                                ? RDLocalization.string("localizable.nova.emergency.version.active",
                                    table: .localizable, fallback: "Yürürlükte")
                                : RDLocalization.string("localizable.nova.emergency.version.superseded",
                                    table: .localizable, fallback: "Geçmiş"),
                                status: version.isActive ? .success : .neutral)
                        }
                        HStack(spacing: 10) {
                            NovaSizedText(text: RDLocalization.string("localizable.nova.emergency.row.prepared",
                                table: .localizable, fallback: "Hazırlanma") + ": " + version.preparedOn,
                                size: 10.5, weight: "Medium")
                            if let until = version.validUntil {
                                NovaSizedText(text: RDLocalization.string("localizable.nova.emergency.row.until",
                                    table: .localizable, fallback: "Geçerlilik") + ": " + until,
                                    size: 10.5, weight: "Medium")
                            }
                        }
                        if version.needsReview {
                            NovaAnalysisTag(symbol: "exclamationmark.circle",
                                text: RDLocalization.string("localizable.nova.emergency.row.review",
                                    table: .localizable, fallback: "Dayanağı yazılmamış · gözden geçirin"),
                                status: .warning)
                        } else if let note = version.reviewNote, !note.isEmpty {
                            NovaText(text: note, style: .meta,
                                color: NovaColorToken.textSecondary.color(in: scheme))
                        }
                        team(version.team, title: String(format: RDLocalization.string(
                            "localizable.nova.emergency.detail.versionteam", table: .localizable,
                            fallback: "Bu sürümün ekibi (%d)"), version.team.count))
                    }
                }
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

/// Publishing a plan, or the next version of one. There is no edit form,
/// because a published version is never edited.
struct NovaEmergencyPlanSheet: View {
    private enum Step: String, CaseIterable { case scope, dates, team, file, review }
    @State var draft: NovaEmergencyPlanDraft
    let catalogue: NovaEmergencyCatalogue?
    /// The plan attaches one of the archive's own filed entries; adding one
    /// here opens the same upload sheet Dosyalarım uses, pinned to this plan's
    /// company and the "emergency_plan" heading.
    let fileClient: NovaFileLibraryClient
    var fileCompany: UUID?
    var fileCategories: [NovaFileCategory] = []
    var fileAccepts: [NovaFileAcceptance] = []
    var fileAssurance = NovaFileAssurance()
    var employees: (UUID, String, UUID?) async throws -> NovaEmployeePage = { _,_,_ in
        throw NovaPersonnelFailure.unavailable
    }
    let onSave: (NovaEmergencyPlanDraft) async -> String?
    var onSaveDraft: ((NovaEmergencyPlanDraft) -> Void)? = nil
    let onClose: () -> Void
    @State private var failure: String?
    @State private var saving = false
    @State private var choosingWorkplace = false
    @State private var supportStaffPicker = false
    @State private var personnel: [NovaEmployeeRow] = []
    @State private var personnelLoading = false
    @State private var personnelFailure: String?
    @State private var selectedEmployeeID: UUID?
    @State private var memberName = ""
    @State private var memberRole: NovaEmergencyRole = .coordinator
    @State private var memberContact = ""
    @State private var addingFile = false
    @State private var currentStep: Step = .scope
    @State private var didSave = false
    @State private var confirmingExit = false
    @Environment(\.colorScheme) private var scheme

    private var emergencyFileCategories: [NovaFileCategory] {
        let scoped = fileCategories.filter { $0.code == "emergency_plan" }
        return scoped.isEmpty ? fileCategories : scoped
    }

    private var workplaceTitle: String {
        catalogue?.workplaces.first { $0.id == draft.workplaceID }?.name
            ?? RDLocalization.string("localizable.nova.emergency.form.pickplace", table: .localizable,
                fallback: "İşyeri seçin")
    }

    private var suggestedYears: Int? {
        catalogue?.workplaces.first { $0.id == draft.workplaceID }?.suggestedPeriodYears
    }

    /// Prefills the field, never overwrites what the expert already set —
    /// the same "auto-fill once, editable after" rule Risk Analizi uses.
    private func fillSuggestedValidity() {
        guard draft.validUntil.isEmpty, let years = suggestedYears,
              let prepared = NovaDayField.date(draft.preparedOn),
              let until = Calendar.current.date(byAdding: .year, value: years, to: prepared) else { return }
        draft.validUntil = NovaDayField.text(until)
    }

    private var stepNumber: Int { (Step.allCases.firstIndex(of: currentStep) ?? 0) + 1 }
    private var scopeReady: Bool { draft.workplaceID != nil }
    private var datesReady: Bool {
        guard let prepared = NovaDayField.date(draft.preparedOn),
              let until = NovaDayField.date(draft.validUntil) else { return false }
        return until > prepared
    }
    private var teamReady: Bool { true }

    var body: some View {
        Group {
            if didSave {
                NovaTaskSuccessView(title: RDLocalization.string("localizable.nova.emergency.plan.sheets.acil.durum.plani.kaydedildi.e8f47cc2", table: .localizable, fallback: "Acil durum planı kaydedildi"),
                    message: RDLocalization.format("localizable.nova.emergency.plan.sheets.hazirlama.1.gecerlilik.2.ekip.3.kisi.siradaki.on.546fa80b", table: .localizable, fallback: "Hazırlama: %1$@\nGeçerlilik: %2$@\nEkip: %3$@ kişi\n\nSıradaki önerilen işlem: tatbikat kaydı oluştur.", arguments: [String(describing: draft.preparedOn), String(describing: draft.validUntil), String(describing: draft.team.count)]),
                    doneTitle: "Planlara dön", onDone: onClose)
            } else {
                NovaPageSurface(onEdgeBack: onClose) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            NovaTaskHeader(title: draft.isRenewal ? "Acil durum planını yenile" : "Acil durum planı ekle",
                                step: stepNumber, total: Step.allCases.count,
                                stepTitle: stepTitle(currentStep), onClose: { confirmingExit = true })
                            if let failure { NovaTaskErrorSummary(message: failure) }
                            stepContent(currentStep)
                        }.padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 28)
                    }.scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom) {
                        NovaTaskStickyActions(primaryTitle: currentStep == .review ? "Yayımla" : "Devam",
                            primarySymbol: currentStep == .review ? "checkmark.seal" : "arrow.right",
                            isWorking: saving, canGoBack: currentStep != .scope,
                            onBack: previousStep, onPrimary: advance)
                    }
                }
            }
        }
        .accessibilityIdentifier("nova.emergency.form")
        .onAppear {
            if draft.workplaceID == nil, let only = catalogue?.workplaces, only.count == 1 {
                draft.workplaceID = only[0].id
            }
            fillSuggestedValidity()
        }
        .onChange(of: draft.workplaceID) { _ in fillSuggestedValidity() }
        .onChange(of: draft.preparedOn) { _ in fillSuggestedValidity() }
        .task(id: fileCompany) { await loadPersonnel() }
        .confirmationDialog(RDLocalization.string("localizable.nova.emergency.plan.sheets.acil.durum.plani.akisindan.cikilsin.mi.8c071740", table: .localizable, fallback: "Acil durum planı akışından çıkılsın mı?"), isPresented: $confirmingExit,
            titleVisibility: .visible) {
                Button(RDLocalization.string("localizable.nova.emergency.plan.sheets.cik.043a3e3c", table: .localizable, fallback: "Çık"), role: .destructive, action: onClose)
                Button(RDLocalization.string("localizable.nova.emergency.plan.sheets.devam.et.b7ee7f8b", table: .localizable, fallback: "Devam et"), role: .cancel) {}
            } message: { Text(RDLocalization.string("localizable.nova.emergency.plan.sheets.henuz.kaydedilmemis.bilgiler.silinir.d13139a9", table: .localizable, fallback: "Henüz kaydedilmemiş bilgiler silinir.")) }
    }

    @ViewBuilder private func stepContent(_ step: Step) -> some View {
        switch step {
        case .scope: scopeStep
        case .dates: datesStep
        case .team: teamStep
        case .file: fileStep
        case .review: reviewStep
        }
    }

    private var scopeStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            let workplaces = catalogue?.workplaces ?? []
            NovaCard(padding: 12) {
                fieldIcon("building.2") {
                    if draft.isRenewal || workplaces.count == 1 {
                        VStack(alignment: .leading, spacing: 4) {
                            NovaText(text: RDLocalization.string("localizable.nova.emergency.plan.sheets.isyeri.b018b168", table: .localizable, fallback: "İşyeri"), style: .label)
                            NovaText(text: workplaceTitle, style: .cardTitle)
                        }
                    } else if workplaces.isEmpty {
                        NovaText(text: RDLocalization.string("localizable.nova.emergency.plan.sheets.bu.firmada.kayit.acilacak.bir.isyeri.yok.4d56b127", table: .localizable, fallback: "Bu firmada kayıt açılacak bir işyeri yok."), style: .metaQuiet)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            NovaFileChooserButton(label: RDLocalization.string("localizable.nova.emergency.plan.sheets.isyeri.2cb75cfe", table: .localizable, fallback: "İşyeri"), value: workplaceTitle,
                                isOpen: choosingWorkplace, identifier: "nova.emergency.form.workplace") {
                                    choosingWorkplace.toggle()
                                }
                            if choosingWorkplace {
                                NovaFileChooserPanel(options: workplaces.map { .init(id: $0.id.uuidString, title: $0.name) },
                                    selected: draft.workplaceID?.uuidString,
                                    identifier: "nova.emergency.form.workplace.panel") { value in
                                        draft.workplaceID = value.flatMap(UUID.init(uuidString:))
                                        choosingWorkplace = false
                                    }
                            }
                        }
                    }
                }
            }
        }
    }

    private var datesStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaCard(padding: 12) {
                VStack(spacing: 4) {
                    compactDateRow(label: RDLocalization.string("localizable.nova.emergency.plan.sheets.hazirlama.tarihi.3780ce96", table: .localizable, fallback: "Hazırlama tarihi"), symbol: "calendar",
                        value: $draft.preparedOn, identifier: "nova.emergency.form.prepared")
                    Divider().opacity(0.45)
                    compactDateRow(label: RDLocalization.string("localizable.nova.emergency.plan.sheets.gecerlilik.5bf8d450", table: .localizable, fallback: "Geçerlilik"), symbol: "calendar.badge.clock",
                        value: $draft.validUntil, identifier: "nova.emergency.form.until", isClearable: true)
                }
            }
            if let years = suggestedYears {
                NovaWhyDisclosure {
                    NovaText(text: String(format: "İşyerinin tehlike sınıfına göre %d yıl otomatik dolduruldu. Gerekirse değiştirebilirsiniz.", years), style: .metaQuiet)
                }
            }
        }
    }

    private var teamStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaText(text: RDLocalization.string("localizable.nova.emergency.plan.sheets.acil.durum.ekibi.18ad36bc", table: .localizable, fallback: "Acil durum ekibi"), style: .sectionTitle)
            NovaHelpHint(text: RDLocalization.string("localizable.nova.emergency.plan.sheets.ekip.eklemek.istege.baglidir.simdi.kisi.secebili.b045146f", table: .localizable, fallback: "Ekip eklemek isteğe bağlıdır. Şimdi kişi seçebilir veya bu adımı boş geçip ekibi daha sonra tamamlayabilirsiniz."))
            NovaCard(padding: 12) { fieldIcon("person.2") { teamEditor } }
        }
    }

    private var fileStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            NovaText(text: RDLocalization.string("localizable.nova.emergency.plan.sheets.plan.dosyasi.c0653321", table: .localizable, fallback: "Plan dosyası"), style: .sectionTitle)
            NovaCard(padding: 12) { fieldIcon("paperclip") { fileEditor } }
            DisclosureGroup("Dosya bilgileri") {
                NovaText(text: RDLocalization.string("localizable.nova.emergency.plan.sheets.dosya.eklemek.zorunlu.degil.plani.kaydedip.belge.d622cd94", table: .localizable, fallback: "Dosya eklemek zorunlu değil; planı kaydedip belgeyi daha sonra bağlayabilirsiniz."), style: .metaQuiet)
                    .padding(.top, 8)
            }.padding(12).novaControlBackground(cornerRadius: 14)
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            NovaText(text: RDLocalization.string("localizable.nova.emergency.plan.sheets.kaydetmeden.once.kontrol.edin.ee541d97", table: .localizable, fallback: "Kaydetmeden önce kontrol edin"), style: .sectionTitle)
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    reviewRow("İşyeri", workplaceTitle)
                    reviewRow("Hazırlama", draft.preparedOn)
                    reviewRow("Geçerlilik", draft.validUntil)
                    reviewRow("Ekip", "\(draft.team.count) kişi")
                    reviewRow("Dosya", draft.assetID == nil ? "Daha sonra eklenebilir" : "Dosya eklendi")
                }
            }
            if let onSaveDraft {
                NovaButton(label: RDLocalization.string("localizable.nova.emergency.plan.sheets.taslak.olarak.kaydet.941bd4e0", table: .localizable, fallback: "Taslak olarak kaydet"), symbol: "tray.and.arrow.down", variant: .surface) {
                    onSaveDraft(draft)
                }.accessibilityIdentifier("nova.emergency.form.save-draft")
                NovaText(text: RDLocalization.string("localizable.nova.emergency.plan.sheets.taslak.yayimlanmaz.ve.plan.listesinde.gorunmez.d.1d7f4e9a", table: .localizable, fallback: "Taslak yayımlanmaz ve plan listesinde görünmez; daha sonra bu bilgilerle devam edebilirsiniz."), style: .metaQuiet)
            }
        }
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .metaQuiet)
            NovaText(text: value, style: .bodyStrong)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func stepTitle(_ step: Step) -> String {
        switch step {
        case .scope: return "Kapsam"
        case .dates: return RDLocalization.string("localizable.nova.emergency.plan.sheets.tarih.ve.gecerlilik.9d2e1c12", table: .localizable, fallback: "Tarih ve geçerlilik")
        case .team: return RDLocalization.string("localizable.nova.emergency.plan.sheets.acil.durum.ekibi.d4a2c823", table: .localizable, fallback: "Acil durum ekibi")
        case .file: return RDLocalization.string("localizable.nova.emergency.plan.sheets.plan.dosyasi.e9c3aec5", table: .localizable, fallback: "Plan dosyası")
        case .review: return RDLocalization.string("localizable.nova.emergency.plan.sheets.kontrol.ve.kaydet.8e64637b", table: .localizable, fallback: "Kontrol ve kaydet")
        }
    }

    private func advance() {
        failure = nil
        let valid: Bool
        switch currentStep {
        case .scope: valid = scopeReady
        case .dates: valid = datesReady
        case .team: valid = true
        case .file, .review: valid = true
        }
        guard valid else {
            failure = "Bu adımı tamamlamak için eksik bilgileri kontrol edin."
            return
        }
        guard currentStep != .review else {
            Task { await save() }
            return
        }
        guard let index = Step.allCases.firstIndex(of: currentStep) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { currentStep = Step.allCases[index + 1] }
    }

    private func previousStep() {
        failure = nil
        guard let index = Step.allCases.firstIndex(of: currentStep), index > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) { currentStep = Step.allCases[index - 1] }
    }

    private func save() async {
        guard !saving else { return }
        saving = true
        failure = await onSave(draft)
        saving = false
        if failure == nil { didSave = true }
    }

    /// A plain line icon in front of one field group — no tint, no background
    /// chip, matching the rest of the app's forms.
    @ViewBuilder private func fieldIcon<V: View>(_ symbol: String, @ViewBuilder _ content: @escaping () -> V) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).font(.system(size: 15, weight: .regular))
                .foregroundStyle(NovaColorToken.textSecondary.color(in: scheme)).frame(width: 20, height: 22)
            content().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private func compactDateRow(label: String, symbol: String, value: Binding<String>,
                                              identifier: String, isClearable: Bool = false) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).font(.system(size: 14, weight: .regular))
                .foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                .frame(width: 19)
            NovaText(text: label, style: .label)
            Spacer(minLength: 6)
            if isClearable && value.wrappedValue.isEmpty {
                Button { value.wrappedValue = NovaDayField.text(Date()) } label: {
                    NovaText(text: "Belirtilmedi", style: .meta)
                }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier("\(identifier).set")
            } else {
                DatePicker("", selection: Binding(
                    get: { NovaDayField.date(value.wrappedValue) ?? Date() },
                    set: { value.wrappedValue = NovaDayField.text($0) }), displayedComponents: .date)
                    .labelsHidden().datePickerStyle(.compact)
                    .fixedSize(horizontal: true, vertical: false)
                    .accessibilityIdentifier(identifier)
                    .accessibilityLabel(Text(verbatim: label))
                if isClearable {
                    Button { value.wrappedValue = "" } label: {
                        Image(systemName: "xmark.circle").font(.system(size: 13)).frame(width: 28, height: 34)
                    }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier("\(identifier).clear")
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 42)
    }

    /// The upload happens right here — no cover, no second screen. Opening it
    /// expands the same picker/title/category fields Dosyalarım uses, inline.
    @ViewBuilder private var fileEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            NovaText(text: RDLocalization.string("localizable.nova.emergency.form.file",
                table: .localizable, fallback: "Dosya"), style: .label)
            if draft.assetID != nil && !addingFile {
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NovaColorToken.statusSuccessInk.color(in: scheme))
                    NovaText(text: RDLocalization.string("localizable.nova.emergency.form.file.attached",
                        table: .localizable, fallback: "Dosya ekli"), style: .meta)
                    Spacer(minLength: 0)
                    NovaButton(label: RDLocalization.string("localizable.nova.emergency.form.file.replace",
                        table: .localizable, fallback: "Dosyayı değiştir"), symbol: "arrow.triangle.2.circlepath",
                        variant: .surface) { addingFile = true }
                        .accessibilityIdentifier("nova.emergency.form.file.replace")
                    Button { draft.assetID = nil } label: {
                        Image(systemName: "xmark.circle").font(.system(size: 12))
                    }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier("nova.emergency.form.file.remove")
                }
            } else if fileCompany != nil {
                // The upload area shows up on its own — no "Dosya ekle" tap
                // needed first.
                NovaFileAddInline(companies: [], preselected: fileCompany,
                    categories: emergencyFileCategories, accepts: fileAccepts,
                    assurance: fileAssurance, client: fileClient) { entry in
                        if let entry { draft.assetID = entry.assetID }
                        addingFile = false
                    }
            }
        }
    }

    @ViewBuilder private var teamEditor: some View {
        VStack(alignment: .leading, spacing: 6) {
            NovaText(text: RDLocalization.string("localizable.nova.emergency.form.team",
                table: .localizable, fallback: "Ekip"), style: .label)
            if draft.team.isEmpty {
                NovaText(text: RDLocalization.string("localizable.nova.emergency.form.teamempty",
                    table: .localizable, fallback: "En az bir kişi gerekli."), style: .meta,
                    color: NovaColorToken.textSecondary.color(in: scheme))
            }
            NovaFileChooserButton(label: RDLocalization.string("localizable.nova.emergency.plan.sheets.firma.personeli.a5cb6b09", table: .localizable, fallback: "Firma personeli"),
                value: personnel.first { $0.id == selectedEmployeeID }?.name ?? "Personel seçin",
                symbol: "person", isOpen: supportStaffPicker,
                isAnswered: selectedEmployeeID != nil,
                identifier: "nova.emergency.form.employee") { supportStaffPicker.toggle() }
            if supportStaffPicker {
                NovaFileChooserPanel(options: personnel.filter { employee in
                    !draft.team.contains { $0.fullName == employee.name }
                }.map { .init(id: $0.id.uuidString, title: $0.name) },
                    selected: selectedEmployeeID?.uuidString,
                    identifier: "nova.emergency.form.employee.options") { value in
                    selectedEmployeeID = value.flatMap(UUID.init(uuidString:))
                    if let person = personnel.first(where: { $0.id == selectedEmployeeID }) {
                        memberName = person.fullName
                    }
                    supportStaffPicker = false
                }
            }
            if personnelLoading { ProgressView().controlSize(.small) }
            if let personnelFailure { NovaText(text: personnelFailure, style: .metaQuiet) }
            ForEach(draft.team) { member in
                HStack(spacing: 6) {
                    Image(systemName: member.role.symbol).font(.system(size: 11, weight: .semibold))
                    NovaText(text: member.fullName + " · " + member.role.title, style: .meta)
                    Spacer(minLength: 0)
                    Button { draft.team.removeAll { $0.id == member.id } } label: {
                        Image(systemName: "xmark.circle").font(.system(size: 12))
                    }.buttonStyle(NovaRowPressStyle())
                }
            }
            // Only the roles the schema knows, so the snapshot cannot carry one
            // the server would refuse.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(catalogue?.roles ?? NovaEmergencyRole.allCases) { role in
                        let isSelected = memberRole == role
                        Button { memberRole = role } label: {
                            HStack(spacing: 4) {
                                Image(systemName: role.symbol).font(.system(size: 10, weight: .semibold))
                                NovaSizedText(text: role.title, size: 11, weight: isSelected ? "Bold" : "Medium")
                            }
                            .foregroundStyle(isSelected ? NovaColorToken.onInverse.color(in: scheme)
                                                        : NovaColorToken.textSecondary.color(in: scheme))
                            .padding(.vertical, 7).padding(.horizontal, 11)
                            .background(isSelected ? NovaColorToken.accent.color(in: scheme)
                                                    : NovaColorToken.surfaceMuted.color(in: scheme),
                                in: Capsule())
                            .animation(NovaMotion.easeOut(0.14), value: isSelected)
                        }
                        .buttonStyle(NovaRowPressStyle())
                        .accessibilityIdentifier("nova.emergency.form.role.\(role.rawValue)")
                    }
                }
            }
            TextField(RDLocalization.string("localizable.nova.emergency.form.contact",
                table: .localizable, fallback: "İletişim (isteğe bağlı)"), text: $memberContact)
                .frame(minHeight: 36)
                .accessibilityIdentifier("nova.emergency.form.contact")
            NovaButton(label: RDLocalization.string("localizable.nova.emergency.form.addmember",
                table: .localizable, fallback: "Ekibe ekle"), symbol: "person.badge.plus", variant: .surface) {
                let name = memberName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, draft.team.count < 200 else { return }
                let contact = memberContact.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.team.append(.init(fullName: name, role: memberRole,
                                        contact: contact.isEmpty ? nil : contact))
                memberName = ""; memberContact = ""; selectedEmployeeID = nil
            }
            .disabled(selectedEmployeeID == nil)
        }
    }

    @MainActor private func loadPersonnel() async {
        guard let company = fileCompany else { return }
        personnelLoading = true; personnelFailure = nil
        do {
            var rows: [NovaEmployeeRow] = []
            var cursor: UUID?
            repeat {
                let page = try await employees(company, "", cursor)
                rows.append(contentsOf: page.rows)
                cursor = page.next
            } while cursor != nil && rows.count < 1_000
            personnel = rows
            if rows.isEmpty { personnelFailure = "Bu firmada henüz aktif personel yok." }
        } catch {
            personnelFailure = "Firma personelleri yüklenemedi. Yeniden deneyin."
        }
        personnelLoading = false
    }
}
