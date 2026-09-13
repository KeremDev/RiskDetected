import SwiftUI
import Supabase

#if !targetEnvironment(simulator)
#error("Native acceptance harness is simulator-only, never a production configuration")
#endif

struct NativeFixture: Decodable {
    let synthetic: Bool
    let email: String; let password: String; let company: UUID
    let secondEmail: String; let secondPassword: String; let secondCompany: UUID
}
/// Only replaces app-wide endpoint wiring. Controller, services, SDK, journal and screens are production sources.
@MainActor final class SupabaseService {
    static let shared = SupabaseService()
    let url: URL; let key: String; let client: SupabaseClient
    private init() {
        let env = ProcessInfo.processInfo.environment
        let endpoint = URL(string: env["ISG_QA_URL"] ?? "")!
        precondition(endpoint.scheme == "http" && endpoint.host == "127.0.0.1" && endpoint.port != nil && endpoint.path.isEmpty)
        let key = env["ISG_QA_KEY"] ?? ""; precondition(key.count == 64)
        self.url = endpoint; self.key = key
        client = SupabaseClient(supabaseURL: endpoint, supabaseKey: key, options: .init(auth: .init(storageKey: "native-qa-\(endpoint.port!)", autoRefreshToken: false)))
    }
    func qa(_ path: String, action: String? = nil) async throws -> Data {
        var request = URLRequest(url: url.appendingPathComponent("qa/\(path)"))
        request.setValue(key, forHTTPHeaderField: "apikey")
        if let action { request.httpMethod = "POST"; request.setValue("application/json", forHTTPHeaderField: "Content-Type"); request.httpBody = try JSONSerialization.data(withJSONObject: ["action": action]) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw NovaPersonnelFailure.unavailable }
        return data
    }
}
@main struct NativeHarnessApp: App { var body: some Scene { WindowGroup { NativeRoot() } } }
struct NativeRoot: View {
    @State private var fixture: NativeFixture?
    @State private var failed = false
    var body: some View {
        Group {
            if let fixture { NativeWorkspace(fixture: fixture) }
            else { Text(failed ? "QA bootstrap failed" : "QA connecting").accessibilityIdentifier("qa.bootstrap") }
        }.task {
            do {
                let service = SupabaseService.shared
                let value = try JSONDecoder().decode(NativeFixture.self, from: await service.qa("bootstrap"))
                guard value.synthetic else { throw NovaPersonnelFailure.denied }
                _ = try await service.client.auth.signIn(email: value.email, password: value.password)
                fixture = value
            } catch { failed = true }
        }.preferredColorScheme(.light)
    }
}
struct NativeWorkspace: View {
    let fixture: NativeFixture
    @StateObject private var controller = NovaWorkspaceController()
    @State private var status = "ready"
    @State private var kind: NovaDirectoryKind?
    @State private var directoryParent: UUID?
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        VStack(spacing: 0) {
            Text("\(status)|\(controller.resolving ? "loading" : "idle")|\(controller.canWrite ? "write" : "readonly")").accessibilityIdentifier("qa.state")
            HStack {
                Button("Firma A") { kind = nil; controller.select(fixture.company) }.accessibilityIdentifier("qa.company.a")
                Button("Firma B") { kind = nil; controller.select(fixture.secondCompany) }.accessibilityIdentifier("qa.company.b")
                Button("Hesap B") { login(second: true) }.accessibilityIdentifier("qa.account.b")
                Button("Hesap A") { login(second: false) }.accessibilityIdentifier("qa.account.a")
            }.font(.system(size: 12))
            ScrollView(.horizontal) { HStack {
                ForEach(["drop_next","write_off","read_off","paid_off","reset"], id: \.self) { action in
                    Button(action) { control(action) }.accessibilityIdentifier("qa.\(action)")
                }
            } }.font(.system(size: 11))
            Menu("Rehber") { ForEach(NovaDirectoryKind.allCases, id: \.self) { target in Button(target.rawValue) { open(target) }.accessibilityIdentifier("qa.directory.\(target.rawValue)") } }.accessibilityIdentifier("qa.directory")
            if let scope = controller.scope {
                NavigationStack {
                    if let kind { NovaDirectoryDestination(scope: scope, kind: kind, parent: directoryParent, client: controller.directoryClient, onBack: { self.kind = nil }, canWrite: controller.canWrite).id(kind) }
                    else { NovaPersonnelDestination(scope: scope, companyName: "Native QA", client: controller.personnelClient, onBack: { controller.select(nil) }, directory: controller.directoryClient, canWrite: controller.canWrite) }
                }.id(scope)
            } else { Spacer(); Text("Firma seçin").accessibilityIdentifier("qa.no.scope"); Spacer() }
        }
        .task { await controller.observe() }
        .onChange(of: scenePhase) { if $0 == .active { controller.refresh() } }
    }
    private func control(_ action: String) {
        status = "working"
        Task { do { _ = try await SupabaseService.shared.qa("control", action: action); status = action; if action != "drop_next" { controller.refresh() } } catch { status = "error" } }
    }
    private func open(_ target: NovaDirectoryKind) {
        guard let scope = controller.scope else { return }
        Task {
            do {
                var parent: UUID?
                if target == .contexts {
                    let page = try await controller.directoryClient.read(scope, .workplaces, nil, nil, false)
                    parent = page.rows.first(where: { $0.title == "Native ios workplace" })?.id
                    guard parent != nil else { throw NovaPersonnelFailure.validation }
                }
                if target == .assignments || target == .employers {
                    let page = try await controller.personnelClient.employees(scope, "Native ios Son", false, nil)
                    parent = page.rows.first?.id; guard parent != nil else { throw NovaPersonnelFailure.validation }
                }
                directoryParent = parent; kind = target; status = target.rawValue
            } catch { status = "directory.error" }
        }
    }
    private func login(second: Bool) {
        status = "working"
        Task { do { _ = try await SupabaseService.shared.client.auth.signIn(email: second ? fixture.secondEmail : fixture.email, password: second ? fixture.secondPassword : fixture.password); status = second ? "account.b" : "account.a" } catch { status = "error" } }
    }
}
