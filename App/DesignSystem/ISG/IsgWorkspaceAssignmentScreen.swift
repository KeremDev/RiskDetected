import SwiftUI

/// Company-to-expert assignment management for the OSGB workspace. Membership
/// and company access remain separate: an invited expert receives no company
/// data until a manager creates an effective assignment here.
struct IsgWorkspaceAssignmentManagement: View {
    @ObservedObject var store: IsgWorkspaceStore
    let company: IsgWorkspaceCompany
    @State private var members: [IsgWorkspaceMember] = []
    @State private var assignments: [IsgWorkspaceCompanyAssignment] = []
    @State private var membershipID: UUID?
    @State private var assignmentRole = "support"
    @State private var startsAt = Date()
    @State private var hasEnd = false
    @State private var endsAt = Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date()
    @State private var reason = ""
    @State private var ending: IsgWorkspaceCompanyAssignment?
    @State private var loading = true
    @State private var working = false
    @State private var error: String?
    @State private var mutationAttempt = IsgWorkspaceMutationAttempt()
    @State private var detailsExpanded = true
    @Environment(\.novaCelebrate) private var celebrate

    private var experts: [IsgWorkspaceMember] {
        members.filter { $0.status == "active" && $0.isPracticingExpert }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                NovaPopupHeading(text: label("localizable.nova.workspace.assignment.title", "Firma uzmanları"),
                                 symbol: "person.2.badge.gearshape")
                NovaHelpHint(text: String(format: label(
                    "localizable.nova.workspace.assignment.hint",
                    "%@ firmasında işlem yapabilecek uzmanları ve görev sürelerini yönetin."), company.name))
                stats
                if loading {
                    NovaLoadingView(message: label("localizable.nova.workspace.assignment.loading", "Atamalar yükleniyor…"))
                } else {
                    createForm
                    assignmentList
                }
                if let error { NovaHelpHint(text: error) }
            }.padding(18).padding(.bottom, 24).novaPopupContentSize()
        }
        .scrollDismissesKeyboard(.interactively)
        .task { await load() }
        .novaPopup(item: $ending, onDismiss: { Task { await load() } }) { assignment in
            IsgWorkspaceAssignmentEndEditor(store: store, assignment: assignment) { ending = nil }
        }
    }

    private var stats: some View {
        HStack(spacing: 8) {
            NovaListStat(title: label("localizable.nova.workspace.assignment.current", "Aktif"),
                         symbol: "person.badge.checkmark", value: String(assignments.filter(isCurrent).count))
            NovaListStat(title: label("localizable.nova.workspace.assignment.future", "Planlı"),
                         symbol: "calendar.badge.clock", value: String(assignments.filter(isFuture).count))
            NovaListStat(title: label("localizable.nova.workspace.assignment.ended", "Sona eren"),
                         symbol: "clock.arrow.circlepath", value: String(assignments.filter { $0.periodState() == .ended }.count))
        }
    }

    private var createForm: some View {
        NovaCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) { detailsExpanded.toggle() }
                } label: {
                    HStack {
                        NovaText(text: label("localizable.nova.workspace.assignment.add", "Uzman ata"), style: .bodyStrong)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.down").rotationEffect(.degrees(detailsExpanded ? 180 : 0))
                    }.frame(minHeight: 38).contentShape(Rectangle())
                }.buttonStyle(NovaRowPressStyle())
                if detailsExpanded {
                    if experts.isEmpty {
                        NovaHelpHint(text: label("localizable.nova.workspace.assignment.no.expert",
                            "Önce aktif ve operasyon yapabilen bir uzmanı çalışma alanına davet edin."))
                    } else {
                        expertMenu
                        Picker(label("localizable.nova.workspace.assignment.role", "Atama rolü"), selection: $assignmentRole) {
                            Text(label("localizable.nova.workspace.assignment.support", "Destek uzmanı")).tag("support")
                            Text(label("localizable.nova.workspace.assignment.primary", "Birincil uzman")).tag("primary")
                        }.pickerStyle(.segmented)
                        HStack(spacing: 8) {
                            DatePicker(label("localizable.nova.workspace.assignment.starts", "Başlangıç"), selection: $startsAt,
                                       displayedComponents: [.date, .hourAndMinute])
                                .labelsHidden().frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10).novaControlBackground(cornerRadius: 14)
                            Toggle(label("localizable.nova.workspace.assignment.has.end", "Bitiş"), isOn: $hasEnd)
                                .labelsHidden().frame(width: 62, height: 42).novaControlBackground(cornerRadius: 14)
                        }
                        if hasEnd {
                            DatePicker(label("localizable.nova.workspace.assignment.ends", "Bitiş"), selection: $endsAt,
                                       in: startsAt..., displayedComponents: [.date, .hourAndMinute])
                                .padding(10).novaControlBackground(cornerRadius: 14)
                        }
                        TextField(label("localizable.nova.workspace.assignment.reason", "Atama nedeni"), text: $reason,
                                  axis: .vertical).lineLimit(2...3)
                            .padding(10).novaControlBackground(cornerRadius: 14)
                        NovaCompactActionButton(title: working
                            ? label("localizable.nova.workspace.saving", "Kaydediliyor…")
                            : label("localizable.nova.workspace.assignment.save", "Atamayı kaydet"),
                            symbol: "checkmark", prominent: true, enabled: canSave && !working) { create() }
                    }
                }
            }
        }
    }

    private var expertMenu: some View {
        Menu {
            ForEach(experts, id: \.id) { member in
                Button { membershipID = member.id } label: {
                    HStack {
                        Text(memberLabel(member))
                        if membershipID == member.id { Image(systemName: "checkmark") }
                    }
                }
            }
        } label: {
            HStack(spacing: 9) {
                NovaIcon(symbol: "person.badge.shield.checkmark", size: 17)
                VStack(alignment: .leading, spacing: 2) {
                    NovaText(text: label("localizable.nova.workspace.assignment.expert", "Uzman"), style: .metaQuiet)
                    NovaText(text: membershipID.flatMap { id in experts.first { $0.id == id }.map(memberLabel) }
                        ?? label("localizable.nova.workspace.assignment.expert.pick", "Uzman seçin"), style: .body)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 11, weight: .semibold))
            }.padding(.horizontal, 10).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .novaControlBackground(cornerRadius: 14)
        }.buttonStyle(NovaRowPressStyle())
    }

    @ViewBuilder private var assignmentList: some View {
        if assignments.isEmpty {
            NovaEmptyState(title: label("localizable.nova.workspace.assignment.empty", "Henüz uzman ataması yok"),
                message: label("localizable.nova.workspace.assignment.empty.detail",
                    "Uzman atadığınızda firma operasyonlarına erişim başlangıç ve bitiş tarihine göre açılır."))
        } else {
            ForEach(assignments) { assignment in
                NovaCard(padding: 12) {
                    HStack(alignment: .top, spacing: 10) {
                        NovaIcon(symbol: assignment.assignmentRole == "primary" ? "person.badge.shield.checkmark" : "person.2", size: 19)
                        VStack(alignment: .leading, spacing: 3) {
                            NovaText(text: assignmentLabel(assignment), style: .bodyStrong)
                            NovaText(text: roleLabel(assignment.assignmentRole), style: .metaQuiet)
                            NovaText(text: interval(assignment), style: .metaQuiet)
                            if assignment.periodState() != .ended {
                                NovaStatusPill(label: isFuture(assignment)
                                    ? label("localizable.nova.workspace.assignment.future", "Planlı")
                                    : label("localizable.nova.workspace.assignment.current", "Aktif"), status: .neutral)
                            }
                        }
                        Spacer(minLength: 0)
                        if assignment.periodState() != .ended {
                            Button { ending = assignment } label: {
                                Image(systemName: "stop.circle").frame(width: 44, height: 44)
                            }.buttonStyle(NovaRowPressStyle())
                                .accessibilityLabel(label("localizable.nova.workspace.assignment.end", "Atamayı bitir"))
                        } else {
                            NovaStatusPill(label: label("localizable.nova.workspace.assignment.ended", "Sona eren"), status: .neutral)
                        }
                    }
                }
            }
        }
    }

    private var canSave: Bool {
        membershipID != nil && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (!hasEnd || endsAt > startsAt)
    }

    private func create() {
        guard let membershipID, canSave else { return }
        let starts = Self.instant(startsAt)
        let ends = hasEnd ? Self.instant(endsAt) : nil
        var attempt = mutationAttempt
        let mutationID = attempt.id(namespace: "assignment.create", components: [company.id.uuidString,
            membershipID.uuidString, assignmentRole, starts, ends ?? "", reason])
        mutationAttempt = attempt
        working = true; error = nil
        Task { @MainActor in
            do {
                _ = try await store.mutateAssignment(mutationID: mutationID, companyID: company.id,
                    action: "create", membershipID: membershipID, role: assignmentRole,
                    startsAt: starts, endsAt: ends,
                    reason: reason)
                celebrate(NovaSuccessMessage.recordSaved(label(
                    "localizable.nova.workspace.assignment.record", "Uzman ataması")))
                reason = ""; hasEnd = false
                await load()
            } catch {
                self.error = label("localizable.nova.workspace.mutation.failed",
                    "İşlem tamamlanamadı. Bilgileri kontrol edip yeniden deneyin.")
            }
            working = false
        }
    }

    @MainActor private func load() async {
        loading = true; error = nil
        do {
            async let memberRows = store.members(status: "active")
            async let assignmentRows = store.assignments(companyID: company.id)
            (members, assignments) = try await (memberRows, assignmentRows)
            if membershipID == nil { membershipID = experts.first?.id }
        } catch {
            self.error = label("localizable.nova.workspace.connection.retry",
                "Bağlantınızı kontrol edip yeniden deneyin.")
        }
        loading = false
    }

    private func memberLabel(_ member: IsgWorkspaceMember) -> String {
        let identity = member.userID ?? member.id
        return roleLabel(member.role) + " · " + String(identity.uuidString.prefix(8))
    }
    private func assignmentLabel(_ assignment: IsgWorkspaceCompanyAssignment) -> String {
        if let member = members.first(where: { $0.id == assignment.membershipID }) { return memberLabel(member) }
        return label("localizable.nova.workspace.assignment.expert", "Uzman") + " · " +
            String(assignment.membershipID.uuidString.prefix(8))
    }
    private func roleLabel(_ role: String) -> String {
        switch role {
        case "primary": return label("localizable.nova.workspace.assignment.primary", "Birincil uzman")
        case "support": return label("localizable.nova.workspace.assignment.support", "Destek uzmanı")
        case "owner": return label("localizable.nova.workspace.role.owner", "OSGB sahibi")
        case "admin": return label("localizable.nova.workspace.role.admin", "OSGB yöneticisi")
        default: return label("localizable.nova.workspace.role.expert", "İSG uzmanı")
        }
    }
    private func interval(_ assignment: IsgWorkspaceCompanyAssignment) -> String {
        String(assignment.startsAt.prefix(10)) + " → " + (assignment.endsAt.map { String($0.prefix(10)) } ?? "∞")
    }
    private func isCurrent(_ assignment: IsgWorkspaceCompanyAssignment) -> Bool {
        assignment.periodState() == .current
    }
    private func isFuture(_ assignment: IsgWorkspaceCompanyAssignment) -> Bool {
        assignment.periodState() == .future
    }
    private func label(_ key: String, _ fallback: String) -> String {
        RDLocalization.string(key, table: .localizable, fallback: fallback)
    }
    private static func instant(_ date: Date) -> String { ISO8601DateFormatter().string(from: date) }
}

private struct IsgWorkspaceAssignmentEndEditor: View {
    @ObservedObject var store: IsgWorkspaceStore
    let assignment: IsgWorkspaceCompanyAssignment
    let onDone: () -> Void
    @State private var reason = ""
    @State private var working = false
    @State private var error: String?
    @State private var requestedEndAt: String?
    @State private var mutationAttempt = IsgWorkspaceMutationAttempt()
    @Environment(\.novaCelebrate) private var celebrate

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            NovaPopupHeading(text: label("localizable.nova.workspace.assignment.end", "Atamayı bitir"),
                             symbol: "stop.circle")
            NovaHelpHint(text: label("localizable.nova.workspace.assignment.end.hint",
                "Firma erişimi işlem tamamlandığında kesilir; geçmiş kayıtların yazarı değişmez."))
            TextField(label("localizable.nova.workspace.assignment.end.reason", "Sonlandırma nedeni"),
                      text: $reason, axis: .vertical).lineLimit(2...4)
                .padding(12).novaControlBackground(cornerRadius: 14)
            if let error { NovaHelpHint(text: error) }
            NovaCompactActionButton(title: working
                ? label("localizable.nova.workspace.saving", "Kaydediliyor…")
                : label("localizable.nova.workspace.assignment.end", "Atamayı bitir"),
                symbol: "checkmark", prominent: true,
                enabled: !working && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) { save() }
        }.padding(18).novaPopupContentSize()
    }

    private func save() {
        let ending = requestedEndAt ?? ISO8601DateFormatter().string(from: Date())
        requestedEndAt = ending
        var attempt = mutationAttempt
        let mutationID = attempt.id(namespace: "assignment.end", components: [assignment.id.uuidString,
            String(assignment.version), ending, reason])
        mutationAttempt = attempt
        working = true; error = nil
        Task { @MainActor in
            do {
                _ = try await store.mutateAssignment(mutationID: mutationID, companyID: assignment.companyID,
                    action: "end", assignmentID: assignment.id, expectedVersion: assignment.version,
                    endsAt: ending, reason: reason)
                celebrate(NovaSuccessMessage.recordSaved(label(
                    "localizable.nova.workspace.assignment.record", "Uzman ataması")))
                onDone()
            } catch {
                self.error = label("localizable.nova.workspace.mutation.failed",
                    "İşlem tamamlanamadı. Bilgileri kontrol edip yeniden deneyin.")
            }
            working = false
        }
    }

    private func label(_ key: String, _ fallback: String) -> String {
        RDLocalization.string(key, table: .localizable, fallback: fallback)
    }
}
