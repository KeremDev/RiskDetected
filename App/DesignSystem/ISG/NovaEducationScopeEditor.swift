import SwiftUI

/// The curriculum shared by every company/workplace in one training record:
/// which topics, how many minutes each (and whether today's session actually
/// covered a given one), plus trainer assignment per topic. Reached by its
/// own "Konuları ve Süre" link from the info step, opened in the same Nova
/// popup chrome as every other module. The guided flow shows a topic summary
/// first; this sheet is for optional edits to those topics and minutes.
struct NovaEducationTopicsPopup: View {
    /// Bound to the record's shared template scope (or, once at least one
    /// real company/workplace has been added, to that first scope — the
    /// caller keeps every other scope mirrored to whichever this is).
    @Binding var scope: NovaEducationScope
    let context: NovaEducationContext
    /// True once a real company/workplace exists: the hazard class is then
    /// a fact, not a guess, and is shown read-only instead of offered as a
    /// preview picker.
    let hazardLocked: Bool
    private var basic: Bool { ["initial","periodic_repeat"].contains(scope.cycle) }
    private var hazardBinding: Binding<String> {
        Binding(get: { scope.hazard_class ?? "low" }, set: { scope.hazard_class = $0; defaults() })
    }
    var body: some View {
        NovaPopup {
            ScrollView {
                // NovaPopup already draws its own close X (top trailing,
                // with space reserved above content for it) — a second
                // "Kapat" button here just duplicated it.
                VStack(alignment: .leading, spacing: 16) {
                    NovaText(text: RDLocalization.string("localizable.nova.education.topics.title", table: .localizable, fallback: "Konuları ve Süre"), style: .screenTitle)
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
            NovaWhyDisclosure {
                Text(basic && scope.cycle == "initial"
                    ? RDLocalization.string("localizable.nova.education.topics.hint.official", table: .localizable, fallback: "Dakikalar Bakanlık rehberindeki örnek dağılımdan gelir; düzenlenebilir.")
                    : RDLocalization.string("localizable.nova.education.topics.hint.custom", table: .localizable, fallback: "Tekrar eğitimi dağılımı düzenlenebilir ürün önerisidir."))
                    .font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
            }
            Button(RDLocalization.string("localizable.nova.education.topics.resetdefaults", table: .localizable, fallback: "Varsayılanlara dön")) { defaults() }
                .font(NovaFont.font(.meta))
        }
    }
    private func topicRow(_ binding: Binding<NovaEducationTopic>) -> some View {
        let topic = binding.wrappedValue
        return NovaEducationTopicEditor(topic: binding,
            removable: topic.group == "G4" || !basic || topic.parent_code != nil,
            defaultMinutes: defaultMinutes(topic),
            remove: { scope.topics.removeAll { $0.code == topic.code } })
    }
    /// The package's own minutes for this topic, restored when the "dahil
    /// edildi" toggle is switched back on after being switched off.
    private func defaultMinutes(_ topic: NovaEducationTopic) -> Int {
        context.package.topics(cycle: scope.cycle, hazard: scope.hazard_class ?? "low").first { $0.code == topic.code }?.instruction_minutes ?? 30
    }
    private func defaults() {
        let method = scope.topics.first?.method ?? "face_to_face"
        let trainerIDs = scope.topics.first?.trainer_ids ?? []
        let curriculum = context.curricula.first { $0.company_id == scope.company_id && $0.workplace_id == scope.workplace_id && $0.education.cycle == scope.cycle && $0.education.group_name == scope.group_name && $0.education.hazard_class == scope.hazard_class }
        scope.topics = curriculum?.education.topics ?? context.package.topics(cycle: scope.cycle, hazard: scope.hazard_class ?? "low")
        for i in scope.topics.indices {
            let inPersonRequired = scope.topics[i].group == "G4" && (scope.hazard_class != "low" || scope.cycle == "onboarding")
            scope.topics[i].method = inPersonRequired ? "face_to_face" : method
            scope.topics[i].trainer_ids = trainerIDs
        }
        scope.context_note = curriculum?.education.context_note ?? ""
    }
    private func groupSummary(_ group: String) -> String {
        let minutes = scope.topics.filter { $0.group == group }.reduce(0) { $0 + $1.instruction_minutes }
        return RDLocalization.format("localizable.nova.education.scope.editor.1.2.3.dk.ffd5515e", table: .localizable, fallback: "%1$@ · %2$@ · %3$@ dk", arguments: [String(describing: group), String(describing: groupName(group)), String(describing: minutes)])
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

/// One row: a checkbox, the subtopic's own title, and its minutes — nothing
/// else. Trainer and method (yüz yüze/online) do not vary per topic, so
/// they live one level up (the "Eğiticiler" step and the info step's bulk
/// toggle) instead of being asked again here for every single row.
struct NovaEducationTopicEditor: View {
    @Binding var topic: NovaEducationTopic
    let removable: Bool
    @Environment(\.colorScheme) private var scheme
    /// Restored when the checkbox is switched back on after being switched
    /// off — switching it off just zeroes the minutes rather than deleting
    /// the topic, so a session that only covered part of the curriculum
    /// (e.g. only G1 today) can say so without losing the rest.
    let defaultMinutes: Int
    let remove: () -> Void
    /// The minutes field always stays editable, in both directions: typing
    /// a positive number here also switches the checkbox on, typing 0
    /// switches it off, and the checkbox itself does the same in reverse —
    /// one true state, shown two ways.
    private var includedBinding: Binding<Bool> {
        Binding(get: { topic.instruction_minutes > 0 }, set: { on in topic.instruction_minutes = on ? (defaultMinutes > 0 ? defaultMinutes : 30) : 0 })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button { includedBinding.wrappedValue.toggle() } label: {
                    Label(includedBinding.wrappedValue ? "Seçildi" : "Eğitime ekle",
                        systemImage: includedBinding.wrappedValue ? "checkmark.square.fill" : "square")
                        .font(NovaFont.font(.bodyStrong))
                        .foregroundStyle(includedBinding.wrappedValue ? NovaColorToken.accentInk.color(in: scheme) : NovaFont.secondaryInk)
                        .frame(minHeight: 40)
                }.buttonStyle(NovaRowPressStyle())
                    .accessibilityLabel(RDLocalization.string("localizable.nova.education.topics.included",
                        table: .localizable, fallback: "Bu konu bu eğitimde işlendi"))
                    .accessibilityValue(includedBinding.wrappedValue ? "Seçildi" : "Seçilmedi")
                Spacer(minLength: 0)
                if removable {
                    Button { remove() } label: { Image(systemName: "trash").font(.system(size: 15)).frame(width: 40, height: 40) }
                        .foregroundStyle(NovaColorToken.statusDangerInk.color(in: scheme))
                        .accessibilityLabel(RDLocalization.string("localizable.nova.education.topics.removetopic", table: .localizable, fallback: "Kaldır"))
                }
            }
            if topic.group == "G4" || topic.parent_code != nil || topic.code.hasPrefix("CUSTOM") {
                TextField(RDLocalization.string("localizable.nova.education.topics.topictitle", table: .localizable, fallback: "Konu başlığı"), text: $topic.title, axis: .vertical)
                    .lineLimit(2...3)
            } else {
                Text(topic.title).font(NovaFont.font(.body)).fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 10) {
                Button { topic.instruction_minutes = max(0, topic.instruction_minutes - 10) } label: {
                    Image(systemName: "minus.circle").font(.system(size: 22))
                }.accessibilityLabel(RDLocalization.string("localizable.nova.education.scope.editor.10.dakika.azalt.614dc4c4", table: .localizable, fallback: "10 dakika azalt"))
                TextField(RDLocalization.string("localizable.nova.education.topics.minutes", table: .localizable, fallback: "Dakika"), value: $topic.instruction_minutes, format: .number)
                    .keyboardType(.numberPad).multilineTextAlignment(.center).frame(width: 52)
                Text("dk").font(NovaFont.font(.meta)).foregroundStyle(NovaFont.secondaryInk)
                Button { topic.instruction_minutes += 10 } label: {
                    Image(systemName: "plus.circle").font(.system(size: 22))
                }.accessibilityLabel(RDLocalization.string("localizable.nova.education.scope.editor.10.dakika.artir.366b6fd4", table: .localizable, fallback: "10 dakika artır"))
                Spacer(minLength: 0)
                Menu(RDLocalization.string("localizable.nova.education.scope.editor.hizli.sec.13697dbb", table: .localizable, fallback: "Hızlı seç")) {
                    ForEach([10, 20, 30, 40, 60], id: \.self) { minutes in
                        Button("\(minutes) dk") { topic.instruction_minutes = minutes }
                    }
                }.font(NovaFont.font(.meta))
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
                includedBinding.wrappedValue ? NovaColorToken.accent.color(in: scheme) : NovaColorToken.border.color(in: scheme), lineWidth: 1))
    }
}
