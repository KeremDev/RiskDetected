import SwiftUI

/// The curriculum shared by every company/workplace in one training record:
/// which topics, how many minutes each (and whether today's session actually
/// covered a given one), plus trainer assignment per topic. Reached by its
/// own "Konuları ve Süre" link from the info step, opened in the same Nova
/// popup chrome as every other module. Cycle (İlk Temel Eğitim / Yenileme /
/// …) and the realized days/hours live one level up now — cycle in the info
/// step next to the title, schedule in its own accordion step — this popup
/// is topics only.
struct NovaEducationTopicsPopup: View {
    /// Bound to the record's shared template scope (or, once at least one
    /// real company/workplace has been added, to that first scope — the
    /// caller keeps every other scope mirrored to whichever this is).
    @Binding var scope: NovaEducationScope
    let context: NovaEducationContext
    let trainers: [NovaEducationTrainer]
    /// True once a real company/workplace exists: the hazard class is then
    /// a fact, not a guess, and is shown read-only instead of offered as a
    /// preview picker.
    let hazardLocked: Bool
    /// nil until a real scope exists — "firma varsayılanı" has no firma to
    /// save against before that.
    let saveCurriculum: (() -> Void)?
    let onClose: () -> Void
    private var basic: Bool { ["initial","periodic_repeat"].contains(scope.cycle) }
    private var hazardBinding: Binding<String> {
        Binding(get: { scope.hazard_class ?? "low" }, set: { scope.hazard_class = $0; defaults() })
    }
    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        NovaText(text: RDLocalization.string("localizable.nova.education.topics.title", table: .localizable, fallback: "Konuları ve Süre"), style: .screenTitle)
                        Spacer()
                        NovaButton(label: RDLocalization.string("localizable.nova.education.close", table: .localizable, fallback: "Kapat"), symbol: "xmark", variant: .surface, action: onClose)
                    }
                    if hazardLocked {
                        Text(String(format: RDLocalization.string("localizable.nova.education.topics.hazard.locked", table: .localizable, fallback: "Tehlike sınıfı: %@ (eklenen işyerinden)"),
                            hazardName(scope.hazard_class ?? ""))).font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
                    } else {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(RDLocalization.string("localizable.nova.education.topics.hazard.preview", table: .localizable, fallback: "Tehlike sınıfı (önizleme)")).font(NovaFont.font(.bodyStrong))
                            Picker("", selection: hazardBinding) {
                                Text(RDLocalization.string("localizable.nova.education.hazard.low", table: .localizable, fallback: "az tehlikeli")).tag("low")
                                Text(RDLocalization.string("localizable.nova.education.hazard.medium", table: .localizable, fallback: "tehlikeli")).tag("medium")
                                Text(RDLocalization.string("localizable.nova.education.hazard.high", table: .localizable, fallback: "çok tehlikeli")).tag("high")
                            }.pickerStyle(.segmented)
                            Text(RDLocalization.string("localizable.nova.education.topics.hazard.previewhint", table: .localizable,
                                fallback: "Firma eklendiğinde gerçek tehlike sınıfına göre otomatik güncellenir."),
                            ).font(NovaFont.font(.micro)).foregroundStyle(NovaFont.secondaryInk)
                        }
                    }
                    Text(String(format: RDLocalization.string("localizable.nova.education.topics.profile", table: .localizable, fallback: "Profil: %@"),
                        context.package.preset(cycle: scope.cycle, hazard: scope.hazard_class ?? "")?.label ?? scope.cycleName)).font(NovaFont.font(.meta))
                    topicsForm
                }.padding(20).novaPopupContentSize()
            }
        }
    }
    private var topicsForm: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(RDLocalization.string("localizable.nova.education.topics.header", table: .localizable, fallback: "Eğitim konuları ve dakikalar")).font(NovaFont.font(.bodyStrong))
            ForEach(["G1","G2","G3","G4"], id: \.self) { group in
                DisclosureGroup {
                    ForEach($scope.topics) { binding in
                        if binding.wrappedValue.group == group { topicRow(binding) }
                    }
                } label: {
                    Text(groupSummary(group)).font(NovaFont.font(.bodyStrong))
                }.padding(10).overlay(RoundedRectangle(cornerRadius: 10).stroke(.gray.opacity(0.7)))
            }
            Button(RDLocalization.string("localizable.nova.education.topics.addcustom", table: .localizable, fallback: "İşyerine özgü konu ekle"), systemImage: "plus") {
                scope.topics.append(.init(code: "G4-" + UUID().uuidString, group: "G4", title: "", instruction_minutes: 0))
            }
            TextField(RDLocalization.string("localizable.nova.education.topics.context", table: .localizable, fallback: "İşyeri, görev ve risk dayanağı açıklaması"), text: $scope.context_note, axis: .vertical).lineLimit(3...8)
            Text(basic && scope.cycle == "initial"
                ? RDLocalization.string("localizable.nova.education.topics.hint.official", table: .localizable, fallback: "Dakikalar Bakanlık rehberindeki örnek dağılımdan gelir; düzenlenebilir.")
                : RDLocalization.string("localizable.nova.education.topics.hint.custom", table: .localizable, fallback: "Tekrar eğitimi dağılımı düzenlenebilir ürün önerisidir."))
                .font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
            HStack {
                Button(RDLocalization.string("localizable.nova.education.topics.resetdefaults", table: .localizable, fallback: "Varsayılanlara dön")) { defaults() }
                Spacer()
                if let saveCurriculum {
                    Button(RDLocalization.string("localizable.nova.education.topics.savedefault", table: .localizable, fallback: "Firma varsayılanı olarak kaydet"), action: saveCurriculum)
                }
            }.font(NovaFont.font(.meta))
        }
    }
    private func topicRow(_ binding: Binding<NovaEducationTopic>) -> some View {
        let topic = binding.wrappedValue
        return NovaEducationTopicEditor(topic: binding, trainers: trainers,
            removable: topic.group == "G4" || !basic || topic.parent_code != nil,
            defaultMinutes: defaultMinutes(topic),
            remove: { scope.topics.removeAll { $0.code == topic.code } }, split: { split(topic) })
    }
    /// The package's own minutes for this topic, restored when the "dahil
    /// edildi" toggle is switched back on after being switched off.
    private func defaultMinutes(_ topic: NovaEducationTopic) -> Int {
        context.package.topics(cycle: scope.cycle, hazard: scope.hazard_class ?? "low").first { $0.code == topic.code }?.instruction_minutes ?? 30
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
    private func groupName(_ group: String) -> String {
        [
            "G1": RDLocalization.string("localizable.nova.education.topics.group.g1", table: .localizable, fallback: "Genel"),
            "G2": RDLocalization.string("localizable.nova.education.topics.group.g2", table: .localizable, fallback: "Sağlık"),
            "G3": RDLocalization.string("localizable.nova.education.topics.group.g3", table: .localizable, fallback: "Teknik"),
            "G4": RDLocalization.string("localizable.nova.education.topics.group.g4", table: .localizable, fallback: "İşyerine Özgü Riskler"),
        ][group] ?? group
    }
    private func hazardName(_ value: String) -> String {
        ["low": RDLocalization.string("localizable.nova.education.hazard.low", table: .localizable, fallback: "az tehlikeli"),
         "medium": RDLocalization.string("localizable.nova.education.hazard.medium", table: .localizable, fallback: "tehlikeli"),
         "high": RDLocalization.string("localizable.nova.education.hazard.high", table: .localizable, fallback: "çok tehlikeli")][value] ?? value
    }
}

private struct NovaEducationTopicEditor: View {
    @Binding var topic: NovaEducationTopic
    let trainers: [NovaEducationTrainer]
    let removable: Bool
    /// Restored when "Bu konu bu eğitimde işlendi" is switched back on after
    /// being switched off — switching it off just zeroes the minutes rather
    /// than deleting the topic, so a session that only covered part of the
    /// curriculum (e.g. only G1 today) can say so without losing the rest.
    let defaultMinutes: Int
    let remove: () -> Void
    let split: () -> Void
    private var includedBinding: Binding<Bool> {
        Binding(get: { topic.instruction_minutes > 0 }, set: { on in topic.instruction_minutes = on ? (defaultMinutes > 0 ? defaultMinutes : 30) : 0 })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if topic.group == "G4" || topic.parent_code != nil || topic.code.hasPrefix("CUSTOM") {
                TextField(RDLocalization.string("localizable.nova.education.topics.topictitle", table: .localizable, fallback: "Konu başlığı"), text: $topic.title, axis: .vertical)
            } else { Text(topic.title).font(NovaFont.font(.body)) }
            if let parent = topic.parent_code {
                Text(String(format: RDLocalization.string("localizable.nova.education.topics.officialtopic", table: .localizable, fallback: "Resmî konu: %@"), parent)).font(NovaFont.font(.micro))
            }
            Toggle(RDLocalization.string("localizable.nova.education.topics.included", table: .localizable, fallback: "Bu konu bu eğitimde işlendi"), isOn: includedBinding)
                .font(NovaFont.font(.meta))
            if topic.instruction_minutes > 0 {
                HStack {
                    Button("−5") { topic.instruction_minutes = max(0,topic.instruction_minutes - 5) }.buttonStyle(.bordered)
                    TextField(RDLocalization.string("localizable.nova.education.topics.minutes", table: .localizable, fallback: "Dakika"), value: $topic.instruction_minutes, format: .number).keyboardType(.numberPad).frame(width: 65)
                    Text("dk").font(NovaFont.font(.meta))
                    Button("+5") { topic.instruction_minutes = min(1440,topic.instruction_minutes + 5) }.buttonStyle(.bordered)
                }
                Picker(RDLocalization.string("localizable.nova.education.topics.method", table: .localizable, fallback: "Yöntem"), selection: $topic.method) {
                    Text(RDLocalization.string("localizable.nova.education.method.inperson", table: .localizable, fallback: "Yüz yüze")).tag("face_to_face")
                    Text(RDLocalization.string("localizable.nova.education.method.online", table: .localizable, fallback: "Online")).tag("online")
                }.pickerStyle(.segmented)
                Menu {
                    ForEach(trainers) { trainer in
                        Toggle(trainer.name.isEmpty ? RDLocalization.string("localizable.nova.education.topics.unnamedtrainer", table: .localizable, fallback: "Adsız eğitici") : trainer.name,
                            isOn: Binding(get: { topic.trainer_ids.contains(trainer.id) }, set: { selected in
                            topic.trainer_ids.removeAll { $0 == trainer.id }; if selected { topic.trainer_ids.append(trainer.id) }
                        }))
                    }
                } label: {
                    Label(topic.trainer_ids.isEmpty ? RDLocalization.string("localizable.nova.education.topics.picktrainers", table: .localizable, fallback: "Eğiticileri seç")
                        : trainers.filter { topic.trainer_ids.contains($0.id) }.map(\.name).joined(separator: ", "), systemImage: "person")
                }.font(NovaFont.font(.meta))
            }
            HStack {
                if topic.group != "G4" { Button(RDLocalization.string("localizable.nova.education.topics.split", table: .localizable, fallback: "Alt konulara ayır"), action: split) }
                Spacer(); if removable { Button(RDLocalization.string("localizable.nova.education.topics.removetopic", table: .localizable, fallback: "Kaldır"), role: .destructive, action: remove) }
            }.font(NovaFont.font(.meta))
            Divider()
        }.padding(.vertical, 6)
    }
}
