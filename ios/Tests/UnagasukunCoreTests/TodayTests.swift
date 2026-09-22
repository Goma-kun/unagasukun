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
            Item(id: "soon", label: "点滴", time: "09:00",
                 intervalDays: 3, noticeDays: 3, anchorDate: "2026-09-20"),
        ]
        let (todo, done) = Today.entries(schedule: schedule, records: [:], now: now)

        XCTAssertTrue(done.isEmpty)
        XCTAssertEqual(todo.map(\.item.id), ["block", "any", "future", "past", "soon"],
                       "進行中 → いつでも → これから → 未対応 → 予告中")
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
