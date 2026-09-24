import Foundation

/// 「今日の予定」でのカードの置きどころ。**拡張機能 sidepanel.js の `groupOf()` をそのまま移した。**
/// 数字が小さいほど上に出る。
public enum TodayGroup: Int, Comparable, Sendable {
    /// 時間帯のまっただ中
    case active = 0
    /// 「いつでも」と、目安日が来ている「◯日ごと」。いま着手できるもの
    case ready = 1
    /// まだ時間が来ていない
    case upcoming = 2
    /// 時間が過ぎたのに記録がない
    case overdue = 3
    /// 「◯日ごと」の予告中。今日の本来の予定を邪魔しないよう一番下
    /// （アプリでは目安日の当日から出すので、いまは entries() に現れない。拡張機能との並びの対応で残す）
    case heads_up = 4
    /// できた・休んだ
    case resolved = 5

    public static func < (a: TodayGroup, b: TodayGroup) -> Bool { a.rawValue < b.rawValue }
}

public struct TodayEntry: Equatable, Sendable {
    public var item: Item
    /// 今日の記録。まだなら nil
    public var mark: Mark?
    public var group: TodayGroup
}

public enum Today {

    /// 今日の画面に出すものを「これから」と「対応済み」に分けて返す。
    ///
    /// 並びは 進行中 → いつでも → これから → 未対応 → 予告中 で、各組の中は時刻順。
    /// **拡張機能と同じ並びでなければならない。** 同じ製品なのに端末ごとに並びが違うと、
    /// 「さっき上にあったものが無い」と探すことになる。
    ///
    /// 拡張側のこの処理は sidepanel.js にあってマーカーブロックの外なので、
    /// いまは突き合わせテストの対象外。**いずれ logic.js に寄せてここと突き合わせる。**
    public static func entries(
        schedule: [Item], records: Records, now: Date
    ) -> (todo: [TodayEntry], done: [TodayEntry]) {
        let key = Logic.dateKey(now)
        let rec = records[key] ?? [:]
        let c = Logic.calendar.dateComponents([.hour, .minute], from: now)
        let nowHM = String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)

        var entries: [TodayEntry] = []

        for item in schedule {
            if item.origId != nil || Logic.isArchived(item) || !item.enabled { continue }

            let mark = rec[item.id]
            let group = groupOf(item, mark: mark, records: records, now: now, nowHM: nowHM)

            // 今日の予定でないものは出さない（記録が付いているものは「対応済み」に出す）
            if group != .resolved {
                let due: Bool
                if Logic.isInterval(item) {
                    // 目安日の当日（と過ぎた日）だけ出す。前日から出すと「今日やる」と読めて紛らわしい
                    // （2026-09-24 本人指摘）。翌日以降のぶんは「登録済み」に次の日付つきで出ている。
                    // noticeDays（何日前から出すか）は拡張機能の設定で、アプリでは見ない
                    let info = Logic.intervalDueInfo(item, records, now)
                    due = (info?.daysUntil ?? 0) <= 0
                } else if Logic.isOneOff(item) {
                    due = item.date == key
                } else {
                    due = Logic.isScheduledOn(item.days, now)
                }
                if !due { continue }
            }

            entries.append(TodayEntry(item: item, mark: mark, group: group))
        }

        entries.sort {
            $0.group == $1.group
                ? ($0.item.time ?? "") < ($1.item.time ?? "")
                : $0.group < $1.group
        }

        return (entries.filter { $0.group != .resolved },
                entries.filter { $0.group == .resolved })
    }

    private static func groupOf(
        _ item: Item, mark: Mark?, records: Records, now: Date, nowHM: String
    ) -> TodayGroup {
        if mark != nil { return .resolved }

        // 時間帯のまっただ中（終了時刻つきの予定）
        if let time = item.time, let end = item.endTime,
           Logic.isValidEndTime(time, end), time <= nowHM, nowHM < end {
            return .active
        }

        // ◯日ごと：目安日以降は「いつでも」と同じ扱い。まだ先なら一番下
        if Logic.isInterval(item) {
            let info = Logic.intervalDueInfo(item, records, now)
            return (info?.daysUntil ?? 0) > 0 ? .heads_up : .ready
        }

        // 「いつでも」は時間切れの概念がないので、未対応にはならない
        if Logic.isAnytime(item) { return .ready }

        return (item.time ?? "") > nowHM ? .upcoming : .overdue
    }
}
