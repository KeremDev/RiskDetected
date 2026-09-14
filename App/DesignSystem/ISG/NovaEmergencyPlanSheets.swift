import SwiftUI

/// One plan: the version that stands, and every version behind it with its own
/// team, dates and scope. Nothing here edits a published version.
struct NovaEmergencyDetailSheet: View {
    let plan: NovaEmergencyPlan
    var canWrite: Bool = true
    let onRenew: () -> Void
    let onClose: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: plan.scope, style: .screenTitle)
                        NovaText(text: [plan.workplaceName, plan.companyName]
                            .compactMap { $0 }.joined(separator: " · "), style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                        NovaText(text: NovaEmergencyWords.explain(plan), style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                    }
                    facts
                    team(plan.team, title: RDLocalization.string("localizable.nova.emergency.detail.team",
                        table: .localizable, fallback: "Ekip"))
                    if canWrite {
                        VStack(alignment: .leading, spacing: 8) {
                            NovaButton(label: RDLocalization.string("localizable.nova.emergency.detail.renew",
                                table: .localizable, fallback: "Yeni sürüm yayımla"),
                                symbol: "arrow.triangle.2.circlepath", variant: .primary, action: onRenew)
                            NovaText(text: NovaEmergencyWords.renewalNote, style: .meta,
                                color: NovaColorToken.textSecondary.color(in: scheme))
                        }
                    }
                    history
                }
                .padding(20).novaPopupContentSize()
            }
        }
        .accessibilityIdentifier("nova.emergency.detail")
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
            if plan.needsReview {
                NovaHelpHint(text: NovaEmergencyWords.reviewNote)
            } else if let note = plan.reviewNote, !note.isEmpty {
                NovaHelpHint(text: String(format: RDLocalization.string("localizable.nova.emergency.detail.basis",
                    table: .localizable, fallback: "Dayanak: %@"), note))
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
                            NovaText(text: "v\(version.version) · " + version.scope, style: .cardTitle)
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
    @State var draft: NovaEmergencyPlanDraft
    let catalogue: NovaEmergencyCatalogue?
    let onSave: (NovaEmergencyPlanDraft) async -> String?
    let onClose: () -> Void
    @State private var failure: String?
    @State private var saving = false
    @State private var choosingWorkplace = false
    @State private var memberName = ""
    @State private var memberRole: NovaEmergencyRole = .coordinator
    @State private var memberContact = ""
    @Environment(\.colorScheme) private var scheme

    private var workplaceTitle: String {
        catalogue?.workplaces.first { $0.id == draft.workplaceID }?.name
            ?? RDLocalization.string("localizable.nova.emergency.form.pickplace", table: .localizable,
                fallback: "İşyeri seçin")
    }

    var body: some View {
        NovaPopup {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    NovaText(text: draft.isRenewal
                        ? RDLocalization.string("localizable.nova.emergency.form.renew", table: .localizable,
                            fallback: "Yeni sürüm")
                        : RDLocalization.string("localizable.nova.emergency.form.new", table: .localizable,
                            fallback: "Plan yayımla"), style: .screenTitle)
                    if draft.isRenewal {
                        NovaHelpHint(text: NovaEmergencyWords.renewalNote)
                    }

                    // The workplace of a renewal is the plan's own and does not
                    // move, so it is shown rather than offered.
                    if draft.isRenewal {
                        NovaText(text: workplaceTitle, style: .label)
                    } else {
                        NovaFileChooserButton(
                            label: RDLocalization.string("localizable.nova.emergency.form.workplace",
                                table: .localizable, fallback: "İşyeri"),
                            value: workplaceTitle, isOpen: choosingWorkplace,
                            identifier: "nova.emergency.form.workplace") { choosingWorkplace.toggle() }
                        if choosingWorkplace {
                            NovaFileChooserPanel(
                                options: (catalogue?.workplaces ?? []).map { .init(id: $0.id.uuidString, title: $0.name) },
                                selected: draft.workplaceID?.uuidString,
                                identifier: "nova.emergency.form.workplace.panel") { value in
                                draft.workplaceID = value.flatMap(UUID.init(uuidString:))
                                choosingWorkplace = false
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: RDLocalization.string("localizable.nova.emergency.form.scope",
                            table: .localizable, fallback: "Kapsam"), style: .label)
                        TextField("", text: $draft.scope).textFieldStyle(.roundedBorder)
                            .preference(key: NovaPopupBusyKey.self, value: saving)
        .accessibilityIdentifier("nova.emergency.form.scope")
                    }
                    NovaDayField(label: RDLocalization.string("localizable.nova.emergency.row.prepared",
                        table: .localizable, fallback: "Hazırlanma"),
                        value: $draft.preparedOn, identifier: "nova.emergency.form.prepared")
                    NovaDayField(label: RDLocalization.string("localizable.nova.emergency.row.until",
                        table: .localizable, fallback: "Geçerlilik"),
                        value: $draft.validUntil, identifier: "nova.emergency.form.until", isClearable: true)
                    NovaHelpHint(text: NovaEmergencyWords.periodAttribution)

                    teamEditor

                    VStack(alignment: .leading, spacing: 4) {
                        NovaText(text: RDLocalization.string("localizable.nova.emergency.form.basis",
                            table: .localizable, fallback: "Dayanak"), style: .label)
                        TextField("", text: $draft.reviewNote).textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("nova.emergency.form.basis")
                        NovaText(text: NovaEmergencyWords.reviewNote, style: .meta,
                            color: NovaColorToken.textSecondary.color(in: scheme))
                    }

                    if let failure {
                        NovaText(text: failure, style: .meta,
                            color: NovaColorToken.statusDangerInk.color(in: scheme))
                    }
                    HStack(spacing: 10) {
                        NovaButton(label: RDLocalization.string("localizable.nova.emergency.cancel",
                            table: .localizable, fallback: "Vazgeç"), symbol: "xmark",
                            variant: .surface, action: onClose).disabled(saving)
                        NovaButton(label: RDLocalization.string("localizable.nova.emergency.form.save",
                            table: .localizable, fallback: "Yayımla"), symbol: "checkmark.seal",
                            variant: .primary) {
                            Task { saving = true; failure = await onSave(draft); saving = false }
                        }
                        .disabled(saving || draft.team.isEmpty || draft.workplaceID == nil)
                    }
                }
                .padding(20).novaPopupContentSize()
            }
        }
        .accessibilityIdentifier("nova.emergency.form")
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
            ForEach(draft.team) { member in
                HStack(spacing: 6) {
                    Image(systemName: member.role.symbol).font(.system(size: 11, weight: .semibold))
                    NovaText(text: member.fullName + " · " + member.role.title, style: .meta)
                    Spacer(minLength: 0)
                    Button { draft.team.removeAll { $0.id == member.id } } label: {
                        Image(systemName: "xmark.circle").font(.system(size: 12))
                    }.buttonStyle(.plain)
                }
            }
            TextField(RDLocalization.string("localizable.nova.emergency.form.name",
                table: .localizable, fallback: "Ad soyad"), text: $memberName)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("nova.emergency.form.name")
            // Only the roles the schema knows, so the snapshot cannot carry one
            // the server would refuse.
            HStack(spacing: 6) {
                ForEach(catalogue?.roles ?? NovaEmergencyRole.allCases) { role in
                    Button { memberRole = role } label: {
                        NovaSizedText(text: role.title, size: 10.5,
                            weight: memberRole == role ? "Bold" : "Medium",
                            color: memberRole == role
                                ? NovaColorToken.accentInk.color(in: scheme)
                                : NovaColorToken.textSecondary.color(in: scheme))
                            .padding(.vertical, 5).padding(.horizontal, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .strokeBorder(NovaColorToken.hairline.color(in: scheme), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("nova.emergency.form.role.\(role.rawValue)")
                }
            }
            TextField(RDLocalization.string("localizable.nova.emergency.form.contact",
                table: .localizable, fallback: "İletişim (isteğe bağlı)"), text: $memberContact)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("nova.emergency.form.contact")
            NovaButton(label: RDLocalization.string("localizable.nova.emergency.form.addmember",
                table: .localizable, fallback: "Ekibe ekle"), symbol: "person.badge.plus", variant: .surface) {
                let name = memberName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty, draft.team.count < 200 else { return }
                let contact = memberContact.trimmingCharacters(in: .whitespacesAndNewlines)
                draft.team.append(.init(fullName: name, role: memberRole,
                                        contact: contact.isEmpty ? nil : contact))
                memberName = ""; memberContact = ""
            }
        }
    }
}
