import Foundation

public enum LookBack {

    /// 月のカレンダーに並べる日。週の頭（日曜）で揃えるため、先頭を nil で埋める。
    /// 末尾は埋めない（空の行を作らないため）
    public static func monthGrid(_ month: Date) -> [Date?] {
        let cal = Logic.calendar
        let comps = cal.dateComponents([.year, .month], from: month)
        guard let first = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: first)
        else { return [] }

        let lead = Logic.jsWeekday(first)   // 日曜=0
        var cells: [Date?] = Array(repeating: nil, count: lead)
        for i in 0..<range.count {
            cells.append(Logic.day(first, plus: i))
        }
        return cells
    }

    /// ふりかえりのタイル。**先週までの完全な週**だけを並べる。
    ///
    /// 途中の週を混ぜると「今週はまだ途中なのに色が少ない」と見えてしまう。
    /// 拡張機能 v1.4.0 で同じ理由から「先週までの完全12週」に直した経緯がある。
    public static func tileWeeks(now: Date, count: Int = 12) -> [[Date]] {
        let thisWeekStart = Logic.day(now, plus: -Logic.jsWeekday(now))
        return (0..<count).map { w in
            let start = Logic.day(thisWeekStart, plus: -(count - w) * 7)
            return (0..<7).map { Logic.day(start, plus: $0) }
        }
    }

    /// タイル1マスの色分け。**「できた」だけ着色する。**
    /// できなかった日には何も出さない（沈黙が中立）。予定のない曜日も同じ
    public static func tileMark(
        _ item: Item, _ records: Records, _ day: Date, now: Date
    ) -> Mark? {
        guard day <= Logic.startOfDay(now) else { return nil }   // 未来は空
        return records[Logic.dateKey(day)]?[item.id]
    }

    /// ふりかえりのタイルに出す予定（繰り返しのものだけ）。
    /// 1回だけの予定はタイルにしても線にならないので、カレンダー側で見てもらう
    public static func tileItems(_ schedule: [Item]) -> [Item] {
        schedule.filter { !Logic.isOneOff($0) && $0.origId == nil && !Logic.isArchived($0) }
    }
}
