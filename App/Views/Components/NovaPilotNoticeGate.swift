import SwiftUI

/// Bildirim Merkezi. The feed is computed from the expert's own records; this
/// gate only hands the screen a way to ask for it.
struct NovaPilotNoticeGate: View {
    let identity: NovaSessionIdentity
    let onOpen: (NovaDestination) -> Void
    let onBack: () -> Void

    private var service: NovaNoticeService { .live() }

    var body: some View {
        NovaNoticeCenterScreen(client: client, onOpen: onOpen, onBack: onBack)
    }

    private var client: NovaNoticeClient {
        .init(
            feed: { scope in try await service.feed(identity, scope: scope) },
            read: { key in try await service.read(identity, key: key) },
            readAll: { try await service.readAll(identity) },
            dismiss: { key in try await service.dismiss(identity, key: key) },
            dismissAll: { try await service.dismissAll(identity) },
            restore: { key in try await service.restore(identity, key: key) })
    }
}
