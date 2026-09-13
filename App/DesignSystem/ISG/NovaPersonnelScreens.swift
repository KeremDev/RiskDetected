import SwiftUI

/// Scope identity owns all list, search, form and pending-request state.
struct NovaPersonnelDestination: View {
    let scope: NovaPersonnelScope
    let companyName: String
    let client: NovaPersonnelClient
    let onBack: () -> Void
    var directory: NovaDirectoryClient? = nil
    var canWrite = true
    var body: some View { PersonnelContent(scope: scope, companyName: companyName, client: client, onBack: onBack, directory: directory, canWrite: canWrite).id(scope).id(canWrite) }
}

private struct PersonnelContent: View {
    let scope: NovaPersonnelScope
    let companyName: String
    let client: NovaPersonnelClient
    let onBack: () -> Void
    let directory: NovaDirectoryClient?
    let canWrite: Bool
    @State private var rows: [NovaEmployeeRow] = []
    @State private var query = ""
    @State private var archived = false
    @State private var next: UUID?
    @State private var loading = false
    @State private var error: String?
    @State private var route: Route = .list
    @State private var generation = UUID()
    @State private var requestedPage: UUID?
    @State private var pending: NovaEmployeeIntent?
    @State private var pendingChecked = false
    @State private var reconciling = false
    private enum Route: Equatable { case list, create, detail(UUID), edit(NovaEmployeeRow), advanced(UUID, NovaDirectoryKind) }
    private struct Key: Equatable { let query: String; let archived: Bool; let generation: UUID; let page: UUID? }
    var body: some View {
        NovaPageSurface {
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
                    onBack: { route = .list }, onEdit: { route = .edit($0) }, canWrite: canWrite,
                    onDirectory: directory == nil ? nil : { route = .advanced(id, $0) })
            case .advanced(let id, let kind):
                if let directory {
                    NovaDirectoryDestination(scope: scope, kind: kind, parent: id, client: directory,
                        onBack: { route = .detail(id) }, canWrite: canWrite)
                }
            }
        }
    }
    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                PersonnelHeading(title: "Personeller", subtitle: companyName, onBack: onBack)
                NovaCard(padding: 14) {
                    HStack { NovaIcon(symbol: "magnifyingglass", size: 18); TextField(RDLocalization.string("localizable.nova.personnel.screens.personel.ara.6695c740", table: .localizable, fallback: "Personel ara…"), text: $query).font(.custom("PlusJakartaSans-Medium", size: 15)).accessibilityIdentifier("personnel.search") }
                }
                Toggle(RDLocalization.string("localizable.nova.personnel.screens.arsivdekileri.de.goster.1c9e4bc7", table: .localizable, fallback: "Arşivdekileri de göster"), isOn: $archived).font(.subheadline)
                    .accessibilityIdentifier("personnel.archived")
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
                NovaButton(label: RDLocalization.string("localizable.nova.personnel.screens.personel.ekle.565c83dd", table: .localizable, fallback: "Personel Ekle"), symbol: "plus", isEnabled: canWrite && pendingChecked && pending == nil && !reconciling, action: { route = .create }).accessibilityIdentifier("personnel.add")
                if let error { NovaCard(padding: 16) { NovaText(text: error); NovaButton(label: RDLocalization.string("localizable.nova.personnel.screens.tekrar.dene.c2d238eb", table: .localizable, fallback: "Tekrar dene"), symbol: "arrow.clockwise", variant: .surface, action: { generation = UUID() }) } }
                if !loading && error == nil && rows.isEmpty { NovaCard(padding: 18) { NovaText(text: RDLocalization.string("localizable.nova.personnel.screens.henuz.personel.yok.d4c4f866", table: .localizable, fallback: "Henüz personel yok.")) } }
                ForEach(rows) { row in
                    Button { route = .detail(row.id) } label: {
                        NovaCard(padding: 16) {
                            HStack(spacing: 12) {
                                NovaIcon(symbol: "person", size: 24)
                                VStack(alignment: .leading, spacing: 5) {
                                    NovaText(text: row.name, style: .cardTitle)
                                    NovaText(text: row.departmentName ?? RDLocalization.string("localizable.nova.personnel.no.department.selected", table: .localizable, fallback: "Departman seçilmedi"), style: .metaQuiet)
                                    if row.isArchived { NovaText(text: RDLocalization.string("localizable.nova.personnel.screens.arsivde.b15e4fa0", table: .localizable, fallback: "Arşivde"), style: .metaQuiet) }
                                }
                                Spacer(); NovaIcon(symbol: "chevron.right", size: 16)
                            }
                        }
                    }.buttonStyle(.plain).disabled(pending != nil || reconciling).accessibilityIdentifier("personnel.row.\(row.id.uuidString.lowercased())")
                }
                if loading { ProgressView().frame(maxWidth: .infinity).accessibilityIdentifier("personnel.loading") }
                if let next, !loading { NovaButton(label: RDLocalization.string("localizable.nova.personnel.screens.daha.fazla.goster.3e8d6c6b", table: .localizable, fallback: "Daha fazla göster"), symbol: "chevron.down", variant: .surface, action: { requestedPage = next }) }
            }.padding(18).padding(.bottom, 24)
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
    let onBack: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) { NovaIcon(symbol: "chevron.left", size: 22).frame(width: 44, height: 44).background(.white, in: RoundedRectangle(cornerRadius: 16)) }.accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.shell.back", table: .localizable, fallback: "Geri")))
                .buttonStyle(.plain).disabled(!isBackEnabled).accessibilityLabel("Geri").accessibilityIdentifier("personnel.back")
            VStack(alignment: .leading, spacing: 4) { NovaText(text: title, style: .screenTitle); if !subtitle.isEmpty { NovaText(text: subtitle, style: .metaQuiet) } }
        }
    }
}

private struct NovaEmployeeDetail: View {
    let scope: NovaPersonnelScope
    let employeeID: UUID
    let client: NovaPersonnelClient
    let onBack: () -> Void
    let onEdit: (NovaEmployeeRow) -> Void
    let canWrite: Bool
    let onDirectory: ((NovaDirectoryKind) -> Void)?
    @State private var row: NovaEmployeeRow?
    @State private var error = false
    @State private var refresh = UUID()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PersonnelHeading(title: RDLocalization.string("localizable.nova.personnel.screens.personel.detayi.93b8adba", table: .localizable, fallback: "Personel Detayı"), onBack: onBack)
                if let row {
                    NovaCard(padding: 18) {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { NovaIcon(symbol: "person", size: 24); NovaText(text: row.name, style: .cardTitle) }
                            HStack { NovaIcon(symbol: "building.2", size: 20); NovaText(text: row.departmentName ?? RDLocalization.string("localizable.nova.personnel.no.department.selected", table: .localizable, fallback: "Departman seçilmedi")) }
                            NovaText(text: row.isArchived ? RDLocalization.string("localizable.nova.personnel.archived", table: .localizable, fallback: "Arşivde") : RDLocalization.string("localizable.nova.personnel.active", table: .localizable, fallback: "Aktif"), style: .metaQuiet)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.accessibilityIdentifier("personnel.detail")
                    if canWrite { NovaButton(label: row.isArchived ? RDLocalization.string("localizable.nova.personnel.reactivate", table: .localizable, fallback: "Yeniden etkinleştir") : RDLocalization.string("localizable.nova.personnel.edit", table: .localizable, fallback: "Düzenle"), symbol: row.isArchived ? "arrow.uturn.backward" : "pencil", action: { onEdit(row) }).accessibilityIdentifier(row.isArchived ? "personnel.restore" : "personnel.edit") }
                    if let onDirectory {
                        NovaButton(label: RDLocalization.string("localizable.nova.personnel.screens.gorevlendirme.gecmisi.b56428ce", table: .localizable, fallback: "Görevlendirme geçmişi"), symbol: "clock.arrow.circlepath", variant: .surface) { onDirectory(.assignments) }.accessibilityIdentifier("personnel.assignments")
                        NovaButton(label: RDLocalization.string("localizable.nova.personnel.screens.isveren.iliskisi.9ad2bc6f", table: .localizable, fallback: "İşveren ilişkisi"), symbol: "building.2", variant: .surface) { onDirectory(.employers) }.accessibilityIdentifier("personnel.employers")
                    }
                } else if error { NovaText(text: RDLocalization.string("localizable.nova.personnel.screens.personel.yuklenemedi.9398cf6a", table: .localizable, fallback: "Personel yüklenemedi.")); NovaButton(label: RDLocalization.string("localizable.nova.personnel.screens.tekrar.dene.d6e62bf1", table: .localizable, fallback: "Tekrar dene"), symbol: "arrow.clockwise", action: { refresh = UUID() }) }
                else { ProgressView() }
            }.padding(18)
        }.task(id: refresh) {
            row = nil; error = false
            do {
                let result = try await client.detail(scope, employeeID); try Task.checkCancellation()
                guard result.id == employeeID, result.companyID == scope.companyID, result.ownerID == scope.ownerID else { throw NovaPersonnelFailure.denied }
                row = result
            } catch { if !Task.isCancelled { self.error = true } }
        }
    }
}

private struct NovaEmployeeEditor: View {
    let scope: NovaPersonnelScope
    let companyName: String
    let client: NovaPersonnelClient
    let original: NovaEmployeeRow?
    let onBack: () -> Void
    let onSaved: (NovaEmployeeCommit) -> Void
    @State private var state = NovaEmployeeEditorState()
    @State private var departments: [NovaDepartmentRow] = []
    @State private var departmentsError = false
    @State private var departmentNext: UUID?
    @State private var departmentPage: UUID?
    @State private var message: String?
    @State private var taskID = UUID()
    @State private var confirmation = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    private struct SearchKey: Equatable { let query: String; let page: UUID? }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PersonnelHeading(title: original?.isArchived == true ? RDLocalization.string("localizable.nova.personnel.reactivate.title", table: .localizable, fallback: "Personeli Etkinleştir") : original == nil ? "Personel Ekle" : RDLocalization.string("localizable.nova.personnel.edit.title", table: .localizable, fallback: "Personeli Düzenle"), subtitle: companyName,
                    isBackEnabled: state.phase != .submitting && state.phase != .uncertain, onBack: onBack)
                if original?.isArchived == true {
                    NovaCard(padding: 18) { VStack(alignment: .leading, spacing: 12) {
                        HStack { NovaIcon(symbol: "person", size: 24); NovaText(text: original?.name ?? "Personel", style: .cardTitle) }
                        NovaText(text: RDLocalization.string("localizable.nova.personnel.screens.personel.yeniden.etkinlestirilecek.tarihler.ve.g.945b2a9b", table: .localizable, fallback: "Personel yeniden etkinleştirilecek. Tarihler ve geçmiş kayıtlar değişmez; gerekirse daha sonra yeni görevlendirme ekleyebilirsiniz."))
                    } }
                } else {
                NovaCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { NovaIcon(symbol: "person", size: 20); NovaText(text: RDLocalization.string("localizable.nova.personnel.screens.ad.soyad.afff790d", table: .localizable, fallback: "Ad soyad"), style: .cardTitle) }
                        TextField(RDLocalization.string("localizable.nova.personnel.screens.ad.soyad.9ca817b1", table: .localizable, fallback: "Ad soyad"), text: $state.name).font(.custom("PlusJakartaSans-Medium", size: 15)).textContentType(.name).disabled(!state.canEdit).accessibilityIdentifier("personnel.name")
                    }
                }
                NovaCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack { NovaIcon(symbol: "building.2", size: 20); NovaText(text: RDLocalization.string("localizable.nova.personnel.screens.departman.istege.bagli.baf6041e", table: .localizable, fallback: "Departman · isteğe bağlı"), style: .cardTitle) }
                        if let selected = state.selectedDepartment {
                            HStack { NovaText(text: selected.name); Spacer(); Button(RDLocalization.string("localizable.nova.personnel.screens.kaldir.f6bad754", table: .localizable, fallback: "Kaldır")) { state.selectedDepartment = nil; state.departmentText = "" }.disabled(!state.canEdit) }
                        } else {
                            TextField(RDLocalization.string("localizable.nova.personnel.screens.departman.sec.veya.yeni.ad.yaz.70373e55", table: .localizable, fallback: "Departman seç veya yeni ad yaz"), text: $state.departmentText).font(.custom("PlusJakartaSans-Medium", size: 15)).disabled(!state.canEdit).accessibilityIdentifier("personnel.department")
                            NovaText(text: RDLocalization.string("localizable.nova.personnel.screens.bos.birakabilirsiniz.yeni.ad.personelle.birlikte.7e36904d", table: .localizable, fallback: "Boş bırakabilirsiniz. Yeni ad, personelle birlikte kaydedilir."), style: .metaQuiet)
                            ForEach(departments) { d in
                                Button { state.selectedDepartment = d; state.departmentText = "" } label: { HStack { NovaIcon(symbol: "building.2", size: 18); NovaText(text: d.name); Spacer(); NovaIcon(symbol: "plus", size: 16) }.frame(minHeight: 44) }
                                    .buttonStyle(.plain).disabled(!state.canEdit).accessibilityIdentifier("personnel.department.\(d.id.uuidString.lowercased())")
                            }
                            if let departmentNext { Button(RDLocalization.string("localizable.nova.personnel.screens.diger.departmanlar.d52232c2", table: .localizable, fallback: "Diğer departmanlar")) { departmentPage = departmentNext }.disabled(!state.canEdit) }
                            if departmentsError { NovaText(text: RDLocalization.string("localizable.nova.personnel.screens.departman.listesi.yuklenemedi.bos.birakabilir.ve.256eb508", table: .localizable, fallback: "Departman listesi yüklenemedi. Boş bırakabilir veya yeni ad yazabilirsiniz."), style: .metaQuiet) }
                        }
                    }
                }
                }
                if let message { NovaText(text: message).accessibilityIdentifier("personnel.message") }
                if state.phase == .uncertain {
                    NovaText(text: RDLocalization.string("localizable.nova.personnel.screens.kayit.sonucu.dogrulanamadi.yeni.kayit.acmadan.ay.b06ff69b", table: .localizable, fallback: "Kayıt sonucu doğrulanamadı. Yeni kayıt açmadan aynı işlemi kontrol edin."))
                    NovaButton(label: RDLocalization.string("localizable.nova.personnel.screens.ayni.islemi.tekrar.kontrol.et.e7b5d522", table: .localizable, fallback: "Aynı işlemi tekrar kontrol et"), symbol: "arrow.clockwise", action: { if state.retry(scope: scope) != nil { taskID = UUID() } }).accessibilityIdentifier("personnel.retry")
                } else {
                    NovaButton(label: original?.isArchived == true ? RDLocalization.string("localizable.nova.personnel.reactivate", table: .localizable, fallback: "Yeniden etkinleştir") : original == nil ? RDLocalization.string("localizable.nova.personnel.save", table: .localizable, fallback: "Personeli kaydet") : RDLocalization.string("localizable.nova.personnel.save.changes", table: .localizable, fallback: "Değişiklikleri kaydet"), symbol: "checkmark", isEnabled: state.canSubmit,
                        isLoading: state.phase == .submitting, action: { if state.begin(scope: scope, original: original, restore: original?.isArchived == true) != nil { taskID = UUID() } }).accessibilityIdentifier("personnel.save")
                    if original != nil && original?.isArchived == false { NovaButton(label: RDLocalization.string("localizable.nova.personnel.screens.personeli.arsivle.715aa012", table: .localizable, fallback: "Personeli arşivle"), symbol: "archivebox", variant: .danger, isEnabled: state.canEdit, action: { confirmation = true }).accessibilityIdentifier("personnel.archive") }
                }
            }.padding(18).padding(.bottom, 24)
        }
        .onAppear {
            if let original, state.name.isEmpty {
                state.name = original.name
                if let id = original.departmentID, let name = original.departmentName { state.selectedDepartment = .init(id: id, ownerID: scope.ownerID, companyID: scope.companyID, name: name) }
            }
        }
        .fullScreenCover(isPresented: $confirmation) {
            NovaPersonnelPopupBackdrop {
                ZStack {
                    Color(red: 15/255, green: 15/255, blue: 17/255).opacity(0.34).ignoresSafeArea().onTapGesture { confirmation = false }
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
                if state.complete(intent, row: result, scope: scope) { onSaved(result) }
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
                if !reduceTransparency { Rectangle().fill(.ultraThinMaterial).ignoresSafeArea() }
            }.presentationBackground(.clear)
        } else {
            // iOS 16.0–16.3 has no public transparent presentation API.
            content().background(NovaColorToken.canvas.color(in: .light).ignoresSafeArea())
        }
    }
}
