import SwiftUI

/// Install on the session-owned root, above sheets. Call only after a verified commit.
struct NovaSuccessPresentation: ViewModifier {
    private struct Event: Identifiable { let id = UUID(); let text: String }
    @State private var event: Event?
    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var scheme
    func body(content: Content) -> some View {
        content
            .environment(\.novaCelebrate, { event = Event(text: $0) })
            .overlay {
                if let event {
                    ZStack {
                        Color.black.opacity(0.30).ignoresSafeArea()
                        NovaCard(padding: 24) {
                            VStack(spacing: 14) {
                                HStack(spacing: 18) {
                                    Image(systemName: "sparkles").font(.title3).foregroundStyle(.orange)
                                    Image(systemName: "checkmark.seal").font(.system(size: 44, weight: .light))
                                        .foregroundStyle(NovaColorToken.accentInk.color(in: scheme))
                                    Image(systemName: "party.popper").font(.title3).foregroundStyle(.purple)
                                }.accessibilityHidden(true)
                                NovaText(text: event.text, style: .cardTitle)
                                    .multilineTextAlignment(.center)
                            }.frame(maxWidth: .infinity)
                        }.frame(maxWidth: 300).padding(24)
                            .scaleEffect(reduceMotion || appeared ? 1 : 0.9)
                    }
                    .accessibilityElement(children: .combine).accessibilityAddTraits(.isModal)
                    .accessibilityIdentifier("nova.success")
                    .task(id: event.id) {
                        appeared = false
                        withAnimation(reduceMotion ? nil : .spring(response: 0.35)) { appeared = true }
                        UIAccessibility.post(notification: .announcement, argument: event.text)
                        do { try await Task.sleep(nanoseconds: 2_500_000_000) } catch { return }
                        if self.event?.id == event.id { self.event = nil }
                    }
                }
            }
    }
}
