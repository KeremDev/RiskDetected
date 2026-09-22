import SwiftUI

/// Product-parity create flows for the records whose personal-pilot editors
/// carry real workflow behavior. They keep the Nova interaction model while
/// every read and mutation still goes through the tenant-scoped workspace API.

private struct IsgParityProgress: View {
    let completed: Int
    let total: Int
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    NovaText(text: "\(completed)/\(total) başlık tamamlandı", style: .label)
                    Spacer(minLength: 0)
                    NovaStatusPill(label: completed == total ? "Kaydedilebilir" : "Bilgi bekliyor",
                                   status: completed == total ? .success : .warning)
                }
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(NovaColorToken.borderMuted.color(in: scheme))
                        Capsule().fill(NovaColorToken.accent.color(in: scheme))
                            .frame(width: proxy.size.width * CGFloat(completed) / CGFloat(max(1, total)))
                    }
                }.frame(height: 6)
            }
        }
    }
}

struct IsgWorkspaceTrainingCreateEditor: View {
    private struct TopicDraft: Identifiable, Equatable {
        let id = UUID()
        var title: String
        var minutes: Int
    }
    private struct StatutoryPreset: Identifiable {
        let id: String
        let title: String
        let hazardClass: String
        let validityYears: Int
        let topics: [TopicDraft]
        var minutes: Int { topics.reduce(0) { $0 + $1.minutes } }
    }
    private enum Step: String, CaseIterable { case info, schedule, trainers, participants, review }
    @ObservedObject var store: IsgWorkspaceStore
    let companyHazardClass: String
    let onDone: () -> Void
    @State private var curricula: [IsgWorkspaceAdvancedRecord] = []
    @State private var employees: [IsgWorkspaceEmployeeEntry] = []
    @State private var curriculumID: UUID?
    @State private var templateKey = "custom"
    @State private var topics: [TopicDraft] = []
    @State private var suggestedValidityYears = 1
    @State private var title = ""
    @State private var trainer = ""
    @State private var method = "face_to_face"
    @State private var location = ""
    @State private var notes = ""
    @State private var heldOn = Calendar.current.startOfDay(for: Date())
    @State private var hasValidity = false
    @State private var validUntil = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var minutes = 60
    @State private var employeeQuery = ""
    @State private var selectedEmployees = Set<UUID>()
    @State private var attachment: IsgWorkspaceAttachmentDraft?
    @State private var currentStep: Step = .info
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    @State private var validationError: String?
    @State private var showingTopics = false
    @State private var confirmingExit = false
    @State private var didSave = false
    @State private var workflowMutationIDs: [String: UUID] = [:]
    @Environment(\.novaCelebrate) private var celebrate

    private var usableCurricula: [IsgWorkspaceAdvancedRecord] {
        curricula.filter { $0.status == "published" && !$0.flag("assessment_required") }
    }
    private var curriculum: IsgWorkspaceAdvancedRecord? {
        usableCurricula.first { $0.id == curriculumID }
    }
    private var statutoryPresets: [StatutoryPreset] {
        [
            .init(id: "legal-low", title: "Temel İSG Eğitimi · Az Tehlikeli", hazardClass: "low",
                  validityYears: 3, topics: Self.topicPlan(total: 480, workSpecific: 120)),
            .init(id: "legal-medium", title: "Temel İSG Eğitimi · Tehlikeli", hazardClass: "medium",
                  validityYears: 2, topics: Self.topicPlan(total: 720, workSpecific: 180)),
            .init(id: "legal-high", title: "Temel İSG Eğitimi · Çok Tehlikeli", hazardClass: "high",
                  validityYears: 1, topics: Self.topicPlan(total: 960, workSpecific: 240))
        ]
    }
    private var filteredEmployees: [IsgWorkspaceEmployeeEntry] {
        let needle = employeeQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return employees }
        return employees.filter { $0.name.localizedCaseInsensitiveContains(needle) ||
            $0.code.localizedCaseInsensitiveContains(needle) }
    }
    private var completed: Int { Step.allCases.filter(isComplete).count }
    private var stepNumber: Int { (Step.allCases.firstIndex(of: currentStep) ?? 0) + 1 }

    var body: some View {
        Group {
            if didSave {
                NovaTaskSuccessView(
                    title: "Eğitim kaydedildi",
                    message: "\(selectedEmployees.count) katılımcı için \(minutes) dakikalık gerçekleşen eğitim kaydı oluşturuldu.",
                    doneTitle: "Eğitimlere dön",
                    onDone: onDone)
            } else {
                NovaPageSurface {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            NovaTaskHeader(title: "Eğitim ekle", step: stepNumber,
                                total: Step.allCases.count, stepTitle: stepTitle(currentStep)) {
                                    confirmingExit = true
                                }
                            if loading {
                                NovaLoadingView(message: "Eğitim kataloğu ve personel hazırlanıyor…")
                            } else {
                                NovaText(text: "Bilgiler akış boyunca korunur.", style: .micro)
                                if let validationError { NovaTaskErrorSummary(message: validationError) }
                                stepContent(currentStep)
                                if let error { NovaTaskErrorSummary(message: error) }
                            }
                        }
                        .padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 28)
                        .novaAsyncContent(isLoading: loading)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom) {
                        if !loading {
                            NovaTaskStickyActions(primaryTitle: currentStep == .review ? "Eğitimi kaydet" : "Devam",
                                primarySymbol: currentStep == .review ? "checkmark" : "arrow.right",
                                isWorking: saving, canGoBack: currentStep != .info,
                                onBack: previousStep, onPrimary: advance)
                        }
                    }
                }
            }
        }
        .task { await prepare() }
        .onChange(of: templateKey) { _ in applyTemplate() }
        .onChange(of: hasValidity) { enabled in if enabled { refreshSuggestedValidity() } }
        .onChange(of: heldOn) { _ in if hasValidity { refreshSuggestedValidity() } }
        .onChange(of: topics) { _ in syncMinutes() }
        .novaFullScreenCover(isPresented: $showingTopics) { topicEditor }
        .confirmationDialog("Eğitim akışından çıkılsın mı?", isPresented: $confirmingExit,
            titleVisibility: .visible) {
                Button("Çık", role: .destructive, action: onDone)
                Button("Devam et", role: .cancel) {}
            } message: {
                Text("Henüz kaydedilmemiş bilgiler silinir.")
            }
    }

    @ViewBuilder private func stepContent(_ step: Step) -> some View {
        switch step {
        case .info: infoStep
        case .schedule: scheduleStep
        case .trainers: trainerStep
        case .participants: participantStep
        case .review: reviewStep
        }
    }

    private var infoStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Kayıtlı eğitim", selection: $templateKey) {
                Text("Özel eğitim").tag("custom")
                Section("Zorunlu temel eğitim şablonları") {
                    ForEach(statutoryPresets) { preset in
                        Text("\(preset.title) · \(preset.minutes) dk").tag(preset.id)
                    }
                }
                if !usableCurricula.isEmpty {
                    Section("OSGB eğitim kataloğu") {
                        ForEach(usableCurricula) { row in
                            Text("\(row.title) · \(row.text("total_minutes") ?? "0") dk")
                                .tag("curriculum:\(row.id.uuidString)")
                        }
                    }
                }
            }.pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
            field("Eğitim başlığı", text: $title, symbol: "text.book.closed")
            if !topics.isEmpty {
                Button { showingTopics = true } label: {
                    HStack(spacing: 11) {
                        Image(systemName: "list.bullet.rectangle").frame(width: 24)
                        VStack(alignment: .leading, spacing: 3) {
                            NovaText(text: "Konular ve süre", style: .bodyStrong)
                            NovaText(text: "\(topics.count) konu · \(minutes) dakika", style: .metaQuiet)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                    }.frame(minHeight: 54).contentShape(Rectangle())
                }.buttonStyle(NovaRowPressStyle()).padding(12).novaControlBackground(cornerRadius: 14)
            } else {
                Stepper("Süre: \(minutes) dakika", value: $minutes, in: 1...100_000)
                    .padding(12).novaControlBackground(cornerRadius: 14)
            }
            DisclosureGroup("Ek bilgiler") {
                field("Eğitim notu (isteğe bağlı)", text: $notes, symbol: "note.text")
                    .padding(.top, 8)
            }.font(NovaFont.font(.bodyStrong)).padding(12).novaControlBackground(cornerRadius: 14)
        }
    }

    private var scheduleStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            compactDate("Tamamlandığı tarih", selection: $heldOn)
            Picker("Eğitim yöntemi", selection: $method) {
                ForEach(["face_to_face", "online", "mixed"], id: \.self) {
                    Text(IsgWorkspaceDisplayText.value($0)).tag($0)
                }
            }.pickerStyle(.segmented)
            field("Konum / toplantı bağlantısı", text: $location, symbol: "mappin.and.ellipse")
            Toggle("Geçerlilik tarihi ekle", isOn: $hasValidity)
                .padding(12).novaControlBackground(cornerRadius: 14)
            if hasValidity {
                compactDate("Geçerlilik tarihi", selection: $validUntil)
                NovaHelpHint(text: "Tarih tehlike sınıfına göre \(suggestedValidityYears) yıl sonrası olarak önerildi; gerekirse değiştirebilirsiniz.")
            }
        }
    }

    private var trainerStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            field("Eğitici ad soyad / kurum", text: $trainer, symbol: "person.crop.rectangle")
            NovaHelpHint(text: "Eğitici bu gerçekleşen eğitim kaydının tamamı için kullanılır.")
        }
    }

    private var participantStep: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                NovaText(text: "Firma personeli", style: .bodyStrong)
                Spacer(); NovaText(text: "\(selectedEmployees.count) seçili", style: .metaQuiet)
            }
            searchField
            if !employees.isEmpty {
                NovaCompactActionButton(title: selectedEmployees.count == employees.count ? "Seçimi temizle" : "Tümünü seç",
                    symbol: selectedEmployees.count == employees.count ? "xmark.circle" : "checkmark.circle") {
                        if selectedEmployees.count == employees.count { selectedEmployees.removeAll() }
                        else { selectedEmployees = Set(employees.map(\.id)) }
                    }
            }
            if employees.isEmpty {
                NovaHelpHint(text: "Eğitim kaydetmek için önce firma personeli ekleyin.")
            } else if filteredEmployees.isEmpty {
                NovaHelpHint(text: "Aramanızla eşleşen personel bulunamadı.")
            }
            ForEach(filteredEmployees) { employee in
                Button {
                    if selectedEmployees.contains(employee.id) { selectedEmployees.remove(employee.id) }
                    else { selectedEmployees.insert(employee.id) }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selectedEmployees.contains(employee.id) ? "checkmark.circle.fill" : "circle")
                        NovaText(text: employee.name, style: .body)
                        Spacer(minLength: 0)
                    }.frame(minHeight: 42).contentShape(Rectangle())
                }.buttonStyle(NovaRowPressStyle())
            }
            NovaHelpHint(text: "Kaydettiğinizde seçilen personelin eğitime katıldığını beyan etmiş olursunuz.")
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            NovaText(text: "Kaydetmeden önce kontrol edin", style: .sectionTitle)
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    reviewRow("Eğitim", title)
                    Divider()
                    reviewRow("Yöntem", IsgWorkspaceDisplayText.value(method))
                    reviewRow("Tarih", Self.day(heldOn))
                    reviewRow("Süre", "\(minutes) dakika")
                    reviewRow("Eğitici", trainer)
                    reviewRow("Katılımcı", "\(selectedEmployees.count) kişi")
                    if !location.trimmed.isEmpty { reviewRow("Yer", location.trimmed) }
                }
            }
            IsgWorkspaceInlineAttachmentField(
                title: "Eğitim belgesi veya yoklama ekle (isteğe bağlı)",
                attachment: $attachment)
            NovaHelpHint(text: "Bir bilgiyi değiştirmek için Geri ile ilgili adıma dönebilirsiniz.")
        }
    }

    private var topicEditor: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    NovaPageHeading(title: "Konular ve süre", onBack: { showingTopics = false })
                    HStack {
                        NovaText(text: "Toplam süre", style: .metaQuiet)
                        Spacer()
                        NovaText(text: "\(minutes) dakika", style: .sectionTitle)
                    }
                    ForEach($topics) { $topic in
                        NovaCard(padding: 12) {
                            VStack(alignment: .leading, spacing: 9) {
                                TextField("Konu", text: $topic.title, axis: .vertical)
                                    .font(NovaFont.font(.body)).lineLimit(1...3)
                                HStack {
                                    Stepper("\(topic.minutes) dakika", value: $topic.minutes, in: 5...2_000, step: 5)
                                    Button { topics.removeAll { $0.id == topic.id }; syncMinutes() } label: {
                                        Image(systemName: "trash").frame(width: 44, height: 44)
                                    }.buttonStyle(NovaRowPressStyle()).accessibilityLabel("Konuyu sil")
                                }
                            }
                        }
                    }
                    NovaCompactActionButton(title: "İşyerine özgü konu ekle", symbol: "plus") {
                        topics.append(.init(title: "", minutes: 30)); syncMinutes()
                    }
                }.padding(18).padding(.bottom, 80)
            }
            .safeAreaInset(edge: .bottom) {
                NovaTaskStickyActions(primaryTitle: "Bitti", primarySymbol: "checkmark",
                    canGoBack: false, onBack: {}, onPrimary: { showingTopics = false })
            }
        }
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            NovaText(text: label, style: .metaQuiet).frame(width: 82, alignment: .leading)
            NovaText(text: value.isEmpty ? "Belirtilmedi" : value, style: .bodyStrong)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
            TextField("Personel ara", text: $employeeQuery)
            if !employeeQuery.isEmpty {
                Button { employeeQuery = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(NovaRowPressStyle())
            }
        }.padding(.horizontal, 12).frame(minHeight: 44).novaControlBackground(cornerRadius: 14)
    }

    private func isComplete(_ step: Step) -> Bool {
        switch step {
        case .info: return !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && minutes > 0
        case .schedule:
            return Calendar.current.startOfDay(for: heldOn) <= Calendar.current.startOfDay(for: Date()) &&
                (!hasValidity || validUntil > heldOn)
        case .trainers: return !trainer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .participants: return !selectedEmployees.isEmpty
        case .review: return Step.allCases.filter { $0 != .review }.allSatisfy(isComplete)
        }
    }
    private func stepTitle(_ step: Step) -> String {
        switch step { case .info: return "Eğitim ve konular"; case .schedule: return "Tarih, yöntem ve yer"
        case .trainers: return "Eğiticiler"; case .participants: return "Katılımcılar"
        case .review: return "Kontrol ve kaydet" }
    }
    private func stepSymbol(_ step: Step) -> String {
        switch step { case .info: return "text.book.closed"; case .schedule: return "calendar.badge.clock"
        case .trainers: return "person.crop.rectangle"; case .participants: return "person.3"
        case .review: return "checkmark.circle" }
    }

    private func advance() {
        validationError = nil
        guard isComplete(currentStep) else {
            validationError = validationMessage(currentStep)
            return
        }
        guard currentStep != .review else { save(); return }
        guard let index = Step.allCases.firstIndex(of: currentStep) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { currentStep = Step.allCases[index + 1] }
    }

    private func previousStep() {
        validationError = nil
        guard let index = Step.allCases.firstIndex(of: currentStep), index > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) { currentStep = Step.allCases[index - 1] }
    }

    private func validationMessage(_ step: Step) -> String {
        switch step {
        case .info: return "Eğitim başlığını ve toplam süreyi kontrol edin."
        case .schedule: return "Eğitim tarihi ve geçerlilik bilgisini kontrol edin."
        case .trainers: return "En az bir eğitici adı veya kurum bilgisi girin."
        case .participants: return "En az bir katılımcı seçin."
        case .review: return "Önceki adımlarda tamamlanmamış bilgi var."
        }
    }

    @MainActor private func prepare() async {
        loading = true; error = nil
        do {
            async let a = store.trainingAdvanced(.curricula)
            async let b = store.employees()
            (curricula, employees) = try await (a, b)
            templateKey = statutoryPresetKey(for: companyHazardClass)
            applyTemplate()
        } catch { self.error = "Eğitim kataloğu veya personel listesi yüklenemedi. Bağlantınızı kontrol edip yeniden deneyin." }
        loading = false
    }

    private func applyTemplate() {
        if let preset = statutoryPresets.first(where: { $0.id == templateKey }) {
            curriculumID = nil
            title = preset.title
            topics = preset.topics
            suggestedValidityYears = preset.validityYears
            hasValidity = true
            syncMinutes()
            refreshSuggestedValidity()
            return
        }
        if templateKey.hasPrefix("curriculum:"),
           let id = UUID(uuidString: String(templateKey.dropFirst("curriculum:".count))),
           let curriculum = usableCurricula.first(where: { $0.id == id }) {
            curriculumID = id
            title = curriculum.title
            topics = curriculum.topics.map { .init(title: $0.title, minutes: $0.durationMinutes) }
            if topics.isEmpty {
                topics = [.init(title: curriculum.title,
                                minutes: Int(curriculum.text("total_minutes") ?? "") ?? 60)]
            }
            suggestedValidityYears = 1
            syncMinutes()
            return
        }
        curriculumID = nil
        topics = []
    }

    private func refreshSuggestedValidity() {
        validUntil = Calendar(identifier: .gregorian).date(byAdding: .year,
            value: suggestedValidityYears, to: heldOn)
            ?? Calendar.current.date(byAdding: .year, value: suggestedValidityYears, to: heldOn) ?? heldOn
    }

    private func syncMinutes() {
        minutes = max(1, topics.reduce(0) { $0 + max(0, $1.minutes) })
    }

    private func save() {
        guard completed == Step.allCases.count else { return }
        let participants = selectedEmployees.sorted { $0.uuidString < $1.uuidString }
        let create: [String: IsgWorkspaceRPCValue] = [
            "action": .string("save"), "expected_version": .number(0), "title": .string(title.trimmed),
            "trainer": .string(trainer.trimmed), "method": .string(method),
            "starts_at": .string(Self.startOfDayInstant(heldOn)), "duration_minutes": .number(minutes),
            "valid_until": hasValidity ? .string(Self.day(validUntil)) : .null,
            "location": .string(location.trimmed), "notes": .string(trainingNotes),
            "participants": .array(participants.map { .object(["id": .id($0), "attended": .bool(false)]) })
        ]
        saving = true; error = nil
        Task { @MainActor in
            do {
                let uploaded = try await uploadAttachmentIfNeeded()
                let created = try await store.mutateDomain(mutationID: workflowID("training.create", create),
                                                           domain: .training, payload: create)
                guard let id = created.recordID else { throw IsgWorkspaceAPIFailure.invalidResponse }
                var expected = created.version ?? 0
                if let curriculumID {
                    let link: [String: IsgWorkspaceRPCValue] = [
                        "action": .string("training_link_curriculum"), "id": .id(id),
                        "expected_version": .number(Int(expected)), "curriculum_id": .id(curriculumID)
                    ]
                    try await store.mutateTrainingAdvanced(mutationID: workflowID("training.link", link), payload: link)
                    guard let linked = try await store.domain(.training).rows.first(where: { $0.id == id }),
                          let version = linked.version else { throw IsgWorkspaceAPIFailure.invalidResponse }
                    expected = version
                }
                let complete: [String: IsgWorkspaceRPCValue] = [
                    "action": .string("complete"), "id": .id(id), "expected_version": .number(Int(expected)),
                    "participants": .array(participants.map { .object(["id": .id($0), "attended": .bool(true)]) })
                ]
                _ = try await store.mutateDomain(mutationID: workflowID("training.complete", complete),
                                                 domain: .training, payload: complete)
                if let uploaded {
                    _ = try await store.attachFile(
                        mutationID: workflowID("training.file.attach", [
                            "entry_id": .id(uploaded.entryID), "parent_id": .id(id)
                        ]), entryID: uploaded.entryID, parentKind: "training",
                        parentID: id, fieldName: "attachment")
                }
                celebrate(NovaSuccessMessage.trainingSaved)
                didSave = true
            } catch {
                self.error = "Eğitim tamamlanamadı. Katalog, tarih, eğitici ve katılımcı bilgilerini kontrol edip yeniden deneyin."
            }
            saving = false
        }
    }

    private func workflowID(_ namespace: String, _ payload: [String: IsgWorkspaceRPCValue]) -> UUID {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let signature = namespace + ":" + IsgWorkspaceMutationAttempt.digest((try? encoder.encode(IsgWorkspaceRPCValue.object(payload))) ?? Data())
        if let id = workflowMutationIDs[signature] { return id }
        let id = UUID(); workflowMutationIDs[signature] = id; return id
    }
    private var trainingNotes: String {
        let topicText = topics.enumerated().map { index, topic in
            "\(index + 1). \(topic.title.trimmed) (\(topic.minutes) dk)"
        }.joined(separator: "\n")
        return [notes.trimmed, topicText.isEmpty ? "" : "Eğitim konuları:\n" + topicText]
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
    private func statutoryPresetKey(for raw: String) -> String {
        switch raw.lowercased() {
        case "low", "az_tehlikeli", "az tehlikeli": return "legal-low"
        case "high", "cok_tehlikeli", "çok tehlikeli": return "legal-high"
        default: return "legal-medium"
        }
    }
    private static func topicPlan(total: Int, workSpecific: Int) -> [TopicDraft] {
        let remaining = total - workSpecific
        let general = remaining / 6
        let health = remaining / 3
        let technical = remaining - general - health
        return [
            .init(title: "Genel konular", minutes: general),
            .init(title: "Sağlık konuları", minutes: health),
            .init(title: "Teknik konular", minutes: technical),
            .init(title: "İşe özgü riskler", minutes: workSpecific)
        ]
    }
    private func uploadAttachmentIfNeeded() async throws -> IsgWorkspaceFileUploadResult? {
        guard let attachment else { return nil }
        let signature: [String: IsgWorkspaceRPCValue] = [
            "filename": .string(attachment.filename),
            "digest": .string(IsgWorkspaceMutationAttempt.digest(attachment.data))
        ]
        return try await store.uploadFile(
            mutationID: workflowID("training.file.upload", signature),
            title: attachment.title, filename: attachment.filename,
            category: "training_material", data: attachment.data)
    }
    private func field(_ label: String, text: Binding<String>, symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).frame(width: 20)
            TextField(label, text: text, axis: .vertical).lineLimit(1...4).font(NovaFont.font(.body))
        }.padding(12).novaControlBackground(cornerRadius: 14)
    }
    private func compactDate(_ label: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            NovaText(text: label, style: .metaQuiet)
            DatePicker(label, selection: selection, displayedComponents: .date).labelsHidden().datePickerStyle(.compact)
        }.padding(12).frame(maxWidth: .infinity, minHeight: 66, alignment: .leading).novaControlBackground(cornerRadius: 14)
    }
    private static func day(_ date: Date) -> String { date.formatted(.iso8601.year().month().day().dateSeparator(.dash)) }
    private static func startOfDayInstant(_ date: Date) -> String { ISO8601DateFormatter().string(from: Calendar.current.startOfDay(for: date)) }
}

/// The workspace provider for the same step-by-step manual finding experience
/// used by the normal expert.  Tenant scoping stays in IsgWorkspaceStore; the
/// visible fields and progression are deliberately provider-independent.
struct IsgWorkspaceManualNonconformityEditor: View {
    private enum Step: String, CaseIterable {
        case attachment, workplace, hazard, scoring, legislation, responsible
    }

    @ObservedObject var store: IsgWorkspaceStore
    let onDone: () -> Void
    @State private var workplaces: [IsgWorkspaceDirectoryEntry] = []
    @State private var workplaceID: UUID?
    @State private var title = ""
    @State private var hazard = ""
    @State private var control = ""
    @State private var severity: NovaNonconformitySeverity = .medium
    @State private var score = NovaRiskScoreInput()
    @State private var legislation = ""
    @State private var responsible = ""
    @State private var openedOn = Calendar.current.startOfDay(for: Date())
    @State private var dueOn = Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()
    @State private var attachment: IsgWorkspaceAttachmentDraft?
    @State private var open: Step? = .attachment
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    @State private var workflowMutationIDs: [String: UUID] = [:]
    @Environment(\.novaCelebrate) private var celebrate

    private var canSave: Bool {
        workplaceID != nil && !title.trimmed.isEmpty && !hazard.trimmed.isEmpty &&
        !control.trimmed.isEmpty && dueOn >= openedOn && (score.isEmpty || score.isComplete)
    }
    private var completed: Int { Step.allCases.filter(isComplete).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NovaPopupHeading(text: "Elle Uygunsuzluk", symbol: "exclamationmark.triangle",
                    subtitle: "Normal uzman paneliyle aynı alanlar ve adımlı kayıt akışı")
                if loading {
                    NovaLoadingView(message: "İşyerleri hazırlanıyor…")
                } else {
                    IsgParityProgress(completed: completed, total: Step.allCases.count)
                    ForEach(Step.allCases, id: \.self) { step in accordion(step) }
                    if let error { NovaHelpHint(text: error) }
                    NovaButton(label: saving ? "Kaydediliyor…" : "Kaydı aç", symbol: "checkmark",
                        isEnabled: canSave && !saving) { save() }
                }
            }.padding(18).novaPopupContentSize(extra: 150)
                .novaAsyncContent(isLoading: loading)
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await prepare() }
    }

    @ViewBuilder private func accordion(_ step: Step) -> some View {
        NovaCompanyAccordion(title: stepTitle(step), symbol: stepSymbol(step),
            state: isComplete(step) ? .complete : .missing,
            identifier: "workspace.nonconformity.step.\(step.rawValue)",
            expanded: Binding(get: { open == step }, set: { open = $0 ? step : nil })) {
            VStack(alignment: .leading, spacing: 10) {
                switch step {
                case .attachment:
                    IsgWorkspaceInlineAttachmentField(
                        title: "Fotoğraf veya kanıt ekle (isteğe bağlı)", attachment: $attachment)
                case .workplace:
                    if workplaces.isEmpty {
                        NovaEmptyState(title: "İşyeri bulunamadı",
                            message: "Uygunsuzluk eklemek için önce firmaya bir işyeri ekleyin.")
                    } else {
                        Picker("İşyeri", selection: $workplaceID) {
                            ForEach(workplaces) { Text($0.name).tag(Optional($0.id)) }
                        }.pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
                        HStack(spacing: 10) {
                            compactDate("Kayıt tarihi", selection: $openedOn)
                            compactDate("Termin", selection: $dueOn)
                        }
                    }
                case .hazard:
                    field("Tehlike başlığı", text: $title, symbol: "text.cursor")
                    area("Açıklama", text: $hazard)
                    area("Önlem", text: $control)
                    VStack(alignment: .leading, spacing: 5) {
                        NovaText(text: "Önem derecesi", style: .label)
                        Picker("Önem derecesi", selection: $severity) {
                            ForEach(NovaNonconformitySeverity.allCases) { value in
                                Text(NovaNonconformityWords.severity(value)).tag(value)
                            }
                        }.labelsHidden().pickerStyle(.segmented)
                    }
                case .scoring:
                    NovaRiskScoreEditor(score: $score)
                case .legislation:
                    area("İlgili madde, yönetmelik veya standart (isteğe bağlı)", text: $legislation)
                case .responsible:
                    field("Firmadaki sorumlu kişi (isteğe bağlı)", text: $responsible,
                          symbol: "person.crop.circle")
                    NovaHelpHint(text: "Bu kişi uygulama kullanıcısı olmak zorunda değildir; kaydın takip bilgisinde görünür.")
                }
                if isComplete(step), let next = nextIncomplete(after: step) {
                    NovaButton(label: "Sıradaki: \(stepTitle(next))", symbol: "chevron.down", variant: .surface) {
                        withAnimation { open = next }
                    }
                }
            }
        }
    }

    private func isComplete(_ step: Step) -> Bool {
        switch step {
        case .attachment: return attachment != nil
        case .workplace: return workplaceID != nil && dueOn >= openedOn
        case .hazard: return !title.trimmed.isEmpty && !hazard.trimmed.isEmpty && !control.trimmed.isEmpty
        case .scoring: return score.isComplete
        case .legislation: return !legislation.trimmed.isEmpty
        case .responsible: return !responsible.trimmed.isEmpty
        }
    }

    private func nextIncomplete(after step: Step) -> Step? {
        guard let index = Step.allCases.firstIndex(of: step) else { return nil }
        return (Array(Step.allCases.dropFirst(index + 1)) + Array(Step.allCases.prefix(index)))
            .first { !isComplete($0) }
    }

    private func stepTitle(_ step: Step) -> String {
        switch step {
        case .attachment: return "Fotoğraf ve kanıt"
        case .workplace: return "İşyeri ve tarihler"
        case .hazard: return "Tehlike ve önlem"
        case .scoring: return "Risk skoru · isteğe bağlı"
        case .legislation: return "Mevzuat · isteğe bağlı"
        case .responsible: return "Sorumlu · isteğe bağlı"
        }
    }

    private func stepSymbol(_ step: Step) -> String {
        switch step {
        case .attachment: return "camera"
        case .workplace: return "building.2"
        case .hazard: return "exclamationmark.triangle"
        case .scoring: return "number.square"
        case .legislation: return "books.vertical"
        case .responsible: return "person.crop.circle"
        }
    }

    @MainActor private func prepare() async {
        loading = true; error = nil
        do {
            workplaces = try await store.directory(.workplace)
            workplaceID = workplaces.first?.id
        } catch {
            self.error = "İşyeri listesi alınamadı. Bağlantınızı kontrol edip yeniden deneyin."
        }
        loading = false
    }

    private func save() {
        guard canSave, let workplaceID else { return }
        let create: [String: IsgWorkspaceRPCValue] = [
            "action": .string("create"), "workplace_id": .id(workplaceID),
            "source_kind": .string("manual"), "source_ref": .null,
            "title": .string(title.trimmed), "severity": .string(severity.rawValue),
            "opened_on": .string(Self.day(openedOn)), "due_on": .string(Self.day(dueOn))
        ]
        saving = true; error = nil
        Task { @MainActor in
            do {
                let uploaded = try await uploadAttachmentIfNeeded()
                let created = try await store.mutateDomain(
                    mutationID: workflowID("nonconformity.create", create),
                    domain: .nonconformity, payload: create)
                guard let recordID = created.recordID else { throw IsgWorkspaceAPIFailure.invalidResponse }
                let detail = detailsText
                if !detail.isEmpty {
                    let action: [String: IsgWorkspaceRPCValue] = [
                        "action": .string("add_action"), "id": .id(recordID),
                        "expected_version": .number(Int(created.version ?? 0)),
                        "description": .string(String(detail.prefix(1000))),
                        "assignee_contact": responsible.trimmed.isEmpty ? .null : .string(responsible.trimmed),
                        "due_on": .string(Self.day(dueOn))
                    ]
                    _ = try await store.mutateDomain(
                        mutationID: workflowID("nonconformity.detail", action),
                        domain: .nonconformity, payload: action)
                }
                if let uploaded {
                    _ = try await store.attachFile(
                        mutationID: workflowID("nonconformity.file.attach", [
                            "entry_id": .id(uploaded.entryID), "parent_id": .id(recordID)
                        ]), entryID: uploaded.entryID, parentKind: "nonconformity",
                        parentID: recordID, fieldName: "attachment")
                }
                celebrate(NovaSuccessMessage.findingCreated)
                onDone()
            } catch {
                self.error = "Uygunsuzluk kaydedilemedi. İşyeri, tarih ve zorunlu alanları kontrol edip yeniden deneyin."
            }
            saving = false
        }
    }

    private var detailsText: String {
        var rows = ["Tehlike: \(hazard.trimmed)", "Önlem: \(control.trimmed)"]
        if !legislation.trimmed.isEmpty { rows.append("Mevzuat: \(legislation.trimmed)") }
        if let value = score.score, let method = score.method {
            rows.append("Risk skoru (\(method.rawValue)): \(value.formatted())")
        }
        return rows.joined(separator: "\n")
    }

    private func uploadAttachmentIfNeeded() async throws -> IsgWorkspaceFileUploadResult? {
        guard let attachment else { return nil }
        return try await store.uploadFile(
            mutationID: workflowID("nonconformity.file.upload", [
                "filename": .string(attachment.filename),
                "digest": .string(IsgWorkspaceMutationAttempt.digest(attachment.data))
            ]), title: attachment.title, filename: attachment.filename,
            category: "other", data: attachment.data)
    }

    private func workflowID(_ namespace: String,
                            _ payload: [String: IsgWorkspaceRPCValue]) -> UUID {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let signature = namespace + ":" + IsgWorkspaceMutationAttempt.digest(
            (try? encoder.encode(IsgWorkspaceRPCValue.object(payload))) ?? Data())
        if let id = workflowMutationIDs[signature] { return id }
        let id = UUID(); workflowMutationIDs[signature] = id; return id
    }

    private func field(_ label: String, text: Binding<String>, symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).frame(width: 20)
            TextField(label, text: text, axis: .vertical).lineLimit(1...3)
                .font(NovaFont.font(.body))
        }.padding(12).novaControlBackground(cornerRadius: 14)
    }

    private func area(_ label: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            NovaText(text: label, style: .metaQuiet)
            TextEditor(text: text).font(NovaFont.font(.body)).frame(minHeight: 76)
                .scrollContentBackground(.hidden)
                .background(NovaColorToken.surfaceMuted.color(in: .light),
                            in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func compactDate(_ label: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            NovaText(text: label, style: .micro)
            DatePicker(label, selection: selection, displayedComponents: .date)
                .labelsHidden().datePickerStyle(.compact)
        }.padding(10).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .novaControlBackground(cornerRadius: 14)
    }

    private static func day(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().dateSeparator(.dash))
    }
}

struct IsgWorkspaceRiskCreateEditor: View {
    private enum Step: String, CaseIterable { case details, file, review }
    @ObservedObject var store: IsgWorkspaceStore
    let onDone: () -> Void
    @State private var workplaces: [IsgWorkspaceDirectoryEntry] = []
    @State private var assessments: [IsgWorkspaceDomainRecord] = []
    @State private var workplaceID: UUID?
    @State private var kind = "full"
    @State private var scope = ""
    @State private var reason = ""
    @State private var date = Calendar.current.startOfDay(for: Date())
    @State private var attachment: IsgWorkspaceAttachmentDraft?
    @State private var currentStep: Step = .details
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    @State private var validationError: String?
    @State private var confirmingExit = false
    @State private var didSave = false
    @State private var mutationAttempt = IsgWorkspaceMutationAttempt()
    @State private var workflowMutationIDs: [String: UUID] = [:]
    @Environment(\.novaCelebrate) private var celebrate

    private var assessment: IsgWorkspaceDomainRecord? {
        guard let workplaceID else { return nil }
        return assessments.first { fact("workplace_id", in: $0)?.lowercased() == workplaceID.uuidString.lowercased() }
    }
    private var needsReason: Bool { assessment != nil && ["partial", "metadata"].contains(kind) }
    private var needsScope: Bool { kind == "partial" }
    private var completed: Int { Step.allCases.filter(isComplete).count }
    private var stepNumber: Int { (Step.allCases.firstIndex(of: currentStep) ?? 0) + 1 }

    var body: some View {
        Group {
            if didSave {
                NovaTaskSuccessView(title: "Risk değerlendirmesi taslağı oluşturuldu",
                    message: "Değerlendirme sürümü kaydedildi. Ayrıntı ekranından kontrol edip kesinleştirebilirsiniz.",
                    doneTitle: "Risk değerlendirmelerine dön", onDone: onDone)
            } else {
                NovaPageSurface {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            NovaTaskHeader(title: assessment == nil ? "Risk değerlendirmesi ekle" : "Yeni sürüm",
                                step: stepNumber, total: Step.allCases.count, stepTitle: stepTitle(currentStep)) {
                                    confirmingExit = true
                                }
                            if loading { NovaLoadingView(message: "İşyeri ve sürüm bilgileri hazırlanıyor…") }
                            else {
                                if let validationError { NovaTaskErrorSummary(message: validationError) }
                                stepContent(currentStep)
                                if let error { NovaTaskErrorSummary(message: error) }
                            }
                        }.padding(.horizontal, 18).padding(.top, 8).padding(.bottom, 28)
                            .novaAsyncContent(isLoading: loading)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .safeAreaInset(edge: .bottom) {
                        if !loading {
                            NovaTaskStickyActions(primaryTitle: currentStep == .review ? "Taslağı kaydet" : "Devam",
                                primarySymbol: currentStep == .review ? "checkmark" : "arrow.right",
                                isWorking: saving, canGoBack: currentStep != .details,
                                onBack: previousStep, onPrimary: advance)
                        }
                    }
                }
            }
        }
        .task { await prepare() }
        .onChange(of: workplaceID) { _ in configureKind() }
        .confirmationDialog("Risk değerlendirmesi akışından çıkılsın mı?", isPresented: $confirmingExit,
            titleVisibility: .visible) {
                Button("Çık", role: .destructive, action: onDone)
                Button("Devam et", role: .cancel) {}
            } message: { Text("Henüz kaydedilmemiş bilgiler silinir.") }
    }

    @ViewBuilder private func stepContent(_ step: Step) -> some View {
        switch step {
        case .details: detailsStep
        case .file:
            VStack(alignment: .leading, spacing: 12) {
                NovaText(text: "Risk değerlendirmesi dosyası", style: .sectionTitle)
                IsgWorkspaceInlineAttachmentField(
                    title: "PDF veya belge ekle (isteğe bağlı)", attachment: $attachment)
                NovaHelpHint(text: "Dosya eklemeden de taslak oluşturabilir, daha sonra kayıt ayrıntısından belge bağlayabilirsiniz.")
            }
        case .review: reviewStep
        }
    }

    private var detailsStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("İşyeri", selection: $workplaceID) {
                ForEach(workplaces) { Text($0.name).tag(Optional($0.id)) }
            }.pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
            if assessment == nil {
                NovaFormValueRow(label: "Sürüm türü", symbol: "square.stack.3d.up") {
                    NovaText(text: "Tam değerlendirme", style: .bodyStrong)
                }
                NovaHelpHint(text: "Bu işyerindeki ilk kayıt tam değerlendirme olarak açılır.")
            } else {
                Picker("Sürüm türü", selection: $kind) {
                    Text("Tam yenileme").tag("full")
                    Text("Kısmi revizyon").tag("partial")
                    Text("Bilgi düzeltmesi").tag("metadata")
                }.pickerStyle(.segmented)
            }
            compactDate(kind == "full" ? "Değerlendirme tarihi" : "Revizyon tarihi", selection: $date)
            if kind != "full", let base = assessment.flatMap({ fact("base_assessment_on", in: $0) }) {
                NovaFormValueRow(label: "İlk değerlendirme", symbol: "calendar") {
                    NovaText(text: base, style: .bodyStrong)
                }
            }
            if needsScope { field("Kapsam özeti", text: $scope, symbol: "square.dashed") }
            if needsReason { field("Değişiklik gerekçesi · en az 10 karakter", text: $reason, symbol: "text.quote") }
            NovaHelpHint(text: kind == "full"
                ? "Geçerlilik, taslak kesinleştirilirken işyeri tehlike sınıfına göre hesaplanır."
                : "İlk değerlendirme tarihi korunur; yalnız bu sürümün değişiklikleri kaydedilir.")
        }
    }

    private var reviewStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            NovaText(text: "Kaydetmeden önce kontrol edin", style: .sectionTitle)
            NovaCard(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    reviewRow("İşyeri", workplaces.first(where: { $0.id == workplaceID })?.name ?? "Belirtilmedi")
                    reviewRow("Sürüm", IsgWorkspaceDisplayText.value(kind))
                    reviewRow(kind == "full" ? "Değerlendirme" : "Revizyon", Self.day(date))
                    if needsScope { reviewRow("Kapsam", scope.trimmed) }
                    if needsReason { reviewRow("Gerekçe", reason.trimmed) }
                    reviewRow("Dosya", attachment?.filename ?? "Daha sonra eklenebilir")
                }
            }
        }
    }

    private func reviewRow(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .metaQuiet)
            NovaText(text: value, style: .bodyStrong)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func isComplete(_ step: Step) -> Bool {
        switch step {
        case .details:
            return workplaceID != nil && date <= Date() && (!needsScope || !scope.trimmed.isEmpty)
                && (!needsReason || reason.trimmed.count >= 10)
        case .file: return true
        case .review: return isComplete(.details)
        }
    }
    private func stepTitle(_ step: Step) -> String {
        switch step { case .details: return "Tarih ve kapsam"; case .file: return "Dosya"; case .review: return "Kontrol ve kaydet" }
    }
    private func stepSymbol(_ step: Step) -> String {
        switch step { case .details: return "calendar"; case .file: return "doc.badge.plus"; case .review: return "checkmark.circle" }
    }

    private func advance() {
        validationError = nil
        guard isComplete(currentStep) else {
            validationError = currentStep == .details
                ? "İşyeri, tarih ve gerekiyorsa kapsam ile gerekçe bilgilerini kontrol edin."
                : "Bu adım tamamlanmadan devam edilemiyor."
            return
        }
        guard currentStep != .review else { save(); return }
        guard let index = Step.allCases.firstIndex(of: currentStep) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { currentStep = Step.allCases[index + 1] }
    }

    private func previousStep() {
        validationError = nil
        guard let index = Step.allCases.firstIndex(of: currentStep), index > 0 else { return }
        withAnimation(.easeInOut(duration: 0.2)) { currentStep = Step.allCases[index - 1] }
    }
    @MainActor private func prepare() async {
        loading = true; error = nil
        do {
            async let a = store.directory(.workplace)
            async let b = store.domain(.risk)
            let value = try await (a, b)
            workplaces = value.0; assessments = value.1.rows; workplaceID = workplaces.first?.id; configureKind()
        } catch { self.error = "İşyeri veya risk sürümleri yüklenemedi. Bağlantınızı kontrol edip yeniden deneyin." }
        loading = false
    }
    private func configureKind() { kind = "full"; reason = ""; scope = "" }
    private func save() {
        guard completed == Step.allCases.count, let workplaceID else { return }
        let current = assessment.flatMap { fact("current_version", in: $0) }.flatMap(Int.init) ?? 0
        let baseDate = assessment.flatMap { fact("base_assessment_on", in: $0) } ?? Self.day(date)
        let payload: [String: IsgWorkspaceRPCValue] = [
            "action": .string("draft"), "workplace_id": .id(workplaceID), "expected_current": .number(current),
            "kind": .string(kind), "assessment_on": .string(kind == "full" ? Self.day(date) : baseDate),
            "revision_on": kind == "full" ? .null : .string(Self.day(date)),
            "scope": .object(needsScope ? ["summary": .string(scope.trimmed)] : [:]),
            "reason": needsReason ? .string(reason.trimmed) : .null
        ]
        var attempt = mutationAttempt; let mutationID = attempt.id(namespace: "risk.draft", payload: payload); mutationAttempt = attempt
        saving = true; error = nil
        Task { @MainActor in
            do {
                let uploaded = try await uploadAttachmentIfNeeded()
                let created = try await store.mutateDomain(mutationID: mutationID, domain: .risk, payload: payload)
                if let uploaded, let id = created.recordID {
                    _ = try await store.attachFile(
                        mutationID: workflowID("risk.file.attach", uploaded.entryID, id),
                        entryID: uploaded.entryID, parentKind: "risk_assessment",
                        parentID: id, fieldName: "assessment")
                }
                celebrate(NovaSuccessMessage.recordSaved("Risk değerlendirmesi"))
                didSave = true
            } catch { self.error = "Risk sürümü oluşturulamadı. Tarih, kapsam ve gerekçe bilgilerini kontrol edip yeniden deneyin." }
            saving = false
        }
    }
    private func uploadAttachmentIfNeeded() async throws -> IsgWorkspaceFileUploadResult? {
        guard let attachment else { return nil }
        return try await store.uploadFile(
            mutationID: workflowID("risk.file.upload", attachment.filename,
                                   IsgWorkspaceMutationAttempt.digest(attachment.data)),
            title: attachment.title, filename: attachment.filename,
            category: "risk_assessment", data: attachment.data)
    }
    private func workflowID(_ namespace: String, _ parts: CustomStringConvertible...) -> UUID {
        let key = namespace + ":" + parts.map(\.description).joined(separator: ":")
        if let id = workflowMutationIDs[key] { return id }
        let id = UUID(); workflowMutationIDs[key] = id; return id
    }
    private func fact(_ key: String, in row: IsgWorkspaceDomainRecord) -> String? { row.facts.first { $0.0 == key }?.1 }
    private func field(_ label: String, text: Binding<String>, symbol: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol).frame(width: 20, height: 28)
            TextField(label, text: text, axis: .vertical).lineLimit(2...6).font(NovaFont.font(.body))
        }.padding(12).novaControlBackground(cornerRadius: 14)
    }
    private func compactDate(_ label: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            NovaText(text: label, style: .metaQuiet)
            DatePicker(label, selection: selection, in: ...Date(), displayedComponents: .date).labelsHidden().datePickerStyle(.compact)
        }.padding(12).frame(maxWidth: .infinity, minHeight: 66, alignment: .leading).novaControlBackground(cornerRadius: 14)
    }
    private static func day(_ date: Date) -> String { date.formatted(.iso8601.year().month().day().dateSeparator(.dash)) }
}

struct IsgWorkspaceEquipmentCreateEditor: View {
    private enum Step: String, CaseIterable { case type, identity, period, attachment }
    @ObservedObject var store: IsgWorkspaceStore
    let onDone: () -> Void
    @State private var workplaces: [IsgWorkspaceDirectoryEntry] = []
    @State private var catalog = IsgWorkspaceEquipmentCatalog(suggestions: [], rules: [])
    @State private var workplaceID: UUID?
    @State private var typeCode = ""
    @State private var customType = ""
    @State private var serial = ""
    @State private var location = ""
    @State private var acquiredOn = Date()
    @State private var attachment: IsgWorkspaceAttachmentDraft?
    @State private var open: Step? = .type
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?
    @State private var mutationAttempt = IsgWorkspaceMutationAttempt()
    @State private var workflowMutationIDs: [String: UUID] = [:]
    @Environment(\.novaCelebrate) private var celebrate

    private var typeLabel: String {
        typeCode == "other_equipment" ? customType.trimmed : IsgWorkspaceDisplayText.value(typeCode)
    }
    private var completed: Int { Step.allCases.filter(isComplete).count }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                NovaPopupHeading(text: "Ekipman Ekle", symbol: "shippingbox",
                    subtitle: "Ekipman envantere eklenir; kontrol raporu ekipman ayrıntısından kaydedilir")
                if loading { NovaLoadingView(message: "Ekipman türleri ve süreler hazırlanıyor…") }
                else {
                    IsgParityProgress(completed: completed, total: Step.allCases.count)
                    ForEach(Step.allCases, id: \.self) { step in accordion(step) }
                    if let error { NovaHelpHint(text: error) }
                    NovaButton(label: saving ? "Kaydediliyor…" : "Envantere ekle", symbol: "checkmark",
                               isEnabled: !saving && completed == Step.allCases.count) { save() }
                }
            }.padding(18).novaPopupContentSize(extra: 110)
                .novaAsyncContent(isLoading: loading)
        }.task { await prepare() }
    }

    @ViewBuilder private func accordion(_ step: Step) -> some View {
        NovaCompanyAccordion(title: stepTitle(step), symbol: stepSymbol(step),
            state: isComplete(step) ? .complete : .missing,
            identifier: "workspace.equipment.step.\(step.rawValue)",
            expanded: Binding(get: { open == step }, set: { open = $0 ? step : nil })) {
            VStack(alignment: .leading, spacing: 10) {
                switch step {
                case .type:
                    Picker("Ekipman türü", selection: $typeCode) {
                        ForEach(catalog.suggestions) { suggestion in
                            Text(IsgWorkspaceDisplayText.value(suggestion.code)).tag(suggestion.code)
                        }
                    }.pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
                    if typeCode == "other_equipment" { field("Ekipman türü", text: $customType, symbol: "shippingbox") }
                case .identity:
                    Picker("İşyeri", selection: $workplaceID) {
                        ForEach(workplaces) { Text($0.name).tag(Optional($0.id)) }
                    }.pickerStyle(.menu).padding(12).novaControlBackground(cornerRadius: 14)
                    field("Seri / kod (isteğe bağlı)", text: $serial, symbol: "number")
                    field("Konum (isteğe bağlı)", text: $location, symbol: "mappin.and.ellipse")
                case .period:
                    compactDate("Edinme tarihi", selection: $acquiredOn)
                    if let months = catalog.period(for: typeCode) {
                        NovaFormValueRow(label: "Başlangıç kontrol süresi", symbol: "hourglass") {
                            NovaText(text: "\(months) ay", style: .bodyStrong)
                        }
                        NovaHelpHint(text: catalog.suggestions.first(where: { $0.code == typeCode })?.defaultBasisNote
                            ?? "Süre firma kuralından gelir; uzman ekipman ayrıntısından değiştirebilir.")
                    } else {
                        NovaHelpHint(text: "Bu tür için henüz süre tanımlı değil. Ekipmanı ekledikten sonra kontrol süresini belirleyin.")
                    }
                case .attachment:
                    IsgWorkspaceInlineAttachmentField(
                        title: "Ekipman belgesi ekle (isteğe bağlı)",
                        attachment: $attachment)
                }
            }
        }
    }
    private func isComplete(_ step: Step) -> Bool {
        switch step {
        case .type: return !typeCode.isEmpty && !typeLabel.isEmpty
        case .identity: return workplaceID != nil
        case .period: return acquiredOn <= Date()
        case .attachment: return true
        }
    }
    private func stepTitle(_ step: Step) -> String {
        switch step { case .type: return "Ekipman türü"; case .identity: return "İşyeri ve kimlik"; case .period: return "Tarih ve kontrol süresi"; case .attachment: return "Dosya ve kanıt" }
    }
    private func stepSymbol(_ step: Step) -> String {
        switch step { case .type: return "shippingbox"; case .identity: return "number"; case .period: return "calendar.badge.clock"; case .attachment: return "doc.badge.plus" }
    }
    @MainActor private func prepare() async {
        loading = true; error = nil
        do {
            async let a = store.directory(.workplace)
            async let b = store.equipmentCatalog()
            let value = try await (a, b)
            workplaces = value.0; catalog = value.1
            workplaceID = workplaces.first?.id; typeCode = catalog.suggestions.first?.code ?? "other_equipment"
        } catch { self.error = "İşyeri veya ekipman kataloğu yüklenemedi. Bağlantınızı kontrol edip yeniden deneyin." }
        loading = false
    }
    private func save() {
        guard completed == Step.allCases.count, let workplaceID else { return }
        let payload: [String: IsgWorkspaceRPCValue] = [
            "action": .string("register"), "workplace_id": .id(workplaceID), "equipment_type": .string(typeCode),
            "equipment_type_label": .string(typeLabel),
            "serial_tag": .string(serial.trimmed.isEmpty ? String(UUID().uuidString.prefix(8)).lowercased() : serial.trimmed),
            "acquired_on": .string(Self.day(acquiredOn)), "location_note": .string(location.trimmed)
        ]
        var attempt = mutationAttempt; let mutationID = attempt.id(namespace: "equipment.register", payload: payload); mutationAttempt = attempt
        saving = true; error = nil
        Task { @MainActor in
            do {
                let uploaded = try await uploadAttachmentIfNeeded()
                let created = try await store.mutateDomain(mutationID: mutationID, domain: .equipment, payload: payload)
                if let uploaded, let id = created.recordID {
                    _ = try await store.attachFile(
                        mutationID: workflowID("equipment.file.attach", uploaded.entryID, id),
                        entryID: uploaded.entryID, parentKind: "equipment",
                        parentID: id, fieldName: "attachment")
                }
                celebrate(NovaSuccessMessage.recordSaved("Ekipman")); onDone()
            } catch { self.error = "Ekipman eklenemedi. Tür, işyeri ve kimlik bilgilerini kontrol edip yeniden deneyin." }
            saving = false
        }
    }
    private func uploadAttachmentIfNeeded() async throws -> IsgWorkspaceFileUploadResult? {
        guard let attachment else { return nil }
        return try await store.uploadFile(
            mutationID: workflowID("equipment.file.upload", attachment.filename,
                                   IsgWorkspaceMutationAttempt.digest(attachment.data)),
            title: attachment.title, filename: attachment.filename,
            category: "inspection_report", data: attachment.data)
    }
    private func workflowID(_ namespace: String, _ parts: CustomStringConvertible...) -> UUID {
        let key = namespace + ":" + parts.map(\.description).joined(separator: ":")
        if let id = workflowMutationIDs[key] { return id }
        let id = UUID(); workflowMutationIDs[key] = id; return id
    }
    private func field(_ label: String, text: Binding<String>, symbol: String) -> some View {
        HStack(spacing: 9) {
            Image(systemName: symbol).frame(width: 20)
            TextField(label, text: text).font(NovaFont.font(.body))
        }.padding(12).novaControlBackground(cornerRadius: 14)
    }
    private func compactDate(_ label: String, selection: Binding<Date>) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            NovaText(text: label, style: .metaQuiet)
            DatePicker(label, selection: selection, in: ...Date(), displayedComponents: .date).labelsHidden().datePickerStyle(.compact)
        }.padding(12).frame(maxWidth: .infinity, minHeight: 66, alignment: .leading).novaControlBackground(cornerRadius: 14)
    }
    private static func day(_ date: Date) -> String { date.formatted(.iso8601.year().month().day().dateSeparator(.dash)) }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
