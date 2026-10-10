import Foundation

/// 予定の繰り返しを日本語で言い切る。
///
/// 登録フォームのプレビュー帯と、登録済み一覧の両方がこれを使う。
/// **同じ予定が場所によって違う言い方をされると、同じものだと分からなくなる。**
public enum Describe {

    /// 曜日の短い名前（端末の言語で。ja は「日・月…」、en は「Sun・Mon…」）
    public static var weekdayNames: [String] { Logic.calendar.shortWeekdaySymbols }

    /// 並べるときの区切り。ja は「・」、en は「 · 」
    public static var sep: String { String(localized: "・") }

    /// 「毎日 07:30」「毎週 月・水 20:00」「3日ごと・次は 9/24(木)」「1回だけ 9/25(金)」「いつでも」
    public static func schedule(_ item: Item, records: Records = [:], now: Date = Date()) -> String {
        var parts: [String] = []

        if Logic.isInterval(item) {
            parts.append(rhythm(item.intervalDays ?? 0))
            if let info = Logic.intervalDueInfo(item, records, now) {
                let due = Logic.day(now, plus: max(0, info.daysUntil))
                parts.append(String(localized: "次は \(short(due))"))
            }
        } else if Logic.isOneOff(item) {
            if let d = Logic.parseDateKey(item.date) {
                parts.append(String(localized: "1回だけ \(short(d))"))
            } else {
                parts.append(String(localized: "1回だけ"))
            }
        } else if let days = item.days, !days.isEmpty, Set(days).count < 7 {
            parts.append(String(localized: "毎週 \(days.sorted().map { weekdayNames[$0] }.joined(separator: sep))"))
        } else {
            // 曜日を7つ全部選んだものは「毎日」。拡張機能の repeatText() と同じ言い方にする
            parts.append(String(localized: "毎日"))
        }

        if Logic.isAnytime(item) {
            parts.append(String(localized: "いつでも"))
            if let m = item.targetMin { parts.append(String(localized: "目安 \(m)分")) }
        } else if let t = item.time {
            if let e = item.endTime, Logic.isValidEndTime(t, e) {
                parts.append(String(localized: "\(t)〜\(e)"))
            } else {
                parts.append(t)
            }
        }

        return parts.joined(separator: sep)
    }

    /// 「3日に1回（間は2日空きます）」。
    /// 「3日ごと」は読みが1つでも、「3日おき」「3日空けて」で考える人には1日ずれて伝わる。
    /// **拡張機能の `intervalText` / `intervalGap` と同じ言い方**にしてある
    public static func rhythm(_ n: Int) -> String {
        n > 1 ? String(localized: "\(n)日に1回（間は\(n - 1)日空きます）") : String(localized: "1日に1回（毎日）")
    }

    /// 「9/24(木)」（en: "Thu, 9/24"）。端末の言語と地域の書式で出す
    public static func short(_ date: Date) -> String { shortFormatter.string(from: date) }

    /// 「2026/10/30(金)」（en: "Fri, 10/30/2026"）
    public static func long(_ date: Date) -> String { longFormatter.string(from: date) }

    /// 「2026年10月」（en: "October 2026"）
    public static func monthTitle(_ date: Date) -> String { monthFormatter.string(from: date) }

    /// 「10月」（en: "Oct"）
    public static func monthShort(_ date: Date) -> String { monthShortFormatter.string(from: date) }

    private static let shortFormatter = formatter("Md EEE")
    private static let longFormatter = formatter("yMd EEE")
    private static let monthFormatter = formatter("yMMMM")
    private static let monthShortFormatter = formatter("MMM")

    private static func formatter(_ template: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Logic.calendar
        f.locale = Locale.current
        f.setLocalizedDateFormatFromTemplate(template)
        return f
    }
}
