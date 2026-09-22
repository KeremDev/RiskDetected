import SwiftUI
import Supabase

// Presentation copy for a model that must stay dependency free, so the isolated
// notebook contract check keeps compiling without the app's localization stack.
private func notebookRecurrenceLabel(_ recurrence: NotebookReminderRecurrence) -> String {
    switch recurrence {
    case .once: return RDLocalization.string("localizable.notebook.reminder.bir.kez.ef18e5ef", table: .localizable, fallback: "Bir kez")
    case .daily: return RDLocalization.string("localizable.notebook.reminder.her.gun.ccd74089", table: .localizable, fallback: "Her gün")
    case .weekly: return RDLocalization.string("localizable.notebook.reminder.her.hafta.e78b21ff", table: .localizable, fallback: "Her hafta")
    case .monthly: return RDLocalization.string("localizable.notebook.reminder.her.ay.90b7df04", table: .localizable, fallback: "Her ay")
    }
}

/// Server owned, account-bound rollout. A previously enabled account can edit
/// its encrypted local drafts offline; server mutations still enforce rollout.
@MainActor final class NotebookUIRelease: ObservableObject {
    static let shared = NotebookUIRelease()
    @Published private(set) var enabled = false
    func refresh() async {
        let identity = novaCurrentSessionIdentity()
        enabled = false
        guard let identity else { return }
        let cacheKey = "notebook.rollout." + identity.userID.uuidString
        let cached = UserDefaults.standard.object(forKey: cacheKey) as? Date
        enabled = cached.map { Date().timeIntervalSince($0) < 7 * 86400 } ?? false
        struct Rollout: Decodable { let schema_version: Int; let enabled: Bool }
        do {
            let data = try await SupabaseService.shared.client.rpc("isg_notebook_rollout_v1").execute().data
            let value = try JSONDecoder().decode(Rollout.self, from: data)
            guard !Task.isCancelled, identity == novaCurrentSessionIdentity() else { return }
            enabled = value.schema_version == 1 && value.enabled
            if enabled { UserDefaults.standard.set(Date(), forKey: cacheKey) }
            else { UserDefaults.standard.removeObject(forKey: cacheKey) }
        } catch {
            if identity != novaCurrentSessionIdentity() { enabled = false }
        }
    }
}

struct NotebookDestination: View {
    var startWithNewNote = false
    let onClose: () -> Void
    @State private var repository = NotebookRepository(sdk: SupabaseService.shared.client)
    @State private var identity: NotebookIdentity?
    var body: some View {
        Group {
            if let identity {
                NotebookContent(repository: repository, identity: identity, startWithNewNote: startWithNewNote, onClose: onClose)
                    .id(identity.owner.uuidString + identity.session.uuidString)
            } else {
                NovaPageSurface { VStack { NovaText(text: RDLocalization.string("localizable.notebook.destination.not.defteri.icin.oturum.acin.b71c112d", table: .localizable, fallback: "Not defteri için oturum açın.")); NovaButton(label: RDLocalization.string("localizable.notebook.destination.kapat.77119d45", table: .localizable, fallback: "Kapat"), symbol: "xmark", action: onClose) }.padding(18) }
            }
        }.privacySensitive().task {
            identity = repository.identity()
            for await _ in SupabaseService.shared.client.auth.authStateChanges {
                guard !Task.isCancelled else { return }; identity = repository.identity()
            }
        }
    }
}

private struct NotebookEditorState {
    let note: UUID
    let version: Int64
    var title: String
    var body: String
    var pending: NotebookPending?
    var serverText: String?
    var originalTitle: String?
    var originalBody: String?
}
private struct NotebookOrganizationEditor {
    let note: UUID; let version: Int64
    var items: [NotebookItem]; var tags: String
    var pending: UUID?; var serverText: String?
}
private struct NotebookReminderEditor {
    var title = ""
    var recurrence = NotebookReminderRecurrence.once
    var dueAt = Date().addingTimeInterval(60 * 60)
    var note: UUID?
}
private struct NotebookContent: View {
    private enum LibrarySection: String, CaseIterable, Identifiable {
        case notes, reminders, drafts
        var id: String { rawValue }
        var title: String {
            switch self {
            case .notes: return RDLocalization.string("localizable.notebook.section.notes", table: .localizable, fallback: "Notlar")
            case .reminders: return RDLocalization.string("localizable.notebook.section.reminders", table: .localizable, fallback: "Hatırlatıcılar")
            case .drafts: return RDLocalization.string("localizable.notebook.section.drafts", table: .localizable, fallback: "Taslaklar")
            }
        }
        var symbol: String {
            switch self { case .notes: return "note.text"; case .reminders: return "bell"; case .drafts: return "icloud.slash" }
        }
    }
    private enum EditorFocus { case title, body }
    let repository: NotebookRepository
    let identity: NotebookIdentity
    var startWithNewNote = false
    let onClose: () -> Void
    @State private var snapshot = NotebookReader.Snapshot(notes: [], drafts: [])
    @State private var editor: NotebookEditorState?
    @State private var organization: NotebookOrganizationEditor?
    @State private var reminderEditor: NotebookReminderEditor?
    @State private var reminders: [NotebookReminder] = []
    @State private var busy = false
    @State private var message: String?
    @State private var confirmDelete = false
    @State private var confirmExit = false
    @State private var closeAfterExit = false
    @State private var librarySection = LibrarySection.notes
    @State private var searchText = ""
    @FocusState private var editorFocus: EditorFocus?
    @ObservedObject private var notifications = NotificationService.shared
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        NovaPageSurface {
            ZStack {
                VStack(spacing: 0) {
                    topBar
                    if organization != nil { organizationFields }
                    else if reminderEditor != nil { reminderFields }
                    else if editor != nil { editorFields }
                    else { list }
                }
                .disabled(busy || confirmDelete || confirmExit)
                .blur(radius: confirmDelete || confirmExit ? 7 : 0)
                if confirmExit {
                    Color.black.opacity(0.34).ignoresSafeArea().onTapGesture { confirmExit = false }
                    NovaPopupSurface {
                        VStack(spacing: 16) {
                            Label(RDLocalization.string("localizable.notebook.destination.kaydedilmemis.degisiklikler.40096567", table: .localizable, fallback: "Kaydedilmemiş değişiklikler"), systemImage: "exclamationmark.triangle")
                            NovaText(text: RDLocalization.string("localizable.notebook.destination.editordeki.degisiklikleri.kaydetmeden.cikmak.ist.636699d9", table: .localizable, fallback: "Editördeki değişiklikleri kaydetmeden çıkmak istiyor musunuz? Daha önce kaydedilmiş taslaklar silinmez."))
                            NovaButton(label: RDLocalization.string("localizable.notebook.destination.kaydetmeden.cik.90c82e30", table: .localizable, fallback: "Kaydetmeden çık"), symbol: "xmark", variant: .danger) {
                                confirmExit = false; editor = nil; organization = nil; reminderEditor = nil; if closeAfterExit { onClose() }
                            }
                            NovaButton(label: RDLocalization.string("localizable.notebook.destination.duzenlemeye.don.1c743dcf", table: .localizable, fallback: "Düzenlemeye dön"), symbol: "chevron.left", variant: .surface) { confirmExit = false }
                        }
                    }.padding(18)
                }
                if confirmDelete {
                    Color.black.opacity(0.34).ignoresSafeArea().onTapGesture { confirmDelete = false }
                    NovaPopupSurface {
                        VStack(spacing: 16) {
                            Label(RDLocalization.string("localizable.notebook.destination.not.silinsin.mi.7635c311", table: .localizable, fallback: "Not silinsin mi?"), systemImage: "trash")
                            NovaText(text: RDLocalization.string("localizable.notebook.destination.islem.once.cihazda.saklanir.sunucu.onayladiginda.61586112", table: .localizable, fallback: "İşlem önce cihazda saklanır. Sunucu onayladığında not diğer cihazlarda da silinir."))
                            NovaButton(label: "Sil", symbol: "trash", variant: .danger) { confirmDelete = false; Task { await save(delete: true) } }
                            NovaButton(label: RDLocalization.string("localizable.notebook.destination.vazgec.30cebb09", table: .localizable, fallback: "Vazgeç"), symbol: "chevron.left", variant: .surface) { confirmDelete = false }
                        }
                    }.padding(18)
                }
                if busy { ProgressView().accessibilityLabel(RDLocalization.string("localizable.notebook.destination.islem.suruyor.3e5058a7", table: .localizable, fallback: "İşlem sürüyor")) }
            }
        }.preferredColorScheme(.light).task {
            if startWithNewNote { openNewNote() }
            await refresh()
        }.onReceive(NetworkMonitor.shared.$isOnline) { online in
            if online { Task { await sync() } }
        }.privacySensitive()
    }
    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: backAction) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(NovaColorToken.surface.color(in: colorScheme)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(editor == nil && organization == nil && reminderEditor == nil
                ? RDLocalization.string("localizable.notebook.close", table: .localizable, fallback: "Kapat")
                : RDLocalization.string("localizable.notebook.back.to.notes", table: .localizable, fallback: "Notlara dön"))

            VStack(alignment: .leading, spacing: 1) {
                Text(topBarTitle)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(NovaColorToken.text.color(in: colorScheme))
                Text(topBarSubtitle)
                    .font(.caption)
                    .foregroundStyle(NovaColorToken.textTertiary.color(in: colorScheme))
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if editor != nil {
                Button("Bitti") { Task { await finishEditor(closeDestination: false) } }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(NovaColorToken.accentInk.color(in: colorScheme))
                    .padding(.horizontal, 15).frame(height: 42)
                    .background(Capsule().fill(NovaColorToken.accentSoft.color(in: colorScheme)))
                    .buttonStyle(.plain)
            } else if organization == nil && reminderEditor == nil {
                notebookIconButton("arrow.triangle.2.circlepath", label: RDLocalization.string("localizable.notebook.destination.esitle.ec7babeb", table: .localizable, fallback: "Eşitle")) { Task { await sync() } }
                notebookIconButton("square.and.pencil", label: RDLocalization.string("localizable.notebook.new.note", table: .localizable, fallback: "Yeni not")) { openNewNote() }
                    .accessibilityIdentifier("notebook.add")
            }
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
        .background(.ultraThinMaterial)
        .overlay(alignment: .bottom) { Rectangle().fill(NovaColorToken.hairline.color(in: colorScheme)).frame(height: 1) }
        .zIndex(2)
    }
    private var topBarTitle: String {
        if organization != nil { return RDLocalization.string("localizable.notebook.checklist.tags", table: .localizable, fallback: "Checklist ve Etiketler") }
        if reminderEditor != nil { return RDLocalization.string("localizable.notebook.new.reminder", table: .localizable, fallback: "Yeni Hatırlatıcı") }
        if editor != nil { return RDLocalization.string("localizable.notebook.note", table: .localizable, fallback: "Not") }
        return RDLocalization.string("localizable.notebook.destination.kisisel.notlar.a3d7499d", table: .localizable, fallback: "Kişisel Notlar")
    }
    private var topBarSubtitle: String {
        if organization != nil { return RDLocalization.string("localizable.notebook.organization", table: .localizable, fallback: "Not düzeni") }
        if reminderEditor != nil { return RDLocalization.string("localizable.notebook.server.notification", table: .localizable, fallback: "Sunucu bildirimi") }
        if editor != nil { return RDLocalization.string("localizable.notebook.device.safe", table: .localizable, fallback: "Değişiklikler cihazda güvenle saklanır") }
        return String(format: RDLocalization.string("localizable.notebook.private.count", table: .localizable,
            fallback: "Yalnızca size ait · %d not"), snapshot.notes.count)
    }
    private func notebookIconButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 16, weight: .semibold))
                .frame(width: 42, height: 42)
                .background(Circle().fill(NovaColorToken.surface.color(in: colorScheme)))
        }.buttonStyle(.plain).accessibilityLabel(label)
    }
    private func backAction() {
        if organization != nil || reminderEditor != nil { closeAfterExit = false; confirmExit = true }
        else if editor != nil { Task { await finishEditor(closeDestination: false) } }
        else { onClose() }
    }
    private var filteredNotes: [NotebookRecord] {
        snapshot.notes
            .filter { searchText.isEmpty || ($0.title ?? "").localizedCaseInsensitiveContains(searchText) || ($0.body ?? "").localizedCaseInsensitiveContains(searchText) }
            .sorted { (NotebookReminderDate.parse($0.updated_at) ?? .distantPast) > (NotebookReminderDate.parse($1.updated_at) ?? .distantPast) }
    }
    private var filteredDrafts: [NotebookPending] {
        snapshot.drafts.filter {
            searchText.isEmpty || ($0.intent.title ?? "").localizedCaseInsensitiveContains(searchText) ||
            ($0.intent.body ?? "").localizedCaseInsensitiveContains(searchText)
        }
    }
    private var filteredReminders: [NotebookReminder] {
        reminders.filter { $0.state == "active" && (searchText.isEmpty || $0.title.localizedCaseInsensitiveContains(searchText)) }
            .sorted { (NotebookReminderDate.parse($0.next_occurrence?.effective_due_at ?? "") ?? .distantFuture) < (NotebookReminderDate.parse($1.next_occurrence?.effective_due_at ?? "") ?? .distantFuture) }
    }
    private var list: some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(NovaColorToken.textTertiary.color(in: colorScheme))
                    TextField(RDLocalization.string("localizable.notebook.search", table: .localizable, fallback: "Notlarda ara"), text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    if !searchText.isEmpty {
                        Button { searchText = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).foregroundStyle(NovaColorToken.textMuted.color(in: colorScheme))
                            .accessibilityLabel(RDLocalization.string("localizable.notebook.search.clear", table: .localizable,
                                fallback: "Aramayı temizle"))
                    }
                }
                .padding(.horizontal, 14).frame(height: 46)
                .background(RoundedRectangle(cornerRadius: 15).fill(NovaColorToken.surface.color(in: colorScheme)))
                .overlay(RoundedRectangle(cornerRadius: 15).stroke(NovaColorToken.border.color(in: colorScheme)))
                .accessibilityIdentifier("notebook.search")

                HStack(spacing: 6) {
                    ForEach(LibrarySection.allCases) { section in
                        Button {
                            withAnimation(.spring(response: 0.3, dampingFraction: 1)) { librarySection = section }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: section.symbol)
                                Text(section.title)
                                if section == .drafts && !snapshot.drafts.isEmpty {
                                    Text("\(snapshot.drafts.count)").font(.caption2.bold())
                                }
                            }
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(librarySection == section ? NovaColorToken.onInverse.color(in: colorScheme) : NovaColorToken.textSecondary.color(in: colorScheme))
                            .frame(maxWidth: .infinity).padding(.vertical, 10)
                            .background(Capsule().fill(librarySection == section ? NovaColorToken.inverse.color(in: colorScheme) : .clear))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(4).background(Capsule().fill(NovaColorToken.surfaceMuted.color(in: colorScheme)))
                if let message { notebookMessage(message) }
            }
            .padding(.horizontal, 18).padding(.top, 14).padding(.bottom, 10)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    switch librarySection {
                    case .notes: notesLibrary
                    case .reminders: reminderLibrary
                    case .drafts: draftsLibrary
                    }
                }.padding(.horizontal, 18).padding(.top, 4).padding(.bottom, 110)
            }
            .scrollDismissesKeyboard(.interactively)
            .refreshable { await refresh() }
        }
        .overlay(alignment: .bottomTrailing) {
            Button { openNewNote() } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(NovaColorToken.onInverse.color(in: colorScheme))
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(NovaColorToken.inverse.color(in: colorScheme)))
                    .shadow(color: .black.opacity(0.18), radius: 14, y: 7)
            }.buttonStyle(.plain).padding(22).accessibilityLabel(RDLocalization.string("localizable.notebook.new.note", table: .localizable, fallback: "Yeni not"))
        }
    }
    @ViewBuilder private var notesLibrary: some View {
        if !filteredDrafts.isEmpty {
            libraryHeading(RDLocalization.string("localizable.notebook.device.drafts", table: .localizable, fallback: "Cihazdaki Taslaklar"), detail: "\(filteredDrafts.count)")
            ForEach(filteredDrafts, id: \.intent.mutation) { draftRow($0, compact: true) }
        }
        libraryHeading(searchText.isEmpty
            ? RDLocalization.string("localizable.notebook.recent.notes", table: .localizable, fallback: "Son Notlar")
            : RDLocalization.string("localizable.notebook.search.results", table: .localizable, fallback: "Arama Sonuçları"), detail: "\(filteredNotes.count)")
        if filteredNotes.isEmpty && filteredDrafts.isEmpty {
            notebookEmpty(symbol: "note.text",
                title: searchText.isEmpty
                    ? RDLocalization.string("localizable.notebook.empty.title", table: .localizable, fallback: "İlk notunuzu oluşturun")
                    : RDLocalization.string("localizable.notebook.no.match.title", table: .localizable, fallback: "Eşleşen not bulunamadı"),
                detail: searchText.isEmpty
                    ? RDLocalization.string("localizable.notebook.empty.detail", table: .localizable, fallback: "Düşüncelerinizi, yapılacakları ve saha notlarını tek yerde tutun.")
                    : RDLocalization.string("localizable.notebook.no.match.detail", table: .localizable, fallback: "Farklı bir sözcükle aramayı deneyin."))
        } else {
            ForEach(filteredNotes, id: \.note_id) { noteRow($0) }
        }
    }
    @ViewBuilder private var draftsLibrary: some View {
        HStack {
            libraryHeading(RDLocalization.string("localizable.notebook.pending.actions", table: .localizable, fallback: "Bekleyen İşlemler"), detail: "\(filteredDrafts.count)")
            Spacer()
            if !snapshot.drafts.isEmpty {
                Button(RDLocalization.string("localizable.notebook.sync.now", table: .localizable, fallback: "Şimdi eşitle")) { Task { await sync() } }
                    .font(.caption.bold()).foregroundStyle(NovaColorToken.accentInk.color(in: colorScheme))
            }
        }
        if filteredDrafts.isEmpty {
            notebookEmpty(symbol: "checkmark.icloud",
                title: RDLocalization.string("localizable.notebook.synced.title", table: .localizable, fallback: "Tüm değişiklikler eşitlendi"),
                detail: RDLocalization.string("localizable.notebook.synced.detail", table: .localizable, fallback: "Çevrimdışı kaydettiğiniz notlar burada görünür."))
        } else {
            ForEach(filteredDrafts, id: \.intent.mutation) { draftRow($0, compact: false) }
        }
    }
    @ViewBuilder private var reminderLibrary: some View {
        HStack {
            libraryHeading(RDLocalization.string("localizable.notebook.upcoming.reminders", table: .localizable, fallback: "Yaklaşan Hatırlatıcılar"), detail: "\(filteredReminders.count)")
            Spacer()
            Button { reminderEditor = NotebookReminderEditor() } label: {
                Label("Yeni", systemImage: "plus").font(.caption.bold())
            }.buttonStyle(.plain).foregroundStyle(NovaColorToken.accentInk.color(in: colorScheme))
        }
        if filteredReminders.isEmpty {
            notebookEmpty(symbol: "bell",
                title: RDLocalization.string("localizable.notebook.no.reminder.title", table: .localizable, fallback: "Hatırlatıcı yok"),
                detail: RDLocalization.string("localizable.notebook.no.reminder.detail", table: .localizable, fallback: "Bir nota bağlı veya bağımsız sunucu bildirimi oluşturabilirsiniz."))
        } else {
            ForEach(filteredReminders) { reminderRow($0) }
        }
    }
    private func libraryHeading(_ title: String, detail: String) -> some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 17, weight: .bold, design: .rounded))
            Text(detail).font(.caption.bold()).foregroundStyle(NovaColorToken.textTertiary.color(in: colorScheme))
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
    }
    private func noteRow(_ note: NotebookRecord) -> some View {
        let blocked = snapshot.drafts.contains { $0.intent.note == note.note_id }
        return Button {
            editor = .init(note: note.note_id, version: note.version, title: note.title ?? "", body: note.body ?? "",
                           originalTitle: note.title ?? "", originalBody: note.body ?? "")
        } label: {
            HStack(alignment: .top, spacing: 13) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(NovaColorToken.accentSoft.color(in: colorScheme))
                    .frame(width: 46, height: 54)
                    .overlay(Image(systemName: "note.text").font(.system(size: 18, weight: .semibold)).foregroundStyle(NovaColorToken.accentInk.color(in: colorScheme)))
                VStack(alignment: .leading, spacing: 5) {
                    Text(note.title?.isEmpty == false ? note.title! : RDLocalization.string("localizable.notebook.untitled", table: .localizable, fallback: "Başlıksız Not"))
                        .font(.system(size: 15, weight: .bold)).foregroundStyle(NovaColorToken.text.color(in: colorScheme)).lineLimit(1)
                    Text(notePreview(note.body))
                        .font(.system(size: 13)).foregroundStyle(NovaColorToken.textSecondary.color(in: colorScheme)).lineLimit(2)
                    HStack(spacing: 6) {
                        Text(noteDate(note.updated_at))
                        if blocked { Label(RDLocalization.string("localizable.notebook.sync.pending", table: .localizable, fallback: "Eşitleme bekliyor"), systemImage: "icloud.slash") }
                    }.font(.caption2).foregroundStyle(NovaColorToken.textTertiary.color(in: colorScheme))
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(NovaColorToken.textSubtle.color(in: colorScheme)).padding(.top, 18)
            }
            .padding(15).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 18).fill(NovaColorToken.surface.color(in: colorScheme)).shadow(color: .black.opacity(0.045), radius: 9, y: 3))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(NovaColorToken.hairline.color(in: colorScheme)))
        }
        .buttonStyle(.plain).disabled(blocked)
        .contextMenu {
            Button { Task { await openOrganization(note.note_id) } } label: { Label("Checklist ve Etiketler", systemImage: "checklist") }
            Button { reminderEditor = NotebookReminderEditor(title: note.title ?? "", note: note.note_id) } label: {
                Label(RDLocalization.string("localizable.notebook.add.reminder", table: .localizable, fallback: "Hatırlatıcı Ekle"), systemImage: "bell.badge")
            }
        }
    }
    private func draftRow(_ pending: NotebookPending, compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Label(pending.blocked == nil
                    ? RDLocalization.string("localizable.notebook.destination.gonderilmeyi.bekliyor.303c7ae8", table: .localizable, fallback: "Gönderilmeyi bekliyor")
                    : RDLocalization.string("localizable.notebook.action.required", table: .localizable, fallback: "İşlem gerekli"), systemImage: pending.blocked == nil ? "icloud.slash" : "exclamationmark.icloud")
                    .font(.caption.bold()).foregroundStyle(pending.blocked == nil ? NovaColorToken.statusWarningInk.color(in: colorScheme) : NovaColorToken.statusDangerInk.color(in: colorScheme))
                Spacer()
                if pending.intent.action == "organize" { Image(systemName: "checklist") }
            }
            Text(pending.intent.title ?? (pending.intent.action == "organize"
                ? RDLocalization.string("localizable.notebook.destination.checklist.ve.etiket.taslagi.e192ce35", table: .localizable, fallback: "Checklist ve etiket taslağı")
                : pending.intent.action == "delete"
                    ? RDLocalization.string("localizable.notebook.destination.silme.istegi.fa696aef", table: .localizable, fallback: "Silme isteği")
                    : RDLocalization.string("localizable.notebook.untitled", table: .localizable, fallback: "Başlıksız Not")))
                .font(.system(size: 15, weight: .bold)).lineLimit(1)
            if !compact { Text(notePreview(pending.intent.body)).font(.system(size: 13)).foregroundStyle(NovaColorToken.textSecondary.color(in: colorScheme)).lineLimit(3) }
            if pending.blocked == "VERSION_CONFLICT" && pending.intent.action == "organize" {
                Button(RDLocalization.string("localizable.notebook.destination.checklist.surumlerini.incele.97092e1b", table: .localizable, fallback: "Checklist sürümlerini incele")) { Task { await openOrganization(pending.intent.note, pending: pending) } }.font(.caption.bold())
            }
            if pending.conflictID != nil {
                Button(RDLocalization.string("localizable.notebook.destination.iki.surumu.incele.df04069e", table: .localizable, fallback: "İki sürümü incele")) { Task { await resolve(pending) } }.font(.caption.bold())
            }
        }
        .padding(15).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(NovaColorToken.statusWarningBg.color(in: colorScheme)))
    }
    private func reminderRow(_ reminder: NotebookReminder) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(alignment: .top) {
                Image(systemName: "bell.fill").foregroundStyle(NovaColorToken.statusWarningInk.color(in: colorScheme))
                    .frame(width: 38, height: 38).background(Circle().fill(NovaColorToken.statusWarningBg.color(in: colorScheme)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(reminder.title).font(.system(size: 15, weight: .bold))
                    Text(notebookRecurrenceLabel(reminder.recurrence) + reminderSchedule(reminder))
                        .font(.caption).foregroundStyle(NovaColorToken.textSecondary.color(in: colorScheme))
                }
                Spacer()
            }
            if let occurrence = reminder.next_occurrence {
                HStack(spacing: 8) {
                    Button { Task { await settleReminder("complete", reminder: reminder, occurrence: occurrence) } } label: { Label("Tamamla", systemImage: "checkmark") }
                    Button { Task { await settleReminder("snooze", reminder: reminder, occurrence: occurrence) } } label: { Label("10 dk ertele", systemImage: "clock.arrow.circlepath") }
                }.font(.caption.bold()).buttonStyle(.bordered)
            }
        }
        .padding(15).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18).fill(NovaColorToken.surface.color(in: colorScheme)).shadow(color: .black.opacity(0.045), radius: 9, y: 3))
        .contextMenu { Button(role: .destructive) { Task { await settleReminder("cancel", reminder: reminder) } } label: {
            Label(RDLocalization.string("localizable.notebook.destination.hatirlaticiyi.iptal.et.66814eec", table: .localizable, fallback: "Hatırlatıcıyı iptal et"), systemImage: "bell.slash")
        } }
    }
    private func notebookEmpty(symbol: String, title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 28, weight: .light)).foregroundStyle(NovaColorToken.textTertiary.color(in: colorScheme))
            Text(title).font(.system(size: 16, weight: .bold))
            Text(detail).font(.system(size: 13)).foregroundStyle(NovaColorToken.textSecondary.color(in: colorScheme)).multilineTextAlignment(.center)
        }.padding(.vertical, 42).padding(.horizontal, 22).frame(maxWidth: .infinity)
    }
    private func notebookMessage(_ text: String) -> some View {
        Label(text, systemImage: "info.circle.fill")
            .font(.caption).foregroundStyle(NovaColorToken.statusInfoInk.color(in: colorScheme))
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 13).fill(NovaColorToken.statusInfoBg.color(in: colorScheme)))
    }
    private func notePreview(_ body: String?) -> String {
        let value = (body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "Metin yok" : value.replacingOccurrences(of: "\n", with: " ")
    }
    private func noteDate(_ raw: String) -> String {
        guard let date = NotebookReminderDate.parse(raw) else { return "" }
        return date.formatted(.relative(presentation: .named))
    }
    private var reminderFields: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Image(systemName: "bell.badge.fill").font(.system(size: 21))
                            .foregroundStyle(NovaColorToken.statusWarningInk.color(in: colorScheme))
                            .frame(width: 46, height: 46).background(Circle().fill(NovaColorToken.statusWarningBg.color(in: colorScheme)))
                        TextField(RDLocalization.string("localizable.notebook.reminder.title", table: .localizable, fallback: "Hatırlatıcı başlığı"), text: Binding(get: { reminderEditor?.title ?? "" }, set: { reminderEditor?.title = $0 }))
                            .font(.system(size: 18, weight: .semibold)).accessibilityIdentifier("notebook.reminder.title")
                    }.padding(16)
                    Divider().padding(.leading, 74)
                    HStack {
                        Label("Tekrar", systemImage: "repeat")
                        Spacer()
                        Picker("Tekrar", selection: Binding(get: { reminderEditor?.recurrence ?? .once }, set: { reminderEditor?.recurrence = $0 })) {
                            ForEach(NotebookReminderRecurrence.allCases) { recurrence in Text(notebookRecurrenceLabel(recurrence)).tag(recurrence) }
                        }.pickerStyle(.menu).labelsHidden()
                    }.padding(16)
                    Divider().padding(.leading, 16)
                    DatePicker("Tarih ve saat", selection: Binding(get: { reminderEditor?.dueAt ?? Date() }, set: { reminderEditor?.dueAt = $0 }),
                               in: Date()..., displayedComponents: [.date, .hourAndMinute]).padding(16)
                }
                .background(RoundedRectangle(cornerRadius: 20).fill(NovaColorToken.surface.color(in: colorScheme)))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(NovaColorToken.hairline.color(in: colorScheme)))

                if let note = reminderEditor?.note {
                    Label(RDLocalization.string("localizable.notebook.reminder.linked", table: .localizable, fallback: "Bu hatırlatıcı seçili nota bağlanacak"), systemImage: "link")
                        .font(.caption).foregroundStyle(NovaColorToken.textSecondary.color(in: colorScheme))
                        .accessibilityValue(note.uuidString)
                }
                if let message { notebookMessage(message) }
                if let error = notifications.lastError { notebookMessage(error) }
                Button { notifications.enableNotifications() } label: {
                    Label(notifications.isRegistering
                        ? RDLocalization.string("localizable.notebook.device.registering", table: .localizable, fallback: "Cihaz kaydı yenileniyor…")
                        : RDLocalization.string("localizable.notebook.notifications.enable", table: .localizable, fallback: "Bildirimleri aç / cihaz kaydını yenile"), systemImage: "bell.badge")
                        .font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity).padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 15).fill(NovaColorToken.surface.color(in: colorScheme)))
                }.buttonStyle(.plain).disabled(notifications.isRegistering)
                NovaText(text: RDLocalization.string("localizable.notebook.destination.teslimat.sahibi.bu.cihazdaki.sunucu.bildirimi.ka.d07077c3", table: .localizable, fallback: "Teslimat sahibi: bu cihazdaki sunucu bildirimi kaydı. Bildirim izni veya güncel cihaz kaydı yoksa hatırlatıcı oluşturulmaz."), style: .metaQuiet)
                NovaButton(label: RDLocalization.string("localizable.notebook.destination.hatirlaticiyi.olustur.f3065fd2", table: .localizable, fallback: "Hatırlatıcıyı oluştur"), symbol: "checkmark") { Task { await createReminder() } }
            }.padding(18)
        }.scrollDismissesKeyboard(.interactively)
    }
    private var editorFields: some View {
        VStack(spacing: 0) {
            if let text = editor?.serverText {
                VStack(alignment: .leading, spacing: 5) {
                    Label(RDLocalization.string("localizable.notebook.destination.guncel.sunucu.surumu.df387713", table: .localizable, fallback: "Güncel sunucu sürümü"), systemImage: "icloud") .font(.caption.bold())
                    Text(text).font(.caption).lineLimit(4).textSelection(.enabled)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(NovaColorToken.statusInfoBg.color(in: colorScheme))
            }
            if let message { notebookMessage(message).padding(.horizontal, 18).padding(.top, 12) }
            VStack(alignment: .leading, spacing: 0) {
                TextField(RDLocalization.string("localizable.notebook.destination.baslik.035bd998", table: .localizable, fallback: "Başlık"), text: Binding(get: { editor?.title ?? "" }, set: { editor?.title = $0 }), axis: .vertical)
                    .font(.system(size: 27, weight: .bold, design: .rounded))
                    .focused($editorFocus, equals: .title).submitLabel(.next)
                    .onSubmit { editorFocus = .body }
                    .accessibilityIdentifier("notebook.title")
                    .padding(.horizontal, 20).padding(.top, 22).padding(.bottom, 8)
                Rectangle().fill(NovaColorToken.hairline.color(in: colorScheme)).frame(height: 1).padding(.horizontal, 20)
                TextEditor(text: Binding(get: { editor?.body ?? "" }, set: { editor?.body = $0 }))
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .lineSpacing(5).scrollContentBackground(.hidden)
                    .focused($editorFocus, equals: .body)
                    .padding(.horizontal, 15).padding(.vertical, 10)
                    .accessibilityIdentifier("notebook.body")
            }
            .background(NovaColorToken.surface.color(in: colorScheme))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 8) {
                Button {
                    guard let note = editor?.note, editor?.version ?? 0 > 0 else { return }
                    Task {
                        await finishEditor(closeDestination: false)
                        guard editor == nil else { return }
                        await openOrganization(note)
                    }
                } label: { Label("Checklist", systemImage: "checklist") }
                    .disabled((editor?.version ?? 0) == 0 || editor?.pending != nil)
                Button {
                    guard let note = editor?.note else { return }
                    let title = editor?.title ?? ""
                    Task {
                        await finishEditor(closeDestination: false)
                        guard editor == nil else { return }
                        reminderEditor = NotebookReminderEditor(title: title, note: note)
                    }
                } label: { Label(RDLocalization.string("localizable.notebook.remind", table: .localizable, fallback: "Hatırlat"), systemImage: "bell.badge") }
                    .disabled((editor?.version ?? 0) == 0)
                Spacer()
                Text("\((editor?.body ?? "").count) karakter").font(.caption2).foregroundStyle(NovaColorToken.textTertiary.color(in: colorScheme))
                if editor?.version ?? 0 > 0 && editor?.pending == nil {
                    Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }.accessibilityLabel("Notu sil")
                }
            }
            .font(.system(size: 13, weight: .semibold)).buttonStyle(.borderless)
            .padding(.horizontal, 18).frame(height: 54)
            .background(.ultraThinMaterial)
            .overlay(alignment: .top) { Rectangle().fill(NovaColorToken.hairline.color(in: colorScheme)).frame(height: 1) }
        }
        .onAppear { if editor?.version == 0 { editorFocus = .title } }
    }
    private var organizationFields: some View {
        ScrollView { VStack(spacing: 14) {
            if let message { notebookMessage(message) }
            if let text = organization?.serverText { NovaCard(padding: 18) { Text(RDLocalization.string("localizable.notebook.destination.guncel.sunucu.checklist.i.f6e5b3eb", table: .localizable, fallback: "Güncel sunucu checklist'i") + text).textSelection(.enabled) } }
            NovaCard(padding: 18) {
                VStack(spacing: 12) {
                    TextField(RDLocalization.string("localizable.notebook.destination.etiketler.virgulle.ayirin.a64c2c8c", table: .localizable, fallback: "Etiketler (virgülle ayırın)"), text: Binding(get: { organization?.tags ?? "" }, set: { organization?.tags = $0 }))
                    ForEach(organization?.items ?? [], id: \.item_id) { item in
                        HStack {
                            Toggle(RDLocalization.string("localizable.notebook.destination.tamamlandi.0f48813c", table: .localizable, fallback: "Tamamlandı"), isOn: Binding(get: { organization?.items.first { $0.item_id == item.item_id }?.done ?? false },
                                set: { value in if let i = organization?.items.firstIndex(where: { $0.item_id == item.item_id }) { organization?.items[i].done = value } })).labelsHidden()
                            TextField(RDLocalization.string("localizable.notebook.destination.yapilacak.23e57a0e", table: .localizable, fallback: "Yapılacak"), text: Binding(get: { organization?.items.first { $0.item_id == item.item_id }?.text ?? "" },
                                set: { value in if let i = organization?.items.firstIndex(where: { $0.item_id == item.item_id }) { organization?.items[i].text = value } }))
                            Button { organization?.items.removeAll { $0.item_id == item.item_id } } label: { Image(systemName: "minus.circle") }.accessibilityLabel(RDLocalization.string("localizable.notebook.destination.checklist.maddesini.kaldir.4f80a1e0", table: .localizable, fallback: "Checklist maddesini kaldır"))
                        }
                    }
                }
            }
            NovaButton(label: RDLocalization.string("localizable.notebook.destination.madde.ekle.cf6ff89c", table: .localizable, fallback: "Madde ekle"), symbol: "plus", isEnabled: (organization?.items.count ?? 0) < 500) { organization?.items.append(.init(item_id: UUID(), text: "", done: false)) }
            NovaButton(label: RDLocalization.string("localizable.notebook.destination.checklist.taslagini.kaydet.378765a8", table: .localizable, fallback: "Checklist taslağını kaydet"), symbol: "checkmark") {
                guard let value = organization else { return }
                do {
                    let tags = value.tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    let intent = NotebookMutation(mutation: UUID(), note: value.note, action: "organize", expected: value.version, title: nil, body: nil, conflict: nil, items: value.items, tags: tags)
                    if let pending = value.pending { try repository.queue.replaceOrganization(pending, with: intent, identity: identity) }
                    else { try repository.queue.stage(intent, identity: identity) }
                    snapshot = try repository.snapshot(identity); organization = nil; message = RDLocalization.string("localizable.notebook.destination.checklist.taslagi.kaydedildi.esitle.ile.gonderin.69a4d941", table: .localizable, fallback: "Checklist taslağı kaydedildi. Eşitle ile gönderin.")
                } catch { message = RDLocalization.string("localizable.notebook.destination.checklist.kaydedilemedi.bos.tekrar.eden.alanlari.fc47d00d", table: .localizable, fallback: "Checklist kaydedilemedi. Boş/tekrar eden alanları ve uzunluk sınırlarını kontrol edin.") }
            }
        }.padding(18) }.scrollDismissesKeyboard(.interactively)
    }
    private func openNewNote() {
        editor = .init(note: UUID(), version: 0, title: "", body: "", originalTitle: "", originalBody: "")
        message = nil
        Task { @MainActor in editorFocus = .title }
    }
    private func finishEditor(closeDestination: Bool) async {
        guard let edit = editor else { if closeDestination { onClose() }; return }
        let title = edit.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = edit.body.trimmingCharacters(in: .whitespacesAndNewlines)
        if edit.version == 0 && title.isEmpty && body.isEmpty {
            editor = nil
            if closeDestination { onClose() }
            return
        }
        if edit.pending == nil && edit.originalTitle == edit.title && edit.originalBody == edit.body {
            editor = nil
            if closeDestination { onClose() }
            return
        }
        await save(closeDestination: closeDestination)
    }
    private func openOrganization(_ note: UUID, pending: NotebookPending? = nil) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let value = try await repository.organization(note, identity: identity)
            guard !value.tombstone else { throw NotebookFailure.invalid }
            organization = .init(note: note, version: value.version, items: pending?.intent.items ?? value.items,
                tags: (pending?.intent.tags ?? value.tags).joined(separator: ", "), pending: pending?.intent.mutation,
                serverText: pending == nil ? nil : value.items.map { ($0.done ? "✓ " : "○ ") + $0.text }.joined(separator: "\n") + "\n" + value.tags.joined(separator: ", "))
        } catch { message = RDLocalization.string("localizable.notebook.destination.checklist.yuklenemedi.veya.not.silinmis.kaydedil.417bd636", table: .localizable, fallback: "Checklist yüklenemedi veya not silinmiş. Kaydedilmiş taslaklar korunuyor.") }
    }
    private func refresh() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            snapshot = try repository.snapshot(identity)
            try await repository.reader.refresh(identity)
            async let currentReminders = repository.reminders(identity)
            snapshot = try repository.snapshot(identity)
            reminders = try await currentReminders
            message = nil
        } catch { message = RDLocalization.string("localizable.notebook.destination.esitleme.kullanilamiyor.bu.cihazdaki.kaydedilmis.bc0dfda7", table: .localizable, fallback: "Eşitleme kullanılamıyor. Bu cihazdaki kaydedilmiş taslaklarınız korunuyor.") }
    }
    private func save(delete: Bool = false, closeDestination: Bool = false) async {
        guard !busy, let edit = editor else { return }
        do {
            let intent = NotebookMutation(mutation: UUID(), note: edit.note, action: delete ? "delete" : edit.pending == nil ? "sync" : "resolve",
                expected: edit.version, title: delete ? nil : edit.title, body: delete ? nil : edit.body, conflict: edit.pending?.conflictID)
            if let pending = edit.pending { try repository.queue.resolveBlocked(pending.intent.mutation, with: intent, identity: identity) }
            else { try repository.queue.stage(intent, identity: identity) }
            snapshot = try repository.snapshot(identity); editor = nil; message = RDLocalization.string("localizable.notebook.destination.taslak.bu.cihazda.kaydedildi.esitle.ile.sunucuya.564ba03c", table: .localizable, fallback: "Taslak bu cihazda kaydedildi. Eşitle ile sunucuya gönderebilirsiniz.")
            if NetworkMonitor.shared.isOnline { await sync() }
            if closeDestination { onClose() }
        } catch { message = RDLocalization.string("localizable.notebook.destination.kaydedilemedi.metni.kapatmadan.uzunlugu.oturumu..8cd64c3f", table: .localizable, fallback: "Kaydedilemedi. Metni kapatmadan uzunluğu, oturumu ve cihaz erişimini kontrol edin.") }
    }
    private func sync() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            for _ in 0..<20 { if try await repository.queue.syncNext(identity) == "idle" { break } }
            try await repository.reader.refresh(identity)
            reminders = try await repository.reminders(identity)
            snapshot = try repository.snapshot(identity); message = RDLocalization.string("localizable.notebook.destination.esitleme.tamamlandi.islem.gerektiren.taslaklar.a.d6d47393", table: .localizable, fallback: "Eşitleme tamamlandı. İşlem gerektiren taslaklar ayrıca gösterilir.")
        } catch {
            snapshot = (try? repository.snapshot(identity)) ?? .init(notes: [], drafts: [])
            message = RDLocalization.string("localizable.notebook.destination.esitleme.tamamlanamadi.bekleyen.islemler.ayni.ki.544f48e2", table: .localizable, fallback: "Eşitleme tamamlanamadı. Bekleyen işlemler aynı kimlikle yeniden denenecek.")
        }
    }
    private func resolve(_ pending: NotebookPending) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let (note, _) = try await repository.conflict(pending, identity: identity)
            editor = .init(note: note.note_id, version: note.version, title: pending.intent.title ?? "", body: pending.intent.body ?? "", pending: pending,
                serverText: (note.title ?? "") + "\n" + (note.body ?? ""))
        } catch { message = RDLocalization.string("localizable.notebook.destination.guncel.surum.alinamadi.veya.not.silinmis.taslagi.45311491", table: .localizable, fallback: "Güncel sürüm alınamadı veya not silinmiş. Taslağınız korunuyor; eşitleyip yeniden deneyin.") }
    }
    private func createReminder() async {
        guard !busy, let value = reminderEditor else { return }
        busy = true; defer { busy = false }
        do {
            _ = try await repository.createReminder(title: value.title, recurrence: value.recurrence,
                dueAt: value.dueAt, note: value.note, identity: identity)
            reminders = try await repository.reminders(identity)
            reminderEditor = nil
            message = RDLocalization.string("localizable.notebook.destination.hatirlatici.bu.cihazin.sunucu.bildirimi.kaydina..4ea41591", table: .localizable, fallback: "Hatırlatıcı bu cihazın sunucu bildirimi kaydına bağlandı.")
        } catch let error as NotebookServerFailure {
            message = error.code == "DEVICE_UNAVAILABLE"
                ? RDLocalization.string("localizable.notebook.destination.bildirim.izni.ve.guncel.cihaz.kaydi.gerekli.bild.a2d8f091", table: .localizable, fallback: "Bildirim izni ve güncel cihaz kaydı gerekli. Bildirimleri açıp yeniden deneyin.")
                : RDLocalization.string("localizable.notebook.destination.hatirlatici.olusturulamadi.oturumu.ve.alanlari.k.a096b14c", table: .localizable, fallback: "Hatırlatıcı oluşturulamadı. Oturumu ve alanları kontrol edip yeniden deneyin.")
        } catch { message = RDLocalization.string("localizable.notebook.destination.hatirlatici.olusturulamadi.baglantiyi.ve.tarihi..a8b8cf37", table: .localizable, fallback: "Hatırlatıcı oluşturulamadı. Bağlantıyı ve tarihi kontrol edip yeniden deneyin.") }
    }
    private func settleReminder(_ action: String, reminder: NotebookReminder,
                                occurrence: NotebookReminderOccurrence? = nil) async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            let baseline = occurrence.flatMap { NotebookReminderDate.parse($0.effective_due_at) } ?? Date()
            let snoozedUntil = action == "snooze" ? max(baseline, Date()).addingTimeInterval(10 * 60) : nil
            try await repository.settleReminder(action, reminder: reminder, occurrence: occurrence,
                snoozedUntil: snoozedUntil, identity: identity)
            reminders = try await repository.reminders(identity)
            message = action == "complete" ? RDLocalization.string("localizable.notebook.destination.hatirlatici.tamamlandi.01582ea4", table: .localizable, fallback: "Hatırlatıcı tamamlandı.") : action == "snooze" ? RDLocalization.string("localizable.notebook.destination.hatirlatici.10.dakika.ertelendi.4ccf81b9", table: .localizable, fallback: "Hatırlatıcı 10 dakika ertelendi.") : RDLocalization.string("localizable.notebook.destination.hatirlatici.iptal.edildi.d1892027", table: .localizable, fallback: "Hatırlatıcı iptal edildi.")
        } catch { message = RDLocalization.string("localizable.notebook.destination.hatirlatici.degistirilemedi.guncel.listeyi.esitl.b46c2f0f", table: .localizable, fallback: "Hatırlatıcı değiştirilemedi. Güncel listeyi eşitleyip yeniden deneyin.") }
    }
    private func reminderSchedule(_ reminder: NotebookReminder) -> String {
        guard let raw = reminder.next_occurrence?.effective_due_at,
              let date = NotebookReminderDate.parse(raw) else { return "" }
        return " · " + date.formatted(date: .abbreviated, time: .shortened)
    }
}
