import Foundation

/// extension/logic.js の「スケジュール計算ロジック」ブロックをそのまま移したもの。
///
/// **judgement の意味づけは logic.js のコメントが正本。** ここを直すときは向こうも直す。
/// 両方が同じ答えを返すことは ../test/parity_test.mjs が実際に突き合わせて確かめる。
///
/// JS の `Date` は端末のタイムゾーンのローカル時刻で年月日を組み立てる。
/// ここも同じになるよう `Calendar.current`（システムのタイムゾーン）で揃えている。
public enum Logic {

    // MARK: - 暦の足回り

    static var calendar: Calendar { Calendar.current }

    /// JS の `getDay()`（日曜=0）に合わせる。Foundation の weekday は日曜=1
    static func jsWeekday(_ date: Date) -> Int {
        calendar.component(.weekday, from: date) - 1
    }

    /// その日の 00:00
    static func startOfDay(_ date: Date) -> Date {
        calendar.startOfDay(for: date)
    }

    /// 日数を足した日の 00:00。月をまたぐ繰り上がりは Calendar に任せる
    static func day(_ date: Date, plus days: Int) -> Date {
        calendar.date(byAdding: .day, value: days, to: startOfDay(date)) ?? date
    }

    /// その日の指定時刻。JS の `new Date(y, m, d, hh, mm)` と同じで、
    /// 24時以降や60分以降は翌日へ繰り上がる（終了時刻 "24:00" がこれに当たる）。
    /// `bySettingHour:` は範囲外を受け付けないので、components を組んで Calendar に正規化させる
    static func at(_ date: Date, hour: Int, minute: Int) -> Date {
        let ymd = calendar.dateComponents([.year, .month, .day], from: date)
        var c = DateComponents()
        c.year = ymd.year; c.month = ymd.month; c.day = ymd.day
        c.hour = hour; c.minute = minute; c.second = 0
        return calendar.date(from: c) ?? startOfDay(date)
    }

    /// その日の 23:59:59.999（JS の `new Date(y, m, d, 23, 59, 59, 999)` と同じ）
    static func endOfDay(_ date: Date) -> Date {
        at(date, hour: 23, minute: 59).addingTimeInterval(59.999)
    }

    /// JS の `Date.getTime()` と同じミリ秒。アプリ側と突き合わせ用プローブの両方が使う
    public static func ms(_ date: Date) -> Double { date.timeIntervalSince1970 * 1000 }

    private static let dayMs: Double = 24 * 60 * 60 * 1000

    /// "HH:MM" の**形**だけを見て (時, 分) に。範囲は見ない。
    /// JS 版の `/^\d{2}:\d{2}$/` に対応する。`isValidEndTime` と `blockEndMs` はここまでしか見ておらず、
    /// 終了時刻 "24:00"（その日の終わり）を通す。**範囲を足すと拡張機能と答えが変わる**
    static func parseTimeParts(_ s: String?) -> (Int, Int)? {
        guard let s, s.count == 5 else { return nil }
        let p = s.split(separator: ":", omittingEmptySubsequences: false)
        guard p.count == 2, p[0].count == 2, p[1].count == 2,
              p[0].allSatisfy(\.isNumber), p[1].allSatisfy(\.isNumber),
              let h = Int(p[0]), let m = Int(p[1])
        else { return nil }
        return (h, m)
    }

    /// 発火時刻として妥当な "HH:MM"。`nextOccurrence` だけがここまで見る（JS も同じ）
    static func parseTime(_ s: String?) -> (Int, Int)? {
        guard let (h, m) = parseTimeParts(s), h <= 23, m <= 59 else { return nil }
        return (h, m)
    }

    /// "YYYY-MM-DD" をその日の 00:00 に。形式が違えば nil
    static func parseDateKey(_ s: String?) -> Date? {
        guard let s, isDateKey(s) else { return nil }
        let p = s.split(separator: "-")
        guard let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]) else { return nil }
        var c = DateComponents()
        c.year = y; c.month = m; c.day = d
        return calendar.date(from: c)
    }

    static func isDateKey(_ s: String) -> Bool {
        let p = s.split(separator: "-", omittingEmptySubsequences: false)
        guard p.count == 3, p[0].count == 4, p[1].count == 2, p[2].count == 2 else { return false }
        return p.allSatisfy { $0.allSatisfy(\.isNumber) }
    }

    // MARK: - 日付キー

    /// その日付のキー（実績記録に使う）。例: "2026-08-13"
    public static func dateKey(_ date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: - 予定の種類

    /// その日にこの予定があるか（days が空＝毎日）
    public static func isScheduledOn(_ days: [Int]?, _ date: Date) -> Bool {
        guard let days, !days.isEmpty else { return true }
        return days.contains(jsWeekday(date))
    }

    /// 1回だけの予定か（日付があり、曜日の繰り返しがない）
    public static func isOneOff(_ item: Item) -> Bool {
        item.date != nil && !(item.date!.isEmpty) && (item.days?.isEmpty ?? true)
    }

    /// 時刻を固定しない予定か
    public static func isAnytime(_ item: Item) -> Bool { item.anytime }

    /// 「◯日ごと」の予定か（済ませた日を基準に数え直す）
    public static func isInterval(_ item: Item) -> Bool {
        guard let n = item.intervalDays else { return false }
        return n > 0
    }

    /// 保管済みの予定か（日付が過ぎた1回だけ。一覧・通知には出さないが名前を引ける）
    public static func isArchived(_ item: Item) -> Bool { item.archived }

    /// 何日前から「今日の予定」に出すか（未設定は3日前から）。
    /// 拡張機能の設定。アプリの今日の予定は目安日の当日から出すので、これは見ない（Today.swift）
    public static func intervalNoticeDays(_ item: Item) -> Int {
        guard let n = item.noticeDays, n >= 0 else { return 3 }
        return n
    }

    // MARK: - 「◯日ごと」

    /// 基準日（YYYY-MM-DD）。records の最新の「できた」と anchorDate の新しいほう
    public static func intervalAnchorKey(_ item: Item, _ records: Records, _ now: Date) -> String? {
        let anchor: String? = {
            guard let a = item.anchorDate, isDateKey(a) else { return nil }
            return a
        }()
        var d = startOfDay(now)
        for _ in 0..<366 {
            let k = dateKey(d)
            // anchorDate のほうが新しいと分かった時点で records を遡っても勝てない
            if let anchor, anchor >= k { return anchor }
            if records[k]?[item.id] == .done { return k }
            d = day(d, plus: -1)
        }
        return anchor
    }

    /// 目安日まであと何日か。基準が無ければ「そろそろ」扱い（daysUntil 0）
    public static func intervalDueInfo(_ item: Item, _ records: Records, _ now: Date) -> IntervalDue? {
        guard isInterval(item) else { return nil }
        guard let anchor = intervalAnchorKey(item, records, now) else {
            return IntervalDue(daysUntil: 0, sinceDone: nil)
        }
        let today = startOfDay(now)
        guard let anchorDay = parseDateKey(anchor) else {
            return IntervalDue(daysUntil: 0, sinceDone: nil)
        }
        let due = day(anchorDay, plus: item.intervalDays ?? 0)
        return IntervalDue(
            daysUntil: Int(((ms(due) - ms(today)) / dayMs).rounded()),
            sinceDone: Int(((ms(today) - ms(anchorDay)) / dayMs).rounded())
        )
    }

    // MARK: - 次に来る日時

    /// 予定が次に来る日時。無効な予定や空振りなら nil
    public static func nextOccurrence(_ item: Item, _ now: Date, _ records: Records = [:]) -> Date? {
        // 時刻を固定しない予定は発火時刻を持たない（アラームを張らない）
        if isAnytime(item) { return nil }
        guard item.enabled, let (hh, mm) = parseTime(item.time) else { return nil }

        // ◯日ごと：目安日の指定時刻に1回だけ知らせる。
        // 目安日を過ぎても翌日以降は鳴らさない（催促を重ねない＝責めない設計）
        if isInterval(item) {
            guard let info = intervalDueInfo(item, records, now), info.daysUntil >= 0 else { return nil }
            let cand = at(day(now, plus: info.daysUntil), hour: hh, minute: mm)
            return cand > now ? cand : nil
        }

        if isOneOff(item) {
            guard let base = parseDateKey(item.date) else { return nil }
            let cand = at(base, hour: hh, minute: mm)
            return cand > now ? cand : nil
        }

        for add in 0..<8 {
            let cand = at(day(now, plus: add), hour: hh, minute: mm)
            if cand <= now { continue }
            if isScheduledOn(item.days, cand) { return cand }
        }
        return nil
    }

    /// 発火が遅すぎたか（30分以上遅れは「いま知らせても意味がない」）
    public static func isTooLate(_ scheduledMs: Double, _ nowMs: Double) -> Bool {
        nowMs - scheduledMs > 30 * 60 * 1000
    }

    /// 終了時刻が開始時刻より後か（"HH:MM" 同士は文字列比較で正しく比べられる）
    public static func isValidEndTime(_ time: String?, _ endTime: String?) -> Bool {
        guard let endTime, parseTimeParts(endTime) != nil, let time else { return false }
        return endTime > time
    }

    /// 開始日時の予定の終了時刻（同じ日の endTime）
    public static func blockEndMs(_ endTime: String, _ startDate: Date) -> Double {
        guard let (hh, mm) = parseTimeParts(endTime) else { return .nan }
        return ms(at(startDate, hour: hh, minute: mm))
    }

    // MARK: - 並び順

    /// 登録済み一覧の並び順キー（ミリ秒）。実行予定のないものは無限大で一番下
    public static func listSortMs(_ item: Item, _ now: Date, _ records: Records = [:]) -> Double {
        // ◯日ごとは「目安日ならいつでも」なので目安日の終わりを使う。
        // 過ぎていたら「今日やれる」ので今日の終わり
        if isInterval(item) {
            guard item.enabled, let info = intervalDueInfo(item, records, now) else { return .infinity }
            return ms(endOfDay(day(now, plus: max(0, info.daysUntil))))
        }
        if !isAnytime(item) {
            guard let next = nextOccurrence(item, now, records) else { return .infinity }
            return ms(next)
        }
        guard item.enabled else { return .infinity }
        if isOneOff(item) {
            guard let base = parseDateKey(item.date) else { return .infinity }
            let end = ms(endOfDay(base))
            return end > ms(now) ? end : .infinity
        }
        for add in 0..<8 {
            let cand = endOfDay(day(now, plus: add))
            if isScheduledOn(item.days, cand) { return ms(cand) }
        }
        return .infinity
    }

    // MARK: - ふりかえりの集計

    /// 連続記録。スキップは連続を切らないが日数にも数えない（責めない設計）
    public static func streakFor(_ records: Records, _ itemId: String, _ now: Date, _ days: [Int]?) -> Int {
        var streak = 0
        var d = startOfDay(now)
        // 今日まだ「できた」でなければ昨日から数え始める（今日の分はまだ失敗ではない）
        if records[dateKey(d)]?[itemId] != .done { d = day(d, plus: -1) }
        for _ in 0..<366 {
            if isScheduledOn(days, d) {
                let rec = records[dateKey(d)]?[itemId]
                if rec == .done { streak += 1 }
                else if rec != .skip { break }
            }
            d = day(d, plus: -1)
        }
        return streak
    }

    /// 直近 windowDays 日（今日を含む）の「できた」回数。達成率は出さない
    public static func doneCountRecent(_ records: Records, _ itemId: String, _ now: Date, _ windowDays: Int) -> Int {
        var count = 0
        var d = startOfDay(now)
        for _ in 0..<windowDays {
            if records[dateKey(d)]?[itemId] == .done { count += 1 }
            d = day(d, plus: -1)
        }
        return count
    }

    /// 直近 windowDays 日の「できた」日どうしの平均間隔（日）。2回未満なら nil
    public static func avgDoneIntervalDays(_ records: Records, _ itemId: String, _ now: Date, _ windowDays: Int) -> Int? {
        var dates: [Date] = []
        var d = startOfDay(now)
        for _ in 0..<windowDays {
            if records[dateKey(d)]?[itemId] == .done { dates.append(d) }
            d = day(d, plus: -1)
        }
        guard dates.count >= 2 else { return nil }
        let span = (ms(dates[0]) - ms(dates[dates.count - 1])) / dayMs
        return Int((span / Double(dates.count - 1)).rounded())
    }

    // MARK: - カレンダー

    /// これから来る日の予定（カレンダーで先の日を押したとき用）。
    /// `itemsOnDay` は過去向けで「◯日ごと」を毎日出す（付け忘れを直せるように）が、
    /// 未来では次の目安日から間隔ごとにだけ出す。休み中・保管済みは出さない。並びは時刻順（いつでも→時刻）
    public static func plannedOnDay(_ schedule: [Item], _ records: Records, _ key: String, now: Date) -> [Item] {
        guard let day = parseDateKey(key) else { return [] }
        let today = startOfDay(now)
        return schedule.filter { item in
            if item.origId != nil || isArchived(item) || !item.enabled { return false }
            if isOneOff(item) { return item.date == key }
            if isInterval(item) {
                guard let n = item.intervalDays, n > 0,
                      let info = intervalDueInfo(item, records, now) else { return false }
                let due = self.day(today, plus: max(0, info.daysUntil))
                let gap = Int(((ms(day) - ms(due)) / dayMs).rounded())
                return gap >= 0 && gap % n == 0
            }
            return isScheduledOn(item.days, day)
        }
        .sorted { ($0.time ?? "") < ($1.time ?? "") }
    }

    /// その日にあった予定（1回だけ・保管済みを含む）。やりなおしコピーは出さない
    public static func itemsOnDay(_ schedule: [Item], _ records: Records, _ key: String) -> [Item] {
        guard let day = parseDateKey(key) else { return [] }
        let rec = records[key] ?? [:]
        return schedule.filter { item in
            if item.origId != nil { return false }
            if rec[item.id] != nil { return true }
            if isOneOff(item) { return item.date == key }
            if isInterval(item) {
                // 「どの日にやってもよい」予定なので、登録時の「最後にやった日」より後なら毎日出す
                // （出さないと、済ませたのに付け忘れた日に「できた」を付け直す場所が無くなる）
                let anchor: String? = {
                    guard let a = item.anchorDate, isDateKey(a) else { return nil }
                    return a
                }()
                return item.enabled && (anchor == nil || key > anchor!)
            }
            return item.enabled && isScheduledOn(item.days, day)
        }
    }

    /// ◯日ごとの予定を「前に済ませていた」とあとから付けるときの候補日。
    /// 昨日から遡って最大 maxDays 日ぶん、基準日（最後にやった日）の翌日まで。新しい順
    public static func pastDoneCandidates(
        _ item: Item, _ records: Records, _ now: Date, maxDays: Int = 7
    ) -> [String] {
        guard isInterval(item) else { return [] }
        let limit = maxDays > 0 ? maxDays : 7
        let anchor = intervalAnchorKey(item, records, now)
        var out: [String] = []
        var d = startOfDay(now)
        for _ in 0..<limit {
            d = day(d, plus: -1)
            let k = dateKey(d)
            if let anchor, k <= anchor { break }
            out.append(k)
        }
        return out
    }

    /// カレンダーの日の印。できなかった日に印は付けない（沈黙が中立）。
    /// ids に無い記録は数えない（消した予定の色だけが残る食い違いを防ぐ）
    public static func dayMark(_ records: Records, _ key: String, _ ids: [String]) -> Mark? {
        guard let rec = records[key] else { return nil }
        let vals = rec.filter { ids.contains($0.key) }.map(\.value)
        if vals.contains(.done) { return .done }
        return vals.contains(.skip) ? .skip : nil
    }

    // MARK: - こっそりお祝い（隠し機能。掲載文・説明には書かない）

    /// ストリークの節目か。祝うだけで、切れても何も言わない
    public static func isStreakMilestone(_ streak: Int) -> Bool {
        [3, 7, 14, 30, 50, 100, 200, 365].contains(streak)
    }

    /// 今日の予定がぜんぶ「できた」か。スキップが混ざった日は祝わない
    public static func allDoneToday(_ schedule: [Item], _ records: Records, _ now: Date) -> Bool {
        let key = dateKey(now)
        let rec = records[key] ?? [:]
        var count = 0
        for item in schedule {
            if item.origId != nil || isArchived(item) || !item.enabled { continue }
            let due: Bool
            if isInterval(item) {
                due = (intervalDueInfo(item, records, now)?.daysUntil ?? 0) <= 0
            } else if isOneOff(item) {
                due = item.date == key
            } else {
                due = isScheduledOn(item.days, now)
            }
            if !due && rec[item.id] == nil { continue }
            count += 1
            if rec[item.id] != .done { return false }
        }
        return count > 0
    }

    // MARK: - 予告（時間が近づいたら知らせる）

    /// 既定は10分前。Googleカレンダーの既定に寄せた（移動の要らない自宅の予定が主なため）
    public static let preNoticeDefault = PreNotice(on: true, minutes: 10)

    public static func preNoticeSettings(on: Bool?, minutes: Int?) -> PreNotice {
        let isOn = on ?? preNoticeDefault.on
        let m = minutes ?? 0
        let valid = m > 0 && m <= 120
        return PreNotice(on: isOn, minutes: valid ? m : preNoticeDefault.minutes)
    }

    /// 予告を出す時刻（ミリ秒）。出さない場合は nil。
    /// さかのぼって出さない（寝ていて過ぎた予告を起動直後に浴びせない＝責めない設計）
    public static func preNoticeAt(_ nextMs: Double?, on: Bool?, minutes: Int?, nowMs: Double) -> Double? {
        let s = preNoticeSettings(on: on, minutes: minutes)
        guard s.on, let nextMs, nextMs.isFinite else { return nil }
        let at = nextMs - Double(s.minutes) * 60000
        return at <= nowMs ? nil : at
    }
}
