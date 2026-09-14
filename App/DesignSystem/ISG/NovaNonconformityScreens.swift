import SwiftUI

/// The design system never imports the SDK: the destination is handed a client.
struct NovaNonconformityClient {
    let list: (NovaNonconformityState?) async throws -> [NovaNonconformityRow]
    let workplaces: () async throws -> [NovaNonconformityWorkplace]
    let open: (NovaNonconformityIntent) async throws -> NovaNonconformityRow
}

struct NovaNonconformityDestination: View {
    let scope: NovaPersonnelScope
    let client: NovaNonconformityClient
    let onBack: () -> Void
    var canWrite = true
    /// Photo analysis is the live pipeline; the shell owns it and reports back.
    var onStartPhotoAnalysis: (() -> Void)? = nil
    var startOnNew = false
    var body: some View {
        NonconformityContent(scope: scope, client: client, onBack: onBack, canWrite: canWrite,
            onStartPhotoAnalysis: onStartPhotoAnalysis, startOnNew: startOnNew).id(scope).id(canWrite)
    }
}

private struct NonconformityContent: View {
    let scope: NovaPersonnelScope
    let client: NovaNonconformityClient
    let onBack: () -> Void
    let canWrite: Bool
    let onStartPhotoAnalysis: (() -> Void)?
    let startOnNew: Bool
    @Environment(\.colorScheme) private var scheme
    @State private var rows: [NovaNonconformityRow] = []
    @State private var filter: NovaNonconformityState?
    @State private var loading = false
    @State private var error: String?
    @State private var generation = UUID()
    @State private var route: Route = .list
    @State private var started = false
    private enum Route: Equatable { case list, choose, manual }
    private struct Key: Equatable { let state: String?; let generation: UUID }

    var body: some View {
        NovaPageSurface {
            switch route {
            case .list: list
            case .choose: chooser
            case .manual:
                NovaNonconformityManualForm(client: client, onBack: { route = .list },
                    onSaved: { _ in generation = UUID(); route = .list })
            }
        }
        .task(id: Key(state: filter?.rawValue, generation: generation)) { await load() }
        .onAppear { if startOnNew && !started { started = true; route = .choose } }
    }

    private func load() async {
        loading = true; error = nil
        do {
            let loaded = try await client.list(filter)
            try Task.checkCancellation()
            rows = loaded; loading = false
        } catch is CancellationError {
            loading = false
        } catch let failure as NovaNonconformityFailure {
            loading = false
            error = message(for: failure)
        } catch {
            loading = false
            self.error = RDLocalization.string("localizable.nova.nonconformity.error.list", table: .localizable,
                fallback: "Uygunsuzluklar yüklenemedi. Bağlantınızı kontrol edip tekrar deneyin.")
        }
    }

    private func message(for failure: NovaNonconformityFailure) -> String {
        switch failure {
        case .denied:
            return RDLocalization.string("localizable.nova.nonconformity.error.denied", table: .localizable,
                fallback: "Bu firma için uygunsuzluk kaydına erişiminiz yok.")
        case .severityUnknown:
            return RDLocalization.string("localizable.nova.nonconformity.error.severity.unknown", table: .localizable,
                fallback: "Bulgunun risk bandı okunamadı. Önem derecesini kendiniz seçin.")
        case .conflict:
            return RDLocalization.string("localizable.nova.nonconformity.error.conflict", table: .localizable,
                fallback: "Kayıt bu sırada değişti. Listeyi yenileyip tekrar deneyin.")
        case .validation, .payloadRejected:
            return RDLocalization.string("localizable.nova.nonconformity.error.validation", table: .localizable,
                fallback: "Gönderilen bilgiler kabul edilmedi. Alanları kontrol edin.")
        case .unavailable:
            return RDLocalization.string("localizable.nova.nonconformity.error.unavailable", table: .localizable,
                fallback: "Uygunsuzluk modülü şu anda kullanılamıyor.")
        }
    }

    @ViewBuilder private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button(action: onBack) { NovaIcon(symbol: "chevron.left", size: 22).frame(width: 44, height: 44) }
                        .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.shell.back", table: .localizable, fallback: "Geri")))
                        .accessibilityIdentifier("nonconformity.back")
                    NovaText(text: RDLocalization.string("localizable.nova.navigation.uygunsuzluklar", table: .localizable, fallback: "Uygunsuzluklar"), style: .screenTitle)
                }
                if canWrite {
                    NovaButton(label: RDLocalization.string("localizable.nova.nonconformity.new", table: .localizable, fallback: "Yeni Uygunsuzluk"), symbol: "plus") { route = .choose }
                        .accessibilityIdentifier("nonconformity.new")
                } else {
                    NovaText(text: RDLocalization.string("localizable.nova.nonconformity.read.only", table: .localizable,
                        fallback: "Salt okunur · yeni kayıt açılamıyor"), style: .metaQuiet)
                }
                filters
                if let error { NovaCard(padding: 20) { NovaText(text: error, style: .metaQuiet) } }
                if loading && rows.isEmpty {
                    NovaCard(padding: 20) { NovaText(text: RDLocalization.string("localizable.nova.nonconformity.loading", table: .localizable, fallback: "Kayıtlar yükleniyor"), style: .metaQuiet) }
                } else if rows.isEmpty {
                    NovaCard(padding: 20) { NovaText(text: RDLocalization.string("localizable.nova.nonconformity.empty", table: .localizable, fallback: "Henüz uygunsuzluk kaydı yok."), style: .metaQuiet) }
                } else {
                    ForEach(rows) { row in card(row) }
                }
            }.padding(20)
        }
    }

    @ViewBuilder private var filters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(nil, RDLocalization.string("localizable.nova.nonconformity.filter.all", table: .localizable, fallback: "Tümü"))
                chip(.draft, RDLocalization.string("localizable.nova.nonconformity.filter.draft", table: .localizable, fallback: "Taslak"))
                chip(.open, RDLocalization.string("localizable.nova.nonconformity.filter.open", table: .localizable, fallback: "Açık"))
                chip(.closed, RDLocalization.string("localizable.nova.nonconformity.filter.closed", table: .localizable, fallback: "Kapalı"))
            }
        }
    }

    private func chip(_ state: NovaNonconformityState?, _ title: String) -> some View {
        Button { filter = state } label: {
            NovaText(text: title, style: .meta,
                color: filter == state ? NovaColorToken.accentInk.color(in: scheme) : NovaColorToken.textSecondary.color(in: scheme))
                .padding(.horizontal, 12).frame(minHeight: 36)
        }.buttonStyle(.plain).accessibilityIdentifier("nonconformity.filter.\(state?.rawValue ?? "all")")
    }

    private func card(_ row: NovaNonconformityRow) -> some View {
        NovaCard(padding: 20) {
            VStack(alignment: .leading, spacing: 8) {
                NovaText(text: row.title, style: .cardTitle)
                HStack(spacing: 8) {
                    NovaStatusPill(label: severityLabel(row.severity), status: pill(row.severity))
                    NovaText(text: stateLabel(row.state), style: .metaQuiet)
                }
                // A record born from a photo finding says so, and keeps pointing
                // at that finding rather than copying it.
                if row.camefromFinding {
                    NovaText(text: RDLocalization.string("localizable.nova.nonconformity.from.analysis", table: .localizable,
                        fallback: "Fotoğraf analizinden geldi"), style: .metaQuiet)
                }
                NovaText(text: row.opened_on, style: .metaQuiet)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.accessibilityIdentifier("nonconformity.row.\(row.id.uuidString.lowercased())")
    }

    private func pill(_ severity: String) -> NovaStatus {
        switch severity {
        case "critical", "high": return .danger
        case "medium": return .warning
        default: return .neutral
        }
    }

    @ViewBuilder private var chooser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { route = .list } label: { NovaIcon(symbol: "chevron.left", size: 22).frame(width: 44, height: 44) }
                        .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.shell.back", table: .localizable, fallback: "Geri")))
                        .accessibilityIdentifier("nonconformity.choose.back")
                    NovaText(text: RDLocalization.string("localizable.nova.navigation.yeni.uygunsuzluk.0f9172a3", table: .localizable, fallback: "Yeni Uygunsuzluk"), style: .screenTitle)
                }
                NovaText(text: RDLocalization.string("localizable.nova.nonconformity.choose.prompt", table: .localizable,
                    fallback: "Nasıl başlamak istersiniz?"), style: .metaQuiet)
                NovaCard(padding: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        NovaText(text: RDLocalization.string("localizable.nova.nonconformity.choose.photo.title", table: .localizable,
                            fallback: "Fotoğraftan analiz"), style: .cardTitle)
                        NovaText(text: RDLocalization.string("localizable.nova.nonconformity.choose.photo.detail", table: .localizable,
                            fallback: "Mevcut analiz motoru çalışır; seçtiğiniz bulgulardan uygunsuzluk açılır."), style: .metaQuiet)
                        NovaButton(label: RDLocalization.string("localizable.nova.nonconformity.choose.photo.action", table: .localizable, fallback: "Fotoğraf seç"), symbol: "camera",
                            isEnabled: onStartPhotoAnalysis != nil) { onStartPhotoAnalysis?() }
                            .accessibilityIdentifier("nonconformity.choose.photo")
                        if onStartPhotoAnalysis == nil {
                            NovaText(text: RDLocalization.string("localizable.nova.nonconformity.choose.photo.unavailable", table: .localizable,
                                fallback: "Fotoğraf analizi bu ekrana henüz bağlanmadı."), style: .metaQuiet)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                NovaCard(padding: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        NovaText(text: RDLocalization.string("localizable.nova.nonconformity.choose.manual.title", table: .localizable,
                            fallback: "Elle gir"), style: .cardTitle)
                        NovaText(text: RDLocalization.string("localizable.nova.nonconformity.choose.manual.detail", table: .localizable,
                            fallback: "Başlık, işyeri ve önem derecesini kendiniz yazarsınız."), style: .metaQuiet)
                        NovaButton(label: RDLocalization.string("localizable.nova.nonconformity.choose.manual.action", table: .localizable, fallback: "Forma geç"), symbol: "square.and.pencil", variant: .surface) { route = .manual }
                            .accessibilityIdentifier("nonconformity.choose.manual")
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }.padding(20)
        }
    }

    private func severityLabel(_ value: String) -> String {
        switch value {
        case "critical": return RDLocalization.string("localizable.nova.nonconformity.severity.critical", table: .localizable, fallback: "Kritik")
        case "high": return RDLocalization.string("localizable.nova.nonconformity.severity.high", table: .localizable, fallback: "Yüksek")
        case "medium": return RDLocalization.string("localizable.nova.nonconformity.severity.medium", table: .localizable, fallback: "Orta")
        default: return RDLocalization.string("localizable.nova.nonconformity.severity.low", table: .localizable, fallback: "Düşük")
        }
    }

    private func stateLabel(_ value: String) -> String {
        switch value {
        case "open": return RDLocalization.string("localizable.nova.nonconformity.state.open", table: .localizable, fallback: "Açık")
        case "assigned": return RDLocalization.string("localizable.nova.nonconformity.state.assigned", table: .localizable, fallback: "Atandı")
        case "in_progress": return RDLocalization.string("localizable.nova.nonconformity.state.in.progress", table: .localizable, fallback: "Devam ediyor")
        case "pending_verification": return RDLocalization.string("localizable.nova.nonconformity.state.pending", table: .localizable, fallback: "Doğrulama bekliyor")
        case "closed": return RDLocalization.string("localizable.nova.nonconformity.state.closed", table: .localizable, fallback: "Kapandı")
        case "reopened": return RDLocalization.string("localizable.nova.nonconformity.state.reopened", table: .localizable, fallback: "Yeniden açıldı")
        case "cancelled": return RDLocalization.string("localizable.nova.nonconformity.state.cancelled", table: .localizable, fallback: "İptal edildi")
        default: return RDLocalization.string("localizable.nova.nonconformity.state.draft", table: .localizable, fallback: "Taslak")
        }
    }
}

struct NovaNonconformityManualForm: View {
    let client: NovaNonconformityClient
    let onBack: () -> Void
    let onSaved: (NovaNonconformityRow) -> Void
    @State private var title = ""
    @State private var severity: NovaNonconformitySeverity = .medium
    @State private var workplaces: [NovaNonconformityWorkplace] = []
    @State private var selected: UUID?
    @State private var submitting = false
    @State private var error: String?
    /// The identifiers are created once, so a retry cannot open a second record.
    @State private var operationID = UUID()
    @State private var mutationID = UUID()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button(action: onBack) { NovaIcon(symbol: "chevron.left", size: 22).frame(width: 44, height: 44) }
                        .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.shell.back", table: .localizable, fallback: "Geri")))
                        .accessibilityIdentifier("nonconformity.manual.back")
                    NovaText(text: RDLocalization.string("localizable.nova.nonconformity.manual.title", table: .localizable, fallback: "Elle Uygunsuzluk"), style: .screenTitle)
                }
                NovaCard(padding: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        NovaText(text: RDLocalization.string("localizable.nova.nonconformity.field.title", table: .localizable, fallback: "Başlık"), style: .metaQuiet)
                        TextField(RDLocalization.string("localizable.nova.nonconformity.field.title.hint", table: .localizable, fallback: "Kısa ve açık bir başlık"), text: $title)
                            .font(.custom("PlusJakartaSans-Medium", size: 15))
                            .accessibilityIdentifier("nonconformity.field.title")
                        NovaText(text: RDLocalization.string("localizable.nova.nonconformity.field.severity", table: .localizable, fallback: "Önem derecesi"), style: .metaQuiet)
                        Picker("", selection: $severity) {
                            ForEach(NovaNonconformitySeverity.allCases) { value in
                                Text(verbatim: label(value)).tag(value)
                            }
                        }.pickerStyle(.segmented).accessibilityIdentifier("nonconformity.field.severity")
                        NovaText(text: RDLocalization.string("localizable.nova.nonconformity.field.workplace", table: .localizable, fallback: "İşyeri"), style: .metaQuiet)
                        ForEach(workplaces) { place in
                            Button { selected = place.id } label: {
                                HStack {
                                    NovaIcon(symbol: selected == place.id ? "checkmark.circle" : "circle", size: 20)
                                    NovaText(text: place.name)
                                }.frame(minHeight: 44)
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("nonconformity.workplace.\(place.id.uuidString.lowercased())")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
                if let error { NovaText(text: error, style: .metaQuiet) }
                NovaButton(label: RDLocalization.string("localizable.nova.nonconformity.manual.save", table: .localizable, fallback: "Uygunsuzluğu aç"), symbol: "checkmark",
                    isEnabled: !submitting && !title.trimmingCharacters(in: .whitespaces).isEmpty && selected != nil) { Task { await submit() } }
                    .accessibilityIdentifier("nonconformity.manual.save")
            }.padding(20)
        }
        .task {
            do { workplaces = try await client.workplaces(); selected = workplaces.first?.id }
            catch { self.error = RDLocalization.string("localizable.nova.nonconformity.error.workplaces", table: .localizable,
                fallback: "İşyeri listesi alınamadı. Tekrar deneyin.") }
        }
    }

    private func label(_ value: NovaNonconformitySeverity) -> String {
        switch value {
        case .critical: return RDLocalization.string("localizable.nova.nonconformity.severity.critical", table: .localizable, fallback: "Kritik")
        case .high: return RDLocalization.string("localizable.nova.nonconformity.severity.high", table: .localizable, fallback: "Yüksek")
        case .medium: return RDLocalization.string("localizable.nova.nonconformity.severity.medium", table: .localizable, fallback: "Orta")
        case .low: return RDLocalization.string("localizable.nova.nonconformity.severity.low", table: .localizable, fallback: "Düşük")
        }
    }

    private func submit() async {
        guard let workplace = selected else { return }
        submitting = true; error = nil
        do {
            let row = try await client.open(.init(origin: .manual, workplaceID: workplace,
                title: title.trimmingCharacters(in: .whitespaces), severity: severity,
                riskBand: nil, findingID: nil, dueOn: nil, assignee: nil))
            submitting = false
            onSaved(row)
        } catch {
            submitting = false
            self.error = RDLocalization.string("localizable.nova.nonconformity.error.save", table: .localizable,
                fallback: "Kayıt açılamadı. Bilgileri kontrol edip aynı işlemi tekrar deneyin.")
        }
    }
}
