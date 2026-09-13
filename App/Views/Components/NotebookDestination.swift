import SwiftUI
import Supabase

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
                NovaPageSurface { VStack { NovaText(text: "Not defteri için oturum açın."); NovaButton(label: "Kapat", symbol: "xmark", action: onClose) }.padding(18) }
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
private struct NotebookContent: View {
    let repository: NotebookRepository
    let identity: NotebookIdentity
    let onClose: () -> Void
    @State private var snapshot = NotebookReader.Snapshot(notes: [], drafts: [])
    @State private var editor: NotebookEditorState?
    @State private var organization: NotebookOrganizationEditor?
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
                            NovaButton(label: "Kapat", symbol: "chevron.left", variant: .surface) {
                                if editor == nil && organization == nil { onClose() } else { closeAfterExit = true; confirmExit = true }
                            }
                            NovaText(text: "Kişisel Notlar", style: .screenTitle)
                        }
                        NovaText(text: "Ücretsiz · Yalnız size ait · Firmalardan bağımsız", style: .metaQuiet)
                        if let message { NovaCard(padding: 16) { Label(message, systemImage: "info.circle") } }
                        if organization != nil { organizationFields } else if editor != nil { editorFields } else { list }
                    }.padding(18)
                }.disabled(busy || confirmDelete || confirmExit).blur(radius: confirmDelete || confirmExit ? 7 : 0)
                if confirmExit {
                    Color.black.opacity(0.34).ignoresSafeArea().onTapGesture { confirmExit = false }
                    NovaPopupSurface {
                        VStack(spacing: 16) {
                            Label("Kaydedilmemiş değişiklikler", systemImage: "exclamationmark.triangle")
                            NovaText(text: "Editördeki değişiklikleri kaydetmeden çıkmak istiyor musunuz? Daha önce kaydedilmiş taslaklar silinmez.")
                            NovaButton(label: "Kaydetmeden çık", symbol: "xmark", variant: .danger) {
                                confirmExit = false; editor = nil; organization = nil; if closeAfterExit { onClose() }
                            }
                            NovaButton(label: "Düzenlemeye dön", symbol: "chevron.left", variant: .surface) { confirmExit = false }
                        }
                    }.padding(18)
                }
                if confirmDelete {
                    Color.black.opacity(0.34).ignoresSafeArea().onTapGesture { confirmDelete = false }
                    NovaPopupSurface {
                        VStack(spacing: 16) {
                            Label("Not silinsin mi?", systemImage: "trash")
                            NovaText(text: "İşlem önce cihazda saklanır. Sunucu onayladığında not diğer cihazlarda da silinir.")
                            NovaButton(label: "Sil", symbol: "trash", variant: .danger) { confirmDelete = false; Task { await save(delete: true) } }
                            NovaButton(label: "Vazgeç", symbol: "chevron.left", variant: .surface) { confirmDelete = false }
                        }
                    }.padding(18)
                }
                if busy { ProgressView().accessibilityLabel("İşlem sürüyor") }
            }
        }.preferredColorScheme(.light).task { await refresh() }.privacySensitive()
    }
    private var list: some View {
        VStack(alignment: .leading, spacing: 14) {
            NovaButton(label: "Yeni not", symbol: "square.and.pencil") {
                editor = .init(note: UUID(), version: 0, title: "", body: "")
            }.accessibilityIdentifier("notebook.add")
            NovaButton(label: "Eşitle", symbol: "arrow.triangle.2.circlepath", variant: .surface) { Task { await sync() } }
            if snapshot.notes.isEmpty && snapshot.drafts.isEmpty { NovaCard(padding: 20) { Label("Henüz not yok", systemImage: "note.text") } }
            ForEach(snapshot.drafts, id: \.intent.mutation) { pending in
                NovaCard(padding: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(pending.blocked == nil ? "Gönderilmeyi bekliyor" : "Taslağınız korunuyor · işlem gerekli", systemImage: "icloud.slash")
                        NovaText(text: pending.intent.title ?? "Başlıksız not", style: .cardTitle)
                        NovaText(text: pending.intent.body ?? (pending.intent.action == "organize" ? "Checklist ve etiket taslağı" : "Silme isteği"))
                        if pending.intent.action == "organize" {
                            Text((pending.intent.items ?? []).map { ($0.done ? "✓ " : "○ ") + $0.text }.joined(separator: "\n"))
                            Text((pending.intent.tags ?? []).joined(separator: ", "))
                            if pending.blocked == "VERSION_CONFLICT" {
                                NovaButton(label: "Checklist sürümlerini incele", symbol: "checklist", variant: .surface) { Task { await openOrganization(pending.intent.note, pending: pending) } }
                            }
                        }
                        if pending.conflictID != nil {
                            NovaButton(label: "İki sürümü incele", symbol: "arrow.triangle.branch", variant: .surface) { Task { await resolve(pending) } }
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
                            Label(note.title?.isEmpty == false ? note.title! : "Başlıksız not", systemImage: "note.text")
                            NovaText(text: note.body ?? "", style: .metaQuiet).lineLimit(3)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.buttonStyle(.plain).disabled(snapshot.drafts.contains { $0.intent.note == note.note_id })
                NovaButton(label: "Checklist ve etiketler", symbol: "checklist", variant: .surface,
                    isEnabled: !snapshot.drafts.contains { $0.intent.note == note.note_id }) { Task { await openOrganization(note.note_id) } }
            }
        }
    }
    private var editorFields: some View {
        VStack(spacing: 14) {
            if let text = editor?.serverText { NovaCard(padding: 18) { VStack(alignment: .leading) { Label("Güncel sunucu sürümü", systemImage: "icloud"); Text(text).textSelection(.enabled) } } }
            NovaCard(padding: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Başlık", text: Binding(get: { editor?.title ?? "" }, set: { editor?.title = $0 })).accessibilityIdentifier("notebook.title")
                    TextEditor(text: Binding(get: { editor?.body ?? "" }, set: { editor?.body = $0 })).frame(minHeight: 200).accessibilityIdentifier("notebook.body")
                    NovaText(text: "Başlık en çok 200, metin en çok 20.000 karakter.", style: .metaQuiet)
                }
            }
            NovaButton(label: "Taslağı güvenle kaydet", symbol: "checkmark") { Task { await save() } }
            if editor?.version ?? 0 > 0 && editor?.pending == nil {
                NovaButton(label: "Notu sil", symbol: "trash", variant: .danger) { confirmDelete = true }
            }
            NovaButton(label: "Listeye dön", symbol: "chevron.left", variant: .surface) { closeAfterExit = false; confirmExit = true }
        }
    }
    private var organizationFields: some View {
        VStack(spacing: 14) {
            if let text = organization?.serverText { NovaCard(padding: 18) { Text("Güncel sunucu checklist'i\n" + text).textSelection(.enabled) } }
            NovaCard(padding: 18) {
                VStack(spacing: 12) {
                    TextField("Etiketler (virgülle ayırın)", text: Binding(get: { organization?.tags ?? "" }, set: { organization?.tags = $0 }))
                    ForEach(organization?.items ?? [], id: \.item_id) { item in
                        HStack {
                            Toggle("Tamamlandı", isOn: Binding(get: { organization?.items.first { $0.item_id == item.item_id }?.done ?? false },
                                set: { value in if let i = organization?.items.firstIndex(where: { $0.item_id == item.item_id }) { organization?.items[i].done = value } })).labelsHidden()
                            TextField("Yapılacak", text: Binding(get: { organization?.items.first { $0.item_id == item.item_id }?.text ?? "" },
                                set: { value in if let i = organization?.items.firstIndex(where: { $0.item_id == item.item_id }) { organization?.items[i].text = value } }))
                            Button { organization?.items.removeAll { $0.item_id == item.item_id } } label: { Image(systemName: "minus.circle") }.accessibilityLabel("Checklist maddesini kaldır")
                        }
                    }
                }
            }
            NovaButton(label: "Madde ekle", symbol: "plus", isEnabled: (organization?.items.count ?? 0) < 500) { organization?.items.append(.init(item_id: UUID(), text: "", done: false)) }
            NovaButton(label: "Checklist taslağını kaydet", symbol: "checkmark") {
                guard let value = organization else { return }
                do {
                    let tags = value.tags.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    let intent = NotebookMutation(mutation: UUID(), note: value.note, action: "organize", expected: value.version, title: nil, body: nil, conflict: nil, items: value.items, tags: tags)
                    if let pending = value.pending { try repository.queue.replaceOrganization(pending, with: intent, identity: identity) }
                    else { try repository.queue.stage(intent, identity: identity) }
                    snapshot = try repository.snapshot(identity); organization = nil; message = "Checklist taslağı kaydedildi. Eşitle ile gönderin."
                } catch { message = "Checklist kaydedilemedi. Boş/tekrar eden alanları ve uzunluk sınırlarını kontrol edin." }
            }
            NovaButton(label: "Listeye dön", symbol: "chevron.left", variant: .surface) { closeAfterExit = false; confirmExit = true }
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
        } catch { message = "Checklist yüklenemedi veya not silinmiş. Kaydedilmiş taslaklar korunuyor." }
    }
    private func refresh() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            snapshot = try repository.snapshot(identity)
            try await repository.reader.refresh(identity)
            snapshot = try repository.snapshot(identity); message = nil
        } catch { message = "Eşitleme kullanılamıyor. Bu cihazdaki kaydedilmiş taslaklarınız korunuyor." }
    }
    private func save(delete: Bool = false) async {
        guard !busy, let edit = editor else { return }
        do {
            let intent = NotebookMutation(mutation: UUID(), note: edit.note, action: delete ? "delete" : edit.pending == nil ? "sync" : "resolve",
                expected: edit.version, title: delete ? nil : edit.title, body: delete ? nil : edit.body, conflict: edit.pending?.conflictID)
            if let pending = edit.pending { try repository.queue.resolveBlocked(pending.intent.mutation, with: intent, identity: identity) }
            else { try repository.queue.stage(intent, identity: identity) }
            snapshot = try repository.snapshot(identity); editor = nil; message = "Taslak bu cihazda kaydedildi. Eşitle ile sunucuya gönderebilirsiniz."
        } catch { message = "Kaydedilemedi. Metni kapatmadan uzunluğu, oturumu ve cihaz erişimini kontrol edin." }
    }
    private func sync() async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            for _ in 0..<20 { if try await repository.queue.syncNext(identity) == "idle" { break } }
            try await repository.reader.refresh(identity)
            snapshot = try repository.snapshot(identity); message = "Eşitleme tamamlandı. İşlem gerektiren taslaklar ayrıca gösterilir."
        } catch {
            snapshot = (try? repository.snapshot(identity)) ?? .init(notes: [], drafts: [])
            message = "Eşitleme tamamlanamadı. Bekleyen işlemler aynı kimlikle yeniden denenecek."
        }
    }
    private func resolve(_ pending: NotebookPending) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do {
            let (note, _) = try await repository.conflict(pending, identity: identity)
            editor = .init(note: note.note_id, version: note.version, title: pending.intent.title ?? "", body: pending.intent.body ?? "", pending: pending,
                serverText: (note.title ?? "") + "\n" + (note.body ?? ""))
        } catch { message = "Güncel sürüm alınamadı veya not silinmiş. Taslağınız korunuyor; eşitleyip yeniden deneyin." }
    }
}
