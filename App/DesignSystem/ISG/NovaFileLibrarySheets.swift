import SwiftUI
import CryptoKit
import UniformTypeIdentifiers

/// One filed document in full, and every action on it, in one popup: what it
/// is, where it got to, what cleared it, and how to open, rename or put it away.
struct NovaFileEntrySheet: View {
    let entry: NovaFileEntry
    let catalogue: [NovaFileCategory]
    let assurance: NovaFileAssurance
    let client: NovaFileLibraryClient
    var canWrite = true
    let onChanged: () -> Void
    let onClosed: () -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var current: NovaFileEntry?
    @State private var editing = false
    @State private var confirmingArchive = false
    @State private var busy = false
    @State private var error: String?
    @State private var opened: URL?

    private var row: NovaFileEntry { current ?? entry }
    private var group: NovaFileGroup { .of(row.state) }
    private var tone: NovaStatus { NovaFileScreenWords.tone(group) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                heading
                chips
                if row.state.isStopped { refusal }
                facts
                assuranceCard
                if let error {
                    NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme))
                }
                controls
            }.padding(16).novaPopupContentSize()
        }
        .novaFullScreenCover(isPresented: $editing) {
            NovaPopup {
                NovaFileRenameSheet(entry: row, catalogue: catalogue) { title, category, note in
                    current = try await client.rename(row, title, category, note)
                    editing = false
                    onChanged()
                }
            }
        }
        // The original, exactly as it was filed. The share sheet is the OS's.
        .sheet(item: $opened) { url in NovaFileShareSheet(url: url) }
    }

    private var heading: some View {
        HStack(alignment: .top, spacing: 10) {
            NovaIcon(symbol: NovaFileWords.symbol(row.state), size: 19)
                .foregroundStyle(tone.tokens.ink.color(in: scheme))
                .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                NovaText(text: row.title, style: .sheetTitle).lineLimit(2)
                if row.fileName != row.title { NovaText(text: row.fileName, style: .metaQuiet) }
            }
            Spacer(minLength: 0)
        }
    }

    private var chips: some View {
        HStack(spacing: 5) {
            NovaStatusPill(label: NovaFileWords.state(row.state), status: tone)
            if let name = row.companyName {
                NovaAnalysisTag(symbol: "building.2", text: name, status: .neutral)
            }
            NovaAnalysisTag(symbol: "folder", text: NovaFileWords.category(row.category), status: .neutral)
            Spacer(minLength: 0)
        }
    }

    /// Why the file is not in the archive, in the expert's own terms, with the
    /// inspector's own finding underneath when it named one.
    private var refusal: some View {
        NovaCard(padding: 11, tint: tone.tokens.background.color(in: scheme)) {
            VStack(alignment: .leading, spacing: 5) {
                NovaText(text: NovaFileWords.rejection(row.rejectionCode), style: .meta)
                if let finding = row.scanFinding, !finding.isEmpty {
                    NovaText(text: NovaFileWords.finding(finding), style: .metaQuiet)
                }
                if row.state == .scanFailed {
                    NovaText(text: RDLocalization.string("localizable.nova.file.unchecked.explain", table: .localizable,
                        fallback: "Denetim tamamlanamadığı için dosya arşive alınmadı. Bu, dosyanın zararlı olduğu anlamına gelmez; dosyayı yeniden ekleyerek tekrar deneyebilirsiniz."),
                        style: .metaQuiet)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var facts: some View {
        NovaCard(padding: 11) {
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 7), GridItem(.flexible(), spacing: 7)],
                      alignment: .leading, spacing: 7) {
                cell("doc", RDLocalization.string("localizable.nova.file.field.type", table: .localizable, fallback: "Tür"),
                     row.fileExtension.isEmpty ? "—" : row.fileExtension.uppercased())
                cell("externaldrive", RDLocalization.string("localizable.nova.file.field.size", table: .localizable, fallback: "Boyut"),
                     NovaFileWords.size(row.bytes))
                // The type the server worked out from the bytes, not from the name.
                cell("magnifyingglass", RDLocalization.string("localizable.nova.file.field.detected", table: .localizable, fallback: "Saptanan tür"),
                     row.detectedType ?? RDLocalization.string("localizable.nova.file.field.unknown", table: .localizable, fallback: "Henüz belirlenmedi"))
                cell("clock", RDLocalization.string("localizable.nova.file.field.added", table: .localizable, fallback: "Eklendi"),
                     row.createdAt.map { String($0.prefix(10)) } ?? "—")
            }
            if let note = row.note, !note.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    NovaText(text: RDLocalization.string("localizable.nova.document.field.note", table: .localizable, fallback: "Not"),
                        style: .micro, color: NovaColorToken.textTertiary.color(in: scheme))
                    NovaText(text: note, style: .metaQuiet)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 7)
            }
        }
    }

    /// What cleared this file, and what that does and does not mean. A row that
    /// nothing cleared says so rather than staying silent.
    private var assuranceCard: some View {
        NovaCard(padding: 11, tint: NovaColorToken.surfaceMuted.color(in: scheme)) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Image(systemName: "shield.lefthalf.filled").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                    NovaText(text: RDLocalization.string("localizable.nova.file.assurance.title", table: .localizable, fallback: "Denetim"),
                        style: .micro, color: NovaColorToken.textTertiary.color(in: scheme))
                }
                NovaText(text: row.scanner == nil
                    ? RDLocalization.string("localizable.nova.file.assurance.none", table: .localizable, fallback: "Bu dosya henüz denetlenmedi.")
                    : row.assurance == "format_inspection"
                        ? RDLocalization.string("localizable.nova.file.assurance.format", table: .localizable,
                            fallback: "Biçim denetimi: gerçek tür, boyut, özet ve makro/çalışan içerik kontrol edildi.")
                        : RDLocalization.string("localizable.nova.file.assurance.other", table: .localizable,
                            fallback: "Dosya, tanımlı olmayan bir denetimden geçti."),
                    style: .metaQuiet)
                // Never implied, always stated: no malware scan ran.
                if !row.malwareScanned {
                    NovaText(text: RDLocalization.string("localizable.nova.file.assurance.no.malware", table: .localizable,
                        fallback: "Virüs taraması yapılmadı."), style: .micro,
                        color: NovaColorToken.statusWarningInk.color(in: scheme))
                }
                if let scanner = row.scanner {
                    NovaText(text: scanner, style: .micro, color: NovaColorToken.textMuted.color(in: scheme))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var controls: some View {
        if row.canDownload {
            NovaButton(label: RDLocalization.string("localizable.nova.file.open", table: .localizable, fallback: "Dosyayı aç"),
                symbol: "arrow.down.doc", isEnabled: !busy, isLoading: busy) { open() }
                .accessibilityIdentifier("file.entry.open")
        } else if row.state.isWorking {
            NovaButton(label: RDLocalization.string("localizable.nova.file.recheck", table: .localizable, fallback: "Denetimi tekrar çalıştır"),
                symbol: "arrow.clockwise", variant: .surface, isEnabled: !busy, isLoading: busy) {
                run { current = try await client.recheck(row); onChanged() }
            }.accessibilityIdentifier("file.entry.recheck")
        }
        if canWrite {
            HStack(spacing: 8) {
                action("square.and.pencil", RDLocalization.string("localizable.nova.document.edit.short", table: .localizable, fallback: "Düzenle"),
                       id: "edit", status: .neutral) { editing = true }
                // An upload that never became a file is abandoned; a filed one
                // is put away. They are different things and say so.
                if row.state.isWorking {
                    action("xmark.circle", RDLocalization.string("localizable.nova.file.cancel", table: .localizable, fallback: "Yüklemeyi iptal et"),
                           id: "cancel", status: .danger) {
                        run { try await client.cancel(row); onChanged(); onClosed() }
                    }
                } else {
                    action("archivebox", RDLocalization.string("localizable.nova.file.archive", table: .localizable, fallback: "Listeden kaldır"),
                           id: "archive", status: .danger) { confirmingArchive = true }
                }
            }
            if confirmingArchive {
                NovaText(text: RDLocalization.string("localizable.nova.file.archive.confirm", table: .localizable,
                    fallback: "Kayıt listeden çıkar. Arşivdeki dosyanın kendisi silinmez."), style: .metaQuiet)
                NovaButton(label: RDLocalization.string("localizable.nova.document.archive.yes", table: .localizable, fallback: "Evet, arşivle"),
                    symbol: "archivebox", variant: .danger, isEnabled: !busy, isLoading: busy) {
                    run { try await client.archive(row); onChanged(); onClosed() }
                }.accessibilityIdentifier("file.entry.archive.confirm")
            }
        }
    }

    /// The original is written to a temporary file so the OS share sheet can
    /// hand it on. Nothing is sent anywhere by this app.
    private func open() {
        run {
            let data = try await client.contents(row)
            let name = row.fileName.isEmpty ? "belge.\(row.fileExtension)" : row.fileName
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
                .appendingPathComponent(name)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            try data.write(to: url, options: .completeFileProtection)
            opened = url
        }
    }

    private func run(_ work: @escaping () async throws -> Void) {
        Task {
            busy = true; error = nil
            do { try await work() }
            catch let failure as NovaFileFailure { error = NovaFileScreenWords.failure(failure) }
            catch { self.error = NovaFileScreenWords.failure(.unavailable) }
            busy = false
        }
    }

    private func action(_ symbol: String, _ label: String, id: String, status: NovaStatus,
                        run: @escaping () -> Void) -> some View {
        let palette = status.tokens
        return Button(action: run) {
            HStack(spacing: 7) {
                Image(systemName: symbol).font(.system(size: 13, weight: .semibold))
                NovaText(text: label, style: .meta, color: palette.ink.color(in: scheme))
            }
            .foregroundStyle(palette.ink.color(in: scheme))
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(palette.background.color(in: scheme), in: RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain).disabled(busy)
            .accessibilityIdentifier("file.entry.\(id)")
    }

    private func cell(_ symbol: String, _ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
                NovaText(text: label, style: .micro, color: NovaColorToken.textTertiary.color(in: scheme))
            }
            NovaText(text: value, style: .meta).lineLimit(2)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Renaming and refiling. The file itself never changes: what the expert edits
/// is the name it is filed under and the heading it belongs to.
struct NovaFileRenameSheet: View {
    let entry: NovaFileEntry
    let catalogue: [NovaFileCategory]
    let save: (String, String, String) async throws -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var title: String
    @State private var category: String
    @State private var note: String
    @State private var busy = false
    @State private var error: String?
    @State private var choosing = false

    init(entry: NovaFileEntry, catalogue: [NovaFileCategory],
         save: @escaping (String, String, String) async throws -> Void) {
        self.entry = entry; self.catalogue = catalogue; self.save = save
        _title = State(initialValue: entry.title)
        _category = State(initialValue: entry.category)
        _note = State(initialValue: entry.note ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                NovaText(text: RDLocalization.string("localizable.nova.file.rename.title", table: .localizable, fallback: "Dosya kaydını düzenle"),
                    style: .sheetTitle)
                NovaText(text: entry.fileName, style: .metaQuiet)
                field(RDLocalization.string("localizable.nova.file.field.title", table: .localizable, fallback: "Başlık"), $title, id: "title")
                categoryPicker
                field(RDLocalization.string("localizable.nova.document.field.note", table: .localizable, fallback: "Not"), $note, id: "note")
                if let error {
                    NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme))
                }
                NovaButton(label: RDLocalization.string("localizable.nova.document.save", table: .localizable, fallback: "Kaydet"),
                    symbol: "checkmark", isEnabled: !busy && !title.trimmingCharacters(in: .whitespaces).isEmpty,
                    isLoading: busy) {
                    Task {
                        busy = true; error = nil
                        do { try await save(title, category, note) }
                        catch let failure as NovaFileFailure { error = NovaFileScreenWords.failure(failure) }
                        catch { self.error = NovaFileScreenWords.failure(.validation) }
                        busy = false
                    }
                }.accessibilityIdentifier("file.rename.save")
            }.padding(16).novaPopupContentSize()
        }
    }

    /// The same chooser the archive uses, so refiling reads the way filing did.
    @ViewBuilder private var categoryPicker: some View {
        NovaFileChooserButton(
            label: RDLocalization.string("localizable.nova.file.field.category", table: .localizable, fallback: "Başlık altında sakla"),
            value: NovaFileWords.category(category), symbol: "folder",
            isOpen: choosing, identifier: "file.rename.category") { choosing.toggle() }
        if choosing {
            NovaFileChooserPanel(
                options: catalogue.map { .init(id: $0.code, title: NovaFileWords.category($0.code), symbol: "folder") },
                selected: category, identifier: "file.rename.category") { picked in
                    if let picked { category = picked }
                    choosing = false
                }
        }
    }

    private func field(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextField(label, text: text).font(NovaFont.font(.body))
                .frame(minHeight: 34).accessibilityIdentifier("file.rename.\(id)")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Filing a document. The company comes first, then the file itself, then what
/// it is called and where it belongs. The screen never shows the file as filed
/// before the server says it is.
/// A single "attach a file" field for a module form: shows what is attached,
/// opens the plain upload flow inline (no cover, no second screen) when there
/// is none, and lets the expert swap it. Self-loads the catalogue it needs, so
/// a caller only has to hand it a company, a category and a binding.
struct NovaInlineFileField: View {
    let category: String
    let company: UUID?
    let fileClient: NovaFileLibraryClient
    @Binding var assetID: String
    @Environment(\.colorScheme) private var scheme
    @State private var adding = false
    @State private var categories: [NovaFileCategory] = []
    @State private var accepts: [NovaFileAcceptance] = []
    @State private var assurance = NovaFileAssurance()
    @State private var loaded = false

    private var scopedCategories: [NovaFileCategory] {
        let scoped = categories.filter { $0.code == category }
        return scoped.isEmpty ? categories : scoped
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if !assetID.isEmpty && !adding {
                HStack(spacing: 8) {
                    Image(systemName: "doc.fill").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NovaColorToken.statusSuccessInk.color(in: scheme))
                    NovaText(text: RDLocalization.string("localizable.nova.emergency.form.file.attached",
                        table: .localizable, fallback: "Dosya ekli"), style: .meta)
                    Spacer(minLength: 0)
                    Button { assetID = "" } label: {
                        Image(systemName: "xmark.circle").font(.system(size: 12))
                    }.buttonStyle(.plain).accessibilityIdentifier("nova.inline.file.remove")
                }
            }
            if adding {
                NovaCard(padding: 12) {
                    NovaFileAddInline(companies: [], preselected: company, categories: scopedCategories,
                        accepts: accepts, assurance: assurance, client: fileClient) { entry in
                            if let entry, let id = entry.assetID { assetID = id.uuidString }
                            adding = false
                        }
                }
            } else {
                NovaButton(label: assetID.isEmpty
                    ? RDLocalization.string("localizable.nova.emergency.form.file.add", table: .localizable, fallback: "Dosya ekle")
                    : RDLocalization.string("localizable.nova.emergency.form.file.replace", table: .localizable, fallback: "Dosyayı değiştir"),
                    symbol: "paperclip", variant: .surface, isEnabled: company != nil) { adding = true }
                    .accessibilityIdentifier("nova.inline.file.add")
            }
        }
        .task {
            guard !loaded else { return }
            loaded = true
            if let filing = try? await fileClient.catalogue() {
                categories = filing.categories; accepts = filing.accepts; assurance = filing.assurance
            }
        }
    }
}

/// The bare upload flow — file pick, title/category/note, submit, result — with
/// no page chrome of its own, so a caller can drop it straight into an existing
/// form or scroll view instead of pushing to a separate screen for it.
struct NovaFileAddInline: View {
    let companies: [NovaAnalysisCompanyOption]
    var preselected: UUID?
    let categories: [NovaFileCategory]
    let accepts: [NovaFileAcceptance]
    let assurance: NovaFileAssurance
    let client: NovaFileLibraryClient
    /// Carries the filed row back once known, so a caller embedding this view
    /// (the emergency plan form, say) can pick up the asset it just cleared.
    let onDone: (NovaFileEntry?) -> Void
    @Environment(\.colorScheme) private var scheme
    @State private var company: UUID?
    @State private var draft = NovaFileDraft()
    @State private var payload: Data?
    @State private var picking = false
    @State private var busy = false
    @State private var error: String?
    @State private var outcome: NovaFileEntry?
    /// Opened on its own once a file is chosen, because filing it is the next
    /// thing the expert has to decide.
    @State private var choosingCategory = false
    @State private var choosingCompany = false

    private var maxBytes: Int { accepts.map(\.maxBytes).max() ?? 0 }
    private var allExtensions: [String] { accepts.flatMap(\.extensions).sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            if let outcome { result(outcome) } else { form }
        }
        .onAppear { if company == nil { company = preselected ?? companies.first?.id } }
        .fileImporter(isPresented: $picking,
                      allowedContentTypes: NovaFileScreenWords.contentTypes(accepts),
                      allowsMultipleSelection: false) { answer in take(answer) }
    }

    @ViewBuilder private var form: some View {
        if companies.count > 1 && preselected == nil { companyPicker }
        filePicker
        if payload != nil {
            field(RDLocalization.string("localizable.nova.file.field.title", table: .localizable, fallback: "Başlık"),
                  $draft.title, id: "title")
            categoryPicker
            field(RDLocalization.string("localizable.nova.document.field.note", table: .localizable, fallback: "Not"),
                  $draft.note, id: "note")
        }
        // What the server will accept, as the server declared it. The size is a
        // candidate limit and the screen says so rather than promising it.
        NovaHelpHint(text: String(format: RDLocalization.string("localizable.nova.file.accepts", table: .localizable,
            fallback: "Kabul edilen türler: %1$@. Üst sınır %2$@ (henüz onaylanmamış aday sınır)."),
            allExtensions.joined(separator: ", ").uppercased(), NovaFileWords.size(maxBytes)))
        if !assurance.malwareScanningAvailable {
            NovaText(text: RDLocalization.string("localizable.nova.file.add.no.malware", table: .localizable,
                fallback: "Dosya biçim denetiminden geçirilir; virüs taraması yapılmaz."),
                style: .micro, color: NovaColorToken.statusWarningInk.color(in: scheme))
        }
        if let error {
            NovaText(text: error, style: .metaQuiet, color: NovaColorToken.statusDangerInk.color(in: scheme))
        }
        NovaButton(label: RDLocalization.string("localizable.nova.file.add.save", table: .localizable, fallback: "Yükle ve denetle"),
            symbol: "arrow.up.doc", isEnabled: !busy && draft.isReady && payload != nil && company != nil,
            isLoading: busy) { send() }
            .accessibilityIdentifier("file.add.save")
    }

    /// The same chooser as the heading, so a long company list stays reachable.
    @ViewBuilder private var companyPicker: some View {
        NovaFileChooserButton(
            label: RDLocalization.string("localizable.nova.file.field.company", table: .localizable, fallback: "Firma"),
            value: companies.first { $0.id == company }?.name
                ?? RDLocalization.string("localizable.nova.file.company.choose", table: .localizable, fallback: "Firma seçin"),
            symbol: "building.2", isOpen: choosingCompany, isAnswered: company != nil,
            identifier: "file.add.company") { choosingCompany.toggle() }
        if choosingCompany {
            NovaFileChooserPanel(
                options: companies.map { .init(id: $0.id.uuidString, title: $0.name, symbol: "building.2") },
                selected: company?.uuidString, identifier: "file.add.company") { picked in
                    company = picked.flatMap(UUID.init(uuidString:))
                    choosingCompany = false
                }
        }
    }

    private var filePicker: some View {
        Button { picking = true } label: {
            HStack(spacing: 10) {
                NovaIcon(symbol: payload == nil ? "folder.badge.plus" : "doc", size: 17)
                    .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    NovaText(text: payload == nil
                        ? RDLocalization.string("localizable.nova.file.pick", table: .localizable, fallback: "Cihazdan dosya seçin")
                        : draft.fileName, style: .cardTitle).lineLimit(1)
                    NovaText(text: payload == nil
                        ? RDLocalization.string("localizable.nova.file.pick.hint", table: .localizable, fallback: "PDF, Word, Excel veya fotoğraf")
                        : NovaFileWords.size(draft.bytes), style: .micro,
                        color: NovaColorToken.textTertiary.color(in: scheme))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .bold))
                    .foregroundStyle(NovaColorToken.textTertiary.color(in: scheme))
            }
            .padding(11)
            .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
        }.buttonStyle(.plain).accessibilityIdentifier("file.add.pick")
    }

    /// The heading the file will be filed under. A chooser rather than a strip
    /// that runs off the side: thirteen headings are all reachable, and the one
    /// in force is always the thing on the button.
    @ViewBuilder private var categoryPicker: some View {
        NovaFileChooserButton(
            label: RDLocalization.string("localizable.nova.file.field.category", table: .localizable, fallback: "Başlık altında sakla"),
            value: draft.category.map(NovaFileWords.category)
                ?? RDLocalization.string("localizable.nova.file.category.choose", table: .localizable, fallback: "Başlık seçin"),
            symbol: "folder", isOpen: choosingCategory, isAnswered: draft.category != nil,
            identifier: "file.add.category") { choosingCategory.toggle() }
        if choosingCategory {
            NovaFileChooserPanel(
                options: categories.map { .init(id: $0.code, title: NovaFileWords.category($0.code), symbol: "folder") },
                selected: draft.category, identifier: "file.add.category") { picked in
                    draft.category = picked
                    choosingCategory = false
                }
        }
    }

    /// What actually happened to the file, from the server's own row.
    private func result(_ entry: NovaFileEntry) -> some View {
        let group = NovaFileGroup.of(entry.state)
        let tone = NovaFileScreenWords.tone(group)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                NovaIcon(symbol: NovaFileWords.symbol(entry.state), size: 18)
                    .foregroundStyle(tone.tokens.ink.color(in: scheme))
                    .frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    NovaText(text: entry.title, style: .cardTitle).lineLimit(2)
                    NovaText(text: NovaFileWords.state(entry.state), style: .metaQuiet)
                }
                Spacer(minLength: 0)
            }
            if entry.state.isStopped {
                NovaCard(padding: 11, tint: tone.tokens.background.color(in: scheme)) {
                    VStack(alignment: .leading, spacing: 5) {
                        NovaText(text: NovaFileWords.rejection(entry.rejectionCode), style: .meta)
                        if let finding = entry.scanFinding, !finding.isEmpty {
                            NovaText(text: NovaFileWords.finding(finding), style: .metaQuiet)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if entry.state.isWorking {
                NovaText(text: RDLocalization.string("localizable.nova.file.add.working", table: .localizable,
                    fallback: "Dosya denetimde. Listedeki kaydından durumu izleyebilir, denetimi tekrar çalıştırabilirsiniz."),
                    style: .metaQuiet)
            }
            NovaButton(label: RDLocalization.string("localizable.nova.document.close", table: .localizable, fallback: "Kapat"),
                symbol: "xmark", variant: .surface) { onDone(entry) }
                .accessibilityIdentifier("file.add.close")
        }
    }

    /// Reads the chosen file and fingerprints it here, so the server can refuse
    /// bytes that are not the bytes this device announced.
    private func take(_ answer: Result<[URL], Error>) {
        error = nil
        guard case .success(let urls) = answer, let url = urls.first else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let fileExtension = url.pathExtension.lowercased()
            guard allExtensions.contains(fileExtension) else {
                error = NovaFileScreenWords.failure(.unsupportedFormat); return
            }
            guard !data.isEmpty, data.count <= maxBytes else {
                error = NovaFileScreenWords.failure(.tooLarge); return
            }
            payload = data
            draft.fileName = url.lastPathComponent
            draft.fileExtension = fileExtension
            draft.bytes = data.count
            draft.sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            if draft.title.isEmpty {
                draft.title = url.deletingPathExtension().lastPathComponent
            }
            // The heading is the expert's decision, so it is asked for rather
            // than defaulted to whatever happens to be first in the catalogue.
            if draft.category == nil { choosingCategory = true }
        } catch {
            self.error = NovaFileScreenWords.failure(.uploadFailed)
        }
    }

    private func send() {
        guard let company, let data = payload else { return }
        Task {
            busy = true; error = nil
            do { outcome = try await client.file(company, draft, data) }
            catch let failure as NovaFileFailure { error = NovaFileScreenWords.failure(failure) }
            catch { self.error = NovaFileScreenWords.failure(.unavailable) }
            busy = false
        }
    }

    private func field(_ label: String, _ text: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
            TextField(label, text: text).font(NovaFont.font(.body))
                .frame(minHeight: 34).accessibilityIdentifier("file.add.\(id)")
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The page-chrome wrapper around NovaFileAddInline, for a caller that really
/// does want its own screen (Dosyalarım's own add flow).
struct NovaFileAddSheet: View {
    let companies: [NovaAnalysisCompanyOption]
    var preselected: UUID?
    let categories: [NovaFileCategory]
    let accepts: [NovaFileAcceptance]
    let assurance: NovaFileAssurance
    let client: NovaFileLibraryClient
    let onDone: (NovaFileEntry?) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                NovaText(text: RDLocalization.string("localizable.nova.file.add.title", table: .localizable, fallback: "Dosya ekle"),
                    style: .sheetTitle)
                NovaFileAddInline(companies: companies, preselected: preselected, categories: categories,
                    accepts: accepts, assurance: assurance, client: client, onDone: onDone)
            }.padding(16).novaPopupContentSize()
        }
    }
}

/// The OS share sheet, so the expert hands the original on themselves. Nothing
/// is sent anywhere by this app and no recipient is recorded as having read it.
struct NovaFileShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
