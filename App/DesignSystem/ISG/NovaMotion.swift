import SwiftUI
import UIKit

/// The one motion scale for every İSGADA surface.
///
/// `NovaTokens.swift` is generated from the pinned reference and carries colour,
/// type and dimension only, so motion lives here instead. Every curve, duration
/// and spring below is a named value — a screen that needs motion picks one from
/// this file rather than hand-typing a fourth curve that almost matches the other
/// three.
///
/// Two rules the values encode:
/// * **Nothing eases in.** An `ease-in` curve starts slow, which delays exactly the
///   moment the user is looking at. Entrances and exits use `easeOut`; something
///   moving from one on-screen place to another uses `easeInOut`.
/// * **UI motion stays under 300 ms.** The only exceptions are a deliberately slow
///   explanatory moment (onboarding) and indeterminate loops.
enum NovaMotion {
    /// Duration budgets by element class. Picking one of these is how a screen
    /// stays in step with the rest of the app.
    enum Duration {
        /// Press feedback. Short enough that the control is already lit up by the
        /// time the finger has settled.
        static let press = 0.16
        /// Tooltips and small popovers.
        static let popover = 0.18
        /// Filter panels, dropdowns, disclosure rows.
        static let dropdown = 0.22
        /// Progress bars and determinate meters.
        static let progress = 0.28
        /// Full modals and drawers — the one class allowed past 300 ms.
        static let modal = 0.32
        /// Reduce Motion replacement: a plain cross-fade with no travel.
        static let reduced = 0.12
    }

    // MARK: - Curves

    /// Strong ease-out, `cubic-bezier(0.23, 1, 0.32, 1)`. The default for
    /// anything entering or leaving the screen. The built-in `.easeOut` is too
    /// weak to read as deliberate at these durations.
    static func easeOut(_ duration: Double = Duration.dropdown) -> Animation {
        .timingCurve(0.23, 1, 0.32, 1, duration: duration)
    }

    /// Strong ease-in-out, `cubic-bezier(0.77, 0, 0.175, 1)`. For an element
    /// moving or morphing between two on-screen positions, where both ends of
    /// the motion are visible.
    static func easeInOut(_ duration: Double = Duration.dropdown) -> Animation {
        .timingCurve(0.77, 0, 0.175, 1, duration: duration)
    }

    /// The iOS drawer curve, `cubic-bezier(0.32, 0.72, 0, 1)`. Sheets, drawers
    /// and anything that arrives from an edge.
    static func drawer(_ duration: Double = Duration.modal) -> Animation {
        .timingCurve(0.32, 0.72, 0, 1, duration: duration)
    }

    // MARK: - Springs

    // SwiftUI's `response`/`dampingFraction` pair is the same two-parameter model
    // Apple's own motion design uses, so these are the shipped values rather than
    // an approximation of them: damping 1.0 settles with no overshoot, and the
    // bounce below 1.0 is reserved for motion a gesture actually threw.

    /// Repositioning something under the user's control. Critically damped — no
    /// overshoot, because nothing was thrown.
    static let move = Animation.spring(response: 0.4, dampingFraction: 1)

    /// Press and release. Fast, and it must not bounce: a button that wobbles
    /// after every tap becomes noise within a day of use.
    static let press = Animation.spring(response: 0.22, dampingFraction: 1)

    /// Momentum — a flick, a throw, a tab the finger pushed to. The only place
    /// overshoot belongs.
    static let momentum = Animation.spring(response: 0.34, dampingFraction: 0.8)

    /// A sheet or drawer settling into place.
    static let sheet = Animation.spring(response: 0.3, dampingFraction: 0.8)

    /// A rare, first-run celebration. The delight budget lives here and nowhere
    /// else in the app.
    static let celebrate = Animation.spring(response: 0.35, dampingFraction: 0.72)

    // MARK: - Reduce Motion

    /// Reduce Motion means *gentler*, not *none*. Travel and overshoot go; a
    /// short cross-fade stays, because it still explains that the state changed.
    ///
    /// Use this for animations that move or scale something. An animation that
    /// only changes opacity or colour can be left alone.
    static func gated(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: Duration.reduced) : animation
    }

    /// The variant for motion that has no meaningful reduced form — an infinite
    /// spinner, a marquee — where the honest answer is to stop it entirely.
    static func stopped(_ animation: Animation, reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : animation
    }
}

/// Haptics for the four moments that earn one.
///
/// Feedback only works while it stays rare: a haptic on every tap trains the
/// user to stop noticing all of them. Fire one where the event is genuinely
/// causal — a selection changed, a record was committed, something failed — and
/// on the same frame as the matching visual, never after an `await`.
enum NovaHaptics {
    /// A choice changed: a tab, a segment, an option in a picker.
    static func selection() {
        UISelectionFeedbackGenerator().selectionChanged()
    }

    /// A control committed. Keep it light; `.medium` and above read as an alarm.
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    /// A record was saved, a flow finished.
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    /// The action went through but something needs attention.
    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }

    /// The action did not go through.
    static func failure() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }
}

/// Press feedback for compact controls: buttons, icon targets, chips.
///
/// The scale change starts on touch-*down*, not on release — waiting for the tap
/// to complete before showing anything is what makes an interface feel dead. It
/// stays subtle on purpose; anything below about 0.95 reads as the button
/// collapsing rather than being pushed.
///
/// Reduce Motion drops the scale and keeps the opacity change, so the control
/// still answers the finger without moving.
struct NovaPressStyle: ButtonStyle {
    var scale: CGFloat = 0.97
    var pressedOpacity: Double = 0.85

    func makeBody(configuration: Configuration) -> some View {
        NovaPressBody(configuration: configuration, scale: scale, pressedOpacity: pressedOpacity)
    }
}

/// Press feedback for full-width rows and tiles.
///
/// A row is too large to scale — shrinking a list item pulls it away from the
/// rows around it. It dims instead, which is the same answer without the
/// movement.
struct NovaRowPressStyle: ButtonStyle {
    var pressedOpacity: Double = 0.62

    func makeBody(configuration: Configuration) -> some View {
        NovaPressBody(configuration: configuration, scale: 1, pressedOpacity: pressedOpacity)
    }
}

/// `@Environment` is only read on a `View`, and a `ButtonStyle` is not one, so
/// the accessibility setting has to be resolved in this nested body instead.
private struct NovaPressBody: View {
    let configuration: ButtonStyleConfiguration
    let scale: CGFloat
    let pressedOpacity: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        configuration.label
            .scaleEffect(reduceMotion || !configuration.isPressed ? 1 : scale)
            .opacity(configuration.isPressed ? pressedOpacity : 1)
            .animation(NovaMotion.press, value: configuration.isPressed)
    }
}
