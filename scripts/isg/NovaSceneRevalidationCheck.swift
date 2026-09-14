import Foundation

@main struct Check {
    static func main() {
        var state = NovaSceneRevalidation()
        precondition(!state.update(isBackground: false, isActive: true))
        for _ in 0..<10 {
            precondition(!state.update(isBackground: false, isActive: false))
            precondition(!state.update(isBackground: false, isActive: true))
        }
        precondition(!state.update(isBackground: true, isActive: false))
        precondition(!state.update(isBackground: false, isActive: false))
        precondition(state.update(isBackground: false, isActive: true))
        precondition(!state.update(isBackground: false, isActive: true))
        precondition(!state.update(isBackground: true, isActive: false))
        precondition(state.update(isBackground: false, isActive: true))
        print("27 scene lifecycle checks PASS")
    }
}
