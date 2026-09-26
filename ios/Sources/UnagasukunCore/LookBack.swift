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

    /// ふりかえりのタイル。先週までの `count` 週に、**今週の列を足して**並べる（右端が今週）。
    ///
    /// 以前は「今週はまだ途中なのに色が少なく見える」として完全な週だけにしていたが、
    /// それだと昨日の記録を付け直す入口がタイルに無い（2026-09-22 本人指摘）。
    /// 今週のまだ来ていない日は画面側で点線の枠にして、四角の形は崩さない
    public static func tileWeeks(now: Date, count: Int = 12, includeCurrent: Bool = true) -> [[Date]] {
        let thisWeekStart = Logic.day(now, plus: -Logic.jsWeekday(now))
        let columns = includeCurrent ? count + 1 : count
        return (0..<columns).map { w in
            let start = Logic.day(thisWeekStart, plus: -(count - w) * 7)
            return (0..<7).map { Logic.day(start, plus: $0) }
        }
    }

    /// タイルの上に月名を出す列。月が変わった最初の週に付ける。
    /// 左端の列は、隣の列で月が変わるなら付けない（「6月 7月」と詰まって読めないため）。
    /// 返すのは (列番号, その週の日曜)
    public static func monthLabelColumns(_ weeks: [[Date]]) -> [(column: Int, sunday: Date)] {
        let cal = Logic.calendar
        func month(_ w: Int) -> Int { cal.component(.month, from: weeks[w][0]) }
        var out: [(column: Int, sunday: Date)] = []
        for w in weeks.indices {
            let startsMonth = w == 0 || month(w) != month(w - 1)
            let nextStartsMonth = w + 1 < weeks.count && month(w + 1) != month(w)
            if startsMonth && !(w == 0 && nextStartsMonth) {
                out.append((column: w, sunday: weeks[w][0]))
            }
        }
        return out
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

extension LookBack {
    /// カレンダーで日を選んだときの一覧。
    ///
    /// `Logic.itemsOnDay` は「◯日ごと」を毎日出す（付け忘れを直せるように）が、
    /// 今日の予定に無いものまで同じ顔で並ぶと「今日やるの？」と読める（2026-09-26 本人指摘）。
    /// その日に記録があるか、その日の時点で目安日が来ているものだけを `main` に、
    /// 残りの「◯日ごと」は `others`（済ませていたら付けられる控えめな欄）に分ける。
    /// **拡張機能の `itemsOnDay` は変えない**（突き合わせテストの対象なので、ここで分ける）
    public static func dayLists(_ schedule: [Item], _ records: Records, _ key: String)
        -> (main: [Item], others: [Item]) {
        let all = Logic.itemsOnDay(schedule, records, key)
        guard let day = Logic.parseDateKey(key) else { return (all, []) }
        let rec = records[key] ?? [:]
        var main: [Item] = [], others: [Item] = []
        for item in all {
            if Logic.isInterval(item), rec[item.id] == nil,
               let info = Logic.intervalDueInfo(item, records, day), info.daysUntil > 0 {
                others.append(item)
            } else {
                main.append(item)
            }
        }
        return (main, others)
    }
}
