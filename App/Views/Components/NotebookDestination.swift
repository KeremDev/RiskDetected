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

/// Local UI release gate is independent of paid capabilities. Server rollout still authorizes RPCs.
enum NotebookUIRelease { static let enabled = false }

struct NotebookDestination: View {
    let onClose: () -> Void
    @State private var repository = NotebookRepository(sdk: SupabaseService.shared.client)
    @State private var identity: NotebookIdentity?
    var body: some View {
        Group {
            if let identity {
                NotebookContent(repository: repository, identity: identity, onClose: onClose)
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
}
private struct NotebookContent: View {
    let repository: NotebookRepository
    let identity: NotebookIdentity
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
    var body: some View {
        NovaPageSurface {
            ZStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            NovaButton(label: RDLocalization.string("localizable.notebook.destination.kapat.fc1bf7d5", table: .localizable, fallback: "Kapat"), symbol: "chevron.left", variant: .surface) {
                                if editor == nil && organization == nil && reminderEditor == nil { onClose() } else { closeAfterExit = true; confirmExit = true }
                            }
                            NovaText(text: RDLocalization.string("localizable.notebook.destination.kisisel.notlar.a3d7499d", table: .localizable, fallback: "Kişisel Notlar"), style: .screenTitle)
                        }
                        NovaText(text: RDLocalization.string("localizable.notebook.destination.ucretsiz.yalniz.size.ait.firmalardan.bagimsiz.0a2e3688", table: .localizable, fallback: "Ücretsiz · Yalnız size ait · Firmalardan bağımsız"), style: .metaQuiet)
                        if let message { NovaCard(padding: 16) { Label(message, systemImage: "info.circle") } }
                        if organization != nil { organizationFields }
                        else if reminderEditor != nil { reminderFields }
                        else if editor != nil { editorFields }
                        else { list }
                    }.padding(18)
                }.disabled(busy || confirmDelete || confirmExit).blur(radius: confirmDelete || confirmExit ? 7 : 0)
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
        }.preferredColorScheme(.light).task { await refresh() }.privacySensitive()
    }
    private var list: some View {
        VStack(alignment: .leading, spacing: 14) {
            NovaButton(label: RDLocalization.string("localizable.notebook.destination.yeni.not.96d419d7", table: .localizable, fallback: "Yeni not"), symbol: "square.and.pencil") {
                editor = .init(note: UUID(), version: 0, title: "", body: "")
            }.accessibilityIdentifier("notebook.add")
            NovaButton(label: RDLocalization.string("localizable.notebook.destination.esitle.ec7babeb", table: .localizable, fallback: "Eşitle"), symbol: "arrow.triangle.2.circlepath", variant: .surface) { Task { await sync() } }
            HStack {
                NovaText(text: RDLocalization.string("localizable.notebook.destination.hatirlaticilar.sunucu.bildirimi.1de99c40", table: .localizable, fallback: "Hatırlatıcılar · Sunucu bildirimi"), style: .cardTitle)
                Spacer()
                Image(systemName: "bell.badge")
            }
            NovaText(text: RDLocalization.string("localizable.notebook.destination.ilk.surumde.yerel.alarm.kullanilmaz.teslimat.bu..a5c0ee4a", table: .localizable, fallback: "İlk sürümde yerel alarm kullanılmaz. Teslimat, bu kurulumun yetkili bildirim kaydına bağlanır."), style: .metaQuiet)
            NovaButton(label: RDLocalization.string("localizable.notebook.destination.yeni.hatirlatici.dbfa239c", table: .localizable, fallback: "Yeni hatırlatıcı"), symbol: "bell.badge") {
                reminderEditor = NotebookReminderEditor()
            }
            ForEach(reminders.filter { $0.state == "active" }) { reminder in
                NovaCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Label(reminder.title, systemImage: "bell")
                        NovaText(text: notebookRecurrenceLabel(reminder.recurrence) + reminderSchedule(reminder), style: .metaQuiet)
                        if let occurrence = reminder.next_occurrence {
                            HStack {
                                NovaButton(label: "Tamamla", symbol: "checkmark", variant: .surface) {
                                    Task { await settleReminder("complete", reminder: reminder, occurrence: occurrence) }
                                }
                                NovaButton(label: RDLocalization.string("localizable.notebook.destination.10.dk.ertele.5de1fe5a", table: .localizable, fallback: "10 dk ertele"), symbol: "clock.arrow.circlepath", variant: .surface) {
                                    Task { await settleReminder("snooze", reminder: reminder, occurrence: occurrence) }
                                }
                            }
                        }
                        NovaButton(label: RDLocalization.string("localizable.notebook.destination.hatirlaticiyi.iptal.et.66814eec", table: .localizable, fallback: "Hatırlatıcıyı iptal et"), symbol: "bell.slash", variant: .danger) {
                            Task { await settleReminder("cancel", reminder: reminder) }
                        }
                    }
                }
            }
            if snapshot.notes.isEmpty && snapshot.drafts.isEmpty { NovaCard(padding: 20) { Label(RDLocalization.string("localizable.notebook.destination.henuz.not.yok.01cfb913", table: .localizable, fallback: "Henüz not yok"), systemImage: "note.text") } }
            ForEach(snapshot.drafts, id: \.intent.mutation) { pending in
                NovaCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(pending.blocked == nil ? RDLocalization.string("localizable.notebook.destination.gonderilmeyi.bekliyor.303c7ae8", table: .localizable, fallback: "Gönderilmeyi bekliyor") : RDLocalization.string("localizable.notebook.destination.taslaginiz.korunuyor.islem.gerekli.9cc6b790", table: .localizable, fallback: "Taslağınız korunuyor · işlem gerekli"), systemImage: "icloud.slash")
                        NovaText(text: pending.intent.title ?? RDLocalization.string("localizable.notebook.destination.basliksiz.not.032c1b51", table: .localizable, fallback: "Başlıksız not"), style: .cardTitle)
                        NovaText(text: pending.intent.body ?? (pending.intent.action == "organize" ? RDLocalization.string("localizable.notebook.destination.checklist.ve.etiket.taslagi.e192ce35", table: .localizable, fallback: "Checklist ve etiket taslağı") : RDLocalization.string("localizable.notebook.destination.silme.istegi.fa696aef", table: .localizable, fallback: "Silme isteği")))
                        if pending.intent.action == "organize" {
                            Text((pending.intent.items ?? []).map { ($0.done ? "✓ " : "○ ") + $0.text }.joined(separator: "\n"))
                            Text((pending.intent.tags ?? []).joined(separator: ", "))
                            if pending.blocked == "VERSION_CONFLICT" {
                                NovaButton(label: RDLocalization.string("localizable.notebook.destination.checklist.surumlerini.incele.97092e1b", table: .localizable, fallback: "Checklist sürümlerini incele"), symbol: "checklist", variant: .surface) { Task { await openOrganization(pending.intent.note, pending: pending) } }
                            }
                        }
                        if pending.conflictID != nil {
                            NovaButton(label: RDLocalization.string("localizable.notebook.destination.iki.surumu.incele.df04069e", table: .localizable, fallback: "İki sürümü incele"), symbol: "arrow.triangle.branch", variant: .surface) { Task { await resolve(pending) } }
                        }
                    }
                }
            }
            ForEach(snapshot.notes, id: \.note_id) { note in
                Button {
                    editor = .init(note: note.note_id, version: note.version, title: note.title ?? "", body: note.body ?? "")
                } label: {
                    NovaCard(padding: 18) {
                        VStack(alignment: .leading, spacing: 8) {
                            Label(note.title?.isEmpty == false ? note.title! : RDLocalization.string("localizable.notebook.destination.basliksiz.not.0ceaa7da", table: .localizable, fallback: "Başlıksız not"), systemImage: "note.text")
                            NovaText(text: note.body ?? "", style: .metaQuiet).lineLimit(3)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.buttonStyle(.plain).disabled(snapshot.drafts.contains { $0.intent.note == note.note_id })
                NovaButton(label: RDLocalization.string("localizable.notebook.destination.checklist.ve.etiketler.8bf05f5e", table: .localizable, fallback: "Checklist ve etiketler"), symbol: "checklist", variant: .surface,
                    isEnabled: !snapshot.drafts.contains { $0.intent.note == note.note_id }) { Task { await openOrganization(note.note_id) } }
            }
        }
    }
    private var reminderFields: some View {
        VStack(spacing: 14) {
            NovaCard(padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    Label(RDLocalization.string("localizable.notebook.destination.yeni.hatirlatici.acb2b922", table: .localizable, fallback: "Yeni hatırlatıcı"), systemImage: "bell.badge")
                    TextField(RDLocalization.string("localizable.notebook.destination.baslik.f4cde22e", table: .localizable, fallback: "Başlık"), text: Binding(get: { reminderEditor?.title ?? "" }, set: { reminderEditor?.title = $0 }))
                        .accessibilityIdentifier("notebook.reminder.title")
                    Picker("Tekrar", selection: Binding(get: { reminderEditor?.recurrence ?? .once }, set: { reminderEditor?.recurrence = $0 })) {
                        ForEach(NotebookReminderRecurrence.allCases) { recurrence in
                            Text(notebookRecurrenceLabel(recurrence)).tag(recurrence)
                        }
                    }.pickerStyle(.menu)
                    DatePicker(RDLocalization.string("localizable.notebook.destination.tarih.ve.saat.12f085f6", table: .localizable, fallback: "Tarih ve saat"), selection: Binding(get: { reminderEditor?.dueAt ?? Date() }, set: { reminderEditor?.dueAt = $0 }),
                               in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    NovaText(text: RDLocalization.string("localizable.notebook.destination.teslimat.sahibi.bu.cihazdaki.sunucu.bildirimi.ka.d07077c3", table: .localizable, fallback: "Teslimat sahibi: bu cihazdaki sunucu bildirimi kaydı. Bildirim izni veya güncel cihaz kaydı yoksa hatırlatıcı oluşturulmaz."), style: .metaQuiet)
                }
            }
            NovaButton(label: RDLocalization.string("localizable.notebook.destination.hatirlaticiyi.olustur.f3065fd2", table: .localizable, fallback: "Hatırlatıcıyı oluştur"), symbol: "checkmark") { Task { await createReminder() } }
            NovaButton(label: RDLocalization.string("localizable.notebook.destination.listeye.don.b77bb4b3", table: .localizable, fallback: "Listeye dön"), symbol: "chevron.left", variant: .surface) { closeAfterExit = false; confirmExit = true }
        }
    }
    private var editorFields: some View {
        VStack(spacing: 14) {
            if let text = editor?.serverText { NovaCard(padding: 18) { VStack(alignment: .leading) { Label(RDLocalization.string("localizable.notebook.destination.guncel.sunucu.surumu.df387713", table: .localizable, fallback: "Güncel sunucu sürümü"), systemImage: "icloud"); Text(text).textSelection(.enabled) } } }
            NovaCard(padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField(RDLocalization.string("localizable.notebook.destination.baslik.035bd998", table: .localizable, fallback: "Başlık"), text: Binding(get: { editor?.title ?? "" }, set: { editor?.title = $0 })).accessibilityIdentifier("notebook.title")
                    TextEditor(text: Binding(get: { editor?.body ?? "" }, set: { editor?.body = $0 })).frame(minHeight: 200).accessibilityIdentifier("notebook.body")
                    NovaText(text: RDLocalization.string("localizable.notebook.destination.baslik.en.cok.200.metin.en.cok.20.000.karakter.158acde5", table: .localizable, fallback: "Başlık en çok 200, metin en çok 20.000 karakter."), style: .metaQuiet)
                }
            }
            NovaButton(label: RDLocalization.string("localizable.notebook.destination.taslagi.guvenle.kaydet.53b9a015", table: .localizable, fallback: "Taslağı güvenle kaydet"), symbol: "checkmark") { Task { await save() } }
            if editor?.version ?? 0 > 0 && editor?.pending == nil {
                NovaButton(label: RDLocalization.string("localizable.notebook.destination.notu.sil.e405f33b", table: .localizable, fallback: "Notu sil"), symbol: "trash", variant: .danger) { confirmDelete = true }
            }
            NovaButton(label: RDLocalization.string("localizable.notebook.destination.listeye.don.d70e4dff", table: .localizable, fallback: "Listeye dön"), symbol: "chevron.left", variant: .surface) { closeAfterExit = false; confirmExit = true }
        }
    }
    private var organizationFields: some View {
        VStack(spacing: 14) {
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
            NovaButton(label: RDLocalization.string("localizable.notebook.destination.listeye.don.fdea1f52", table: .localizable, fallback: "Listeye dön"), symbol: "chevron.left", variant: .surface) { closeAfterExit = false; confirmExit = true }
        }
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
    private func save(delete: Bool = false) async {
        guard !busy, let edit = editor else { return }
        do {
            let intent = NotebookMutation(mutation: UUID(), note: edit.note, action: delete ? "delete" : edit.pending == nil ? "sync" : "resolve",
                expected: edit.version, title: delete ? nil : edit.title, body: delete ? nil : edit.body, conflict: edit.pending?.conflictID)
            if let pending = edit.pending { try repository.queue.resolveBlocked(pending.intent.mutation, with: intent, identity: identity) }
            else { try repository.queue.stage(intent, identity: identity) }
            snapshot = try repository.snapshot(identity); editor = nil; message = RDLocalization.string("localizable.notebook.destination.taslak.bu.cihazda.kaydedildi.esitle.ile.sunucuya.564ba03c", table: .localizable, fallback: "Taslak bu cihazda kaydedildi. Eşitle ile sunucuya gönderebilirsiniz.")
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
                dueAt: value.dueAt, identity: identity)
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
