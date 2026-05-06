import Foundation
import SwiftUI
import Combine

enum AppFlow: Equatable {
    case splash
    case onboarding
    case auth
    case main
}

@MainActor
final class AppState: ObservableObject {
    @Published var flow: AppFlow = .splash
    @Published var isPro: Bool = false
    @Published var profile: UserProfile?
    @Published var hasSeenOnboarding: Bool
    @Published var authError: String?

    let auth: AuthService

    private var cancellables = Set<AnyCancellable>()

    init(auth: AuthService? = nil) {
        let resolved = auth ?? AuthService()
        self.auth = resolved
        self.hasSeenOnboarding = UserDefaults.standard.bool(forKey: "rd.onboarding.completed")
        self.profile = resolved.profile
        self.isPro = resolved.profile?.isPro ?? false
        self.authError = resolved.lastError
        observeAuth()
        Task { await bootstrap() }
    }

    func bootstrap() async {
        try? await Task.sleep(nanoseconds: 800_000_000)

        if auth.isAuthenticated {
            // Profile observer'ı zaten bağladığımız için fetch otomatik tetiklenir,
            // yine de kesinlik için bir kez daha refresh edelim.
            await auth.refreshProfile()
            flow = .main
            return
        }

        flow = hasSeenOnboarding ? .auth : .onboarding
    }

    func finishOnboarding() {
        hasSeenOnboarding = true
        UserDefaults.standard.set(true, forKey: "rd.onboarding.completed")
        flow = .auth
    }

    /// Auth tarafı zaten signedIn yayınladığında otomatik geçilecek; manuel çağrıyı
    /// AuthView'in geçici "demo giriş" senaryosu için saklıyoruz.
    func signIn() {
        flow = .main
    }

    func signOut() {
        Task {
            try? await auth.signOut()
        }
    }

    // MARK: - Observation

    /// Combine .sink ile auth state'ini SENKRON olarak mirror'lar.
    /// AsyncSequence (.values) pattern'i bazı durumlarda gecikmeli/atlamalı
    /// tetiklenebiliyor — sink garanti tetikler.
    private func observeAuth() {
        // Profile mirror
        auth.$profile
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newProfile in
                guard let self else { return }
                self.profile = newProfile
                self.isPro = newProfile?.isPro ?? false
            }
            .store(in: &cancellables)

        // Session mirror — flow geçişlerini tetikle
        auth.$session
            .receive(on: DispatchQueue.main)
            .sink { [weak self] session in
                guard let self else { return }
                if session != nil {
                    if self.flow != .main {
                        self.flow = .main
                    }
                } else if self.flow == .main {
                    self.flow = .auth
                }
            }
            .store(in: &cancellables)

        // lastError mirror — UI gösterimi için
        auth.$lastError
            .receive(on: DispatchQueue.main)
            .sink { [weak self] err in
                self?.authError = err
            }
            .store(in: &cancellables)
    }
}
