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

    /// ラベルの8色。ライトは白いカードの上で沈まない濃さ、ダークは暗いカードの上で浮く明るさ。
    /// 状態の色（done の緑・accent の橙）と見分けがつくよう、緑は青寄り、橙は赤寄りにずらしてある
    static func tagColor(_ key: String) -> Color {
        let h = tagHex(key)
        return dynamic(light: h.light, dark: h.dark)
    }

    /// カードの地。**ラベルが付いていたら、その色をほんの少し混ぜる**（本人の要望・2026-10-01
    /// 「ラベルを付けるだけでなくカード自体の色が変わったほうがパッと見て分かる」）。
    ///
    /// ベタ塗りにはしない。カードの上には本文も「できた」の緑も載るので、地を濃くすると
    /// そちらが読みにくくなる。**左の帯＋地を1割ほど寄せる**のが、仕分けの色づけの定石
    /// （色だけで意味を伝えないよう、名前入りのチップも今までどおり残す）
    static func cardBg(_ key: String?) -> Color {
        guard let key, !key.isEmpty, key != "none" else { return card }
        let h = tagHex(key)
        // ダークは地が暗いぶん、同じ割合だと差が出ない。17% では「色合いが微妙で分かりづらい」
        // （2026-10-03 本人指摘・Mac と iPhone 両方）ので 3割まで寄せ、枠線（cardStroke）も添える
        // 暗い地に色を多く混ぜると、橙は茶色に、桃色はくすんだ色に沈む（色の性質）。
        // 地は2割に抑え、鮮やかさは枠線と時刻の文字（timeColor）に持たせる（2026-10-04 本人指摘）
        return dynamic(light: mix(0xFFFFFF, h.light, 0.16), dark: mix(0x1E2638, h.dark, 0.20))
    }

    /// カードの枠線。ラベルがあればその色、無ければ薄い灰色。
    /// 地の色だけだと暗い画面で見分けにくいのでラベルの色で縁取る。文字や「できた」の緑には重ならない。
    /// **ラベルの無いカードにも同じ太さの枠を付ける**（枠の有無で凹凸が違って見える・2026-10-03 本人指摘）
    static func cardStroke(_ key: String?) -> Color {
        guard let key, !key.isEmpty, key != "none" else { return plainStroke }
        return tagColor(key).opacity(0.95)
    }

    /// 枠の太さ。ラベル付きは少し太くして色をはっきり見せる
    static func cardStrokeWidth(_ key: String?) -> CGFloat {
        guard let key, !key.isEmpty, key != "none" else { return 1.5 }
        return 2
    }

    /// 時刻（「いつでも」「09:00」）の文字色。ラベルがあればその色、無ければいつもの青。
    /// 大きな文字に色を持たせると、地を濃く塗らなくても一目で仕分けが分かる
    static func timeColor(_ key: String?) -> Color {
        guard let key, !key.isEmpty, key != "none" else { return tint }
        return tagColor(key)
    }

    /// ラベルの無いカードの枠
    static let plainStroke = skip.opacity(0.4)

    private static func tagHex(_ key: String) -> (light: UInt32, dark: UInt32) {
        switch key {
        // ダークは彩度を上げてある。暗い地に混ぜると、くすんだ色は茶色や灰色に沈むため
        // （2026-10-04 本人指摘「買い物が茶色っぽい・遊びがくすんでいる」）
        case "red":    return (0xD65A4A, 0xFF6B5E)
        case "orange": return (0xE07B2E, 0xFF9A2E)
        case "yellow": return (0xC9A227, 0xFFD23F)
        case "green":  return (0x4C9F70, 0x3DD68C)
        case "teal":   return (0x2E9AA6, 0x2ED3E0)
        case "blue":   return (0x3B78D8, 0x5AA2FF)
        case "purple": return (0x8A5CC7, 0xB57BFF)
        case "pink":   return (0xD4569A, 0xFF6FB5)
        default:       return (0x7A8299, 0x9AA3B8)
        }
    }

    /// 2色を混ぜる（ratio の分だけ b に寄せる）。半透明を重ねるのではなく
    /// 混ぜた不透明色を作るので、カードが重なっても見え方が変わらない
    private static func mix(_ a: UInt32, _ b: UInt32, _ ratio: Double) -> UInt32 {
        func ch(_ shift: UInt32) -> UInt32 {
            let x = Double((a >> shift) & 0xFF), y = Double((b >> shift) & 0xFF)
            return UInt32((x + (y - x) * ratio).rounded())
        }
        return (ch(16) << 16) | (ch(8) << 8) | ch(0)
    }

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
