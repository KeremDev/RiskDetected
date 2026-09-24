import SwiftUI

/// Kontrol listesi modu (rd-checklist.js): liste türü, konular, sorular ve özet. Metinler köprüden gelir.
struct NovaChecklistWizardView: Decodable {
    struct Choice: Decodable, Identifiable { let id: String; let title: String; var help: String?; let selected: Bool }
    struct Topic: Decodable, Identifiable {
        let id: String; let title: String; let kind: String; let kindLabel: String; let reasons: [String]
        let core: Bool; let suggested: Bool; let selected: Bool; let isNew: Bool; let questions: Int
    }
    struct Question: Decodable, Identifiable {
        let key: String; let text: String; let vm: String; let vmLabel: String; let isNew: Bool; let selected: Bool
        var id: String { key }
    }
    struct Own: Decodable, Identifiable { let index: Int; let pack: String; let text: String; var id: Int { index } }
    struct TopicGroup: Decodable, Identifiable {
        let id: String; let title: String; let kindLabel: String; let total: Int; let on: Int; let items: [Question]; let custom: [Own]
    }
    let texts: [String: String]
    let version: String
    let purpose: String
    let freq: String
    let layout: String
    let title: String
    let titleManual: Bool
    let purposes: [Choice]
    let freqs: [Choice]
    let layouts: [Choice]
    let topics: [Topic]
    let groups: [TopicGroup]
    let loose: [Own]
    let topicCount: Int
    let itemCount: Int
    let listCount: Int
    let gaps: [String]
    func text(_ key: String) -> String { texts[key] ?? "" }
}

/// The finished list (RDBridge.result in checklist mode): what the documents show and what Listelerim receives.
struct NovaChecklistWizardList: Decodable {
    struct Firm: Decodable { let name: String; let address: String; let date: String; let sector: String; let hazardClass: String }
    struct Ref: Decodable { let template: String; let item: String }
    struct Entry: Decodable, Identifiable {
        let no: Int; let text: String; let vm: String; let vmLabel: String; let ref: Ref?; let isNew: Bool; let own: Bool
        var id: Int { no }
    }
    struct Section: Decodable, Identifiable { let id: String; let title: String; let kindLabel: String; let why: [String]; let items: [Entry] }
    struct SaveItem: Decodable { let text: String; let section: String; let ref: Ref?; let allowsNotApplicable: Bool }
    struct SavedList: Decodable { let title: String; let items: [SaveItem] }
    let title: String
    let firm: Firm
    let purposeLabel: String
    let freqLabel: String
    let layout: String
    let sections: [Section]
    let lists: [SavedList]
    let total: Int
    let fromCatalog: Int
    let newCatalog: Int
    let own: Int
    let approvalNote: String
    let note: String
}

/// Kontrol listesi sayfaları; yalnız eylem gönderir.
struct NovaChecklistWizardPage: View {
    let step: String
    let view: NovaRiskWizardView
    let checklist: NovaChecklistWizardView
    let runtime: NovaRiskWizardRuntime?
    let perform: ([String: Any]) -> Void
    let go: (String) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var query = ""
    @State private var hits: [NovaChecklistWizardView.Topic] = []
    @State private var open: Set<String> = []
    @State private var drafts: [String: String] = [:]

    private func t(_ key: String) -> String { checklist.text(key) }
    private func wideCard<Content: View>(padding: CGFloat = 14, @ViewBuilder _ content: () -> Content) -> some View {
        let body = content()
        return NovaCard(padding: padding) { body.frame(maxWidth: .infinity, alignment: .leading) }
    }
    private func heading(_ title: String, _ help: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NovaText(text: title, style: .sheetTitle)
            if !help.isEmpty { NovaText(text: help, style: .meta, color: NovaColorToken.textSecondary.color(in: scheme)) }
        }.padding(.bottom, 4)
    }

    var body: some View {
        switch step {
        case "purpose": purposePage
        case "topics": topicsPage
        case "items": itemsPage
        default: summaryPage
        }
    }

    private var purposePage: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading(t("purpose.title"), t("purpose.help"))
            ForEach(checklist.purposes) { item in
                NovaWizardOptionRow(title: item.title, subtitle: item.help ?? "", selected: item.selected, single: true) {
                    perform(["type": "ckPurpose", "id": item.id])
                }.accessibilityIdentifier("checklistWizard.purpose.\(item.id)")
            }
            if checklist.purpose == "site" {
                NovaText(text: t("freq.title"), style: .overline).padding(.top, 8)
                chips(checklist.freqs) { perform(["type": "ckFreq", "id": $0]) }
                NovaText(text: t("freq.help"), style: .metaQuiet)
            }
            NovaText(text: t("layout.title"), style: .overline).padding(.top, 8)
            chips(checklist.layouts) { perform(["type": "ckLayout", "id": $0]) }
            NovaText(text: t("layout.help"), style: .metaQuiet)
        }
    }

    private var topicsPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading(t("topics.title"), t("topics.help"))
            NovaText(text: t("topics.suggested") + " · \(checklist.topics.filter(\.suggested).count)", style: .overline)
            if checklist.topics.isEmpty { NovaText(text: t("topics.empty"), style: .metaQuiet) }
            ForEach(checklist.topics) { topicRow($0) }
            NovaText(text: t("topics.add"), style: .overline).padding(.top, 8)
            NovaAnalysisSearchField(text: $query, placeholder: t("topics.search"), identifier: "checklistWizard.topicSearch")
                .onChange(of: query) { _ in refreshHits() }
            ForEach(hits) { topicRow($0) }
            if query.count >= 2 && hits.isEmpty { NovaText(text: t("topics.noHits"), style: .metaQuiet) }
        }
    }
    private func topicRow(_ topic: NovaChecklistWizardView.Topic) -> some View {
        var badges = [topic.kindLabel, "\(topic.questions) " + t("topics.questions")]
        if topic.isNew { badges.append(t("topics.new")) }
        let tags = topic.suggested ? Array(topic.reasons.prefix(3)) : (topic.selected ? [t("topics.manual")] : [])
        return NovaWizardOptionRow(title: topic.title, tags: tags, badges: badges, selected: topic.selected) {
            perform(["type": "ckTopic", "id": topic.id]); refreshHits()
        }.accessibilityIdentifier("checklistWizard.topic.\(topic.id)")
    }
    private func refreshHits() {
        hits = query.count >= 2 ? ((try? runtime?.checklistTopics(query)) ?? []) : []
    }

    private var itemsPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading(t("items.title"), t("items.help"))
            NovaText(text: t("summary.items") + " · \(checklist.itemCount)", style: .overline)
            if checklist.groups.isEmpty { NovaText(text: t("items.empty"), style: .metaQuiet) }
            ForEach(checklist.groups) { groupCard($0) }
            wideCard {
                VStack(alignment: .leading, spacing: 8) {
                    NovaText(text: t("items.own"), style: .cardTitle)
                    NovaText(text: t("items.ownHelp"), style: .metaQuiet)
                    ForEach(checklist.loose) { ownRow($0) }
                    addField(pack: "")
                }
            }
        }
    }
    private func groupCard(_ group: NovaChecklistWizardView.TopicGroup) -> some View {
        let isOpen = open.contains(group.id)
        return wideCard {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { if isOpen { open.remove(group.id) } else { open.insert(group.id) } }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            NovaText(text: group.title, style: .bodyStrong)
                            NovaText(text: group.kindLabel + " · \(group.on) / \(group.total) " + t("topics.questions")
                                     + (group.custom.isEmpty ? "" : " + \(group.custom.count)"), style: .metaQuiet)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down").foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("checklistWizard.group.\(group.id)")
                if isOpen {
                    Button(group.on == group.total ? t("items.none") : t("items.all")) { perform(["type": "ckItems", "id": group.id]) }
                        .font(NovaFont.font(.label)).foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                    ForEach(group.items) { questionRow($0) }
                    ForEach(group.custom) { ownRow($0) }
                    addField(pack: group.id)
                }
            }
        }
    }
    private func questionRow(_ item: NovaChecklistWizardView.Question) -> some View {
        Button { perform(["type": "ckItem", "id": item.key]) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: item.selected ? "checkmark.square.fill" : "square").font(.system(size: 18))
                    .foregroundStyle(item.selected ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.textTertiary.color(in: scheme))
                VStack(alignment: .leading, spacing: 4) {
                    NovaText(text: item.text, style: .body, color: item.selected ? NovaColorToken.text.color(in: scheme) : NovaColorToken.textSecondary.color(in: scheme))
                    NovaWizardWrap(spacing: 6) {
                        NovaWizardTag(text: item.vmLabel, tone: "neutral")
                        if item.isNew { NovaWizardTag(text: t("topics.new"), tone: "low") }
                    }
                }
                Spacer(minLength: 0)
            }.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(item.selected ? .isSelected : [])
    }
    private func ownRow(_ own: NovaChecklistWizardView.Own) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "person.fill.questionmark").font(.system(size: 15)).foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
            VStack(alignment: .leading, spacing: 4) {
                NovaText(text: own.text, style: .body)
                NovaWizardTag(text: t("items.mine"), tone: "info")
            }
            Spacer(minLength: 0)
            Button { perform(["type": "ckCustom", "op": "remove", "index": own.index]) } label: {
                Image(systemName: "trash").frame(width: 36, height: 36)
            }.buttonStyle(.plain).accessibilityLabel(Text(verbatim: t("items.remove")))
        }
    }
    private func addField(pack: String) -> some View {
        let draft = Binding(get: { drafts[pack] ?? "" }, set: { drafts[pack] = $0 })
        return HStack(spacing: 8) {
            TextField(t("items.placeholder"), text: draft, axis: .vertical)
                .font(NovaFont.font(.body))
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityIdentifier("checklistWizard.custom.\(pack.isEmpty ? "own" : pack)")
            NovaButton(label: t("items.add"), symbol: "plus", variant: .surface,
                       isEnabled: !(drafts[pack] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, compact: true) {
                perform(["type": "ckCustom", "op": "add", "pack": pack, "text": drafts[pack] ?? ""])
                drafts[pack] = ""
            }.frame(width: 96)
        }
    }

    private var summaryPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(t("summary.title"), t("summary.help"))
            VStack(alignment: .leading, spacing: 6) {
                NovaText(text: t("summary.name"), style: .label)
                TextField(checklist.title, text: Binding(get: { checklist.titleManual ? checklist.title : "" },
                                                         set: { perform(["type": "ckTitle", "value": $0]) }), axis: .vertical)
                    .font(NovaFont.font(.body))
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("checklistWizard.title")
            }
            wideCard {
                VStack(alignment: .leading, spacing: 10) {
                    line(t("summary.firm"), view.firm.name, "firm")
                    line(t("summary.sector"), view.sectors.map(\.title).joined(separator: ", ") + (view.hazardClassLabel.isEmpty ? "" : " · " + view.hazardClassLabel), "sector")
                    line(t("summary.purpose"), ([checklist.purposes.first(where: \.selected)?.title]
                        + (checklist.purpose == "site" ? [checklist.freqs.first { $0.selected && !$0.id.isEmpty }?.title] : [])).compactMap { $0 }.joined(separator: " · "), "purpose")
                    line(t("summary.layout"), (checklist.layouts.first(where: \.selected)?.title ?? "") + " · \(checklist.listCount)", "purpose")
                    line(t("summary.topics"), "\(checklist.topicCount) · " + checklist.topics.filter(\.selected).map(\.title).joined(separator: ", "), "topics")
                    line(t("summary.items"), "\(checklist.itemCount)", "items")
                }
            }
            if !checklist.gaps.isEmpty {
                wideCard {
                    VStack(alignment: .leading, spacing: 6) {
                        NovaText(text: t("summary.gaps"), style: .overline)
                        ForEach(checklist.gaps, id: \.self) { NovaText(text: "• " + $0, style: .meta) }
                    }
                }
            }
        }
    }
    private func line(_ label: String, _ value: String, _ target: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                NovaText(text: label, style: .metaQuiet)
                NovaText(text: value.isEmpty ? "—" : value, style: .body)
            }
            Spacer()
            Button(t("summary.edit")) { go(target) }.font(NovaFont.font(.label)).foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
        }
    }
    private func chips(_ items: [NovaChecklistWizardView.Choice], pick: @escaping (String) -> Void) -> some View {
        NovaWizardWrap(spacing: 8) {
            ForEach(items) { item in
                Button { pick(item.id) } label: {
                    NovaText(text: item.title, style: .label, color: item.selected ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.text.color(in: scheme))
                        .padding(.vertical, 9).padding(.horizontal, 14)
                        .background((item.selected ? NovaColorToken.accentSoft : NovaColorToken.surface).color(in: scheme), in: Capsule())
                        .overlay(Capsule().strokeBorder(item.selected ? NovaColorToken.accent.color(in: scheme) : .clear, lineWidth: 1.5))
                }.buttonStyle(.plain).accessibilityAddTraits(item.selected ? .isSelected : [])
            }
        }
    }
}

/// Liste sonucu: indirme, Listelerim'e kaydetme, kontrolü başlatma ve soruların önizlemesi.
struct NovaChecklistWizardResultView: View {
    let list: NovaChecklistWizardList
    let checklist: NovaChecklistWizardView
    let busy: Bool
    let canSave: Bool
    let saved: [String]
    let export: (String) -> Void
    let save: () -> Void
    let start: ((String) -> Void)?
    @Environment(\.colorScheme) private var scheme
    @State private var open: Set<String> = []
    private func t(_ key: String) -> String { checklist.text(key) }

    private func wideCard<Content: View>(padding: CGFloat = 14, @ViewBuilder _ content: () -> Content) -> some View {
        let body = content()
        return NovaCard(padding: padding) { body.frame(maxWidth: .infinity, alignment: .leading) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                NovaText(text: list.title, style: .sheetTitle)
                NovaText(text: [list.purposeLabel, list.freqLabel, "\(list.sections.count) " + t("topics.unit"),
                                "\(list.total) " + t("topics.questions")].filter { !$0.isEmpty }.joined(separator: " · "),
                         style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
            }
            if list.total == 0 {
                NovaHelpHint(text: t("result.nothing"))
            } else {
                wideCard {
                    VStack(alignment: .leading, spacing: 10) {
                        NovaText(text: t("result.download"), style: .cardTitle)
                        HStack(spacing: 8) {
                            NovaButton(label: t("result.word"), symbol: "doc.text", isEnabled: !busy, compact: true) { export("docx") }
                                .accessibilityIdentifier("checklistWizard.docx")
                            NovaButton(label: t("result.excel"), symbol: "tablecells", variant: .surface, isEnabled: !busy, compact: true) { export("xlsx") }
                                .accessibilityIdentifier("checklistWizard.xlsx")
                            NovaButton(label: t("result.pdf"), symbol: "doc.richtext", variant: .surface, isEnabled: !busy, compact: true) { export("pdf") }
                        }
                    }
                }
                if canSave {
                    wideCard {
                        VStack(alignment: .leading, spacing: 8) {
                            NovaText(text: t("result.save"), style: .cardTitle)
                            NovaText(text: t("result.saveHelp"), style: .metaQuiet)
                            NovaText(text: t("result.lists") + " · \(list.lists.count)", style: .overline)
                            ForEach(Array(list.lists.enumerated()), id: \.offset) { _, entry in
                                NovaText(text: "• " + entry.title + " · \(entry.items.count) " + t("topics.questions"), style: .meta)
                            }
                            NovaButton(label: saved.isEmpty ? (busy ? t("result.saving") : t("result.save")) : t("result.saved"),
                                       symbol: saved.isEmpty ? "tray.and.arrow.down" : "checkmark.circle",
                                       variant: saved.isEmpty ? .primary : .surface, isEnabled: !busy && saved.isEmpty, compact: true) { save() }
                                .accessibilityIdentifier("checklistWizard.save")
                            if let start, saved.count == 1, let code = saved.first {
                                NovaText(text: t("result.startHelp"), style: .metaQuiet)
                                NovaButton(label: t("result.start"), symbol: "play", variant: .surface, isEnabled: !busy, compact: true) { start(code) }
                                    .accessibilityIdentifier("checklistWizard.start")
                            }
                        }
                    }
                }
                ForEach(list.sections) { sectionCard($0) }
            }
            NovaHelpHint(text: list.note)
        }
    }
    private func sectionCard(_ section: NovaChecklistWizardList.Section) -> some View {
        let isOpen = open.contains(section.id)
        return wideCard {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { if isOpen { open.remove(section.id) } else { open.insert(section.id) } }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            NovaText(text: section.title, style: .bodyStrong)
                            NovaText(text: section.kindLabel + " · \(section.items.count) " + t("topics.questions"), style: .metaQuiet)
                            if !section.why.isEmpty { NovaWizardTag(text: section.why.joined(separator: ", "), tone: "low") }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down").foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("checklistWizard.section.\(section.id)")
                if isOpen {
                    ForEach(section.items) { entry in
                        HStack(alignment: .top, spacing: 8) {
                            NovaText(text: "\(entry.no).", style: .metaQuiet).frame(width: 30, alignment: .leading)
                            VStack(alignment: .leading, spacing: 4) {
                                NovaText(text: entry.text, style: .body)
                                NovaWizardWrap(spacing: 6) {
                                    if !entry.vmLabel.isEmpty { NovaWizardTag(text: entry.vmLabel, tone: "neutral") }
                                    if entry.own { NovaWizardTag(text: t("result.own"), tone: "info") }
                                    if entry.isNew { NovaWizardTag(text: t("result.newItem"), tone: "low") }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Publishes the finished list to Listelerim with the module's own template actions: server catalogue questions are
/// copied with their method and help text, the rest are written as the expert's own questions, then the version is
/// published. Returns the template codes in list order.
enum NovaChecklistWizardSaver {
    static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "tr_TR"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// A new title opens a new list; the same title would open a new version of an existing one instead.
    static func unique(_ title: String, taken: Set<String>) -> String {
        guard taken.contains(fold(title)) else { return title }
        var number = 2
        while taken.contains(fold("\(title) (\(number))")) { number += 1 }
        return "\(title) (\(number))"
    }

    @MainActor
    static func save(runtime: NovaRiskWizardRuntime, client: NovaChecklistClient, company: UUID?) async throws -> [String] {
        let result = try runtime.checklistList()
        var taken = Set(try await client.templates(company).map { fold($0.title) })
        var codes: [String] = []
        for entry in result.lists where !entry.items.isEmpty {
            let title = unique(entry.title, taken: taken)
            taken.insert(fold(title))
            try await client.draftTemplate(company, title)
            guard let template = try await client.templates(company).first(where: { fold($0.title) == fold(title) }),
                  let draft = template.draft else { throw NovaChecklistFailure.unavailable }
            let code = template.templateCode
            var revision = draft.revision
            var position = draft.items.count
            var pending: [NovaChecklistItemSelection] = []
            // Every template action bumps the draft's edit revision by one.
            func flush() async throws {
                for start in stride(from: 0, to: pending.count, by: 100) {
                    try await client.copyItems(company, code, draft.version, revision, Array(pending[start..<min(start + 100, pending.count)]))
                    revision += 1
                }
                pending = []
            }
            for item in entry.items {
                position += 1
                if let ref = item.ref {
                    pending.append(.init(sourceTemplateCode: ref.template, sourceItemCode: ref.item, sectionTitle: item.section))
                } else {
                    try await flush()
                    if let setSectionItem = client.setSectionItem {
                        try await setSectionItem(company, code, draft.version, revision, "w\(position)", item.text, item.allowsNotApplicable, position, item.section)
                    } else {
                        try await client.setItem(company, code, draft.version, revision, "w\(position)", item.text, item.allowsNotApplicable, position)
                    }
                    revision += 1
                }
            }
            try await flush()
            try await client.publishTemplate(company, code, draft.version, revision, result.approvalNote)
            codes.append(code)
        }
        return codes
    }
}

extension NovaRiskWizardScreen {
    /// The checklist wizard as the Kontroller and Kontrol Listeleri screens open it.
    static func checklist(client: NovaChecklistClient, initialCompany: UUID?,
                          onStart: @escaping (String) -> Void, onBack: @escaping () -> Void) -> NovaRiskWizardScreen {
        NovaRiskWizardScreen(mode: "checklist", companiesSource: client.companies,
            workplacesSource: { company in try await client.catalogue(company).workplaces.map { .init(id: $0.id, name: $0.name) } },
            files: nil, initialCompany: initialCompany, checklistClient: client, onChecklistStart: onStart, onBack: onBack)
    }
}
