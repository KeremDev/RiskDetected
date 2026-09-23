import SwiftUI

private enum IsgTrainingAdvancedSection: String, CaseIterable, Identifiable {
    case curriculum, plan, assessment, certificate
    var id: String { rawValue }
    var title: String {
        switch self { case .curriculum: return RDLocalization.string("localizable.isg.workspace.training.advanced.screen.mufredat.dd1f3af0", table: .localizable, fallback: "Müfredat"); case .plan: return RDLocalization.string("localizable.isg.workspace.training.advanced.screen.yillik.plan.344d3bf9", table: .localizable, fallback: "Yıllık plan")
        case .assessment: return RDLocalization.string("localizable.isg.workspace.training.advanced.screen.sinavlar.f5fad819", table: .localizable, fallback: "Sınavlar"); case .certificate: return "Belgeler" }
    }
    var symbol: String {
        switch self { case .curriculum: return "books.vertical"; case .plan: return "calendar"
        case .assessment: return "checkmark.seal"; case .certificate: return "doc.badge.checkmark" }
    }
}

private enum IsgTrainingAdvancedEditorKind {
    case curriculumCreate, curriculum(IsgWorkspaceAdvancedRecord), linkCurriculum
    case curriculumTopic(IsgWorkspaceAdvancedRecord, IsgWorkspaceAdvancedTopic)
    case planCreate, plan(IsgWorkspaceAdvancedRecord), planItemCreate(IsgWorkspaceAdvancedRecord)
    case planItem(IsgWorkspaceAdvancedRecord), attemptCreate
    case certificateCreate, certificate(IsgWorkspaceAdvancedRecord)
}

private struct IsgTrainingAdvancedRoute: Identifiable {
    let id = UUID()
    let kind: IsgTrainingAdvancedEditorKind
}

struct IsgWorkspaceTrainingAdvancedScreen: View {
    @ObservedObject var store: IsgWorkspaceStore
    let canOperate: Bool
    let onClose: () -> Void
    @State private var section: IsgTrainingAdvancedSection = .curriculum
    @State private var curricula: [IsgWorkspaceAdvancedRecord] = []
    @State private var plans: [IsgWorkspaceAdvancedRecord] = []
    @State private var planItems: [IsgWorkspaceAdvancedRecord] = []
    @State private var attempts: [IsgWorkspaceAdvancedRecord] = []
    @State private var certificates: [IsgWorkspaceAdvancedRecord] = []
    @State private var workplaces: [IsgWorkspaceDirectoryEntry] = []
    @State private var employees: [IsgWorkspaceEmployeeEntry] = []
    @State private var trainings: [IsgWorkspaceDomainRecord] = []
    @State private var files: [IsgWorkspaceDomainRecord] = []
    @State private var route: IsgTrainingAdvancedRoute?
    @State private var loading = true
    @State private var error: String?
    @State private var revision = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NovaPopupHeading(text: RDLocalization.string("localizable.isg.workspace.training.advanced.screen.egitim.yonetimi.4384e31e", table: .localizable, fallback: "Eğitim yönetimi"), symbol: "books.vertical",
                                 subtitle: RDLocalization.string("localizable.isg.workspace.training.advanced.screen.mufredat.surumleri.yillik.plan.sinav.ve.belgeler.2b6874c2", table: .localizable, fallback: "Müfredat sürümleri, yıllık plan, sınav ve belgeler aynı firma kapsamında tutulur."))
                Picker("", selection: $section) {
                    ForEach(IsgTrainingAdvancedSection.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                if canOperate {
                    NovaCompactActionButton(title: "\(section.title) ekle", symbol: "plus", prominent: true) {
                        route = .init(kind: createRoute)
                    }
                    if section == .curriculum, !publishedCurricula.isEmpty,
                       trainings.contains(where: { $0.status == "planned" }) {
                        NovaCompactActionButton(title: RDLocalization.string("localizable.isg.workspace.training.advanced.screen.egitime.mufredat.bagla.ad09bbe1", table: .localizable, fallback: "Eğitime müfredat bağla"), symbol: "link") {
                            route = .init(kind: .linkCurriculum)
                        }
                    }
                }
                if loading { NovaLoadingView(message: RDLocalization.string("localizable.isg.workspace.training.advanced.screen.egitim.yapisi.yukleniyor.9bc58004", table: .localizable, fallback: "Eğitim yapısı yükleniyor…")) }
                else if let error {
                    NovaEmptyState(title: RDLocalization.string("localizable.isg.workspace.training.advanced.screen.egitim.yonetimi.yuklenemedi.379d3762", table: .localizable, fallback: "Eğitim yönetimi yüklenemedi"), message: error)
                    NovaCompactActionButton(title: RDLocalization.string("localizable.isg.workspace.training.advanced.screen.tekrar.dene.b3a8783c", table: .localizable, fallback: "Tekrar dene"), symbol: "arrow.clockwise") { revision = UUID() }
                } else if records.isEmpty {
                    NovaEmptyState(title: RDLocalization.format("localizable.isg.workspace.training.advanced.screen.henuz.1.kaydi.yok.4a9a5d04", table: .localizable, fallback: "Henüz %1$@ kaydı yok.", arguments: [String(describing: section.title.lowercased())]),
                                   message: RDLocalization.string("localizable.isg.workspace.training.advanced.screen.ilk.kaydi.ekleyerek.bu.firmadaki.egitim.surecini.f2a11c17", table: .localizable, fallback: "İlk kaydı ekleyerek bu firmadaki eğitim sürecini planlayabilirsiniz."))
                } else { ForEach(records) { recordRow($0) } }
            }.padding(18).novaPopupContentSize(extra: 120)
                .novaAsyncContent(isLoading: loading)
        }
        .task(id: revision) { await load() }
        .novaPopup(item: $route, onDismiss: { revision = UUID() }) { route in
            IsgWorkspaceTrainingAdvancedEditor(store: store, route: route, curricula: curricula,
                plans: plans, workplaces: workplaces, employees: employees, trainings: trainings, files: files) {
                self.route = nil
            }
        }
    }

    private var publishedCurricula: [IsgWorkspaceAdvancedRecord] { curricula.filter { $0.status == "published" } }
    private var records: [IsgWorkspaceAdvancedRecord] {
        switch section { case .curriculum: return curricula; case .plan: return plans + planItems
        case .assessment: return attempts; case .certificate: return certificates }
    }
    private var createRoute: IsgTrainingAdvancedEditorKind {
        switch section { case .curriculum: return .curriculumCreate; case .plan: return .planCreate
        case .assessment: return .attemptCreate; case .certificate: return .certificateCreate }
    }
    private func recordRow(_ row: IsgWorkspaceAdvancedRecord) -> some View {
        Button {
            switch row.kind { case "curriculum": route = .init(kind: .curriculum(row))
            case "annual_plan": route = .init(kind: .plan(row)); case "annual_item": route = .init(kind: .planItem(row))
            case "certificate": route = .init(kind: .certificate(row)); default: break }
        } label: {
            NovaCard(padding: 14) {
                HStack(spacing: 10) {
                    NovaIcon(symbol: section.symbol, size: 19)
                    VStack(alignment: .leading, spacing: 3) {
                        NovaText(text: row.title, style: .bodyStrong)
                        if let subtitle = row.subtitle { NovaText(text: subtitle, style: .metaQuiet) }
                        if let status = row.status { NovaStatusPill(label: IsgWorkspaceDisplayText.value(status),
                                                                   status: status == "published" || status == "verified" || status == "realised" ? .success : .neutral) }
                    }
                    Spacer(); if row.kind != "attempt" { Image(systemName: "chevron.right") }
                }.contentShape(Rectangle())
            }
        }.buttonStyle(NovaRowPressStyle())
    }
    @MainActor private func load() async {
        loading = true; error = nil
        do {
            async let a = store.trainingAdvanced(.curricula); async let b = store.trainingAdvanced(.annualPlans)
            async let c = store.trainingAdvanced(.annualItems); async let d = store.trainingAdvanced(.attempts)
            async let e = store.trainingAdvanced(.certificates); async let f = store.directory(.workplace)
            async let g = store.employees(); async let h = store.domain(.training)
            async let i = store.domain(.files)
            let values = try await (a, b, c, d, e, f, g, h, i)
            (curricula, plans, planItems, attempts, certificates, workplaces, employees) =
                (values.0, values.1, values.2, values.3, values.4, values.5, values.6)
            trainings = values.7.rows; files = values.8.rows
        } catch { self.error = "Bağlantınızı ve firma yetkinizi kontrol edip yeniden deneyin." }
        loading = false
    }
}

private struct IsgWorkspaceTrainingAdvancedEditor: View {
    @ObservedObject var store: IsgWorkspaceStore
    let route: IsgTrainingAdvancedRoute
    let curricula: [IsgWorkspaceAdvancedRecord]
    let plans: [IsgWorkspaceAdvancedRecord]
    let workplaces: [IsgWorkspaceDirectoryEntry]
    let employees: [IsgWorkspaceEmployeeEntry]
    let trainings: [IsgWorkspaceDomainRecord]
    let files: [IsgWorkspaceDomainRecord]
    let onDone: () -> Void
    @State private var title = ""
    @State private var secondary = ""
    @State private var notes = ""
    @State private var option = "other"
    @State private var hazard = "high"
    @State private var number = 1
    @State private var score = 70
    @State private var assessmentRequired = false
    @State private var hasExpiry = false
    @State private var firstDate = Date()
    @State private var secondDate = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var workplaceID: UUID?
    @State private var employeeID: UUID?
    @State private var curriculumID: UUID?
    @State private var trainingID: UUID?
    @State private var fileID: UUID?
    @State private var working = false
    @State private var error: String?
    @State private var mutationAttempt = IsgWorkspaceMutationAttempt()
    @Environment(\.novaCelebrate) private var celebrate

    init(store: IsgWorkspaceStore, route: IsgTrainingAdvancedRoute,
         curricula: [IsgWorkspaceAdvancedRecord], plans: [IsgWorkspaceAdvancedRecord],
         workplaces: [IsgWorkspaceDirectoryEntry], employees: [IsgWorkspaceEmployeeEntry],
         trainings: [IsgWorkspaceDomainRecord], files: [IsgWorkspaceDomainRecord],
         onDone: @escaping () -> Void) {
        self.store = store; self.route = route; self.curricula = curricula; self.plans = plans
        self.workplaces = workplaces; self.employees = employees; self.trainings = trainings
        self.files = files; self.onDone = onDone
        _workplaceID = State(initialValue: workplaces.first?.id); _employeeID = State(initialValue: employees.first?.id)
        _curriculumID = State(initialValue: curricula.first(where: { $0.status == "published" })?.id)
        switch route.kind {
        case .curriculumTopic(_, let topic):
            _title = State(initialValue: topic.title); _notes = State(initialValue: topic.description)
            _number = State(initialValue: topic.position); _score = State(initialValue: topic.durationMinutes)
        case .planItem(let row):
            _title = State(initialValue: row.title); _secondary = State(initialValue: row.text("target_group") ?? "")
            _notes = State(initialValue: row.text("responsible") ?? "")
            _score = State(initialValue: Int(row.text("duration_minutes") ?? "") ?? 1)
            _firstDate = State(initialValue: Self.date(row.text("planned_on")) ?? Date())
            _curriculumID = State(initialValue: row.uuid("curriculum_id"))
        case .certificate(let row): _fileID = State(initialValue: row.uuid("file_entry_id"))
        default: break
        }
        switch route.kind {
        case .planCreate: _number = State(initialValue: Calendar.current.component(.year, from: Date()))
        case .certificateCreate: _option = State(initialValue: "internal_training")
        default: break
        }
        switch route.kind {
        case .linkCurriculum, .attemptCreate:
            _trainingID = State(initialValue: trainings.first(where: { $0.status == "planned" })?.id)
        case .planItem, .certificateCreate:
            _trainingID = State(initialValue: trainings.first(where: { $0.status == "completed" })?.id)
        default: _trainingID = State(initialValue: trainings.first?.id)
        }
        if case .attemptCreate = route.kind,
           let training = trainings.first(where: { $0.status == "planned" }) {
            _employeeID = State(initialValue: training.trainingParticipants.first?.id)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NovaPopupHeading(text: heading, symbol: "books.vertical", subtitle: hint)
                fields
                if let error { NovaHelpHint(text: error) }
                buttons
            }.padding(18).novaPopupContentSize()
        }.scrollDismissesKeyboard(.interactively)
        .novaPopup(item: $nestedRoute) { child in
            IsgWorkspaceTrainingAdvancedEditor(store: store, route: child, curricula: curricula,
                plans: plans, workplaces: workplaces, employees: employees, trainings: trainings, files: files) {
                nestedRoute = nil; onDone()
            }
        }
    }

    @ViewBuilder private var fields: some View {
        switch route.kind {
        case .curriculumCreate:
            field(RDLocalization.string("localizable.isg.workspace.training.advanced.screen.mufredat.adi.8b54a1ce", table: .localizable, fallback: "Müfredat adı"), text: $title); stringPicker("Döngü", selection: $option,
                values: ["initial", "periodic_repeat", "onboarding", "task_specific", "other"])
            stringPicker("Tehlike sınıfı", selection: $hazard, values: ["low", "medium", "high"])
            field(RDLocalization.string("localizable.isg.workspace.training.advanced.screen.hedef.grup.cf6bc8a1", table: .localizable, fallback: "Hedef grup"), text: $secondary); Toggle(RDLocalization.string("localizable.isg.workspace.training.advanced.screen.sinav.gerekli.8cdcfd3a", table: .localizable, fallback: "Sınav gerekli"), isOn: $assessmentRequired)
                .padding(12).novaControlBackground(cornerRadius: 14)
            if assessmentRequired { Stepper("Geçme puanı: \(score)", value: $score, in: 0...100) }
        case .curriculum(let row) where row.status == "draft":
            NovaHelpHint(text: RDLocalization.format("localizable.isg.workspace.training.advanced.topics.minutes", table: .localizable, fallback: "%1$@ · %2$@ konu · %3$@ dakika", arguments: [String(describing: row.title), String(describing: row.text("topic_count") ?? "0"), String(describing: row.text("total_minutes") ?? "0")]))
            ForEach(row.topics) { topic in
                Button { nestedRoute = .init(kind: .curriculumTopic(row, topic)) } label: {
                    HStack {
                        NovaText(text: "\(topic.position). \(topic.title)", style: .bodyStrong)
                        Spacer(); NovaText(text: "\(topic.durationMinutes) dk", style: .metaQuiet)
                        Image(systemName: "chevron.right")
                    }.padding(12).novaControlBackground(cornerRadius: 14).contentShape(Rectangle())
                }.buttonStyle(NovaRowPressStyle())
            }
            field(RDLocalization.string("localizable.isg.workspace.training.advanced.screen.konu.basligi.bd32509e", table: .localizable, fallback: "Konu başlığı"), text: $title); field(RDLocalization.string("localizable.isg.workspace.training.advanced.screen.konu.aciklamasi.eb12c368", table: .localizable, fallback: "Konu açıklaması"), text: $notes)
            Stepper("Sıra: \(number)", value: $number, in: 1...999)
            Stepper("Süre: \(score) dakika", value: $score, in: 1...1000)
        case .curriculumTopic:
            field(RDLocalization.string("localizable.isg.workspace.training.advanced.screen.konu.basligi.1704979d", table: .localizable, fallback: "Konu başlığı"), text: $title); field(RDLocalization.string("localizable.isg.workspace.training.advanced.screen.konu.aciklamasi.34383aeb", table: .localizable, fallback: "Konu açıklaması"), text: $notes)
            Stepper("Sıra: \(number)", value: $number, in: 1...999)
            Stepper("Süre: \(score) dakika", value: $score, in: 1...1000)
        case .linkCurriculum:
            trainingPicker(plannedOnly: true); curriculumPicker
        case .planCreate:
            field(RDLocalization.string("localizable.isg.workspace.training.advanced.screen.plan.adi.1752444f", table: .localizable, fallback: "Plan adı"), text: $title); workplacePicker
            Stepper("Plan yılı: \(number)", value: $number, in: 2000...2200)
        case .planItemCreate:
            field(RDLocalization.string("localizable.isg.workspace.training.advanced.screen.faaliyet.adi.79713109", table: .localizable, fallback: "Faaliyet adı"), text: $title); field(RDLocalization.string("localizable.isg.workspace.training.advanced.screen.hedef.grup.8771f71b", table: .localizable, fallback: "Hedef grup"), text: $secondary)
            curriculumPicker; DatePicker("Planlanan tarih", selection: $firstDate, displayedComponents: .date)
                .padding(12).novaControlBackground(cornerRadius: 14)
            Stepper("Süre: \(score) dakika", value: $score, in: 1...1000); field("Sorumlu", text: $notes)
        case .planItem:
            field(RDLocalization.string("localizable.isg.workspace.training.advanced.screen.faaliyet.adi.d183c55b", table: .localizable, fallback: "Faaliyet adı"), text: $title); field(RDLocalization.string("localizable.isg.workspace.training.advanced.screen.hedef.grup.fafebc77", table: .localizable, fallback: "Hedef grup"), text: $secondary)
            curriculumPicker; DatePicker("Planlanan tarih", selection: $firstDate, displayedComponents: .date)
                .padding(12).novaControlBackground(cornerRadius: 14)
            Stepper("Süre: \(score) dakika", value: $score, in: 1...1000); field("Sorumlu", text: $notes)
            trainingPicker(plannedOnly: false)
        case .attemptCreate:
            trainingPicker(plannedOnly: true); employeePicker
            Stepper("Deneme: \(number)", value: $number, in: 1...3)
            Stepper("Puan: \(score)", value: $score, in: 0...100)
            DatePicker("Sınav tarihi", selection: $firstDate, displayedComponents: .date)
                .padding(12).novaControlBackground(cornerRadius: 14); field("Not", text: $notes)
        case .certificateCreate:
            employeePicker; trainingPicker(plannedOnly: false, optional: true)
            stringPicker("Belge türü", selection: $option, values: ["internal_training", "external_training", "qualification"])
            field(RDLocalization.string("localizable.isg.workspace.training.advanced.screen.belge.no.452741f8", table: .localizable, fallback: "Belge no"), text: $title); field(RDLocalization.string("localizable.isg.workspace.training.advanced.screen.duzenleyen.67da62d1", table: .localizable, fallback: "Düzenleyen"), text: $secondary)
            filePicker
            DatePicker("Düzenlenme", selection: $firstDate, displayedComponents: .date)
                .padding(12).novaControlBackground(cornerRadius: 14)
            Toggle(RDLocalization.string("localizable.isg.workspace.training.advanced.screen.gecerlilik.sonu.var.7eb7a249", table: .localizable, fallback: "Geçerlilik sonu var"), isOn: $hasExpiry).padding(12).novaControlBackground(cornerRadius: 14)
            if hasExpiry { DatePicker("Geçerlilik sonu", selection: $secondDate, in: firstDate..., displayedComponents: .date)
                .padding(12).novaControlBackground(cornerRadius: 14) }
        default: EmptyView()
        }
    }

    @ViewBuilder private var buttons: some View {
        switch route.kind {
        case .curriculum(let row) where row.status == "draft":
            actionButton("Konu ekle", action: "curriculum_topic_save", prominent: true)
            actionButton("Müfredatı yayımla", action: "curriculum_publish")
        case .curriculum(let row) where row.status == "published":
            actionButton("Yeni sürüm hazırla", action: "curriculum_revise", prominent: true)
            actionButton("Müfredatı kullanımdan kaldır", action: "curriculum_retire")
        case .curriculumTopic:
            actionButton("Konuyu güncelle", action: "curriculum_topic_save", prominent: true)
            actionButton("Konuyu sil", action: "curriculum_topic_delete")
        case .plan(let row) where row.status == "draft": actionButton("Planı etkinleştir", action: "plan_activate", prominent: true)
        case .plan(let row) where row.status == "active":
            NovaCompactActionButton(title: RDLocalization.string("localizable.isg.workspace.training.advanced.screen.faaliyet.ekle.535807b5", table: .localizable, fallback: "Faaliyet ekle"), symbol: "plus", prominent: true) {
                // Replace this detail popup with the item editor while retaining the parent plan.
                nestedRoute = .init(kind: .planItemCreate(row))
            }
            actionButton("Planı kapat", action: "plan_close")
        case .planItem: actionButton("Değişiklikleri kaydet", action: "plan_item_save")
            actionButton("Gerçekleşen eğitime bağla", action: "plan_item_realise", prominent: true)
            actionButton("Faaliyeti iptal et", action: "plan_item_cancel")
        case .certificate(let row) where row.status != "revoked":
            if row.status != "verified" { actionButton("Belgeyi doğrula", action: "certificate_verify", prominent: true) }
            actionButton("Belgeyi iptal et", action: "certificate_revoke")
        case .curriculumCreate: actionButton("Taslak oluştur", action: "curriculum_create", prominent: true)
        case .linkCurriculum: actionButton("Müfredatı bağla", action: "training_link_curriculum", prominent: true)
        case .planCreate: actionButton("Yıllık plan oluştur", action: "plan_create", prominent: true)
        case .planItemCreate: actionButton("Faaliyeti kaydet", action: "plan_item_save", prominent: true)
        case .attemptCreate: actionButton("Sınav sonucunu kaydet", action: "attempt_record", prominent: true)
        case .certificateCreate: actionButton("Belgeyi kaydet", action: "certificate_issue", prominent: true)
        default: EmptyView()
        }
    }

    @State private var nestedRoute: IsgTrainingAdvancedRoute?
    private var heading: String {
        switch route.kind { case .curriculumCreate: return RDLocalization.string("localizable.isg.workspace.training.advanced.screen.mufredat.olustur.2c1c0d0d", table: .localizable, fallback: "Müfredat oluştur"); case .curriculum: return RDLocalization.string("localizable.isg.workspace.training.advanced.screen.mufredat.yonetimi.73408794", table: .localizable, fallback: "Müfredat yönetimi")
        case .curriculumTopic: return RDLocalization.string("localizable.isg.workspace.training.advanced.screen.mufredat.konusu.01963e0d", table: .localizable, fallback: "Müfredat konusu")
        case .linkCurriculum: return RDLocalization.string("localizable.isg.workspace.training.advanced.screen.egitime.mufredat.bagla.3efdf566", table: .localizable, fallback: "Eğitime müfredat bağla"); case .planCreate: return RDLocalization.string("localizable.isg.workspace.training.advanced.screen.yillik.egitim.plani.c4ad8d07", table: .localizable, fallback: "Yıllık eğitim planı")
        case .plan: return RDLocalization.string("localizable.isg.workspace.training.advanced.screen.plan.yonetimi.647a4195", table: .localizable, fallback: "Plan yönetimi"); case .planItemCreate: return RDLocalization.string("localizable.isg.workspace.training.advanced.screen.plan.faaliyeti.f79419fb", table: .localizable, fallback: "Plan faaliyeti")
        case .planItem: return RDLocalization.string("localizable.isg.workspace.training.advanced.screen.faaliyet.sonucu.c3b6e989", table: .localizable, fallback: "Faaliyet sonucu"); case .attemptCreate: return RDLocalization.string("localizable.isg.workspace.training.advanced.screen.sinav.sonucu.fb311cf9", table: .localizable, fallback: "Sınav sonucu")
        case .certificateCreate: return RDLocalization.string("localizable.isg.workspace.training.advanced.screen.belge.ekle.f1ba3177", table: .localizable, fallback: "Belge ekle"); case .certificate: return RDLocalization.string("localizable.isg.workspace.training.advanced.screen.belge.yonetimi.26d50f8d", table: .localizable, fallback: "Belge yönetimi") }
    }
    private var hint: String { "Değişiklikler sürümlenir; yayımlanmış müfredat ve geçmiş kayıtlar geriye dönük değiştirilmez." }
    private var publishedCurricula: [IsgWorkspaceAdvancedRecord] { curricula.filter { $0.status == "published" } }
    private var completedTrainings: [IsgWorkspaceDomainRecord] { trainings.filter { $0.status == "completed" } }
    private var plannedTrainings: [IsgWorkspaceDomainRecord] { trainings.filter { $0.status == "planned" } }

    private func field(_ label: String, text: Binding<String>) -> some View {
        TextField(label, text: text, axis: .vertical).padding(14).novaControlBackground(cornerRadius: 14)
    }
    private func stringPicker(_ label: String, selection: Binding<String>, values: [String]) -> some View {
        Picker(label, selection: selection) {
            ForEach(values, id: \.self) { Text(IsgWorkspaceDisplayText.value($0)).tag($0) }
        }
            .pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
    }
    private var workplacePicker: some View {
        Picker(RDLocalization.string("localizable.isg.workspace.training.advanced.screen.isyeri.71690301", table: .localizable, fallback: "İşyeri"), selection: $workplaceID) { ForEach(workplaces) { Text($0.name).tag(Optional($0.id)) } }
            .pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
    }
    private var employeePicker: some View {
        Picker("Personel", selection: $employeeID) {
            ForEach(selectableEmployees) { Text($0.name).tag(Optional($0.id)) }
        }
            .pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
    }
    private var selectableEmployees: [IsgWorkspaceEmployeeEntry] {
        guard case .attemptCreate = route.kind else { return employees }
        let enrolled = Set(selectedTraining?.trainingParticipants.map(\.id) ?? [])
        return employees.filter { enrolled.contains($0.id) }
    }
    private var curriculumPicker: some View {
        Picker(RDLocalization.string("localizable.isg.workspace.training.advanced.screen.mufredat.f0b8ea0a", table: .localizable, fallback: "Müfredat"), selection: $curriculumID) {
            Text(RDLocalization.string("localizable.isg.workspace.training.advanced.screen.mufredat.yok.533272b3", table: .localizable, fallback: "Müfredat yok")).tag(UUID?.none)
            ForEach(publishedCurricula) { Text($0.title).tag(Optional($0.id)) }
        }
            .pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
    }
    private var filePicker: some View {
        Picker(RDLocalization.string("localizable.isg.workspace.training.advanced.screen.belge.dosyasi.b4f6d871", table: .localizable, fallback: "Belge dosyası"), selection: $fileID) {
            Text(RDLocalization.string("localizable.isg.workspace.training.advanced.screen.dosya.baglama.34455d56", table: .localizable, fallback: "Dosya bağlama")).tag(UUID?.none)
            ForEach(files) { Text($0.title).tag(Optional($0.id)) }
        }.pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
    }
    private func trainingPicker(plannedOnly: Bool, optional: Bool = false) -> some View {
        let values = plannedOnly ? plannedTrainings : completedTrainings
        return Picker(RDLocalization.string("localizable.isg.workspace.training.advanced.screen.egitim.a6877931", table: .localizable, fallback: "Eğitim"), selection: $trainingID) {
            if optional { Text(RDLocalization.string("localizable.isg.workspace.training.advanced.screen.egitime.bagli.degil.a39132e7", table: .localizable, fallback: "Eğitime bağlı değil")).tag(UUID?.none) }
            ForEach(values) { Text($0.title).tag(Optional($0.id)) }
        }.pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
            .onChange(of: trainingID) { _ in
                if case .attemptCreate = route.kind { employeeID = selectableEmployees.first?.id }
            }
    }
    private func actionButton(_ title: String, action: String, prominent: Bool = false) -> some View {
        NovaCompactActionButton(title: working ? "Kaydediliyor…" : title, symbol: "checkmark",
                                prominent: prominent, enabled: !working) { mutate(action) }
    }
    private func mutate(_ action: String) {
        var payload: [String: IsgWorkspaceRPCValue] = ["action": .string(action)]
        switch route.kind {
        case .curriculumCreate:
            payload.merge(["id": .null, "expected_version": .number(0), "title": .string(title),
                "cycle": .string(option), "hazard_class": .string(hazard), "target_group": .string(secondary),
                "assessment_required": .bool(assessmentRequired),
                "pass_score": assessmentRequired ? .number(score) : .null]) { _, new in new }
        case .curriculum(let row):
            payload.merge(["id": .id(row.id), "expected_version": .number(Int(row.version))]) { _, new in new }
            if action == "curriculum_topic_save" {
                payload.merge(["curriculum_id": .id(row.id), "topic_id": .null, "position": .number(number),
                    "title": .string(title), "description": .string(notes), "duration_minutes": .number(score)]) { _, new in new }
            }
        case .curriculumTopic(let curriculum, let topic):
            payload.merge(["id": .id(curriculum.id), "expected_version": .number(Int(curriculum.version)),
                "curriculum_id": .id(curriculum.id), "topic_id": .id(topic.id)]) { _, new in new }
            if action == "curriculum_topic_save" {
                payload.merge(["position": .number(number), "title": .string(title),
                    "description": .string(notes), "duration_minutes": .number(score)]) { _, new in new }
            }
        case .linkCurriculum:
            payload.merge(["id": .id(trainingID), "expected_version": .number(Int(selectedTraining?.version ?? 0)),
                           "curriculum_id": .id(curriculumID)]) { _, new in new }
        case .planCreate:
            payload.merge(["id": .null, "expected_version": .number(0), "workplace_id": .id(workplaceID),
                           "plan_year": .number(number), "title": .string(title)]) { _, new in new }
        case .plan(let row): payload.merge(["id": .id(row.id), "expected_version": .number(Int(row.version))]) { _, new in new }
        case .planItemCreate(let plan):
            payload.merge(["id": .null, "expected_version": .number(0), "plan_id": .id(plan.id),
                "curriculum_id": .id(curriculumID), "title": .string(title), "target_group": .string(secondary),
                "planned_on": .string(Self.day(firstDate)), "duration_minutes": .number(score),
                "responsible": .string(notes)]) { _, new in new }
        case .planItem(let row):
            payload.merge(["id": .id(row.id), "expected_version": .number(Int(row.version)),
                           "training_id": action == "plan_item_realise" ? .id(trainingID) : .null]) { _, new in new }
            if action == "plan_item_save" {
                payload.merge(["plan_id": .id(row.uuid("plan_id")), "curriculum_id": .id(curriculumID),
                    "title": .string(title), "target_group": .string(secondary),
                    "planned_on": .string(Self.day(firstDate)), "duration_minutes": .number(score),
                    "responsible": .string(notes)]) { _, new in new }
            }
        case .attemptCreate:
            payload.merge(["id": .null, "expected_version": .number(0), "training_id": .id(trainingID),
                "employee_id": .id(employeeID), "attempt_no": .number(number), "score": .number(score),
                "passed": .bool(score >= selectedCurriculumPassScore), "taken_on": .string(Self.day(firstDate)),
                "notes": .string(notes)]) { _, new in new }
        case .certificateCreate:
            payload.merge(["id": .null, "expected_version": .number(0), "employee_id": .id(employeeID),
                "training_id": .id(trainingID), "file_entry_id": .id(fileID), "certificate_kind": .string(option),
                "certificate_no": .string(title), "issuer": .string(secondary), "issued_on": .string(Self.day(firstDate)),
                "expires_on": hasExpiry ? .string(Self.day(secondDate)) : .null]) { _, new in new }
        case .certificate(let row): payload.merge(["id": .id(row.id), "expected_version": .number(Int(row.version))]) { _, new in new }
        }
        var attempt = mutationAttempt; let mutationID = attempt.id(namespace: "training.advanced.\(action)", payload: payload)
        mutationAttempt = attempt; working = true; error = nil
        Task { @MainActor in
            do { try await store.mutateTrainingAdvanced(mutationID: mutationID, payload: payload)
                celebrate(NovaSuccessMessage.recordSaved(heading)); onDone() }
            catch { self.error = "İşlem tamamlanamadı. Seçimleri, tarihleri ve kayıt sürümünü kontrol edin." }
            working = false
        }
    }
    private var selectedTraining: IsgWorkspaceDomainRecord? { trainings.first { $0.id == trainingID } }
    private var selectedCurriculumPassScore: Int {
        guard let id = selectedTraining?.facts.first(where: { $0.0 == "workspace_curriculum_id" })?.1,
              let uuid = UUID(uuidString: id), let raw = curricula.first(where: { $0.id == uuid })?.text("pass_score") else { return 0 }
        return Int(raw) ?? 0
    }
    private static func day(_ date: Date) -> String { date.formatted(.iso8601.year().month().day().dateSeparator(.dash)) }
    private static func date(_ value: String?) -> Date? {
        guard let value else { return nil }
        return ISO8601DateFormatter().date(from: value + "T00:00:00Z")
    }
}
