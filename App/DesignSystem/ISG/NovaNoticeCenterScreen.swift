import SwiftUI

/// The design system never imports the SDK; the composition root hands the
/// centre these closures.
struct NovaNoticeClient {
    let feed: (NovaNoticeScope) async throws -> NovaNoticeFeed
    let read: (String) async throws -> Void
    let readAll: () async throws -> Void
    let dismiss: (String) async throws -> Void
    let dismissAll: () async throws -> Void
    let restore: (String) async throws -> Void
}

/// One notice as a card. The whole card opens the record; the controls on the
/// right change only this list.
struct NovaNoticeCard: View {
    let entry: NovaNoticeEntry
    let onOpen: () -> Void
    let onRead: () -> Void
    let onDismiss: () -> Void
    let onRestore: () -> Void
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaCard(padding: 13) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: onOpen) {
                    HStack(alignment: .top, spacing: 10) {
                        NovaIcon(symbol: entry.kind.symbol, size: 19)
                            .foregroundStyle(entry.severity.tone.color(in: scheme))
                            .frame(width: 30, height: 30)
                            .overlay(alignment: .topTrailing) {
                                if entry.unread {
                                    Circle().fill(NovaColorToken.statusDangerDot.color(in: scheme))
                                        .frame(width: 5, height: 5)
                                }
                            }
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .top, spacing: 6) {
                                NovaText(text: entry.title, style: .cardTitle)
                                Spacer(minLength: 0)
                                NovaStatusPill(label: entry.kind.title, status: entry.severity.status)
                            }
                            NovaText(text: NovaNoticeWords.explain(entry), style: .meta,
                                color: entry.severity.tone.color(in: scheme))
                            if let company = entry.companyName {
                                NovaText(text: company, style: .meta,
                                    color: NovaColorToken.textMuted.color(in: scheme))
                            }
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(NovaRowPressStyle())
                    .accessibilityIdentifier("nova.notice.center.row.\(entry.key)")
                VStack(spacing: 2) {
                    if entry.dismissed {
                        action("arrow.uturn.backward",
                            RDLocalization.string("localizable.nova.notice.restore", table: .localizable,
                                fallback: "Geri al"),
                            "nova.notice.center.restore.\(entry.key)", false, onRestore)
                    } else {
                        action(entry.unread ? "envelope.open" : "envelope",
                            RDLocalization.string("localizable.nova.notice.read", table: .localizable,
                                fallback: "Okundu işaretle"),
                            "nova.notice.center.read.\(entry.key)", !entry.unread, onRead)
                        action("trash",
                            RDLocalization.string("localizable.nova.notice.dismiss", table: .localizable,
                                fallback: "Bildirimi sil"),
                            "nova.notice.center.dismiss.\(entry.key)", false, onDismiss)
                    }
                }
            }
        }
        .opacity(entry.dismissed ? 0.55 : 1)
    }

    @ViewBuilder private func action(_ symbol: String, _ label: String, _ identifier: String,
                                     _ disabled: Bool, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            NovaIcon(symbol: symbol, size: 13)
                .foregroundStyle(NovaColorToken.textMuted.color(in: scheme))
                .frame(width: 32, height: 32).contentShape(Rectangle())
        }.buttonStyle(NovaRowPressStyle()).disabled(disabled)
            .accessibilityLabel(Text(verbatim: label)).accessibilityIdentifier(identifier)
    }
}

/// Bildirim Merkezi: everything the bell holds, with the two things the bell
/// has no room to say.
struct NovaNoticeCenterScreen: View {
    let client: NovaNoticeClient
    let onOpen: (NovaDestination) -> Void
    let onBack: () -> Void

    @State private var feed = NovaNoticeFeed.empty
    @State private var scope = NovaNoticeScope.active
    @State private var loading = true
    @State private var failure: String?
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NovaPageSurface(onEdgeBack: onBack) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    counters
                    scopes
                    if loading && feed.rows.isEmpty {
                        ProgressView().frame(maxWidth: .infinity).padding(.vertical, 30)
                    } else if let failure {
                        NovaCard(padding: 16) {
                            NovaText(text: failure, style: .body,
                                color: NovaColorToken.statusDangerInk.color(in: scheme))
                        }
                    } else {
                        list
                    }
                    notes
                }
                .padding(.horizontal, 20).padding(.top, 12)
                .padding(.bottom, 24 + novaTabBarInset)
            }
        }
        .task { await load() }
    }

    @ViewBuilder private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                NovaButton(label: RDLocalization.string("localizable.nova.notice.back", table: .localizable,
                    fallback: "Geri"), symbol: "chevron.left", variant: .surface, action: onBack)
                Spacer(minLength: 0)
                NovaButton(label: RDLocalization.string("localizable.nova.notice.readall", table: .localizable,
                    fallback: "Tümünü oku"), symbol: "envelope.open", variant: .surface) {
                    Task { await run { try await client.readAll() } }
                }
                .disabled(feed.unread == 0)
                NovaButton(label: RDLocalization.string("localizable.nova.notice.clear", table: .localizable,
                    fallback: "Listeyi temizle"), symbol: "trash", variant: .muted) {
                    Task { await run { try await client.dismissAll() } }
                }
                .disabled(feed.total == 0)
            }
            NovaText(text: NovaDestination.notifications.title, style: .screenTitle)
        }
    }

    @ViewBuilder private var counters: some View {
        HStack(spacing: 8) {
            NovaListStat(title: RDLocalization.string("localizable.nova.notice.count.overdue", table: .localizable,
                fallback: "Geçmiş"), symbol: "exclamationmark.triangle", value: feed.overdue) {}
            NovaListStat(title: RDLocalization.string("localizable.nova.notice.count.unread", table: .localizable,
                fallback: "Okunmamış"), symbol: "envelope.badge", value: feed.unread) {}
            NovaListStat(title: RDLocalization.string("localizable.nova.notice.count.total", table: .localizable,
                fallback: "Açık"), symbol: "bell", value: feed.total) {}
        }
    }

    @ViewBuilder private var scopes: some View {
        HStack(spacing: 6) {
            ForEach(NovaNoticeScope.allCases) { value in
                Button {
                    scope = value
                    Task { await load() }
                } label: {
                    NovaSizedText(text: value.title, size: 11,
                        weight: scope == value ? "Bold" : "Medium",
                        color: scope == value ? NovaColorToken.accentInk.color(in: scheme)
                            : NovaColorToken.textSecondary.color(in: scheme))
                        .padding(.vertical, 7).padding(.horizontal, 11)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(NovaColorToken.hairline.color(in: scheme), lineWidth: 1))
                }
                .buttonStyle(NovaRowPressStyle())
                .accessibilityIdentifier("nova.notice.center.scope.\(value.rawValue)")
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder private var list: some View {
        if feed.rows.isEmpty {
            NovaCard(padding: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    NovaText(text: RDLocalization.string("localizable.nova.notice.empty.title",
                        table: .localizable, fallback: "Bekleyen bildirim yok"), style: .cardTitle)
                    NovaText(text: RDLocalization.string("localizable.nova.notice.empty.body",
                        table: .localizable,
                        fallback: "Kayıtlarınızın tarihleri yaklaştığında bildirimler burada görünür."),
                        style: .meta, color: NovaColorToken.textSecondary.color(in: scheme))
                }
            }
        } else {
            VStack(spacing: 10) {
                ForEach(feed.rows) { entry in
                    NovaNoticeCard(entry: entry,
                        onOpen: {
                            Task { await run(reload: false) { try await client.read(entry.key) } }
                            onOpen(entry.destination)
                        },
                        onRead: { Task { await run { try await client.read(entry.key) } } },
                        onDismiss: { Task { await run { try await client.dismiss(entry.key) } } },
                        onRestore: { Task { await run { try await client.restore(entry.key) } } })
                }
                if feed.hasMore {
                    NovaText(text: RDLocalization.string("localizable.nova.notice.more", table: .localizable,
                        fallback: "Daha fazlası var; yaklaşan tarihler önce gösterilir."),
                        style: .meta, color: NovaColorToken.textMuted.color(in: scheme))
                }
            }
        }
    }

    @ViewBuilder private var notes: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Both sentences are on the record, not only in the help text.
            NovaHelpHint(text: NovaNoticeWords.noPushNote)
            NovaText(text: NovaNoticeWords.dismissNote, style: .meta,
                color: NovaColorToken.textSecondary.color(in: scheme))
        }
    }

    private func load() async {
        loading = true; failure = nil
        do { feed = try await client.feed(scope) }
        catch let error as NovaNoticeFailure { failure = error.message }
        catch { failure = NovaNoticeFailure.unavailable.message }
        loading = false
    }

    /// Every write refreshes from the server rather than editing the list in
    /// place: the counts and the situation are the server's to state.
    private func run(reload: Bool = true, _ work: @escaping () async throws -> Void) async {
        do {
            try await work()
            if reload { await load() }
        } catch let error as NovaNoticeFailure {
            failure = error.message
            if error == .notFound { await load() }
        } catch {
            failure = NovaNoticeFailure.unavailable.message
        }
    }
}
