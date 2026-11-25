import XCTest
@testable import UnagasukunCore

/// 「しばらく休む」の再開日（2026-11-26）
final class ResumeTests: XCTestCase {
    private func at(_ day: Int, _ h: Int = 12) -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 11; c.day = day; c.hour = h
        return Calendar.current.date(from: c)!
    }

    func testWakeOnlyWhenTheDayHasCome() {
        let schedule = [
            Item(id: "a", label: "再開日が来た", time: "08:00", enabled: false, resumeDate: "2026-11-26"),
            Item(id: "b", label: "まだ先", time: "08:00", enabled: false, resumeDate: "2026-11-27"),
            Item(id: "c", label: "日を決めていない", time: "08:00", enabled: false),
            Item(id: "d", label: "動いている", time: "08:00"),
        ]
        let woke = Resume.wake(schedule, now: at(26))
        XCTAssertEqual(woke?.map(\.enabled), [true, false, false, true])
        XCTAssertNil(woke?[0].resumeDate, "戻したら再開日は消す（次に休むとき古い日が残らないように）")
        XCTAssertEqual(woke?[1].resumeDate, "2026-11-27")
        XCTAssertNil(Resume.wake(schedule, now: at(25)), "戻すものが無ければ nil（むだな保存と同期をしない）")
    }

    func testTodayHidesUntilWoken() {
        let item = Item(id: "a", label: "薬", time: "08:00", enabled: false, resumeDate: "2026-11-28")
        XCTAssertTrue(Today.entries(schedule: [item], records: [:], now: at(27)).todo.isEmpty)
        let woke = Resume.wake([item], now: at(28))!
        XCTAssertEqual(Today.entries(schedule: woke, records: [:], now: at(28)).todo.map(\.item.id), ["a"])
    }

    /// 再開日にアプリを開かなくても通知が届くよう、休み中のうちから再開日以降のぶんを予約する
    func testNotificationsArePlannedFromResumeDate() {
        let item = Item(id: "a", label: "薬", time: "08:00", days: Array(0...6), enabled: false, resumeDate: "2026-11-28")
        let plan = NotificationPlan.build(schedule: [item], records: [:], now: at(26), preNoticeOn: false)
        let days = plan.filter { $0.kind == .main }.map { Logic.dateKey($0.fireAt) }.sorted()
        XCTAssertEqual(days.first, "2026-11-28")
        XCTAssertFalse(days.contains("2026-11-27"))

        let noDate = Item(id: "b", label: "薬", time: "08:00", days: Array(0...6), enabled: false)
        XCTAssertTrue(NotificationPlan.build(schedule: [noDate], records: [:], now: at(26)).isEmpty)
    }

    func testCalendarShowsFromResumeDate() {
        let item = Item(id: "a", label: "薬", time: "08:00", days: Array(0...6), enabled: false, resumeDate: "2026-11-28")
        XCTAssertTrue(Logic.plannedOnDay([item], [:], "2026-11-27", now: at(26)).isEmpty)
        XCTAssertEqual(Logic.plannedOnDay([item], [:], "2026-11-28", now: at(26)).map(\.id), ["a"])
    }

    func testOldDataWithoutTheKeyStillLoads() throws {
        let json = #"{"id":"x","label":"薬","enabled":false}"#.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(Item.self, from: json).resumeDate)
    }
}
