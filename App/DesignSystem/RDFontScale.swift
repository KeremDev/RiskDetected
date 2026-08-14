import SwiftUI

enum RDFontScale {
    static func size(_ base: CGFloat) -> CGFloat {
        switch base {
        case 28...:
            return base - 3
        case 22..<28:
            return base - 2
        case 17..<22:
            return base - 1.5
        case 13..<17:
            return base - 1
        case 12..<13:
            return base - 0.5
        default:
            return base
        }
    }
}
