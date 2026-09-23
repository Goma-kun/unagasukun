import SwiftUI
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// 拡張機能の sidepanel.css と同じ色（ライト）。**同じ製品に見えることが大事**なので、
/// ライト側を変えるときは向こうの :root も一緒に変える。
///
/// ダークは iPhone/Mac 版だけの話（拡張はライト固定）。
/// **紺の文字を黒い背景に置くと消える。** ダーク対応前は「追加」ボタンも説明文も
/// 見えない状態で、本人に「消えた」「何があるのか分からない」と言われた。
enum Theme {
    /// ヘッダーの地。ダークでも紺のまま（白文字が載るので問題ない）
    static let navy       = dynamic(light: 0x1B2A4A, dark: 0x1B2A4A)
    static let navyLight  = dynamic(light: 0x2E4370, dark: 0x3A5080)
    static let accent     = dynamic(light: 0xE8A13A, dark: 0xE8A13A)
    static let bg         = dynamic(light: 0xF7F8FA, dark: 0x121826)
    static let card       = dynamic(light: 0xFFFFFF, dark: 0x1E2638)
    static let text       = dynamic(light: 0x23293A, dark: 0xE6E9F0)
    static let muted      = dynamic(light: 0x7A8299, dark: 0x9AA3B8)
    static let done       = dynamic(light: 0x3A9E57, dark: 0x3FA862)
    static let skip       = dynamic(light: 0xB0B6C6, dark: 0x4A5468)
    static let danger     = dynamic(light: 0xC0392B, dark: 0xE05A4C)

    /// ボタンやカーソル、選択の枠など「前景の紺」。
    /// ライトでは紺、ダークでは薄い青。**背景の紺（navy）と分けて持つ**のがダーク対応の要
    static let tint       = dynamic(light: 0x1B2A4A, dark: 0x8FB4FF)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        #if os(iOS)
        return Color(uiColor: UIColor { trait in
            trait.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light)
        })
        #else
        return Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(hex: dark) : NSColor(hex: light)
        })
        #endif
    }
}

#if os(iOS)
private extension UIColor {
    convenience init(hex: UInt32) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#else
private extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}
#endif
