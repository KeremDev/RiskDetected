import SwiftUI

/// The design system never imports the SDK; the composition root hands the
/// tracker these closures.
struct NovaDocumentTrackingClient {
    let load: () async throws -> NovaDocumentBoard
    let kinds: () async throws -> [NovaDocumentKind]
    let workplaces: () async throws -> [NovaDocumentWorkplace]
    let add: (NovaDocumentDraft) async throws -> NovaDocumentObligation
    let update: (NovaDocumentObligation, NovaDocumentDraft) async throws -> NovaDocumentObligation
    let archive: (NovaDocumentObligation) async throws -> Void
    let recordCopy: (NovaDocumentObligation, NovaDocumentCopyDraft) async throws -> NovaDocumentObligation
    let removeCopy: (NovaDocumentObligation, NovaDocumentCopy) async throws -> NovaDocumentObligation
}

/// A day, typed as a calendar rather than as free text, and carried as the same
/// ISO string the server stores.
struct NovaDayField: View {
    let label: String
    @Binding var value: String
    var identifier: String
    var isClearable = false
    @Environment(\.colorScheme) private var scheme

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    static func text(_ date: Date) -> String { formatter.string(from: date) }
    static func date(_ text: String) -> Date? { formatter.date(from: text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                NovaText(text: label, style: .label, color: NovaColorToken.textTertiary.color(in: scheme))
                Spacer(minLength: 0)
                if isClearable && !value.isEmpty {
                    Button { value = "" } label: {
                        NovaText(text: RDLocalization.string("localizable.nova.document.date.clear", table: .localizable, fallback: "Temizle"),
                            style: .micro, color: NovaColorToken.accentInk.color(in: scheme))
                    }.buttonStyle(.plain).accessibilityIdentifier("\(identifier).clear")
                }
            }
            DatePicker("", selection: Binding(
                get: { Self.date(value) ?? Date() },
                set: { value = Self.text($0) }), displayedComponents: .date)
                .labelsHidden().datePickerStyle(.compact)
                .accessibilityIdentifier(identifier)
                .accessibilityLabel(Text(verbatim: label))
        }
    }
}

/// Everything the company must hold, what is on file and what is not. The list
/// is a tally of tracked documents; it is never a verdict about the company or
/// about any person.
struct NovaDocumentTrackingScreen: View {
    let client: NovaDocumentTrackingClient
    let onBack: () -> Void
    var canWrite = true
    var companyName: String?
    @Environment(\.colorScheme) private var scheme
    @State private var board: NovaDocumentBoard?
    @State private var kinds: [NovaDocumentKind] = []
    @State private var places: [NovaDocumentWorkplace] = []
    @State private var error: String?
    @State private var query = ""
    @State private var status: NovaDocumentStatus?
    @State private var workplace: UUID?
    @State private var inspecting: NovaDocumentObligation?
    @State private var adding = false
    @State private var reload = UUID()

    private var rows: [NovaDocumentObligation] {
        (board?.rows ?? []).filter { row in
            guard row.matches(query) else { return false }
            if let status, row.status != status { return false }
            if let workplace, row.workplaceID != workplace { return false }
            return true
        }
    }

    var body: some View {
        NovaPageSurface {
            ScrollView {
                VStack(alignment: .leading, spacing: 11) {
                    header
                    overview
                    hint
                    search
                    chips
                    list
                }.padding(.horizontal, 16).padding(.top, 4).padding(.bottom, novaTabBarInset)
            }
        }
        .task(id: reload) { await refresh() }
        .fullScreenCover(item: $inspecting) { row in
            NovaPopup {
                NovaDocumentObligationSheet(obligation: row, kinds: kinds, places: places,
                    canWrite: canWrite, client: client, onChanged: { reload = UUID(); inspecting = nil })
            }
        }
        .fullScreenCover(isPresented: $adding) {
            NovaPopup {
                NovaDocumentObligationForm(title: RDLocalization.string("localizable.nova.document.add.title", table: .localizable, fallback: "Takibe evrak ekle"),
                    kinds: kinds, places: places, draft: NovaDocumentDraft()) { draft in
                        _ = try await client.add(draft)
                        adding = false
                        reload = UUID()
                    }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            NovaBackButton { onBack() }
            VStack(alignment: .leading, spacing: 2) {
                NovaText(text: NovaDestination.documentChecklist.title, style: .screenTitle)
                if let companyName { NovaText(text: companyName, style: .metaQuiet) }
            }
            Spacer(minLength: 0)
            if canWrite {
                Button { adding = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "plus").font(.system(size: 13, weight: .bold))
                        NovaText(text: RDLocalization.string("localizable.nova.nonconformity.new.short", table: .localizable, fallback: "Yeni"),
                            style: .buttonSm, color: NovaRGBA(red: 17, green: 17, blue: 17, alpha: 1).color)
                    }
                    .foregroundStyle(NovaRGBA(red: 17, green: 17, blue: 17, alpha: 1).color)
                    .padding(.horizontal, 14).frame(minHeight: 44)
                    .background(NovaColorToken.accent.color(in: scheme), in: Capsule())
                }.buttonStyle(.plain).accessibilityIdentifier("document.tracking.new")
            }
        }
    }

    private var overview: some View {
        let value = board ?? .init()
        return NovaAnalysisOverviewCard(symbol: "doc.text",
            title: RDLocalization.string("localizable.nova.document.overview.title", table: .localizable, fallback: "Evrak takibi"),
            detail: RDLocalization.string("localizable.nova.document.overview.detail", table: .localizable,
                fallback: "Takibe aldığınız evrakların hangisi dosyada, hangisi süresi dolmuş, tek yerden görün."),
            headline: "\(value.total)",
            headlineCaption: RDLocalization.string("localizable.nova.document.overview.unit", table: .localizable, fallback: "kayıt"),
            figures: [
                .init(symbol: "questionmark.circle", value: "\(value.count(.missing))",
                      label: NovaDocumentWords.status(.missing)),
                .init(symbol: "exclamationmark.circle", value: "\(value.count(.expired))",
                      label: NovaDocumentWords.status(.expired)),
                .init(symbol: "clock", value: "\(value.count(.dueSoon))",
                      label: NovaDocumentWords.status(.dueSoon))
            ])
    }

    /// Two things the screen has to say out loud rather than let a reader assume.
    private var hint: some View {
        NovaHelpHint(text: RDLocalization.string("localizable.nova.document.hint", table: .localizable,
            fallback: "Bu liste takip ettiğiniz evrakların sayımıdır; firmanın veya bir kişinin uygunluğuna dair karar değildir. Sağlık evrakı bu listede tutulmaz ve dosyanın kendisi burada saklanmaz."))
    }

    private var search: some View {
        HStack(spacing: 8) {
            NovaAnalysisSearchField(text: $query,
                placeholder: RDLocalization.string("localizable.nova.document.search", table: .localizable, fallback: "Evrak ara"),
                identifier: "document.tracking.search")
            Menu {
                Button(RDLocalization.string("localizable.nova.nonconformity.filter.all", table: .localizable, fallback: "Tümü")) { workplace = nil }
                ForEach(places) { place in Button(place.name) { workplace = place.id } }
            } label: {
                Image(systemName: workplace == nil ? "building.2" : "building.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(workplace == nil ? NovaColorToken.text.color(in: scheme) : NovaColorToken.accentInk.color(in: scheme))
                    .frame(width: 44, height: 44)
                    .background(NovaColorToken.surface.color(in: scheme), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(NovaColorToken.border.color(in: scheme), lineWidth: 1))
            }
            .accessibilityLabel(Text(verbatim: RDLocalization.string("localizable.nova.nonconformity.field.workplace", table: .localizable, fallback: "İşyeri")))
            .accessibilityIdentifier("document.tracking.workplace")
        }
    }

    private var chips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                NovaAnalysisFilterChip(title: RDLocalization.string("localizable.nova.nonconformity.filter.all", table: .localizable, fallback: "Tümü"),
                    isOn: status == nil, identifier: "document.tracking.filter.all") { status = nil }
                ForEach(NovaDocumentStatus.allCases) { value in
                    NovaAnalysisFilterChip(title: NovaDocumentWords.status(value), isOn: status == value,
                        identifier: "document.tracking.filter.\(value.rawValue)") { status = value }
                }
            }
        }
    }

    @ViewBuilder private var list: some View {
        if let error {
            NovaCard(padding: 16) { NovaText(text: error, style: .metaQuiet) }
        } else if board == nil {
            NovaCard(padding: 16) {
                NovaText(text: RDLocalization.string("localizable.nova.document.loading", table: .localizable,
                    fallback: "Evrak takibi yükleniyor…"), style: .metaQuiet)
            }
        } else if rows.isEmpty {
            NovaCard(padding: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    NovaText(text: (board?.rows.isEmpty ?? true)
                        ? RDLocalization.string("localizable.nova.document.empty", table: .localizable,
                            fallback: "Bu firmada takibe alınmış evrak yok. Takip etmek istediğiniz evrakı ekleyin.")
                        : RDLocalization.string("localizable.nova.document.empty.filtered", table: .localizable,
                            fallback: "Bu filtreye uyan kayıt yok."), style: .metaQuiet)
                    if canWrite && (board?.rows.isEmpty ?? true) {
                        NovaButton(label: RDLocalization.string("localizable.nova.document.add.title", table: .localizable, fallback: "Takibe evrak ekle"),
                            symbol: "plus") { adding = true }
                            .accessibilityIdentifier("document.tracking.empty.add")
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            ForEach(rows) { row in card(row) }
        }
    }

    private func card(_ row: NovaDocumentObligation) -> some View {
        Button { inspecting = row } label: {
            NovaCard(padding: 11) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .top, spacing: 9) {
                        NovaIcon(symbol: NovaDocumentWords.kindSymbol(row.kindCode), size: 16)
                            .foregroundStyle(NovaDocumentWords.tone(row.status).tokens.ink.color(in: scheme))
                            .frame(width: 38, height: 38)
                            .background(NovaDocumentWords.tone(row.status).tokens.background.color(in: scheme),
                                        in: RoundedRectangle(cornerRadius: 12))
                        VStack(alignment: .leading, spacing: 4) {
                            NovaText(text: row.title, style: .cardTitle).lineLimit(2)
                            // The kind is only worth a second line when the
                            // expert renamed the entry away from it.
                            if NovaDocumentWords.kind(row.kindCode) != row.title {
                                NovaText(text: NovaDocumentWords.kind(row.kindCode), style: .micro,
                                    color: NovaColorToken.textTertiary.color(in: scheme))
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                        NovaStatusPill(label: NovaDocumentWords.status(row.status),
                            status: NovaDocumentWords.tone(row.status), showsDot: false)
                    }
                    HStack(spacing: 5) {
                        NovaAnalysisTag(symbol: row.basis == .legal ? "book" : "person",
                            text: NovaDocumentWords.basis(row.basis), status: .neutral)
                        if let name = row.workplaceName {
                            NovaAnalysisTag(symbol: "building.2", text: name, status: .neutral)
                        }
                        if let until = row.latestValidUntil {
                            NovaAnalysisTag(symbol: "calendar", text: until,
                                status: NovaDocumentWords.tone(row.status))
                        }
                        Spacer(minLength: 0)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }.buttonStyle(.plain)
            .accessibilityIdentifier("document.tracking.row.\(row.id.uuidString.lowercased())")
    }

    private func refresh() async {
        error = nil
        do {
            async let loaded = client.load()
            async let catalogue = client.kinds()
            async let workplaceList = client.workplaces()
            var value = try await loaded
            kinds = (try? await catalogue) ?? []
            places = (try? await workplaceList) ?? []
            let names = Dictionary(uniqueKeysWithValues: places.map { ($0.id, $0.name) })
            value.rows = value.rows.map { row in
                var copy = row
                copy.workplaceName = row.workplaceID.flatMap { names[$0] }
                return copy
            }
            board = value
        }
        catch is CancellationError { }
        catch let failure as NovaDocumentFailure {
            board = .init()
            error = NovaDocumentWords.failure(failure)
        }
        catch {
            board = .init()
            self.error = RDLocalization.string("localizable.nova.document.failed", table: .localizable,
                fallback: "Evrak takibi alınamadı. Bağlantınızı kontrol edip tekrar deneyin.")
        }
    }
}
