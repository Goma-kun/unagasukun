import XCTest
@testable import UnagasukunCore

/// 並びは拡張機能（sidepanel.js の groupOf）と同じでなければならない。
/// 同じ製品なのに端末ごとに並びが違うと、「さっき上にあったものが無い」と探すことになる。
final class TodayTests: XCTestCase {

    private func at(_ h: Int, _ m: Int = 0) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 21; c.hour = h; c.minute = m
        return Calendar.current.date(from: c)!
    }

    func testGroupOrder() {
        let now = at(15)
        let schedule = [
            Item(id: "past", label: "朝の分", time: "07:30"),
            Item(id: "future", label: "夜の分", time: "20:00"),
            Item(id: "any", label: "いつでも", anytime: true),
            Item(id: "block", label: "作業", time: "14:00", endTime: "16:00"),
            Item(id: "due", label: "点滴", time: "09:00",
                 intervalDays: 3, noticeDays: 3, anchorDate: "2026-09-18"),
            Item(id: "soon", label: "明日の点滴", time: "09:00",
                 intervalDays: 3, noticeDays: 3, anchorDate: "2026-09-19"),
        ]
        let (todo, done) = Today.entries(schedule: schedule, records: [:], now: now)

        XCTAssertTrue(done.isEmpty)
        XCTAssertEqual(todo.map(\.item.id), ["block", "any", "due", "future", "past"],
                       "進行中 → いつでも（目安日が来た◯日ごとを含む） → これから → 未対応")
        XCTAssertEqual(todo.first(where: { $0.item.id == "due" })?.group, .ready)
        XCTAssertEqual(todo.first(where: { $0.item.id == "past" })?.group, .overdue)
        XCTAssertEqual(todo.first(where: { $0.item.id == "block" })?.group, .active)
    }

    /// 記録が付いたものは下の欄へ移る
    func testRecordedItemsMoveToDone() {
        let now = at(15)
        let schedule = [Item(id: "a", time: "07:30"), Item(id: "b", time: "20:00")]
        let (todo, done) = Today.entries(
            schedule: schedule, records: [Logic.dateKey(now): ["a": .done]], now: now)

        XCTAssertEqual(todo.map(\.item.id), ["b"])
        XCTAssertEqual(done.map(\.item.id), ["a"])
        XCTAssertEqual(done.first?.group, .resolved)
    }

    /// 「いつでも」に時間切れの概念はない。夜になっても未対応にはしない
    func testAnytimeNeverBecomesOverdue() {
        let schedule = [Item(id: "a", label: "本を読む", anytime: true)]
        let (todo, _) = Today.entries(schedule: schedule, records: [:], now: at(23, 50))
        XCTAssertEqual(todo.first?.group, .ready)
    }

    /// 「◯日ごと」は目安日の当日から出す。前日に出すと「今日やる」と読めて紛らわしい
    /// （2026-09-24 本人指摘。noticeDays が付いていても見ない）
    func testIntervalAppearsOnlyFromDueDay() {
        let item = Item(id: "drip", label: "点滴", time: "09:00",
                        intervalDays: 4, noticeDays: 3, anchorDate: "2026-09-18")
        // 目安日は 9/22。9/21 には出ない
        XCTAssertTrue(Today.entries(schedule: [item], records: [:], now: at(15)).todo.isEmpty)
        var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 22; c.hour = 15
        let dueDay = Calendar.current.date(from: c)!
        XCTAssertEqual(Today.entries(schedule: [item], records: [:], now: dueDay).todo.map(\.item.id), ["drip"])
        c.day = 24
        let late = Calendar.current.date(from: c)!
        XCTAssertEqual(Today.entries(schedule: [item], records: [:], now: late).todo.map(\.item.id), ["drip"],
                       "過ぎても出続ける")
    }

    func testDisabledAndArchivedAreHidden() {
        let schedule = [
            Item(id: "off", time: "07:30", enabled: false),
            Item(id: "arch", time: "07:30", archived: true),
        ]
        let (todo, done) = Today.entries(schedule: schedule, records: [:], now: at(15))
        XCTAssertTrue(todo.isEmpty && done.isEmpty)
    }
}

final class LookBackTests: XCTestCase {

    private func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = day
        return Calendar.current.date(from: c)!
    }

    /// 2026年9月1日は火曜（日曜=0 で 2）なので、頭に2つ空きが要る
    func testMonthGridPadsToSunday() {
        let cells = LookBack.monthGrid(d(2026, 9, 15))
        XCTAssertEqual(cells.count, 2 + 30)
        XCTAssertNil(cells[0])
        XCTAssertNil(cells[1])
        XCTAssertEqual(Logic.dateKey(cells[2]!), "2026-09-01")
        XCTAssertEqual(Logic.dateKey(cells.last!!), "2026-09-30")
    }

    /// 先週までの12週に今週の列を足す。右端の列が今週（日曜はじまり）
    func testTileWeeksEndThisWeek() {
        let now = d(2026, 9, 21)   // 月曜
        let weeks = LookBack.tileWeeks(now: now, count: 12)

        XCTAssertEqual(weeks.count, 13)
        XCTAssertTrue(weeks.allSatisfy { $0.count == 7 })
        XCTAssertEqual(Logic.dateKey(weeks.last![0]), "2026-09-20", "右端の列は今週の日曜から")
        XCTAssertEqual(Logic.dateKey(weeks.last!.last!), "2026-09-26", "今週の土曜まで（未来は画面側で点線）")
        XCTAssertEqual(Logic.dateKey(weeks[11].last!), "2026-09-19", "その左は先週")
        XCTAssertTrue(weeks.allSatisfy { Logic.jsWeekday($0[0]) == 0 }, "各週は日曜はじまり")

        let past = LookBack.tileWeeks(now: now, count: 12, includeCurrent: false)
        XCTAssertEqual(past.count, 12)
        XCTAssertEqual(Logic.dateKey(past.last!.last!), "2026-09-19", "今週を外せば先週の土曜で終わる")
    }

    /// 月名は月が変わった最初の週に。左端は隣で月が変わるなら付けない
    func testMonthLabelColumns() {
        let weeks = LookBack.tileWeeks(now: d(2026, 9, 22), count: 12)
        // 6/28(日) はじまりの13列。6/28, 7/5, ..., 9/20
        XCTAssertEqual(Logic.dateKey(weeks[0][0]), "2026-06-28")
        let labels = LookBack.monthLabelColumns(weeks)
        XCTAssertEqual(labels.map(\.column), [1, 5, 10], "6月は隣の列で7月に変わるので付けない")
        XCTAssertEqual(labels.map { Logic.calendar.component(.month, from: $0.sunday) }, [7, 8, 9])

        // 左端の週がその月の途中なら、左端にも付く
        let weeks2 = LookBack.tileWeeks(now: d(2026, 9, 15), count: 12)
        XCTAssertEqual(Logic.dateKey(weeks2[0][0]), "2026-06-21")
        XCTAssertEqual(LookBack.monthLabelColumns(weeks2).map(\.column), [0, 2, 6, 11])
    }

    /// 未来の日は空。色を付けると「やらなかった日」に見える
    func testFutureTilesAreEmpty() {
        let now = d(2026, 9, 21)
        let item = Item(id: "a")
        let records: Records = ["2026-09-25": ["a": .done]]
        XCTAssertNil(LookBack.tileMark(item, records, d(2026, 9, 25), now: now))
    }

    func testOneOffItemsAreNotTiled() {
        let schedule = [Item(id: "once", date: "2026-09-20"), Item(id: "daily", time: "07:00")]
        XCTAssertEqual(LookBack.tileItems(schedule).map(\.id), ["daily"])
    }
}

/// 「◯日ごと」の言い方。間の日数で数える人にもずれて伝わらないこと
final class DescribeTests: XCTestCase {
    func testRhythmSaysOncePerNDaysAndGap() {
        XCTAssertEqual(Describe.rhythm(4), "4日に1回（間は3日空きます）", "ごまくんの点滴：月→金")
        XCTAssertEqual(Describe.rhythm(3), "3日に1回（間は2日空きます）")
        XCTAssertEqual(Describe.rhythm(1), "1日に1回（毎日）")
    }

    func testScheduleTextUsesRhythm() {
        let item = Item(id: "a", label: "点滴", time: "09:00", intervalDays: 4, anchorDate: "2026-09-21")
        var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 22; c.hour = 10
        let now = Calendar.current.date(from: c)!
        XCTAssertEqual(Describe.schedule(item, now: now), "4日に1回（間は3日空きます）・次は 9/25(金)・09:00")
    }
}

/// カレンダーで先の日を押したときの予定（2026-09-26 本人指摘「未来の予定をカレンダーで確認できない」）
final class PlannedOnDayTests: XCTestCase {
    private func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = day; c.hour = 10
        return Calendar.current.date(from: c)!
    }

    func testOneOffWeeklyAndDisabled() {
        let now = d(2026, 9, 26)   // 土
        let schedule = [
            Item(id: "once", label: "集荷", time: "14:00", date: "2026-09-28"),
            Item(id: "mon", label: "ジム", time: "10:30", days: [1]),
            Item(id: "off", label: "休み中", time: "06:00", enabled: false),
            Item(id: "any", label: "いつでも", days: [1], anytime: true),
        ]
        let mon = Logic.plannedOnDay(schedule, [:], "2026-09-28", now: now)
        XCTAssertEqual(mon.map(\.id), ["any", "mon", "once"], "いつでも → 時刻順")
        XCTAssertTrue(Logic.plannedOnDay(schedule, [:], "2026-09-29", now: now).isEmpty)
    }

    /// ◯日ごとは次の目安日から間隔ごと。毎日は出さない
    func testIntervalRepeatsFromDueDate() {
        let now = d(2026, 9, 26)
        let drip = Item(id: "drip", label: "点滴", intervalDays: 4, anchorDate: "2026-09-25")
        // 目安日は 9/29。以降 10/3, 10/7 …
        XCTAssertTrue(Logic.plannedOnDay([drip], [:], "2026-09-28", now: now).isEmpty)
        XCTAssertEqual(Logic.plannedOnDay([drip], [:], "2026-09-29", now: now).map(\.id), ["drip"])
        XCTAssertTrue(Logic.plannedOnDay([drip], [:], "2026-09-30", now: now).isEmpty)
        XCTAssertEqual(Logic.plannedOnDay([drip], [:], "2026-10-03", now: now).map(\.id), ["drip"])
        XCTAssertEqual(Logic.plannedOnDay([drip], [:], "2026-10-07", now: now).map(\.id), ["drip"])
    }

    /// 目安日が過ぎている◯日ごとは、今日から数える
    func testOverdueIntervalStartsToday() {
        let now = d(2026, 9, 26)
        let drip = Item(id: "drip", label: "点滴", intervalDays: 3, anchorDate: "2026-09-10")
        XCTAssertEqual(Logic.plannedOnDay([drip], [:], "2026-09-26", now: now).map(\.id), ["drip"])
        XCTAssertEqual(Logic.plannedOnDay([drip], [:], "2026-09-29", now: now).map(\.id), ["drip"])
        XCTAssertTrue(Logic.plannedOnDay([drip], [:], "2026-09-28", now: now).isEmpty)
    }
}

/// こっそりお祝い。優先順位は ぜんぶ済み > 節目 > ふだん（拡張機能 v1.5.0 と同じ）
final class CheerTests: XCTestCase {
    /// 答えを固定するための乱数（SplitMix64）。
    /// **同じ値を返し続ける生成器は使えない**：`randomElement(using:)` は棄却サンプリングで回り続け、
    /// テストが永遠に終わらない（2026-09-24 に実際に踏んだ）
    struct Fixed: RandomNumberGenerator {
        var state: UInt64
        init(values: [UInt64]) { state = values.first ?? 1 }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }
    private func at(_ y: Int, _ m: Int, _ d: Int) -> Date {
        var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = 12
        return Calendar.current.date(from: c)!
    }

    func testAllDoneWinsAndThrowsParty() {
        let a = Item(id: "a", time: "07:00"), b = Item(id: "b", time: "20:00")
        let now = at(2026, 9, 24)
        let records: Records = [Logic.dateKey(now): ["a": .done, "b": .done]]
        var g = Fixed(values: [0])
        let c = CheerLogic.afterDone(b, schedule: [a, b], records: records, now: now, using: &g)
        XCTAssertTrue(c.party)
        XCTAssertNotNil(c.emoji)
        XCTAssertTrue(c.text.contains("ぜんぶできました"))
    }

    /// スキップが混ざった日は祝わない（何も責めない、ただ静か）
    func testSkipMixedDayIsNotAParty() {
        let a = Item(id: "a", time: "07:00"), b = Item(id: "b", time: "20:00")
        let now = at(2026, 9, 24)
        let records: Records = [Logic.dateKey(now): ["a": .skip, "b": .done]]
        var g = Fixed(values: [7])
        let c = CheerLogic.afterDone(b, schedule: [a, b], records: records, now: now, using: &g)
        XCTAssertFalse(c.party)
        XCTAssertTrue(CheerLogic.praises.contains(c.text))
    }

    func testStreakMilestone() {
        let a = Item(id: "a", time: "07:00"), other = Item(id: "o", time: "21:00")
        let now = at(2026, 9, 24)
        var records: Records = [:]
        for i in 0..<3 { records[Logic.dateKey(Logic.day(now, plus: -i))] = ["a": .done] }
        var g = Fixed(values: [0])
        let c = CheerLogic.afterDone(a, schedule: [a, other], records: records, now: now, using: &g)
        XCTAssertEqual(c.text, "3日つづいています。おめでとう！")
        XCTAssertFalse(c.party, "other が未対応なので、ぜんぶ済みではない")
    }

    /// 1回だけの予定は節目を数えない
    func testOneOffHasNoMilestone() {
        let a = Item(id: "a", time: "07:00", date: "2026-09-24"), other = Item(id: "o", time: "21:00")
        let now = at(2026, 9, 24)
        var records: Records = [:]
        for i in 0..<3 { records[Logic.dateKey(Logic.day(now, plus: -i))] = ["a": .done] }
        var g = Fixed(values: [7])
        let c = CheerLogic.afterDone(a, schedule: [a, other], records: records, now: now, using: &g)
        XCTAssertTrue(CheerLogic.praises.contains(c.text), "節目ではなく、ふだんの一言")
    }
}
