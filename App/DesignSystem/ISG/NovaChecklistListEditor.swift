import SwiftUI

struct NovaChecklistMyListEditorScreen: View {
    let client: NovaChecklistClient
    let company: UUID?
    let templateCode: String
    let onBack: () -> Void

    @State private var template: NovaChecklistTemplate?
    @State private var showingCatalogue = false
    @State private var showingManual = false
    @State private var working = false
    @State private var loading = true
    @State private var failure: String?
    @Environment(\.colorScheme) private var scheme

    private var version: NovaChecklistTemplateVersion? {
        template?.draft ?? template?.published ?? template?.versions.first
    }
    private var isEditable: Bool { version?.isDraft == true && template?.isProduct == false }

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            VStack(spacing: 0) {
                header
                if loading && template == nil {
                    NovaChecklistRunSkeleton().padding(20)
                } else if let template, let version {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            VStack(alignment: .leading, spacing: 5) {
                                NovaText(text: template.title, style: .screenTitle)
                                NovaText(text: "\(version.statusTitle) · v\(version.version) · \(version.items.count) soru",
                                    style: .body, color: NovaColorToken.textSecondary.color(in: scheme))
                            }
                            if isEditable {
                                VStack(spacing: 0) {
                                    editorAction("Hazır maddelerden seç", subtitle: "Katalogda ara ve listeye ekle",
                                        symbol: "text.badge.plus") { showingCatalogue = true }
                                    Divider().overlay(NovaColorToken.hairline.color(in: scheme))
                                    editorAction("Kendi sorunu yaz", subtitle: "Bu listeye özel bir soru ekle",
                                        symbol: "square.and.pencil") { showingManual = true }
                                }
                            }
                            NovaText(text: "Sorular", style: .sectionTitle)
                            if version.items.isEmpty {
                                NovaChecklistMessageState(symbol: "list.number", title: "Henüz soru yok",
                                    message: "Hazır maddelerden seçin veya kendi sorunuzu yazın.",
                                    actionTitle: nil, action: {})
                            } else {
                                ForEach(version.items.sorted { $0.position < $1.position }) { item in
                                    itemRow(item, version: version)
                                    Divider().overlay(NovaColorToken.hairline.color(in: scheme))
                                }
                            }
                            if !isEditable {
                                NovaText(text: "Yayımlanmış sürüm değiştirilemez. Değişiklikler yeni bir taslak sürüm üzerinden yapılır.",
                                    style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                            }
                            if let failure {
                                NovaText(text: failure, style: .meta,
                                    color: NovaColorToken.statusDangerInk.color(in: scheme))
                            }
                        }
                        .padding(20).padding(.bottom, isEditable ? 100 : 30)
                    }
                    if isEditable {
                        NovaButton(label: working ? "Yayımlanıyor…" : "Listeyi yayımla",
                            symbol: "checkmark.seal", variant: .primary,
                            isEnabled: !version.items.isEmpty, isLoading: working) {
                            publish(version)
                        }
                        .padding(.horizontal, 20).padding(.vertical, 12)
                        .background(NovaColorToken.surface.color(in: scheme))
                    }
                } else {
                    NovaChecklistMessageState(symbol: "wifi.exclamationmark", title: "Liste yüklenemedi",
                        message: failure ?? "Liste bulunamadı.", actionTitle: "Yeniden dene") {
                        Task { await load() }
                    }
                    .padding(20)
                }
            }
        }
        .task { await load() }
        .novaFullScreenCover(isPresented: $showingCatalogue) {
            if let version {
                NovaChecklistCatalogItemPickerScreen(client: client,
                    onBack: { showingCatalogue = false }) { selection in
                    await add(selection, version: version)
                }
            }
        }
        .novaFullScreenCover(isPresented: $showingManual) {
            if let version {
                NovaChecklistManualItemScreen(onBack: { showingManual = false }) { prompt, allowsNA in
                    await addManual(prompt, allowsNA: allowsNA, version: version)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) { Label("Listelerim", systemImage: "chevron.left").frame(minHeight: 44) }
                .buttonStyle(NovaRowPressStyle())
            Spacer()
        }
        .overlay { NovaText(text: "Listeyi düzenle", style: .label) }
        .padding(.horizontal, 16).padding(.vertical, 4)
    }

    private func editorAction(_ title: String, subtitle: String, symbol: String,
        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol).font(.system(size: 18, weight: .semibold)).frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    NovaText(text: title, style: .bodyStrong)
                    NovaText(text: subtitle, style: .meta,
                        color: NovaColorToken.textSecondary.color(in: scheme))
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
            }
            .padding(.vertical, 13).contentShape(Rectangle())
        }
        .buttonStyle(NovaRowPressStyle())
    }

    private func itemRow(_ item: NovaChecklistTemplateItem,
        version: NovaChecklistTemplateVersion) -> some View {
        HStack(alignment: .top, spacing: 10) {
            NovaText(text: "\(item.position).", style: .meta,
                color: NovaColorToken.textMuted.color(in: scheme))
                .frame(width: 24, alignment: .leading)
            NovaText(text: item.prompt, style: .body)
            Spacer(minLength: 6)
            if isEditable {
                Menu {
                    Button("Yukarı taşı", systemImage: "arrow.up") { move(item, delta: -1, version: version) }
                        .disabled(item.position == 1)
                    Button("Aşağı taşı", systemImage: "arrow.down") { move(item, delta: 1, version: version) }
                        .disabled(item.position == version.items.count)
                    Button("Soruyu kaldır", systemImage: "trash", role: .destructive) {
                        remove(item, version: version)
                    }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }
            }
        }
        .padding(.vertical, 12)
    }

    private func load() async {
        loading = true; failure = nil
        do { template = try await client.templates(company).first { $0.templateCode == templateCode } }
        catch let error as NovaChecklistFailure { failure = error.message }
        catch { failure = NovaChecklistFailure.unavailable.message }
        loading = false
    }

    private func add(_ selection: NovaChecklistItemSelection,
        version: NovaChecklistTemplateVersion) async -> String? {
        do {
            try await client.copyItems(company, templateCode, version.version, version.revision, [selection])
            await load(); return nil
        } catch let error as NovaChecklistFailure { return error.message }
        catch { return NovaChecklistFailure.unavailable.message }
    }

    private func addManual(_ prompt: String, allowsNA: Bool,
        version: NovaChecklistTemplateVersion) async -> String? {
        do {
            let position = version.items.count + 1
            try await client.setItem(company, templateCode, version.version, version.revision,
                "q\(position)", prompt, allowsNA, position)
            await load()
            showingManual = false
            return nil
        } catch let error as NovaChecklistFailure { return error.message }
        catch { return NovaChecklistFailure.unavailable.message }
    }

    private func move(_ item: NovaChecklistTemplateItem, delta: Int,
        version: NovaChecklistTemplateVersion) {
        var codes = version.items.sorted { $0.position < $1.position }.map(\.itemCode)
        guard let source = codes.firstIndex(of: item.itemCode),
              codes.indices.contains(source + delta) else { return }
        codes.swapAt(source, source + delta)
        Task {
            working = true; failure = nil
            do {
                try await client.reorderItems(company, templateCode, version.version, version.revision, codes)
                await load()
            } catch let error as NovaChecklistFailure { failure = error.message }
            catch { failure = NovaChecklistFailure.unavailable.message }
            working = false
        }
    }

    private func remove(_ item: NovaChecklistTemplateItem,
        version: NovaChecklistTemplateVersion) {
        Task {
            working = true; failure = nil
            do {
                try await client.removeItem(company, templateCode, version.version, version.revision, item.itemCode)
                await load()
            } catch let error as NovaChecklistFailure { failure = error.message }
            catch { failure = NovaChecklistFailure.unavailable.message }
            working = false
        }
    }

    private func publish(_ version: NovaChecklistTemplateVersion) {
        Task {
            working = true; failure = nil
            do {
                try await client.publishTemplate(company, templateCode, version.version,
                    version.revision, "Uygulama üzerinden uzman tarafından yayımlandı.")
                await load()
            } catch let error as NovaChecklistFailure { failure = error.message }
            catch { failure = NovaChecklistFailure.unavailable.message }
            working = false
        }
    }
}

private struct NovaChecklistCatalogItemPickerScreen: View {
    let client: NovaChecklistClient
    let onBack: () -> Void
    let onAdd: (NovaChecklistItemSelection) async -> String?
    @State private var query = ""
    @State private var result: NovaChecklistLibrary?
    @State private var working = false
    @State private var failure: String?
    @State private var added: Set<String> = []
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            VStack(spacing: 0) {
                header
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        NovaAnalysisSearchField(text: $query,
                            placeholder: "Soru, risk, ekipman veya konu ara",
                            identifier: "nova.checklist.builder.search")
                            .padding(.bottom, 14)
                        if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            NovaChecklistMessageState(symbol: "magnifyingglass", title: "Hazır madde bulun",
                                message: "Yazdıkça katalogdaki sorular süzülecek.",
                                actionTitle: nil, action: {})
                        } else if working && result == nil {
                            NovaChecklistRunSkeleton()
                        } else if let failure {
                            NovaChecklistMessageState(symbol: "wifi.exclamationmark", title: "Maddeler yüklenemedi",
                                message: failure, actionTitle: nil, action: {})
                        } else if let items = result?.matchedItems, items.isEmpty {
                            NovaChecklistMessageState(symbol: "magnifyingglass", title: "Sonuç bulunamadı",
                                message: "Daha kısa bir konu, risk veya ekipman adı deneyin.",
                                actionTitle: nil, action: {})
                        } else if let items = result?.matchedItems {
                            ForEach(items) { item in
                                if let context = item.contexts.first {
                                    itemRow(item, context: context)
                                    Divider().overlay(NovaColorToken.hairline.color(in: scheme))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 30)
                }
            }
        }
        .task(id: query) {
            do { try await Task.sleep(nanoseconds: 280_000_000) }
            catch { return }
            guard !Task.isCancelled else { return }
            await search()
        }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) { Label("Listeye dön", systemImage: "chevron.left").frame(minHeight: 44) }
                .buttonStyle(NovaRowPressStyle())
            Spacer()
        }
        .overlay { NovaText(text: "Hazır madde ekle", style: .label) }
        .padding(.horizontal, 16).padding(.vertical, 4)
    }

    private func itemRow(_ item: NovaChecklistLibraryMatch,
        context: NovaChecklistLibraryMatch.Context) -> some View {
        let key = context.templateCode + ":" + context.itemCode
        return Button {
            guard !added.contains(key) else { return }
            Task {
                working = true; failure = await onAdd(.init(sourceTemplateCode: context.templateCode,
                    sourceItemCode: context.itemCode, sectionTitle: "", scopeKey: ""))
                if failure == nil { added.insert(key) }
                working = false
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    NovaText(text: item.prompt, style: .body)
                    NovaText(text: [context.sectorName, item.riskTopic].compactMap { $0 }.joined(separator: " · "),
                        style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                }
                Spacer(minLength: 8)
                Image(systemName: added.contains(key) ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 20, weight: .semibold))
                    .frame(width: 44, height: 44)
            }
            .padding(.vertical, 12).contentShape(Rectangle())
        }
        .buttonStyle(NovaRowPressStyle())
        .disabled(working || added.contains(key))
        .accessibilityLabel(added.contains(key) ? "Eklendi" : "Listeye ekle")
    }

    private func search() async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            result = nil; failure = nil; return
        }
        working = true; failure = nil
        do { result = try await client.library(query, nil, nil, 0) }
        catch let error as NovaChecklistFailure { failure = error.message }
        catch { failure = NovaChecklistFailure.unavailable.message }
        working = false
    }
}

private struct NovaChecklistManualItemScreen: View {
    let onBack: () -> Void
    let onAdd: (String, Bool) async -> String?
    @State private var prompt = ""
    @State private var allowsNA = true
    @State private var working = false
    @State private var failure: String?
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        NovaText(text: "Kontrol sorusunu yazın", style: .screenTitle)
                        TextEditor(text: $prompt).frame(minHeight: 180).padding(9)
                            .scrollContentBackground(.hidden)
                            .background(NovaColorToken.surface.color(in: scheme),
                                in: RoundedRectangle(cornerRadius: 12))
                            .focused($focused)
                            .accessibilityIdentifier("nova.checklist.templates.prompt")
                        Button { allowsNA.toggle() } label: {
                            HStack {
                                Image(systemName: allowsNA ? "checkmark.square.fill" : "square")
                                NovaText(text: "“Uygulanamaz” yanıtına izin ver", style: .body)
                                Spacer()
                            }
                            .frame(minHeight: 44).contentShape(Rectangle())
                        }
                        .buttonStyle(NovaRowPressStyle())
                        if let failure { NovaText(text: failure, style: .meta,
                            color: NovaColorToken.statusDangerInk.color(in: scheme)) }
                    }
                    .padding(20).padding(.bottom, 90)
                }
                .scrollDismissesKeyboard(.interactively)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    NovaButton(label: working ? "Ekleniyor…" : "Soruyu ekle", symbol: "plus",
                        variant: .primary, isEnabled: !cleanPrompt.isEmpty, isLoading: working) {
                        Task { working = true; failure = await onAdd(cleanPrompt, allowsNA); working = false }
                    }
                    .padding(.horizontal, 20).padding(.vertical, 12)
                    .background(NovaColorToken.surface.color(in: scheme))
                }
            }
        }
        .onAppear { focused = true }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) { Label("Listeye dön", systemImage: "chevron.left").frame(minHeight: 44) }
                .buttonStyle(NovaRowPressStyle())
            Spacer()
        }
        .overlay { NovaText(text: "Yeni soru", style: .label) }
        .padding(.horizontal, 16).padding(.vertical, 4)
    }
    private var cleanPrompt: String { prompt.trimmingCharacters(in: .whitespacesAndNewlines) }
}
