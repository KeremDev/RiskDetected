import Foundation

@main struct NovaSessionHostCheck {
    static func main() throws {
        let path = CommandLine.arguments.dropFirst().first ?? "contracts/isg/v1/fixtures/nova-session-host.json"
        let result = try NovaSessionHostCorpus.verify(URL(fileURLWithPath: path))
        print("PASS NOVA session host: \(result.cases) cases / \(result.steps) transitions")
        // SwiftUI-specific Binding bridge: common Kotlin corpus uses events, not a Binding setter.
        var host = NovaSessionHost(implemented: [.companies])
        let actor = NovaSessionIdentity(userID: UUID(), sessionID: UUID())
        host.adopt(actor)
        let pending = host.beginAvailabilityRefresh()!
        var candidate = host.navigation
        candidate.apply(.open(.drawer), from: candidate.epoch)
        host.acceptNavigation(candidate, from: candidate.epoch)
        precondition(host.navigation.overlay == nil)
        host.resolve(pending, ownerID: actor.userID, enabled: [.companies])
        let epoch = host.navigation.epoch
        candidate = host.navigation
        candidate.apply(.select(.companies), from: epoch)
        host.acceptNavigation(candidate, from: epoch)
        precondition(host.navigation.current == .companies)
        let before = host.navigation
        var injected = NovaNavigationState(epoch: epoch, available: Set(NovaDestination.allCases))
        injected.apply(.navigate(.training), from: epoch)
        host.acceptNavigation(injected, from: epoch)
        precondition(host.navigation == before)
        host.acceptNavigation(NovaNavigationState(epoch: UUID().uuidString, available: [.companies]), from: epoch)
        precondition(host.navigation == before)
        host.acceptNavigation(candidate, from: "stale")
        precondition(host.navigation == before)
        host.adopt(nil)
        host.acceptNavigation(candidate, from: epoch)
        precondition(host.phase == .signedOut && host.navigation.current == .home)
        print("PASS SwiftUI host Binding bridge: 6 guards")
    }
}
