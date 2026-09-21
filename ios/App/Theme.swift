import SwiftUI

/// 拡張機能の sidepanel.css と同じ色。**同じ製品に見えることが大事**なので、
/// ここを変えるときは向こうの :root も一緒に変える。
enum Theme {
    static let navy = Color(hex: 0x1B2A4A)
    static let navyLight = Color(hex: 0x2E4370)
    static let accent = Color(hex: 0xE8A13A)
    static let bg = Color(hex: 0xF7F8FA)
    static let card = Color.white
    static let text = Color(hex: 0x23293A)
    static let muted = Color(hex: 0x7A8299)
    static let done = Color(hex: 0x3A9E57)
    static let skip = Color(hex: 0xB0B6C6)
    static let danger = Color(hex: 0xC0392B)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
