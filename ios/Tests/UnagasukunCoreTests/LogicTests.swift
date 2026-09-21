import XCTest
@testable import UnagasukunCore

/// 移植そのものの突き合わせは ../test/parity_test.mjs（JS版と実際に比べる）が担う。
/// ここには「Swift側だけで壊れうるところ」を置く。
final class LogicTests: XCTestCase {

    private func d(_ y: Int, _ m: Int, _ day: Int, _ h: Int = 0, _ min: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = m; c.day = day; c.hour = h; c.minute = min
        return Calendar.current.date(from: c)!
    }

    func testDateKeyIsZeroPadded() {
        XCTAssertEqual(Logic.dateKey(d(2026, 1, 5)), "2026-01-05")
    }

    /// JS の getDay() は日曜=0。Foundation は日曜=1 なので、ここを間違えると全部ずれる
    func testWeekdayMatchesJavaScript() {
        XCTAssertEqual(Logic.jsWeekday(d(2026, 8, 13)), 4, "2026-08-13 は木曜（JSでは4）")
        XCTAssertEqual(Logic.jsWeekday(d(2026, 8, 16)), 0, "2026-08-16 は日曜（JSでは0）")
    }

    func testParseTimeRejectsOutOfRange() {
        XCTAssertNotNil(Logic.parseTime("23:59"))
        XCTAssertNil(Logic.parseTime("24:00"))
        XCTAssertNil(Logic.parseTime("9:00"), "2桁でないものは受け付けない")
        XCTAssertNil(Logic.parseTime(nil))
    }

    func testEndOfDayIsLastMillisecond() {
        let end = Logic.endOfDay(d(2026, 8, 13))
        XCTAssertLessThan(end, d(2026, 8, 14))
        XCTAssertGreaterThan(end, d(2026, 8, 13, 23, 59))
    }

    /// 月をまたぐ繰り上がりを Calendar に任せている部分
    func testDayPlusCrossesMonth() {
        XCTAssertEqual(Logic.dateKey(Logic.day(d(2026, 8, 30), plus: 5)), "2026-09-04")
        XCTAssertEqual(Logic.dateKey(Logic.day(d(2026, 3, 1), plus: -1)), "2026-02-28")
    }
}
