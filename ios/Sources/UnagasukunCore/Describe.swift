import Foundation

/// 予定の繰り返しを日本語で言い切る。
///
/// 登録フォームのプレビュー帯と、登録済み一覧の両方がこれを使う。
/// **同じ予定が場所によって違う言い方をされると、同じものだと分からなくなる。**
public enum Describe {

    static let weekdayNames = ["日", "月", "火", "水", "木", "金", "土"]

    /// 「毎日 07:30」「毎週 月・水 20:00」「3日ごと・次は 9/24(木)」「1回だけ 9/25(金)」「いつでも」
    public static func schedule(_ item: Item, records: Records = [:], now: Date = Date()) -> String {
        var parts: [String] = []

        if Logic.isInterval(item) {
            parts.append("\(item.intervalDays ?? 0)日ごと")
            if let info = Logic.intervalDueInfo(item, records, now) {
                let due = Logic.day(now, plus: max(0, info.daysUntil))
                parts.append("次は \(short(due))")
            }
        } else if Logic.isOneOff(item) {
            if let d = Logic.parseDateKey(item.date) {
                parts.append("1回だけ \(short(d))")
            } else {
                parts.append("1回だけ")
            }
        } else if let days = item.days, !days.isEmpty, Set(days).count < 7 {
            parts.append("毎週 " + days.sorted().map { weekdayNames[$0] }.joined(separator: "・"))
        } else {
            // 曜日を7つ全部選んだものは「毎日」。拡張機能の repeatText() と同じ言い方にする
            parts.append("毎日")
        }

        if Logic.isAnytime(item) {
            parts.append("いつでも")
            if let m = item.targetMin { parts.append("目安 \(m)分") }
        } else if let t = item.time {
            parts.append(t)
        }

        return parts.joined(separator: "・")
    }

    /// 「9/24(木)」
    public static func short(_ date: Date) -> String {
        let c = Logic.calendar.dateComponents([.month, .day, .weekday], from: date)
        return "\(c.month ?? 0)/\(c.day ?? 0)(\(weekdayNames[(c.weekday ?? 1) - 1]))"
    }
}
