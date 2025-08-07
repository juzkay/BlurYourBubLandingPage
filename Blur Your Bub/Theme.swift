import SwiftUI

struct Theme {
    static let accent = Color(hex: "#6a62da")
    static let background = Color(hex: "#f5f2f1")
    static let card = Color(.systemGray6)
    static let primaryText = Color(.label)
    static let secondaryText = Color(.secondaryLabel)
    static let buttonCornerRadius: CGFloat = 16
    static let cardCornerRadius: CGFloat = 20
    static let shadow = Color(.black).opacity(0.07)
    static let fontTitle = Font.system(size: 28, weight: .bold, design: .rounded)
    static let fontSubtitle = Font.system(size: 18, weight: .semibold, design: .rounded)
    static let fontBody = Font.system(size: 16, weight: .regular, design: .rounded)
}

// Add Color extension for hex support
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
} 