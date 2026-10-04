import Foundation

/// 「今日の予定」でのカードの置きどころ。**拡張機能 sidepanel.js の `groupOf()` をそのまま移した。**
/// 数字が小さいほど上に出る。
///
/// **2026-10-04: 「時間が過ぎたのに記録がない」を上から 2 番目に上げた**（本人の指摘
/// 「iPhone に通知が来たが、何の通知かすぐ分からなかった。通知を出すカードは一番上に出してほしい」）。
/// 通知が鳴るのは時刻のある予定で、鳴ったあと記録が付くまでは必ずこの組に入る。
/// それが「いつでも」の下に沈んでいたので、開いても探すことになっていた。
/// 一覧の定石でも、期限が過ぎたものは今日の分と並べて上に置く（Asana・ClickUp）。
/// **責めないための赤は使わない**という方針は変えない（枠は橙のまま）
public enum TodayGroup: Int, Comparable, Sendable {
    /// 時間帯のまっただ中
    case active = 0
    /// 時間が過ぎたのに記録がない。**通知が鳴ったあとのものはここに来る**
    case overdue = 1
    /// 「いつでも」と、目安日が来ている「◯日ごと」。いま着手できるもの
    case ready = 2
    /// まだ時間が来ていない
    case upcoming = 3
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
    /// 並びは 進行中 → 未対応 → いつでも → これから → 予告中 で、各組の中は時刻順。
    /// **拡張機能と同じ並びでなければならない。** 同じ製品なのに端末ごとに並びが違うと、
    /// 「さっき上にあったものが無い」と探すことになる。
    ///
    /// 拡張側のこの処理は sidepanel.js にあってマーカーブロックの外なので、
    /// いまは突き合わせテストの対象外。**いずれ logic.js に寄せてここと突き合わせる。**
    public static func entries(
        schedule: [Item], records: Records, now: Date, tagOrder: [String] = []
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

        // 並びは 組 → 時刻 → ラベル → 登録順。
        // 同じ時刻（とくに「いつでも」どうし）は、同じラベルが隣り合うようにまとめる。
        // 「買い物・遊び・買い物」と飛び飛びに並ぶと見づらい（2026-10-04 本人指摘）。
        // ラベルの順は「ラベルを整える」で並べた順。ラベル無しは最後
        let rank = Dictionary(uniqueKeysWithValues: tagOrder.enumerated().map { ($1, $0) })
        func tagRank(_ item: Item) -> Int { item.tagId.flatMap { rank[$0] } ?? Int.max }
        let order = Dictionary(uniqueKeysWithValues: schedule.enumerated().map { ($1.id, $0) })
        entries.sort { a, b in
            if a.group != b.group { return a.group < b.group }
            let ta = a.item.time ?? "", tb = b.item.time ?? ""
            if ta != tb { return ta < tb }
            let ra = tagRank(a.item), rb = tagRank(b.item)
            if ra != rb { return ra < rb }
            return (order[a.item.id] ?? 0) < (order[b.item.id] ?? 0)
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
