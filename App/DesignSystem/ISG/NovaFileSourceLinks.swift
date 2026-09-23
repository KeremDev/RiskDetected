import SwiftUI
import Supabase

struct NovaFileSourceLinks: View {
    let entry: NovaFileEntry
    let canWrite: Bool
    @State private var rows: [NovaFollowupPage.Row] = []
    @State private var selected: NovaFollowupPage.Row?
    @State private var identity: NovaSessionIdentity?
    @State private var failed = false
    @State private var revision = 0
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if failed { Button(RDLocalization.string("localizable.nova.file.source.links.kayit.baglantilarini.yeniden.yukle.986c83d8", table: .localizable, fallback: "Kayıt bağlantılarını yeniden yükle")) { revision += 1 }.font(NovaFont.font(.meta)) }
            ForEach(rows) { row in
                Button { selected = row } label: {
                    HStack { Image(systemName: "link"); NovaText(text: row.typeTitle + " · " + row.title, style: .meta); Spacer(); Image(systemName: "chevron.right") }
                }.buttonStyle(NovaRowPressStyle())
            }
        }
        .task(id: "\(entry.id):\(revision)") {
            do {
                guard let session = SupabaseService.shared.client.auth.currentSession,
                      let sid = NovaPersonnelService.sessionID(session.accessToken) else { return }
                let user = NovaSessionIdentity(userID: session.user.id, sessionID: sid)
                let data = try await NovaExpertTransport.shared.execute("isg_pilot_file_sources_v1", params: ["p_entry": PersonnelRPCValue.id(entry.id)], ticket: NovaExpertTransport.shared.capture())
                guard let current = SupabaseService.shared.client.auth.currentSession, current.user.id == user.userID,
                      NovaPersonnelService.sessionID(current.accessToken) == user.sessionID else { return }
                try Task.checkCancellation()
                let links = try JSONDecoder().decode([NovaFollowupPage.Row].self, from: data)
                guard links.allSatisfy({ $0.company_id == entry.companyID }) else { throw NovaPPEFailure.denied }
                identity = user; rows = links; failed = false
            } catch { if !Task.isCancelled { failed = true } }
        }
        .novaPopup(item: $selected) { row in
            if let identity { NovaFollowupDestination(identity: identity, row: row, canWrite: canWrite, onBack: { selected = nil }) }
        }
    }
}
