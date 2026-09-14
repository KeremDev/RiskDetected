import Foundation

/// A transient interruption is not an app return. Auth changes are handled separately.
struct NovaSceneRevalidation {
    private var backgrounded = false
    mutating func update(isBackground: Bool, isActive: Bool) -> Bool {
        if isBackground { backgrounded = true }
        guard isActive && backgrounded else { return false }
        backgrounded = false
        return true
    }
}
