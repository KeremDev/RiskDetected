import SwiftUI

/// All former KKD entry points now lead to the bundled editable example.
struct NovaPilotPPEGate: View {
    let identity: NovaSessionIdentity
    let canWrite: Bool
    var initialCompany: UUID?
    var headingOverride: String?
    var startInAddMode = false
    let onBack: () -> Void

    var body: some View {
        NovaPPEExampleScreen(onBack: onBack)
    }
}
