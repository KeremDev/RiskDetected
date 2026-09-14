import SwiftUI

struct NovaEducationScopeEditor: View {
    @Binding var scope: NovaEducationScope
    let context: NovaEducationContext
    let trainers: [NovaEducationTrainer]
    let people: [NovaEmployeeRow]
    let excluded: Set<UUID>
    let saveCurriculum: () -> Void
    let remove: () -> Void
    @State private var suppressInitialDayChange = false
    @State private var days: [NovaEducationDay] = []
    @State private var search = ""
    @State private var showPeople = false
    @State private var cycleChange: String?
    private var basic: Bool { ["initial","periodic_repeat"].contains(scope.cycle) }
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 14) {
                TextField("Görev / içerik grubu", text: $scope.group_name)
                Picker("Eğitim türü", selection: $scope.cycle) {
                    ForEach(NovaEducationScope.cycles, id: \.0) { Text($0.1).tag($0.0) }
                }.onChange(of: scope.cycle) { [old = scope.cycle] _ in cycleChange = old }
                Text("Profil: \(context.package.preset(cycle: scope.cycle, hazard: scope.hazard_class ?? "")?.label ?? scope.cycleName)").font(NovaFont.font(.meta))
                peopleForm
                topicsForm
                timesForm
                documentForm
                ForEach(scope.issues ?? [], id: \.self) { Text(NovaEducationService.issue($0)).font(NovaFont.font(.meta)).foregroundStyle(.orange) }
                Button("Kapsamı kaldır", role: .destructive, action: remove).font(NovaFont.font(.meta))
            }.padding(.top, 12)
        } label: {
            VStack(alignment: .leading) {
                Text(scope.company_name ?? "Firma").font(NovaFont.font(.cardTitle))
                Text("\(scope.workplace_name ?? "") · \(scope.group_name) · \(scope.net) dk").font(NovaFont.font(.meta))
            }
        }.padding(12).overlay(RoundedRectangle(cornerRadius: 12).stroke(.gray.opacity(0.75)))
        .onAppear { if days.isEmpty {
            let restored = scope.draft_days ?? NovaEducationClock.days(from: scope.lessons)
            if !restored.isEmpty { suppressInitialDayChange = true; days = restored }
        } }
        .onChange(of: days) { value in
            if suppressInitialDayChange { suppressInitialDayChange = false } else { scope.draft_days = value }
        }
        .confirmationDialog("Eğitim türü değişti", isPresented: Binding(get: { cycleChange != nil }, set: { if !$0 { cycleChange = nil } })) {
            Button("Yeni türün varsayılan konularını getir") { defaults(); cycleChange = nil }
            Button("Mevcut konuları koru") { cycleChange = nil }
            Button("Vazgeç", role: .cancel) { if let old = cycleChange { scope.cycle = old }; cycleChange = nil }
        } message: { Text("Mevcut dakikaları değiştirmek isteğe bağlıdır; saatleri değişiklikten sonra yeniden dağıtın.") }
    }
    private var peopleForm: some View {
DisclosureGroup("Personeller (\(scope.participants.count))") {
                    TextField("Personel ara", text: $search)
                    ForEach(people.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) }) { person in
                        Toggle(person.name, isOn: Binding(get: { scope.participants.contains { $0.id == person.id } }, set: { on in
                            if on { scope.participants.append(.init(id: person.id, name: person.name)) }
                            else { scope.participants.removeAll { $0.id == person.id } }
                        })).disabled(excluded.contains(person.id))
                    }
                    ForEach($scope.participants) { $person in
                        VStack(alignment: .leading) {
                            Text(person.name ?? "Personel").font(NovaFont.font(.meta))
                            TextField("Belgeye özel unvan", text: $person.job_title)
                        }
                    }
                    Text("Bu unvan personelin güncel görev kaydını değiştirmez.").font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
                }
    }
    private var topicsForm: some View {
DisclosureGroup("Eğitim konuları ve dakikalar") {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(["G1","G2","G3","G4"], id: \.self) { group in
                            DisclosureGroup {
                                ForEach($scope.topics) { binding in
                                    if binding.wrappedValue.group == group { topicRow(binding) }
                                }
                            } label: {
                                Text(groupSummary(group))
                                    .font(NovaFont.font(.bodyStrong))
                            }.padding(10).overlay(RoundedRectangle(cornerRadius: 10).stroke(.gray.opacity(0.7)))
                        }
                        Button("İşyerine özgü konu ekle", systemImage: "plus") {
                            scope.topics.append(.init(code: "G4-" + UUID().uuidString, group: "G4", title: "", instruction_minutes: 0))
                        }
                        TextField("İşyeri, görev ve risk dayanağı açıklaması", text: $scope.context_note, axis: .vertical).lineLimit(3...8)
                        Text(basic && scope.cycle == "initial" ? "Dakikalar Bakanlık rehberindeki örnek dağılımdan gelir; düzenlenebilir." : "Tekrar eğitimi dağılımı düzenlenebilir ürün önerisidir.").font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
                        HStack {
                            Button("Varsayılanlara dön") { defaults() }
                            Spacer()
                            Button("Firma varsayılanı olarak kaydet", action: saveCurriculum)
                        }.font(NovaFont.font(.meta))
                    }
                }
    }
    private var timesForm: some View {
DisclosureGroup("Gerçekleşen günler ve saatler") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Europe/Istanbul · \(scope.net) dk öğretim + \(scope.breakTotal) dk ara").font(NovaFont.font(.meta))
                        ForEach($days) { $day in
                            VStack {
                                DatePicker("Gün / başlangıç", selection: $day.starts, in: ...Date()).environment(\.timeZone, NovaEducationClock.calendar.timeZone)
                                Stepper("\(day.lessonCount) ders", value: $day.lessonCount, in: 1...24)
                                HStack {
                                    Text("Ek ara (dk)"); TextField("0", value: $day.extraBreakMinutes, format: .number).keyboardType(.numberPad)
                                    Text("Ders sonrası"); TextField("4", value: $day.extraBreakAfter, format: .number).keyboardType(.numberPad)
                                }.font(NovaFont.font(.meta))
                                Button("Günü kaldır", role: .destructive) { days.removeAll { $0.id == day.id } }.font(NovaFont.font(.meta))
                            }.padding(.vertical, 6)
                        }
                        Button("Gerçekleşen gün ekle", systemImage: "calendar.badge.plus") {
                            days.append(.init(starts: NovaEducationClock.calendar.date(byAdding: .day, value: -1, to: Date())!, lessonCount: 1))
                        }
                        Button("Konuları derslere dağıt", systemImage: "clock.arrow.circlepath") {
                            if days.isEmpty { days = NovaEducationClock.initialDays(minutes: scope.net, basic: basic) }
                            scope.lessons = NovaEducationClock.distribute(topics: scope.topics, days: days, basic: basic)
                        }
                        Text("Saatler uzman tarafından girilen gerçekleşmiş programdır. Tarihleri kaydetmeden önce kontrol edin.").font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
                        ForEach($scope.lessons) { $lesson in
                            VStack(alignment: .leading) {
                                DatePicker("\(lesson.instruction_minutes) dk ders", selection: Binding(get: { NovaEducationClock.date(lesson.starts_at) ?? Date() }, set: { lesson.starts_at = NovaEducationClock.iso($0) }), in: ...Date()).environment(\.timeZone, NovaEducationClock.calendar.timeZone)
                                Stepper("Ardından \(lesson.break_minutes) dk ara", value: $lesson.break_minutes, in: 0...720, step: 5).font(NovaFont.font(.meta))
                            }.padding(.vertical, 4)
                        }
                    }
                }
    }
    private var documentForm: some View {
DisclosureGroup("İşyeri ve belge bilgileri") {
                    TextField("İşyeri tam unvanı (boşsa firma adı)", text: $scope.legal_name)
                    TextField("Eğitim yeri / online bağlantı açıklaması", text: $scope.location)
                    TextField("İşveren / vekili adı soyadı", text: $scope.employer_name)
                    Picker("İmzalayan sıfatı", selection: $scope.employer_capacity) {
                        Text("İşveren").tag("employer"); Text("İşveren vekili").tag("representative")
                    }
                    if scope.cycle == "custom" { Stepper("Tekrar aralığı: \(scope.renewal_months) ay (0: yok)", value: $scope.renewal_months, in: 0...120) }
                }
    }
    private func topicRow(_ binding: Binding<NovaEducationTopic>) -> some View {
        let topic = binding.wrappedValue
        return NovaEducationTopicEditor(topic: binding, trainers: trainers,
            removable: topic.group == "G4" || !basic || topic.parent_code != nil,
            remove: { scope.topics.removeAll { $0.code == topic.code } }, split: { split(topic) })
    }
    private func defaults() {
        let curriculum = context.curricula.first { $0.company_id == scope.company_id && $0.workplace_id == scope.workplace_id && $0.education.cycle == scope.cycle && $0.education.group_name == scope.group_name && $0.education.hazard_class == scope.hazard_class }
        scope.topics = curriculum?.education.topics ?? context.package.topics(cycle: scope.cycle, hazard: scope.hazard_class ?? "low")
        scope.context_note = curriculum?.education.context_note ?? ""
        // Trainer IDs belong to the old event, never implicitly assign its trainer in a new event.
        for i in scope.topics.indices { scope.topics[i].trainer_ids = scope.topics[i].trainer_ids.filter { id in trainers.contains { $0.id == id } } }
    }
    private func split(_ topic: NovaEducationTopic) {
        guard let index = scope.topics.firstIndex(where: { $0.code == topic.code }) else { return }
        let parent = topic.parent_code ?? topic.code
        var first = topic; first.code = parent + "-" + UUID().uuidString; first.parent_code = parent
        var second = first; second.code = parent + "-" + UUID().uuidString; second.title = "Alt konu"; second.instruction_minutes = 0
        scope.topics.replaceSubrange(index...index, with: [first, second])
    }
    private func groupSummary(_ group: String) -> String {
        let minutes = scope.topics.filter { $0.group == group }.reduce(0) { $0 + $1.instruction_minutes }
        return "\(group) · \(groupName(group)) · \(minutes) dk"
    }
    private func groupName(_ group: String) -> String { ["G1":"Genel", "G2":"Sağlık", "G3":"Teknik", "G4":"İşyerine Özgü Riskler"][group] ?? group }
}

private struct NovaEducationTopicEditor: View {
    @Binding var topic: NovaEducationTopic
    let trainers: [NovaEducationTrainer]
    let removable: Bool
    let remove: () -> Void
    let split: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if topic.group == "G4" || topic.parent_code != nil || topic.code.hasPrefix("CUSTOM") {
                TextField("Konu başlığı", text: $topic.title, axis: .vertical)
            } else { Text(topic.title).font(NovaFont.font(.body)) }
            if let parent = topic.parent_code { Text("Resmî konu: \(parent)").font(NovaFont.font(.micro)) }
            HStack {
                Button("−5") { topic.instruction_minutes = max(0,topic.instruction_minutes - 5) }.buttonStyle(.bordered)
                TextField("Dakika", value: $topic.instruction_minutes, format: .number).keyboardType(.numberPad).frame(width: 65)
                Text("dk").font(NovaFont.font(.meta))
                Button("+5") { topic.instruction_minutes = min(1440,topic.instruction_minutes + 5) }.buttonStyle(.bordered)
            }
            Picker("Yöntem", selection: $topic.method) { Text("Yüz yüze").tag("face_to_face"); Text("Online").tag("online") }.pickerStyle(.segmented)
            Menu {
                ForEach(trainers) { trainer in
                    Toggle(trainer.name.isEmpty ? "Adsız eğitici" : trainer.name, isOn: Binding(get: { topic.trainer_ids.contains(trainer.id) }, set: { selected in
                        topic.trainer_ids.removeAll { $0 == trainer.id }; if selected { topic.trainer_ids.append(trainer.id) }
                    }))
                }
            } label: { Label(topic.trainer_ids.isEmpty ? "Eğiticileri seç" : trainers.filter { topic.trainer_ids.contains($0.id) }.map(\.name).joined(separator: ", "), systemImage: "person") }.font(NovaFont.font(.meta))
            HStack {
                if topic.group != "G4" { Button("Alt konulara ayır", action: split) }
                Spacer(); if removable { Button("Kaldır", role: .destructive, action: remove) }
            }.font(NovaFont.font(.meta))
            Divider()
        }.padding(.vertical, 6)
    }
}
