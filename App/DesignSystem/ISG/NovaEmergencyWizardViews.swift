import SwiftUI
import CryptoKit

/// One selectable wizard row (risk and emergency wizards share it).
struct NovaWizardOptionRow: View {
    let title: String
    var subtitle = ""
    var tags: [String] = []
    var badges: [String] = []
    let selected: Bool
    var single = false
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: selected ? (single ? "largecircle.fill.circle" : "checkmark.square.fill") : (single ? "circle" : "square"))
                    .font(.system(size: 20))
                    .foregroundStyle(selected ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.textTertiary.color(in: scheme))
                VStack(alignment: .leading, spacing: 4) {
                    NovaText(text: title, style: .bodyStrong)
                    if !subtitle.isEmpty { NovaText(text: subtitle, style: .meta, color: NovaColorToken.textSecondary.color(in: scheme)) }
                    if !tags.isEmpty || !badges.isEmpty {
                        NovaWizardWrap(spacing: 6) {
                            ForEach(badges, id: \.self) { NovaWizardTag(text: $0, tone: "neutral") }
                            ForEach(tags, id: \.self) { NovaWizardTag(text: $0, tone: "low") }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background((selected ? NovaColorToken.accentSoft : NovaColorToken.surface).color(in: scheme), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(selected ? NovaColorToken.accent.color(in: scheme) : .clear, lineWidth: 1.5))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Small coloured label; `tone` is a risk level or "info" / "neutral".
struct NovaWizardTag: View {
    let text: String
    let tone: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let colors: (Color, Color) = {
            switch tone {
            case "info": return (NovaColorToken.statusInfoBg.color(in: scheme), NovaColorToken.statusInfoInk.color(in: scheme))
            case "neutral": return (NovaColorToken.statusNeutralBg.color(in: scheme), NovaColorToken.statusNeutralInk.color(in: scheme))
            default: let t = NovaRiskLevelTone.colors(tone, scheme); return (t.background, t.ink)
            }
        }()
        NovaText(text: text, style: .micro, color: colors.1)
            .padding(.vertical, 3).padding(.horizontal, 7)
            .background(colors.0, in: RoundedRectangle(cornerRadius: 6))
    }
}

/// Wrapping row for tags and chips; reports the wrapped height so cards grow with their content.
struct NovaWizardWrap: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let limit = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, line: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.init(width: limit, height: nil))
            if x > 0 && x + size.width > limit { y += line + spacing; x = 0; line = 0 }
            x += size.width + spacing; line = max(line, size.height); widest = max(widest, x - spacing)
        }
        return CGSize(width: proposal.width ?? widest, height: y + line)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, line: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.init(width: bounds.width, height: nil))
            if x > bounds.minX && x + size.width > bounds.maxX { y += line + spacing; x = bounds.minX; line = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: .init(size))
            x += size.width + spacing; line = max(line, size.height)
        }
    }
}

/// A person the company already has on file, offered for the plan team.
struct NovaEmergencyWizardStaff: Identifiable, Equatable {
    let id: UUID
    let name: String
    let detail: String
    let isSupportStaff: Bool
}

/// Acil durum sayfaları: saha koşulları, senaryolar, ekipler, saha bilgileri ve özet.
/// Metinlerin tamamı köprüden (`emergency.texts`) gelir; bu görünüm yalnız eylem gönderir.
struct NovaEmergencyWizardPage: View {
    let step: String
    let view: NovaRiskWizardView
    let emergency: NovaRiskWizardView.Emergency
    let runtime: NovaRiskWizardRuntime?
    let staffSource: (() async throws -> [NovaEmergencyWizardStaff])?
    let perform: ([String: Any]) -> Void
    let go: (String) -> Void

    @Environment(\.colorScheme) private var scheme
    @State private var cardQuery = ""
    @State private var cardHits: [NovaRiskWizardView.Emergency.Card] = []
    @State private var staff: [NovaEmergencyWizardStaff] = []
    @State private var staffQuery = ""
    @State private var staffLoaded = false

    private func t(_ key: String) -> String { emergency.text(key) }

    private func wideCard<Content: View>(padding: CGFloat = 14, @ViewBuilder _ content: () -> Content) -> some View {
        let body = content()
        return NovaCard(padding: padding) { body.frame(maxWidth: .infinity, alignment: .leading) }
    }

    var body: some View {
        switch step {
        case "site": sitePage
        case "cards": cardsPage
        case "team": teamPage
        case "fields": fieldsPage
        default: summaryPage
        }
    }

    private func heading(_ title: String, _ help: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NovaText(text: title, style: .sheetTitle)
            if !help.isEmpty { NovaText(text: help, style: .meta, color: NovaColorToken.textSecondary.color(in: scheme)) }
        }.padding(.bottom, 4)
    }

    private var sitePage: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading(t("site.title"), t("site.help"))
            ForEach(emergency.site) { item in
                NovaWizardOptionRow(title: item.title, subtitle: item.help, selected: item.selected) { perform(["type": "site", "id": item.id]) }
                    .accessibilityIdentifier("emergencyWizard.site.\(item.id)")
            }
        }
    }

    private var cardsPage: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading(t("cards.title"), t("cards.help"))
            ForEach(emergency.cards) { card in
                NovaWizardOptionRow(title: card.title, subtitle: card.trigger + " · " + card.mode,
                                    tags: card.core ? [] : (card.suggested ? Array(card.reasons.prefix(2)) : [t("cards.manual")]),
                                    badges: card.core ? [t("cards.core")] : [], selected: card.selected) {
                    if !card.core { perform(["type": "card", "id": card.id]); refreshHits() }
                }.accessibilityIdentifier("emergencyWizard.card.\(card.id)")
            }
            NovaText(text: t("cards.add"), style: .overline).padding(.top, 8)
            NovaAnalysisSearchField(text: $cardQuery, placeholder: t("cards.search"), identifier: "emergencyWizard.cardSearch")
                .onChange(of: cardQuery) { _ in refreshHits() }
            ForEach(cardHits) { card in
                NovaWizardOptionRow(title: card.title, subtitle: card.trigger, selected: false) {
                    perform(["type": "card", "id": card.id]); refreshHits()
                }
            }
        }
    }
    private func refreshHits() {
        cardHits = cardQuery.count >= 2 ? ((try? runtime?.cards(cardQuery)) ?? []) : []
    }

    private var teamPage: some View {
        let teams = emergency.teams
        return VStack(alignment: .leading, spacing: 12) {
            heading(t("team.title"), t("team.help"))
            wideCard {
                VStack(alignment: .leading, spacing: 10) {
                    NovaText(text: t("team.reference"), style: .overline)
                    NovaText(text: [teams.hazardClassLabel, teams.employees.map { String($0) } ?? t("team.noEmployees")].filter { !$0.isEmpty }.joined(separator: " · "),
                             style: .metaQuiet)
                    ForEach(teams.roles) { role in
                        HStack(alignment: .top, spacing: 10) {
                            VStack(alignment: .leading, spacing: 2) {
                                NovaText(text: role.label, style: .bodyStrong)
                                NovaText(text: role.basis, style: .metaQuiet)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 2) {
                                NovaText(text: role.required.map { String($0) } ?? (teams.combined != nil && role.id != "ilkyardim" ? t("team.shared") : "—"), style: .sectionTitle)
                                NovaText(text: t("team.assigned") + " \(role.assigned)", style: .metaQuiet)
                            }
                        }
                    }
                    NovaText(text: teams.note, style: .metaQuiet, color: NovaColorToken.textSecondary.color(in: scheme))
                }
            }
            NovaText(text: t("team.members") + " · \(emergency.members.count)", style: .overline).padding(.top, 4)
            if emergency.members.isEmpty { NovaText(text: t("team.empty"), style: .metaQuiet) }
            ForEach(emergency.members) { member in memberCard(member) }
            HStack(spacing: 8) {
                Menu {
                    ForEach(teams.roles) { role in
                        Button(role.label) { perform(["type": "member", "op": "add", "role": role.id]) }
                    }
                } label: {
                    Label(t("team.manual"), systemImage: "plus")
                        .font(NovaFont.font(.label)).padding(.vertical, 10).padding(.horizontal, 14)
                        .background(NovaColorToken.surface.color(in: scheme), in: Capsule())
                }.accessibilityIdentifier("emergencyWizard.member.add")
            }
            if staffSource != nil { staffSection }
        }
        .task { await loadStaff() }
    }
    private func memberCard(_ member: NovaRiskWizardView.Emergency.Member) -> some View {
        wideCard(padding: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Menu {
                        ForEach(emergency.teams.roles) { role in
                            Button(role.label) { perform(["type": "member", "op": "set", "index": member.index, "field": "role", "value": role.id]) }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            NovaText(text: emergency.teams.roles.first { $0.id == member.role }?.label ?? member.role, style: .label)
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .semibold))
                        }
                        .padding(.vertical, 8).padding(.horizontal, 10)
                        .background(NovaColorToken.accentSoft.color(in: scheme), in: Capsule())
                    }
                    Spacer()
                    Button { perform(["type": "member", "op": "remove", "index": member.index]) } label: {
                        Image(systemName: "trash").frame(width: 36, height: 36)
                    }.buttonStyle(.plain).accessibilityLabel(Text(verbatim: t("team.remove")))
                }
                memberField(t("team.name"), member.name, member.index, "name")
                memberField(t("team.personTitle"), member.title, member.index, "title")
                memberField(t("team.area"), member.area, member.index, "area")
                memberField(t("team.contact"), member.contact, member.index, "contact")
                Toggle(t("team.backup"), isOn: Binding(get: { member.backup }, set: {
                    perform(["type": "member", "op": "set", "index": member.index, "field": "backup", "value": $0])
                })).font(NovaFont.font(.body))
            }
        }
    }
    private func memberField(_ placeholder: String, _ value: String, _ index: Int, _ field: String) -> some View {
        TextField(placeholder, text: Binding(get: { value }, set: { perform(["type": "member", "op": "set", "index": index, "field": field, "value": $0]) }))
            .font(NovaFont.font(.body))
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(NovaColorToken.surfaceMuted.color(in: scheme), in: RoundedRectangle(cornerRadius: 10))
    }
    @ViewBuilder private var staffSection: some View {
        NovaText(text: t("team.fromCompany"), style: .overline).padding(.top, 8)
        NovaAnalysisSearchField(text: $staffQuery, placeholder: t("team.name"), identifier: "emergencyWizard.staffSearch")
        let taken = Set(emergency.members.compactMap(\.ref))
        let shown = staff.filter { !taken.contains($0.id.uuidString.lowercased()) }
            .filter { staffQuery.count < 2 || $0.name.localizedCaseInsensitiveContains(staffQuery) }
        ForEach(shown.prefix(40)) { person in
            Menu {
                ForEach(emergency.teams.roles) { role in
                    Button(role.label) {
                        perform(["type": "member", "op": "add", "role": role.id, "name": person.name, "title": person.detail,
                                 "ref": person.id.uuidString.lowercased()])
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: person.isSupportStaff ? "person.badge.shield.checkmark" : "person").frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        NovaText(text: person.name, style: .bodyStrong)
                        if !person.detail.isEmpty { NovaText(text: person.detail, style: .metaQuiet) }
                    }
                    Spacer()
                    Image(systemName: "plus.circle").foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                }
                .padding(12)
                .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
            }.buttonStyle(.plain)
        }
    }
    private func loadStaff() async {
        guard !staffLoaded, let staffSource else { return }
        staffLoaded = true
        staff = (try? await staffSource()) ?? []
    }

    private var fieldsPage: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading(t("fields.title"), t("fields.help"))
            NovaText(text: t("fields.general"), style: .overline)
            ForEach(emergency.fields.filter(\.general)) { fieldRow($0) }
            let specific = emergency.fields.filter { !$0.general }
            if !specific.isEmpty {
                NovaText(text: t("fields.specific") + " · \(specific.count)", style: .overline).padding(.top, 6)
                ForEach(specific) { fieldRow($0) }
            }
            NovaText(text: t("fields.contacts"), style: .overline).padding(.top, 6)
            ForEach(emergency.contacts) { contact in
                HStack(spacing: 8) {
                    contactField(t("fields.contactLabel"), contact.label, contact.index, "label")
                    contactField(t("fields.contactNumber"), contact.number, contact.index, "number").frame(maxWidth: 130)
                    Button { perform(["type": "contact", "op": "remove", "index": contact.index]) } label: {
                        Image(systemName: "trash").frame(width: 36, height: 36)
                    }.buttonStyle(.plain)
                }
            }
            NovaButton(label: t("fields.addContact"), symbol: "plus", variant: .surface, compact: true) { perform(["type": "contact", "op": "add"]) }
        }
    }
    private func fieldRow(_ field: NovaRiskWizardView.Emergency.Field) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            NovaText(text: field.card.isEmpty ? field.label : field.label + " · " + field.card, style: .label)
            TextField(t("fields.placeholder"), text: Binding(get: { field.value }, set: { perform(["type": "field", "key": field.key, "value": $0]) }), axis: .vertical)
                .font(NovaFont.font(.body))
                .padding(.horizontal, 14).padding(.vertical, 12)
                .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 12))
        }
    }
    private func contactField(_ placeholder: String, _ value: String, _ index: Int, _ key: String) -> some View {
        TextField(placeholder, text: Binding(get: { value }, set: { perform(["type": "contact", "op": "set", "index": index, "field": key, "value": $0]) }))
            .font(NovaFont.font(.body))
            .padding(.horizontal, 12).padding(.vertical, 10)
            .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 10))
    }

    private var summaryPage: some View {
        let selected = emergency.cards.filter(\.selected)
        let teams = emergency.teams
        return VStack(alignment: .leading, spacing: 12) {
            heading(t("summary.title"), t("summary.help"))
            wideCard {
                VStack(alignment: .leading, spacing: 10) {
                    line(t("summary.firm"), [view.firm.name, emergency.employees.map { String($0) } ?? ""].filter { !$0.isEmpty }.joined(separator: " · "), "firm")
                    line(t("summary.sector"), view.sectors.map(\.title).joined(separator: ", ") + (view.hazardClassLabel.isEmpty ? "" : " · " + view.hazardClassLabel), "sector")
                    line(t("summary.valid"), emergency.validUntil, "sector")
                    line(t("summary.cards"), "\(selected.count) · " + selected.map(\.title).joined(separator: ", "), "cards")
                    line(t("summary.team"), "\(emergency.members.count) · " + teams.roles.map { $0.label + " " + ($0.required.map { String($0) } ?? "—") }.joined(separator: ", "), "team")
                    line(t("summary.fields"), "\(emergency.fields.filter { !$0.value.isEmpty }.count) / \(emergency.fields.count)", "fields")
                }
            }
            wideCard {
                VStack(alignment: .leading, spacing: 6) {
                    NovaText(text: t("summary.gaps") + " · \(emergency.gaps.count)", style: .overline)
                    ForEach(emergency.gaps, id: \.self) { NovaText(text: "• " + $0, style: .meta) }
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
}

/// Plan sonucu: indirme, modüle kaydetme ve senaryoların önizlemesi.
struct NovaEmergencyWizardResultView: View {
    let plan: NovaEmergencyWizardPlan
    let emergency: NovaRiskWizardView.Emergency
    let busy: Bool
    let canSave: Bool
    let saved: Bool
    let export: (String) -> Void
    let save: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var open: Set<String> = []
    private func t(_ key: String) -> String { emergency.text(key) }

    private func wideCard<Content: View>(padding: CGFloat = 14, @ViewBuilder _ content: () -> Content) -> some View {
        let body = content()
        return NovaCard(padding: padding) { body.frame(maxWidth: .infinity, alignment: .leading) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                NovaText(text: plan.firm.name.isEmpty ? t("file.title") : plan.firm.name, style: .sheetTitle)
                NovaText(text: [plan.firm.sector, plan.firm.hazardClass, plan.firm.validUntil].filter { !$0.isEmpty }.joined(separator: " · "),
                         style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
            }
            wideCard {
                VStack(alignment: .leading, spacing: 10) {
                    NovaText(text: t("result.plan"), style: .cardTitle)
                    NovaText(text: t("result.planHelp"), style: .metaQuiet)
                    HStack(spacing: 8) {
                        NovaButton(label: t("result.download"), symbol: "arrow.down.doc", isEnabled: !busy, compact: true) { export("docx") }
                            .accessibilityIdentifier("emergencyWizard.docx")
                        NovaButton(label: t("result.pdf"), symbol: "doc.richtext", variant: .surface, isEnabled: !busy, compact: true) { export("pdf") }
                    }
                    NovaText(text: t("result.cards") + " · " + t("result.cardsHelp"), style: .metaQuiet)
                    NovaButton(label: t("result.downloadCards"), symbol: "printer", variant: .surface, isEnabled: !busy, compact: true) { export("cards") }
                        .accessibilityIdentifier("emergencyWizard.cards")
                }
            }
            wideCard {
                VStack(alignment: .leading, spacing: 8) {
                    NovaText(text: t("result.save"), style: .cardTitle)
                    NovaText(text: canSave ? t("result.saveHelp") : t("result.needsCompany"), style: .metaQuiet)
                    NovaButton(label: saved ? t("result.saved") : t("result.save"), symbol: saved ? "checkmark.circle" : "tray.and.arrow.down",
                               variant: saved ? .surface : .primary, isEnabled: canSave && !busy && !saved, compact: true) { save() }
                        .accessibilityIdentifier("emergencyWizard.save")
                }
            }
            wideCard {
                VStack(alignment: .leading, spacing: 8) {
                    NovaText(text: t("step.team"), style: .cardTitle)
                    ForEach(plan.teams.roles) { role in
                        HStack {
                            NovaText(text: role.label, style: .body)
                            Spacer()
                            NovaText(text: (role.required.map { String($0) } ?? (plan.teams.combined != nil && role.id != "ilkyardim" ? t("team.shared") : "—"))
                                     + " · " + t("team.assigned") + " \(role.assigned)", style: .meta)
                        }
                    }
                }
            }
            NovaText(text: t("result.scenarios"), style: .cardTitle).padding(.top, 6)
            ForEach(Array(plan.cards.enumerated()), id: \.element.id) { index, card in cardRow(index + 1, card) }
            wideCard {
                VStack(alignment: .leading, spacing: 6) {
                    NovaText(text: t("summary.gaps") + " · \(plan.gaps.count)", style: .overline)
                    ForEach(plan.gaps, id: \.self) { NovaText(text: "• " + $0, style: .meta) }
                }
            }
            NovaHelpHint(text: t("result.note"))
        }
    }
    private func cardRow(_ number: Int, _ card: NovaEmergencyWizardPlan.Card) -> some View {
        let isOpen = open.contains(card.id)
        return wideCard {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeOut(duration: 0.2)) { if isOpen { open.remove(card.id) } else { open.insert(card.id) } }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        NovaText(text: "\(number)", style: .metaQuiet).frame(width: 24, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            NovaText(text: card.title, style: .bodyStrong)
                            NovaText(text: card.trigger, style: .meta)
                            NovaWizardWrap(spacing: 6) {
                                NovaWizardTag(text: card.core ? t("cards.core") : card.why.joined(separator: ", "), tone: card.core ? "info" : "low")
                                NovaWizardTag(text: card.mode, tone: "neutral")
                            }
                        }
                        Spacer(minLength: 0)
                        Image(systemName: isOpen ? "chevron.up" : "chevron.down").foregroundStyle(NovaColorToken.textSecondary.color(in: scheme))
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("emergencyWizard.row.\(card.id)")
                if isOpen {
                    list(t("result.before"), card.before)
                    list(t("result.worker"), card.worker)
                    list(t("result.team"), card.team)
                    list(t("result.prohibited"), card.prohibited)
                    list(t("result.after"), card.after)
                    NovaText(text: t("result.reentry") + ": " + card.reentry, style: .meta)
                    ForEach(card.siteFields, id: \.key) { field in
                        NovaText(text: field.label + ": " + (field.value.isEmpty ? t("result.siteLater") : field.value), style: .metaQuiet)
                    }
                }
            }
        }
    }
    private func list(_ title: String, _ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: title, style: .label)
            ForEach(items, id: \.self) { NovaText(text: "• " + $0, style: .body) }
        }
    }
}

/// Saves the finished plan as a module record: the Word plan goes to the file archive, then the plan version is published.
enum NovaEmergencyWizardSaver {
    /// The module stores fire / first aid / evacuation / other; the plan document keeps the exact team names.
    static func role(_ id: String) -> NovaEmergencyRole {
        switch id {
        case "sondurme": return .fire
        case "ilkyardim": return .firstAid
        case "koruma": return .evacuation
        default: return .other
        }
    }
    static func isoDay(_ turkish: String) -> String {
        let parts = turkish.split(separator: ".").map(String.init)
        guard parts.count == 3, let day = Int(parts[0]), let month = Int(parts[1]), let year = Int(parts[2]) else { return "" }
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    @MainActor
    static func save(runtime: NovaRiskWizardRuntime, client: NovaEmergencyClient, company: UUID, workplace: UUID?,
                     texts: NovaRiskWizardView.Emergency) async throws {
        let plan = try runtime.plan()
        let file = try runtime.download(format: "docx")
        let draft = NovaFileDraft(title: texts.text("file.title"), category: "emergency_plan", note: texts.text("file.note") + " · " + runtime.catalogVersion,
            fileName: file.name, fileExtension: "docx", bytes: file.data.count,
            sha256: SHA256.hash(data: file.data).map { String(format: "%02x", $0) }.joined())
        let entry = try await client.fileClient.file(company, draft, file.data)
        var planDraft = NovaEmergencyPlanDraft()
        planDraft.workplaceID = workplace
        planDraft.preparedOn = isoDay(plan.firm.date)
        planDraft.validUntil = isoDay(plan.firm.validUntil)
        planDraft.team = plan.members.filter { !$0.backup }.prefix(200).map {
            NovaEmergencyMember(fullName: $0.name, role: role($0.roleId), contact: $0.contact.isEmpty ? nil : $0.contact)
        }
        // Only a filed (scanned and promoted) file may be attached; otherwise the plan is saved and the file stays in Dosyalarım.
        planDraft.assetID = entry.state.isFiled ? entry.assetID : nil
        _ = try await client.publish(company, planDraft)
    }
}
