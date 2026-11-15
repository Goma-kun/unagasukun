import SwiftUI

#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// カードの「AI に聞く」。予定の名前と詳細を、選んだ AI の入力欄に入れて開く（2026-11-15 本人要望）。
///
/// - 送信はしない。入力欄に入るだけなので、足したい言葉を書いてから本人が送る
/// - **どの聞き先でも、先に同じ文をクリップボードへ入れる。** URL で渡せない相手（Gemini）や、
///   URL の受け取りが変わった相手でも、貼り付ければ済むようにするため
/// - URL の出どころ（2026-11-15 調べ）: Claude のデスクトップ／iPhone アプリは公式ヘルプに記載あり。
///   ChatGPT の `?q=` は公式の記載なし（動かなくなっても貼り付けで足りる）。Gemini は渡す方法が無い
enum AskAI: String, CaseIterable, Identifiable {
    case off, claudeCode, claude, chatgpt, gemini

    static let storageKey = "askAITarget"

    var id: String { rawValue }

    /// 設定に出す名前
    var name: String {
        switch self {
        case .off: return String(localized: "出さない")
        case .claudeCode: return "Claude Code"
        case .claude: return "Claude"
        case .chatgpt: return "ChatGPT"
        case .gemini: return "Gemini"
        }
    }

    /// カードのボタンの文字。どこが開くかが押す前に分かるように、聞き先の名前を入れる
    var buttonTitle: String { String(localized: "\(name) に聞く") }

    /// URL で入力欄まで入るか。入らない相手は、開いたあと貼り付けてもらう
    var prefills: Bool { self != .gemini }

    /// 予定から作る質問文（名前、あれば改行して詳細）
    static func question(for item: Item) -> String {
        var s = item.label
        if let d = item.detail, !d.isEmpty { s += "\n" + d }
        return s
    }

    /// 文をコピーし、聞き先を開く。帯に出す一言を返す
    @discardableResult
    func ask(_ item: Item) -> String {
        let q = Self.question(for: item)
        Self.copy(q)
        for url in urls(q) where Self.open(url) { break }
        return prefills
            ? String(localized: "\(name) を開きました。うまく入らないときは貼り付けてください")
            : String(localized: "コピーしました。\(name) に貼り付けてください")
    }

    /// 開く URL の候補（前から順に試す）。Mac はアプリのリンクを先に、無ければ Web
    private func urls(_ q: String) -> [URL] {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        // Claude のリンクは長いと切れる（デスクトップで約 14,000 字）。詳細メモが長い予定に備えて控えめに切る
        let enc = String(q.prefix(4000)).addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
        var list: [String] = []
        switch self {
        case .off: break
        case .claudeCode:
            #if os(macOS)
            list.append("claude://code/new?q=\(enc)")
            #endif
            list.append("https://claude.ai/code/new?q=\(enc)")
        case .claude:
            #if os(macOS)
            list.append("claude://claude.ai/new?q=\(enc)")
            #endif
            list.append("https://claude.ai/new?q=\(enc)")
        case .chatgpt:
            list.append("https://chatgpt.com/?q=\(enc)")
        case .gemini:
            list.append("https://gemini.google.com/app")
        }
        return list.compactMap { URL(string: $0) }
    }

    private static func copy(_ text: String) {
        #if os(iOS)
        UIPasteboard.general.string = text
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }

    /// 開けたら true。Mac は受け取るアプリが無いリンク（claude://）を飛ばして次の候補へ
    private static func open(_ url: URL) -> Bool {
        #if os(iOS)
        UIApplication.shared.open(url)
        return true
        #else
        guard NSWorkspace.shared.urlForApplication(toOpen: url) != nil else { return false }
        return NSWorkspace.shared.open(url)
        #endif
    }
}

/// カードに置く小さなボタン（「前にできていた」と同じ形）
struct AskAIButton: View {
    let item: Item
    var onNotice: (String) -> Void
    @AppStorage(AskAI.storageKey) private var raw = AskAI.off.rawValue

    var body: some View {
        let target = AskAI(rawValue: raw) ?? .off
        if target != .off {
            Button { onNotice(target.ask(item)) } label: {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles").font(.system(size: 11))
                    Text(target.buttonTitle).font(.system(size: 12, weight: .medium))
                }
                .foregroundStyle(Theme.muted)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .overlay(Capsule().stroke(Theme.skip, lineWidth: 1))
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            // 詳細メモが長くても、ボタンの文字は折り返さない（折り返すと 2 行の楕円になる）
            .lineLimit(1)
            .fixedSize()
        }
    }
}
