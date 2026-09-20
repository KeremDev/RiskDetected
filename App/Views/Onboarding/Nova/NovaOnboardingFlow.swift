#if DEBUG && NOVA_PILOT_BUILD
import SwiftUI

/// Every auth side effect the funnel needs, injected so the screens stay
/// declarative and the real services live at the composition root.
struct NovaOBAuthBridge {
    var signIn: (_ email: String, _ password: String) async throws -> Void
    var signUp: (_ email: String, _ password: String) async throws -> Void
    var sendCode: (_ email: String) async throws -> Void
    var verifyCode: (_ email: String, _ code: String) async throws -> Void
    var recoverPassword: (_ email: String) async throws -> Void
    var appleSignIn: () async throws -> Void
    var googleSignIn: () async throws -> Void
    var requestPush: () async -> Void
    /// Stores the profile before the account exists, so signing in later syncs it.
    var saveDraft: (_ answers: NovaOBAnswers) -> Void
    /// Persists the collected profile and hands control back to the app.
    var finish: (_ answers: NovaOBAnswers?) -> Void
}

/// Screen identifiers, one per `sc-if` branch in the prototype.
enum NovaOBScreen: Equatable {
    case splash, intro1, intro2, intro3, social
    case questions, prep, card, edit
    case signup, emailForm, otp
    case trial, trialHow, push
    case login
}

@MainActor
final class NovaOBController: ObservableObject {
    @Published var screen: NovaOBScreen = .splash
    @Published var questionIndex = 0
    @Published var answers = NovaOBAnswers()
    @Published var skipped: Set<String> = []
    @Published var search = ""
    @Published var returnToCard = false
    @Published var skipModal = false

    // prep
    @Published var prepPercent = 0
    @Published var prepDone = false

    // auth
    @Published var email = ""
    @Published var password = ""
    @Published var showPassword = false
    @Published var marketing = false
    @Published var otpDigits = Array(repeating: "", count: 6)
    @Published var otpError = ""
    @Published var otpVerified = false
    @Published var authError = ""
    @Published var busy = false
    @Published var resendNote = false

    let auth: NovaOBAuthBridge
    private var prepTask: Task<Void, Never>?

    init(auth: NovaOBAuthBridge) {
        self.auth = auth
        applyLaunchOverrideIfNeeded()
    }

    deinit { prepTask?.cancel() }

    /// Design QA hook, mirroring the prototype's own `startScreen` prop:
    /// `RD_NOVA_OB_SCREEN=card` jumps straight to a screen on launch.
    private func applyLaunchOverrideIfNeeded() {
        guard let raw = ProcessInfo.processInfo.environment["RD_NOVA_OB_SCREEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return }
        if raw.hasPrefix("q"), let index = Int(raw.dropFirst()) {
            questionIndex = max(0, min(NovaOBCatalogue.questions.count - 1, index - 1))
            screen = .questions
            return
        }
        let map: [String: NovaOBScreen] = [
            "splash": .splash, "i1": .intro1, "i2": .intro2, "i3": .intro3, "social": .social,
            "prep": .prep, "card": .card, "edit": .edit, "signup": .signup,
            "emailform": .emailForm, "otp": .otp, "trial": .trial, "trialhow": .trialHow,
            "push": .push, "login": .login
        ]
        guard let target = map[raw.lowercased()] else { return }
        if target == .prep {
            prepPercent = 100
            prepDone = true
        }
        screen = target
    }

    var question: NovaOBQuestion { NovaOBCatalogue.questions[questionIndex] }

    var sectionLabel: String {
        NovaOBCatalogue.sections.first { $0.range.contains(questionIndex) }?.label
            ?? NovaOBCatalogue.sections[0].label
    }

    var stepLabel: String { "\(questionIndex + 1) / \(NovaOBCatalogue.questions.count)" }

    var progress: Double {
        Double(questionIndex + 1) / Double(NovaOBCatalogue.questions.count)
    }

    var primaryLabel: String {
        if returnToCard { return "Değişikliği kaydet" }
        return questionIndex == NovaOBCatalogue.questions.count - 1 ? "Profilimi hazırla" : "Devam et"
    }

    // MARK: navigation

    func go(_ next: NovaOBScreen) {
        authError = ""
        screen = next
    }

    func startQuestions() {
        questionIndex = 0
        search = ""
        screen = .questions
    }

    func next() {
        guard canContinue else { return }
        if returnToCard { toCard(); return }
        if questionIndex >= NovaOBCatalogue.questions.count - 1 { startPrep(); return }
        questionIndex += 1
        search = ""
    }

    func skipQuestion() {
        skipped.insert(question.id)
        if returnToCard { toCard(); return }
        if questionIndex >= NovaOBCatalogue.questions.count - 1 { startPrep(); return }
        questionIndex += 1
        search = ""
    }

    func back() {
        switch screen {
        case .otp: go(.emailForm)
        case .trialHow: go(.trial)
        case .emailForm: go(.signup)
        case .questions:
            if returnToCard { toCard(); return }
            if questionIndex == 0 { go(.social); return }
            questionIndex -= 1
            search = ""
        default: go(.card)
        }
    }

    func editQuestion(_ index: Int) {
        questionIndex = index
        returnToCard = true
        search = ""
        screen = .questions
    }

    func toCard() {
        prepTask?.cancel()
        returnToCard = false
        screen = .card
    }

    // MARK: answers

    var canContinue: Bool {
        switch question.kind {
        case .text: return !answers.name.novaTrimmed.isEmpty
        case .counter: return true
        case .slider: return answers.exp != nil || answers.expLess
        case .single: return answers.single(question.id) != nil
        case .multi: return !answers.list(question.id).isEmpty
        }
    }

    func unskip(_ id: String) { skipped.remove(id) }

    func pickSingle(_ value: String) {
        unskip(question.id)
        answers.setSingle(question.id, answers.single(question.id) == value ? nil : value)
    }

    func toggleMulti(_ value: String) {
        let current = answers.list(question.id)
        unskip(question.id)
        var updated: [String]
        if let exclusive = question.exclusive, value == exclusive {
            updated = current.contains(value) ? [] : [value]
        } else if current.contains(value) {
            updated = current.filter { $0 != value }
        } else {
            let base: [String]
            if let exclusive = question.exclusive {
                base = current.filter { $0 != exclusive }
            } else {
                base = current
            }
            if let max = question.max, base.count >= max { return }
            updated = base + [value]
        }
        answers.setList(question.id, updated)
    }

    func isSelected(_ value: String) -> Bool {
        question.kind == .single ? answers.single(question.id) == value : answers.list(question.id).contains(value)
    }

    func isBlocked(_ value: String) -> Bool {
        guard !isSelected(value) else { return false }
        let chosen = answers.list(question.id)
        if let max = question.max, chosen.count >= max { return true }
        if let exclusive = question.exclusive, chosen.contains(exclusive), value != exclusive { return true }
        return false
    }

    /// "Sana uygun olabilir" — the assist step nudges what the growth step picked.
    func isSuggested(_ option: NovaOBOption) -> Bool {
        guard let source = option.suggestedBy, !isSelected(option.value) else { return false }
        return answers.growth.contains(source)
    }

    var selectionNote: String {
        if let max = question.max {
            let count = answers.list(question.id).count
            return "\(count) / \(max) seçildi — en fazla \(max) seçim yapabilirsin."
        }
        if question.kind == .multi {
            let count = answers.list(question.id).count
            return count > 0 ? "\(count) seçim yapıldı." : ""
        }
        return ""
    }

    var visibleOptions: [NovaOBOption] {
        guard question.searchable, !search.novaTrimmed.isEmpty else { return question.options }
        let needle = search.novaTrimmed.lowercased(with: Locale(identifier: "tr_TR"))
        let chosen = answers.list(question.id)
        return question.options.filter {
            $0.label.lowercased(with: Locale(identifier: "tr_TR")).contains(needle) || chosen.contains($0.value)
        }
    }

    var showsOtherField: Bool {
        guard let other = question.other else { return false }
        return question.kind == .single ? answers.single(question.id) == other : answers.list(question.id).contains(other)
    }

    // MARK: experience slider

    func pickStop(_ index: Int) {
        unskip("exp")
        answers.exp = index
        answers.expLess = false
    }

    func toggleLessThanYear() {
        unskip("exp")
        answers.expLess.toggle()
        answers.exp = nil
    }

    func bumpInspections(_ delta: Int) {
        unskip("inspections")
        answers.inspections = max(0, answers.inspections + delta)
    }

    // MARK: prep

    func startPrep() {
        prepTask?.cancel()
        prepPercent = 0
        prepDone = false
        screen = .prep
        prepTask = Task { [weak self] in
            let duration: Double = 3.4
            let start = Date()
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(start)
                let percent = min(100, Int((elapsed / duration) * 100))
                await MainActor.run { self?.prepPercent = percent }
                if percent >= 100 { break }
                try? await Task.sleep(nanoseconds: 40_000_000)
            }
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.prepDone = true }
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.screen == .prep else { return }
                self.toCard()
            }
        }
    }

    // MARK: summary rows

    func summaryValue(_ id: String) -> String {
        if skipped.contains(id) { return "Henüz eklenmedi" }
        let a = answers
        switch id {
        case "name": return a.name.novaTrimmed.isEmpty ? "Henüz eklenmedi" : a.name.novaTrimmed
        case "cert":
            guard let cert = a.cert else { return "Henüz eklenmedi" }
            return cert == "none" ? "Sertifika yok" : NovaOBCatalogue.label("cert", cert)
        case "work":
            guard let work = a.work else { return "Henüz eklenmedi" }
            return NovaOBCatalogue.label("work", work)
        case "role":
            guard let role = a.role else { return "Henüz eklenmedi" }
            if role == "diger" { return a.roleOther.novaTrimmed.isEmpty ? "Diğer" : a.roleOther.novaTrimmed }
            return NovaOBCatalogue.label("role", role)
        case "exp":
            if a.expLess { return "1 yıldan az" }
            guard let exp = a.exp else { return "Henüz eklenmedi" }
            return NovaOBCatalogue.experienceStops[exp].label
        case "sectors":
            let labels = a.sectors.map { value -> String in
                value == "diger" ? (a.sectorsOther.novaTrimmed.isEmpty ? "Diğer" : a.sectorsOther.novaTrimmed)
                    : NovaOBCatalogue.label("sectors", value)
            }
            if labels.isEmpty { return "Henüz eklenmedi" }
            return labels.count <= 2 ? labels.joined(separator: ", ")
                : labels.prefix(2).joined(separator: ", ") + " +\(labels.count - 2) sektör"
        case "trainings":
            if a.trainings.isEmpty { return "Henüz eklenmedi" }
            return a.trainings.contains("yok") ? "Henüz eğitim alınmadı" : "\(a.trainings.count) eğitim seçildi"
        case "approach":
            return a.approach.isEmpty ? "Henüz eklenmedi"
                : a.approach.map { NovaOBCatalogue.label("approach", $0) }.joined(separator: ", ")
        case "inspections":
            if skipped.contains("inspections") { return "Yanıtlanmadı" }
            return a.inspections == 0 ? "Teftiş deneyimi yok (0)" : "\(a.inspections) teftiş"
        case "growth":
            if a.growth.isEmpty { return "Henüz eklenmedi" }
            return a.growth.contains("yok") ? "Belirli bir alan yok" : "\(a.growth.count) alan seçildi"
        case "assist":
            return a.assist.isEmpty ? "Henüz eklenmedi"
                : a.assist.map { NovaOBCatalogue.label("assist", $0) }.joined(separator: ", ")
        default: return "Henüz eklenmedi"
        }
    }

    // MARK: auth actions

    func submitSignup() async {
        guard !busy else { return }
        let address = email.novaTrimmed
        guard !address.isEmpty else { authError = "E-posta adresini yaz."; return }
        guard Self.isValidEmail(address) else { authError = "Bu e-posta adresi geçerli görünmüyor."; return }
        guard IsgPasswordRules(password).valid else {
            authError = "Parola en az 8 karakter olmalı; büyük harf, küçük harf ve rakam içermeli."
            return
        }
        busy = true
        authError = ""
        do {
            try await auth.signUp(address, password)
            await openOtp(for: address)
        } catch IsgPasswordAuthError.confirmationRequired {
            // Expected: Supabase created the account and wants the address verified.
            await openOtp(for: address)
        } catch {
            authError = AppErrorMessage.make(
                error, context: "Hesap oluşturulamadı", fallbackTitle: "Hesap oluşturulamadı"
            ).message
        }
        busy = false
    }

    private func openOtp(for address: String) async {
        do { try await auth.sendCode(address) } catch {
            authError = AppErrorMessage.make(
                error, context: "Doğrulama kodu gönderilemedi", fallbackTitle: "Kod gönderilemedi"
            ).message
            return
        }
        otpDigits = Array(repeating: "", count: 6)
        otpError = ""
        otpVerified = false
        screen = .otp
    }

    func verifyOtp(_ code: String) async {
        guard !busy else { return }
        busy = true
        otpError = ""
        do {
            try await auth.verifyCode(email.novaTrimmed, code)
            otpVerified = true
            try? await Task.sleep(nanoseconds: 700_000_000)
            go(.trial)
        } catch {
            otpVerified = false
            otpError = "Geçersiz kod. Kodu kontrol edip yeniden dene."
            otpDigits = Array(repeating: "", count: 6)
        }
        busy = false
    }

    func resendCode() async {
        guard !email.novaTrimmed.isEmpty else { return }
        try? await auth.sendCode(email.novaTrimmed)
        resendNote = true
        try? await Task.sleep(nanoseconds: 2_600_000_000)
        resendNote = false
    }

    func runApple() async {
        guard !busy else { return }
        busy = true
        authError = ""
        do { try await auth.appleSignIn(); go(.trial) } catch {
            if !Self.isCancellation(error) {
                authError = AppErrorMessage.make(
                    error, context: "Apple ile giriş yapılamadı", fallbackTitle: "Apple ile giriş yapılamadı"
                ).message
            }
        }
        busy = false
    }

    func runGoogle() async {
        guard !busy else { return }
        busy = true
        authError = ""
        do { try await auth.googleSignIn(); go(.trial) } catch {
            if !Self.isCancellation(error) {
                authError = AppErrorMessage.make(
                    error, context: "Google ile giriş yapılamadı", fallbackTitle: "Google ile giriş yapılamadı"
                ).message
            }
        }
        busy = false
    }

    func finish() { auth.finish(answers) }

    static func isValidEmail(_ value: String) -> Bool {
        let address = value.novaTrimmed
        guard let at = address.firstIndex(of: "@"), at != address.startIndex else { return false }
        let domain = address[address.index(after: at)...]
        return !domain.isEmpty && domain.contains(".") && !domain.hasSuffix(".")
            && !domain.hasPrefix(".") && !address.contains(" ")
            && address.filter { $0 == "@" }.count == 1
    }

    static func isCancellation(_ error: Error) -> Bool {
        let text = error.localizedDescription.lowercased()
        return error is CancellationError || text.contains("cancel") || text.contains("vazgeç")
            || text.contains("iptal")
    }
}

/// The prototype's screen switch, one branch per `sc-if`.
struct NovaOnboardingFlow: View {
    @StateObject private var controller: NovaOBController
    let onOpenLogin: () -> Void

    init(auth: NovaOBAuthBridge, onOpenLogin: @escaping () -> Void) {
        _controller = StateObject(wrappedValue: NovaOBController(auth: auth))
        self.onOpenLogin = onOpenLogin
    }

    var body: some View {
        ZStack {
            switch controller.screen {
            case .splash: NovaOBSplashScreen(controller: controller)
            case .intro1: NovaOBIntroScreen(controller: controller, page: 0, onLogin: onOpenLogin)
            case .intro2: NovaOBIntroScreen(controller: controller, page: 1, onLogin: onOpenLogin)
            case .intro3: NovaOBIntroScreen(controller: controller, page: 2, onLogin: onOpenLogin)
            case .social: NovaOBSocialProofScreen(controller: controller, onLogin: onOpenLogin)
            case .questions: NovaOBQuestionScreen(controller: controller)
            case .prep: NovaOBPrepScreen(controller: controller)
            case .card: NovaOBProfileCardScreen(controller: controller)
            case .edit: NovaOBEditSummaryScreen(controller: controller)
            case .signup: NovaOBSignupScreen(controller: controller, onLogin: onOpenLogin)
            case .emailForm: NovaOBEmailFormScreen(controller: controller)
            case .otp: NovaOBOtpScreen(controller: controller)
            case .trial: NovaOBTrialScreen(controller: controller)
            case .trialHow: NovaOBTrialHowScreen(controller: controller)
            case .push: NovaOBPushScreen(controller: controller)
            case .login: Color.clear.onAppear { onOpenLogin() }
            }
        }
        .background(NovaOB.surface.ignoresSafeArea())
        .preferredColorScheme(.light)
        .animation(.easeInOut(duration: 0.28), value: controller.screen)
    }
}
#endif
