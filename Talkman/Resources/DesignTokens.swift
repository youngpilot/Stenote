import SwiftUI

enum DesignTokens {
    enum Color {
        static let accent = SwiftUI.Color.accentColor
        static let recording = SwiftUI.Color.red
        static let background = SwiftUI.Color(.windowBackgroundColor)
        static let label = SwiftUI.Color(.labelColor)
        static let labelSecondary = SwiftUI.Color(.secondaryLabelColor)
    }

    enum Font {
        static let body = SwiftUI.Font.system(.body)
        static let caption = SwiftUI.Font.system(.caption)
        static let headline = SwiftUI.Font.system(.headline)
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let s: CGFloat = 8
        static let m: CGFloat = 12
        static let l: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Radius {
        static let button: CGFloat = 8
    }
}
