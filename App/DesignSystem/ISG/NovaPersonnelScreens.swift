import SwiftUI

/// Direct company-page entry keeps the same pending-operation gate as the personnel list.
struct NovaPersonnelCreateSheet: View {
    let scope: NovaPersonnelScope
    let companyName: String
    let client: NovaPersonnelClient
    @Environment(\.dismiss) private var dismiss
    @State private var checked = false
    @State private var blocked = false
    var body: some View {
        NovaPageSurface {
            if checked && !blocked {
                NovaEmployeeEditor(scope: scope, companyName: companyName, client: client, original: nil,
                    onBack: { dismiss() }, onSaved: { _ in dismiss() })
            } else {
                VStack(alignment: .leading, spacing: 14) {
                    NovaPageHeading(title: RDLocalization.string("localizable.nova.personnel.screens.personel.ekle.565c83dd", table: .localizable, fallback: "Personel Ekle"), onBack: { dismiss() })
                    if checked {
                        NovaHelpHint(text: RDLocalization.string("localizable.nova.personnel.error.pending.unverified", table: .localizable, fallback: "Bekleyen işlem doğrulanamadı. Yeni kayıt açmadan tekrar kontrol edin."))
                    } else { ProgressView() }
                }.padding(18)
            }
        }.task {
            do {
                let pending = try await client.pending(scope)
                try Task.checkCancellation()
                blocked = pending != nil; checked = true
            } catch { if !Task.isCancelled { blocked = true; checked = true } }
        }
    }
}

/// Scope identity owns all list, search, form and pending-request state.
struct NovaPersonnelDestination: View {
    let scope: NovaPersonnelScope
    let companyName: String
    let client: NovaPersonnelClient
    let onBack: () -> Void
    var directory: NovaDirectoryClient? = nil
    var canWrite = true
    /// Preview mode is used in the company accordion: five rows and a Tümü action.
    var preview = false
    var onShowAll: (() -> Void)? = nil
    /// Opened straight onto one employee — the row that sent us here already
    /// knew who, no need to make the expert find them again in the list.
    var initialEmployee: UUID? = nil
    var body: some View { PersonnelContent(scope: scope, companyName: companyName, client: client, onBack: onBack, directory: directory, canWrite: canWrite, preview: preview, onShowAll: onShowAll, initialEmployee: initialEmployee).id(scope).id(canWrite).id(preview) }
}

private struct PersonnelContent: View {
    let scope: NovaPersonnelScope
    let companyName: String
    let client: NovaPersonnelClient
    let onBack: () -> Void
    let directory: NovaDirectoryClient?
    let canWrite: Bool
    let preview: Bool
    let onShowAll: (() -> Void)?
    var initialEmployee: UUID? = nil
    @Environment(\.colorScheme) private var scheme
    @State private var rows: [NovaEmployeeRow] = []
    @State private var query = ""
    @State private var archived = false
    @State private var next: UUID?
    @State private var loading = false
    @State private var error: String?
    @State private var route: Route
    @State private var generation = UUID()
    @State private var requestedPage: UUID?
    @State private var pending: NovaEmployeeIntent?
    @State private var pendingChecked = false
    @State private var reconciling = false
    @State private var showingCreate = false
    private enum Route: Equatable { case list, create, detail(UUID), edit(NovaEmployeeRow), archive(NovaEmployeeRow), advanced(UUID, NovaDirectoryKind) }
    private struct Key: Equatable { let query: String; let archived: Bool; let generation: UUID; let page: UUID? }
    init(scope: NovaPersonnelScope, companyName: String, client: NovaPersonnelClient, onBack: @escaping () -> Void,
         directory: NovaDirectoryClient?, canWrite: Bool, preview: Bool, onShowAll: (() -> Void)?, initialEmployee: UUID? = nil) {
        self.scope = scope; self.companyName = companyName; self.client = client; self.onBack = onBack
        self.directory = directory; self.canWrite = canWrite; self.preview = preview; self.onShowAll = onShowAll
        self.initialEmployee = initialEmployee
        _route = State(initialValue: initialEmployee.map { .detail($0) } ?? .list)
    }
    private var edgeBack: (() -> Void)? {
        switch route {
        case .list:
            return onBack
        case .detail:
            return { route = .list }
        case .advanced(let id, _):
            return { route = .detail(id) }
        case .create, .edit, .archive:
            return nil
        }
    }
    var body: some View {
        NovaPageSurface(onEdgeBack: edgeBack) {
            switch route {
            case .list: list
            case .create:
                NovaEmployeeEditor(scope: scope, companyName: companyName, client: client, original: nil,
                    onBack: { route = .list }, onSaved: { row in requestedPage = nil; generation = UUID(); route = .detail(row.id) })
            case .edit(let row):
                NovaEmployeeEditor(scope: scope, companyName: companyName, client: client, original: row,
                    onBack: { route = .detail(row.id) }, onSaved: { row in requestedPage = nil; generation = UUID(); route = row.isArchived ? .list : .detail(row.id) })
                    .id("edit-\(row.id)-\(row.version)")
            case .detail(let id):
                NovaEmployeeDetail(scope: scope, employeeID: id, client: client,
                    companyName: companyName, onBack: { route = .list }, onEdit: { route = .edit($0) }, onArchive: { route = .archive($0) }, canWrite: canWrite,
                    onDirectory: directory == nil ? nil : { route = .advanced(id, $0) })
            case .archive(let row):
                NovaEmployeeEditor(scope: scope, companyName: companyName, client: client, original: row,
                    onBack: { route = .detail(row.id) }, onSaved: { _ in requestedPage = nil; generation = UUID(); route = .list },
                    archiveOnOpen: true)
                    .id("archive-\(row.id)-\(row.version)")
            case .advanced(let id, let kind):
                if let directory {
                    NovaDirectoryDestination(scope: scope, kind: kind, parent: id, client: directory,
                        onBack: { route = .detail(id) }, canWrite: canWrite)
                }
            }
        }
        .novaFullScreenCover(isPresented: $showingCreate) {
            NovaPopup {
            NavigationStack {
                NovaPageSurface {
                    NovaEmployeeEditor(scope: scope, companyName: companyName, client: client, original: nil,
                        onBack: { showingCreate = false }, onSaved: { row in
                            showingCreate = false; requestedPage = nil; generation = UUID(); route = .detail(row.id)
                        })
                }
            }
            }
        }
    }
    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                PersonnelHeading(title: "Personeller", subtitle: companyName,
                    trailingTitle: "Ekle", trailingAction: { showingCreate = true }, onBack: onBack)
                NovaCard(padding: 14) {
                    HStack { NovaIcon(symbol: "magnifyingglass", size: 18); TextField(RDLocalization.string("localizable.nova.personnel.screens.personel.ara.6695c740", table: .localizable, fallback: "Personel ara…"), text: $query).font(NovaFont.font(.body)).accessibilityIdentifier("personnel.search") }
                }
                HStack(spacing: 8) {
                    NovaIcon(symbol: "archivebox", size: 13)
                    NovaText(text: RDLocalization.string("localizable.nova.personnel.screens.arsivdekileri.de.goster.1c9e4bc7", table: .localizable, fallback: "Arşivdekileri de göster"), style: .metaQuiet)
                    Spacer()
                    Toggle("", isOn: $archived).labelsHidden().scaleEffect(0.72).frame(width: 42, height: 24)
                }.frame(minHeight: 28).accessibilityElement(children: .combine).accessibilityIdentifier("personnel.archived")
                if let pending {
                    NovaCard(padding: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { NovaIcon(symbol: "arrow.clockwise", size: 22); NovaText(text: RDLocalization.string("localizable.nova.personnel.screens.bekleyen.personel.islemi.f9de31cd", table: .localizable, fallback: "Bekleyen personel işlemi"), style: .cardTitle).accessibilityIdentifier("personnel.pending") }
                            NovaText(text: RDLocalization.string("localizable.nova.personnel.screens.onceki.islemin.sonucu.henuz.kesinlesmedi.ayni.is.792fe10f", table: .localizable, fallback: "Önceki işlemin sonucu henüz kesinleşmedi. Aynı işlem anahtarıyla kontrol ederek devam edin."))
                            NovaText(text: pending.name.isEmpty ? RDLocalization.string("localizable.nova.personnel.archiving.operation", table: .localizable, fallback: "Arşivleme işlemi") : pending.name, style: .metaQuiet)
                            NovaButton(label: RDLocalization.string("localizable.nova.personnel.screens.bekleyen.islemi.tamamla.c7e7dd9b", table: .localizable, fallback: "Bekleyen işlemi tamamla"), symbol: "arrow.clockwise", isEnabled: canWrite, isLoading: reconciling, action: { reconciling = true })
                                .accessibilityIdentifier("personnel.recover")
                        }
                    }
                }
                if !canWrite { NovaText(text: RDLocalization.string("localizable.nova.personnel.screens.salt.okunur.yeni.kayit.ve.duzenleme.kullanilamiy.7c6bdf36", table: .localizable, fallback: "Salt okunur · yeni kayıt ve düzenleme kullanılamıyor."), style: .metaQuiet) }
                if let error { NovaCard(padding: 16) { NovaText(text: error); NovaButton(label: RDLocalization.string("localizable.nova.personnel.screens.tekrar.dene.c2d238eb", table: .localizable, fallback: "Tekrar dene"), symbol: "arrow.clockwise", variant: .surface, action: { generation = UUID() }) } }
                if !loading && error == nil && rows.isEmpty {
                    NovaEmptyState(title: RDLocalization.string("localizable.nova.personnel.screens.henuz.personel.yok.d4c4f866", table: .localizable, fallback: "Henüz personel yok."),
                        message: RDLocalization.string("localizable.nova.personnel.empty.detail", table: .localizable,
                            fallback: "Firma personelini ekleyerek eğitim, ekip, zimmet ve diğer İSG kayıtlarında doğrudan seçim yapabilirsiniz."))
                }
                ForEach(preview ? Array(rows.prefix(5)) : rows) { row in
                    Button { route = .detail(row.id) } label: {
                        NovaCard(padding: 16) {
                            HStack(spacing: 12) {
                                NovaIcon(symbol: "person", size: 24)
                                VStack(alignment: .leading, spacing: 5) {
                                    NovaText(text: row.name, style: .cardTitle)
                                    NovaText(text: [row.departmentName, row.jobTitle].compactMap { $0 }.joined(separator: " · ").isEmpty ? RDLocalization.string("localizable.nova.personnel.no.department.selected", table: .localizable, fallback: "Departman seçilmedi") : [row.departmentName, row.jobTitle].compactMap { $0 }.joined(separator: " · "), style: .metaQuiet)
                                    if row.isArchived { NovaText(text: RDLocalization.string("localizable.nova.personnel.screens.arsivde.b15e4fa0", table: .localizable, fallback: "Arşivde"), style: .metaQuiet) }
                                }
                                Spacer(); NovaIcon(symbol: "chevron.right", size: 16)
                            }
                        }
                    }.buttonStyle(NovaRowPressStyle()).disabled(pending != nil || reconciling).accessibilityIdentifier("personnel.row.\(row.id.uuidString.lowercased())")
                }
                if loading { ProgressView().frame(maxWidth: .infinity).accessibilityIdentifier("personnel.loading") }
                if preview, (!rows.isEmpty || next != nil), let onShowAll {
                    Button(action: onShowAll) {
                        HStack { NovaText(text: RDLocalization.string("localizable.nova.personnel.see.all", table: .localizable, fallback: "Tümünü gör"), style: .meta, color: NovaColorToken.accentInk.color(in: scheme)); Spacer(); NovaIcon(symbol: "chevron.right", size: 13) }
                            .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                    }.buttonStyle(NovaRowPressStyle()).accessibilityIdentifier("personnel.show.all")
                } else if let next, !loading {
                    NovaButton(label: RDLocalization.string("localizable.nova.personnel.screens.daha.fazla.goster.3e8d6c6b", table: .localizable, fallback: "Daha fazla göster"), symbol: "chevron.down", variant: .surface, action: { requestedPage = next })
                }
            }.padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 24)
                .novaPopupContentSize()
        }
        .task(id: Key(query: query, archived: archived, generation: generation, page: requestedPage)) {
            let requestedQuery = query, requestedArchive = archived, page = requestedPage
            loading = true; error = nil; pendingChecked = false
            if page == nil { rows = []; next = nil }
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
                let recovered = try await client.pending(scope); try Task.checkCancellation()
                guard recovered == nil || recovered?.scope == scope else { throw NovaPersonnelFailure.unavailable }
                pending = recovered; pendingChecked = true
                let result = try await client.employees(scope, requestedQuery, requestedArchive, page)
                try Task.checkCancellation()
                guard result.rows.count <= 50, result.rows.allSatisfy({ $0.ownerID == scope.ownerID && $0.companyID == scope.companyID && (requestedArchive || !$0.isArchived) }),
                      Set(result.rows.map(\.id)).count == result.rows.count,
                      result.next == nil || result.next == result.rows.last?.id else { throw NovaPersonnelFailure.unavailable }
                rows = page == nil ? result.rows : rows + result.rows.filter { item in !rows.contains(where: { $0.id == item.id }) }
                next = result.next; loading = false
            } catch { if !Task.isCancelled { self.error = RDLocalization.string("localizable.nova.personnel.error.not.loaded", table: .localizable, fallback: "Personeller yüklenemedi. Lütfen tekrar deneyin."); loading = false } }
        }
        .task(id: reconciling) {
            guard canWrite, reconciling, let intent = pending else { return }
            do {
                let result = try await client.save(intent); try Task.checkCancellation()
                guard result.ownerID == scope.ownerID, result.companyID == scope.companyID, result.operationID == intent.operationID,
                      intent.employeeID == nil || intent.employeeID == result.id,
                      result.version == (intent.action == .create ? 0 : intent.expectedVersion + 1), result.isArchived == (intent.action == .archive) else { throw NovaPersonnelFailure.unavailable }
                pending = nil; reconciling = false; requestedPage = nil; generation = UUID()
                route = result.isArchived ? .list : .detail(result.id)
            } catch {
                if !Task.isCancelled { reconciling = false; self.error = RDLocalization.string("localizable.nova.personnel.error.pending.unverified", table: .localizable, fallback: "Bekleyen işlem doğrulanamadı. Yeni kayıt açmadan tekrar kontrol edin."); generation = UUID() }
            }
        }
        .onChange(of: query) { _ in requestedPage = nil }
        .onChange(of: archived) { _ in requestedPage = nil }
    }
}

private struct PersonnelHeading: View {
    let title: String
    var subtitle: String = ""
    var isBackEnabled = true
    var backIdentifier = "personnel.back"
    var trailingTitle: String? = nil
    var trailingAction: (() -> Void)? = nil
    let onBack: () -> Void
    @Environment(\.isNovaPopup) private var isNovaPopup
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 12) {
            if !isNovaPopup { NovaBackButton(isEnabled: isBackEnabled, action: onBack).accessibilityIdentifier(backIdentifier) }
            VStack(alignment: .leading, spacing: 4) { NovaText(text: title, style: .screenTitle); if !subtitle.isEmpty { HStack(spacing: 6) { NovaIcon(symbol: "building.2", size: 13); NovaText(text: subtitle, style: .metaQuiet) } } }
            Spacer(minLength: 0)
            if let trailingAction {
                Button(action: trailingAction) {
                    HStack(spacing: 4) { Image(systemName: "plus").font(.system(size: 11, weight: .medium)); NovaSizedText(text: trailingTitle ?? "Ekle", size: 11.5, weight: "Medium") }
                        .padding(.horizontal, 15).frame(minWidth: 108, minHeight: 32)
                        .foregroundStyle(NovaColorToken.onAccent.color(in: scheme))
                }.buttonStyle(NovaRowPressStyle()).disabled(!isBackEnabled).accessibilityIdentifier("personnel.add")
            }
        }
    }
}

private struct NovaEmployeeDetail: View {
    let scope: NovaPersonnelScope
    let employeeID: UUID
    let client: NovaPersonnelClient
    let companyName: String
    let onBack: () -> Void
    let onEdit: (NovaEmployeeRow) -> Void
    let onArchive: (NovaEmployeeRow) -> Void
    let canWrite: Bool
    let onDirectory: ((NovaDirectoryKind) -> Void)?
    @State private var row: NovaEmployeeRow?
    @State private var error = false
    @State private var refresh = UUID()
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PersonnelHeading(title: RDLocalization.string("localizable.nova.personnel.screens.personel.detayi.93b8adba", table: .localizable, fallback: "Personel Detayı"), onBack: onBack)
                if let row {
                    NovaCard(padding: 16) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(spacing: 8) {
                                NovaIcon(symbol: "person", size: 23)
                                NovaSizedText(text: row.name, size: 16, weight: "Bold")
                                Spacer(minLength: 0)
                                Circle().fill(row.isArchived ? NovaColorToken.statusDangerDot.color(in: scheme) : NovaColorToken.statusSuccessDot.color(in: scheme)).frame(width: 9, height: 9)
                            }
                            let placement = [row.departmentName, row.jobTitle].compactMap { $0 }.joined(separator: " · ")
                            HStack(spacing: 7) { NovaIcon(symbol: "building.2", size: 18); NovaText(text: placement.isEmpty ? RDLocalization.string("localizable.nova.personnel.no.department.selected", table: .localizable, fallback: "Departman seçilmedi") : placement, style: .metaQuiet) }
                            HStack(spacing: 7) { NovaIcon(symbol: "building.2", size: 15).foregroundStyle(NovaColorToken.accentInk.color(in: scheme)); NovaText(text: companyName, style: .metaQuiet) }

                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.accessibilityIdentifier("personnel.detail")
                    NovaEmployeeLearningCard(identity: .init(userID: scope.ownerID, sessionID: scope.sessionID), company: scope.companyID, employee: employeeID, canWrite: canWrite && !row.isArchived)
                    if canWrite { NovaButton(label: row.isArchived ? RDLocalization.string("localizable.nova.personnel.reactivate", table: .localizable, fallback: "Yeniden etkinleştir") : RDLocalization.string("localizable.nova.personnel.edit", table: .localizable, fallback: "Düzenle"), symbol: row.isArchived ? "arrow.uturn.backward" : "pencil", action: { onEdit(row) }).accessibilityIdentifier(row.isArchived ? "personnel.restore" : "personnel.edit") }
                    if let onDirectory {
                        NovaButton(label: RDLocalization.string("localizable.nova.personnel.screens.gorevlendirme.gecmisi.b56428ce", table: .localizable, fallback: "Görevlendirme geçmişi"), symbol: "clock.arrow.circlepath", variant: .surface) { onDirectory(.assignments) }.accessibilityIdentifier("personnel.assignments")
                        NovaButton(label: RDLocalization.string("localizable.nova.personnel.screens.isveren.iliskisi.9ad2bc6f", table: .localizable, fallback: "İşveren ilişkisi"), symbol: "building.2", variant: .surface) { onDirectory(.employers) }.accessibilityIdentifier("personnel.employers")
                    }
                    if canWrite && !row.isArchived {
                        NovaButton(label: RDLocalization.string("localizable.nova.personnel.screens.personeli.arsivle.715aa012", table: .localizable, fallback: "Personeli arşivle"), symbol: "trash", variant: .danger) { onArchive(row) }
                            .accessibilityIdentifier("personnel.detail.archive")
                    }
                } else if error { NovaText(text: RDLocalization.string("localizable.nova.personnel.screens.personel.yuklenemedi.9398cf6a", table: .localizable, fallback: "Personel yüklenemedi.")); NovaButton(label: RDLocalization.string("localizable.nova.personnel.screens.tekrar.dene.d6e62bf1", table: .localizable, fallback: "Tekrar dene"), symbol: "arrow.clockwise", action: { refresh = UUID() }) }
                else { ProgressView() }
            }.padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 18)
                .novaPopupContentSize()
        }.task(id: refresh) {
            row = nil; error = false
            do {
                let result = try await client.detail(scope, employeeID); try Task.checkCancellation()
                guard result.id == employeeID, result.companyID == scope.companyID, result.ownerID == scope.ownerID else { throw NovaPersonnelFailure.denied }
                row = result
            } catch { if !Task.isCancelled { self.error = true } }
        }
    }
    private func employeeTag(_ symbol: String, _ title: String, tone: NovaColorToken) -> some View {
        HStack(spacing: 3) { NovaIcon(symbol: symbol, size: 12); NovaText(text: title, style: .micro, color: tone.color(in: scheme)) }
            .accessibilityLabel(title)
    }
}

private struct NovaEmployeeEditor: View {
    let scope: NovaPersonnelScope
    let companyName: String
    let client: NovaPersonnelClient
    let original: NovaEmployeeRow?
    let onBack: () -> Void
    let onSaved: (NovaEmployeeCommit) -> Void
    var archiveOnOpen = false
    @State private var state = NovaEmployeeEditorState()
    @State private var departments: [NovaDepartmentRow] = []
    @State private var departmentsError = false
    @State private var departmentNext: UUID?
    @State private var departmentPage: UUID?
    @State private var message: String?
    @State private var taskID = UUID()
    @State private var confirmation = false
    @State private var jobDraft = ""
    @Environment(\.novaCelebrate) private var celebrate
    @FocusState private var focusedField: String?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private struct SearchKey: Equatable { let query: String; let page: UUID? }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PersonnelHeading(title: original?.isArchived == true ? RDLocalization.string("localizable.nova.personnel.reactivate.title", table: .localizable, fallback: "Personeli Etkinleştir") : original == nil ? "Personel Ekle" : RDLocalization.string("localizable.nova.personnel.edit.title", table: .localizable, fallback: "Personeli Düzenle"), subtitle: companyName,
                    isBackEnabled: state.phase != .submitting && state.phase != .uncertain, backIdentifier: "personnel.editor.back", onBack: onBack)
                if original?.isArchived == true {
                    NovaCard(padding: 18) { VStack(alignment: .leading, spacing: 12) {
                        HStack { NovaIcon(symbol: "person", size: 24); NovaText(text: original?.name ?? "Personel", style: .cardTitle) }
                        NovaText(text: RDLocalization.string("localizable.nova.personnel.screens.personel.yeniden.etkinlestirilecek.tarihler.ve.g.945b2a9b", table: .localizable, fallback: "Personel yeniden etkinleştirilecek. Tarihler ve geçmiş kayıtlar değişmez; gerekirse daha sonra yeni görevlendirme ekleyebilirsiniz."))
                    } }
                } else {
                NovaCard(padding: 18) {
                    HStack(spacing: 10) {
                        NovaIcon(symbol: "person", size: 18)
                        TextField(RDLocalization.string("localizable.nova.personnel.screens.ad.soyad.9ca817b1", table: .localizable, fallback: "Ad soyad"), text: $state.name).font(NovaFont.font(.body)).textContentType(.name).disabled(!state.canEdit).accessibilityIdentifier("personnel.name")
                            .focused($focusedField, equals: "name").submitLabel(.done).onSubmit { focusedField = nil }
                    }
                }
                NovaCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { NovaIcon(symbol: "building.2", size: 20); NovaText(text: RDLocalization.string("localizable.nova.personnel.screens.departman.istege.bagli.baf6041e", table: .localizable, fallback: "Departman · isteğe bağlı"), style: .cardTitle) }
                        if let selected = state.selectedDepartment {
                            HStack { NovaText(text: selected.name); Spacer(); Button(RDLocalization.string("localizable.nova.personnel.screens.kaldir.f6bad754", table: .localizable, fallback: "Kaldır")) { state.selectedDepartment = nil; state.departmentText = "" }.disabled(!state.canEdit) }
                        } else {
                            TextField(RDLocalization.string("localizable.nova.personnel.screens.departman.sec.veya.yeni.ad.yaz.70373e55", table: .localizable, fallback: "Departman seç veya yeni ad yaz"), text: $state.departmentText).font(NovaFont.font(.body)).disabled(!state.canEdit).accessibilityIdentifier("personnel.department")
                                .focused($focusedField, equals: "department").submitLabel(.done).onSubmit { focusedField = nil }
                            ForEach(departments) { d in
                                Button { state.selectedDepartment = d; state.departmentText = "" } label: { HStack { NovaIcon(symbol: "building.2", size: 18); NovaText(text: d.name); Spacer(); NovaIcon(symbol: "plus", size: 16) }.frame(minHeight: 44) }
                                    .buttonStyle(NovaRowPressStyle()).disabled(!state.canEdit).accessibilityIdentifier("personnel.department.\(d.id.uuidString.lowercased())")
                            }
                            if let departmentNext { Button(RDLocalization.string("localizable.nova.personnel.screens.diger.departmanlar.d52232c2", table: .localizable, fallback: "Diğer departmanlar")) { departmentPage = departmentNext }.disabled(!state.canEdit) }
                            if departmentsError { NovaText(text: RDLocalization.string("localizable.nova.personnel.screens.departman.listesi.yuklenemedi.bos.birakabilir.ve.256eb508", table: .localizable, fallback: "Departman listesi yüklenemedi. Boş bırakabilir veya yeni ad yazabilirsiniz."), style: .metaQuiet) }
                        }
                    }
                }
                }
                if original?.isArchived != true {
                    NovaCard(padding: 18) {
                        HStack(spacing: 10) {
                            Image(systemName: "briefcase")
                            TextField(RDLocalization.string("localizable.nova.visual.0", table: .localizable, fallback: "Görev · isteğe bağlı"), text: $jobDraft)
                                .font(NovaFont.font(.body))
                                .accessibilityIdentifier("personnel.job")
                                .focused($focusedField, equals: "job").submitLabel(.done)
                                .onSubmit { focusedField = nil }
                        }
                    }
                    if !jobDraft.isEmpty { NovaText(text: RDLocalization.string("localizable.nova.visual.1", table: .localizable, fallback: "Görev alanı tasarım önizlemesidir; henüz kaydedilmez."), style: .metaQuiet) }
                }
                if let message { NovaText(text: message).accessibilityIdentifier("personnel.message") }
                if state.phase == .uncertain {
                    NovaText(text: RDLocalization.string("localizable.nova.personnel.screens.kayit.sonucu.dogrulanamadi.yeni.kayit.acmadan.ay.b06ff69b", table: .localizable, fallback: "Kayıt sonucu doğrulanamadı. Yeni kayıt açmadan aynı işlemi kontrol edin."))
                    NovaButton(label: RDLocalization.string("localizable.nova.personnel.screens.ayni.islemi.tekrar.kontrol.et.e7b5d522", table: .localizable, fallback: "Aynı işlemi tekrar kontrol et"), symbol: "arrow.clockwise", action: { if state.retry(scope: scope) != nil { taskID = UUID() } }).accessibilityIdentifier("personnel.retry")
                } else {
                    NovaButton(label: original?.isArchived == true ? RDLocalization.string("localizable.nova.personnel.reactivate", table: .localizable, fallback: "Yeniden etkinleştir") : original == nil ? RDLocalization.string("localizable.nova.personnel.save", table: .localizable, fallback: "Personeli kaydet") : RDLocalization.string("localizable.nova.personnel.save.changes", table: .localizable, fallback: "Değişiklikleri kaydet"), symbol: "checkmark", isEnabled: state.canEdit,
                        isLoading: state.phase == .submitting, action: {
                            focusedField = nil
                            if state.begin(scope: scope, original: original, restore: original?.isArchived == true) != nil { taskID = UUID() }
                            else { message = RDLocalization.string("localizable.nova.personnel.name.required", table: .localizable, fallback: "Ad soyad alanını kontrol edin.") }
                        }).accessibilityIdentifier("personnel.save")
                    if original != nil && original?.isArchived == false { NovaButton(label: RDLocalization.string("localizable.nova.personnel.screens.personeli.arsivle.715aa012", table: .localizable, fallback: "Personeli arşivle"), symbol: "archivebox", variant: .danger, isEnabled: state.canEdit, action: { confirmation = true }).accessibilityIdentifier("personnel.archive") }
                }
            }.padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 24)
                .novaPopupContentSize()
                .background { Color.clear.contentShape(Rectangle()).onTapGesture { focusedField = nil } }
        }
        .scrollDismissesKeyboard(.interactively)

        .interactiveDismissDisabled(state.phase == .submitting || state.phase == .uncertain)
        .onAppear {
            if let original, state.name.isEmpty {
                state.name = original.name
                if let id = original.departmentID, let name = original.departmentName { state.selectedDepartment = .init(id: id, ownerID: scope.ownerID, companyID: scope.companyID, name: name) }
                if archiveOnOpen { confirmation = true }
            }
        }
        .novaFullScreenCover(isPresented: $confirmation) {
            NovaPersonnelPopupBackdrop {
                ZStack {
                    Color.black.opacity(NovaPopupStyle.dimOpacity).ignoresSafeArea().onTapGesture { confirmation = false }
                    NovaPopupSurface {
                        VStack(alignment: .leading, spacing: 16) {
                            NovaText(text: RDLocalization.string("localizable.nova.personnel.screens.personel.arsivlensin.mi.f0b5b5c4", table: .localizable, fallback: "Personel arşivlensin mi?"), style: .sectionTitle)
                            NovaText(text: RDLocalization.string("localizable.nova.personnel.screens.gecmis.kayitlar.silinmez.0e1817f6", table: .localizable, fallback: "Geçmiş kayıtlar silinmez."))
                            NovaButton(label: RDLocalization.string("localizable.nova.personnel.screens.arsivle.bfb5fd4d", table: .localizable, fallback: "Arşivle"), symbol: "archivebox", variant: .danger) {
                                confirmation = false
                                if state.begin(scope: scope, original: original, archive: true) != nil { taskID = UUID() }
                            }.accessibilityIdentifier("personnel.archive.confirm")
                            NovaButton(label: RDLocalization.string("localizable.nova.personnel.screens.vazgec.37a5f5b0", table: .localizable, fallback: "Vazgeç"), symbol: "chevron.left", variant: .surface) { confirmation = false }.accessibilityIdentifier("personnel.archive.cancel")
                        }
                    }.padding(14).accessibilityAddTraits(.isModal)
                }
            }
        }
        .task(id: SearchKey(query: state.departmentText, page: departmentPage)) {
            let page = departmentPage; departmentsError = false
            if page == nil { departments = []; departmentNext = nil }
            do {
                try await Task.sleep(nanoseconds: 180_000_000)
                let result = try await client.departments(scope, state.departmentText, page); try Task.checkCancellation()
                guard result.rows.count <= 50, result.rows.allSatisfy({ $0.companyID == scope.companyID && $0.ownerID == scope.ownerID }),
                      Set(result.rows.map(\.id)).count == result.rows.count, result.next == nil || result.next == result.rows.last?.id else { throw NovaPersonnelFailure.denied }
                departments = page == nil ? result.rows : departments + result.rows.filter { d in !departments.contains(where: { $0.id == d.id }) }; departmentNext = result.next
            } catch { if !Task.isCancelled { departmentsError = true } }
        }
        .onChange(of: state.departmentText) { _ in departmentPage = nil }
        .task(id: taskID) {
            guard state.phase == .submitting, let intent = state.pending else { return }
            message = nil
            do {
                let result = try await client.save(intent); try Task.checkCancellation()
                if state.complete(intent, row: result, scope: scope) {
                    switch intent.action {
                    case .create, .restore: celebrate(NovaSuccessMessage.personnelCreated)
                    case .edit: celebrate(NovaSuccessMessage.personnelUpdated)
                    case .archive: celebrate(NovaSuccessMessage.personnelArchived)
                    }
                    onSaved(result)
                }
                else { state.uncertain(intent, scope: scope) }
            } catch {
                guard !Task.isCancelled else { return }
                if let failure = error as? NovaPersonnelFailure, failure != .unavailable {
                    state.reject(intent, scope: scope, denied: failure == .denied || failure == .conflict)
                    message = failure == .selectionRequired ? RDLocalization.string("localizable.nova.personnel.error.department.ambiguous", table: .localizable, fallback: "Aynı adlı birden fazla departman var. Listeden seçin.") : failure == .conflict ? RDLocalization.string("localizable.nova.personnel.error.record.changed", table: .localizable, fallback: "Kayıt değişmiş. Geri dönüp güncel kaydı açın.") : RDLocalization.string("localizable.nova.personnel.error.rejected", table: .localizable, fallback: "İşlem reddedildi. Bilgileri ve erişiminizi kontrol edin.")
                } else { state.uncertain(intent, scope: scope) }
            }
        }
    }
}

/// Covers the entire window, including shell header/tabs; underlying controls cannot fire.
private struct NovaPersonnelPopupBackdrop<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    var body: some View {
        if #available(iOS 16.4, *) {
            content().background {
                if !reduceTransparency { Rectangle().fill(.thinMaterial).opacity(NovaPopupStyle.materialOpacity).ignoresSafeArea() }
            }.presentationBackground(.clear)
        } else {
            // iOS 16.0–16.3 has no public transparent presentation API.
            content().background(NovaColorToken.canvas.color(in: .light).ignoresSafeArea())
        }
    }
}
