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
