import XCTest
@testable import UnagasukunCore

/// 同期でいちばん怖いのは記録が消えること。判断だけを切り出して確かめる。
final class SyncPlanTests: XCTestCase {

    private func snap(_ records: [String: [String: Mark]], _ at: Double,
                      _ schedule: [Item] = []) -> Snapshot {
        Snapshot(schedule: schedule, records: records, updatedAt: at)
    }

    func testFirstTimePushesEvenWhenEmpty() {
        let d = SyncPlan.decide(local: Snapshot(), remote: nil)
        XCTAssertTrue(d.push)
        XCTAssertFalse(d.updateLocal)
    }

    /// 向こうにしかない記録は、必ず手元に降りてくる
    func testRemoteOnlyRecordComesDown() {
        let local = snap(["2026-09-20": ["a": .done]], 100)
        let remote = snap(["2026-09-21": ["a": .done]], 50)

        let d = SyncPlan.decide(local: local, remote: remote)
        XCTAssertTrue(d.updateLocal, "向こうの記録を取り込む")
        XCTAssertTrue(d.push, "こちらの記録も上げる")
        XCTAssertEqual(d.merged.records["2026-09-20"]?["a"], .done)
        XCTAssertEqual(d.merged.records["2026-09-21"]?["a"], .done)
    }

    /// 中身が同じなら、何もしない。**時刻だけ違うものを上げ続けない**
    func testNoWorkWhenContentMatches() {
        let local = snap(["2026-09-20": ["a": .done]], 999)
        let remote = snap(["2026-09-20": ["a": .done]], 1)

        let d = SyncPlan.decide(local: local, remote: remote)
        XCTAssertFalse(d.updateLocal)
        XCTAssertFalse(d.push)
    }

    /// 手元にしかない記録は上げるだけ。手元は書き換えない
    func testLocalOnlyRecordIsPushed() {
        let local = snap(["2026-09-20": ["a": .done]], 100)
        let remote = snap([:], 50)

        let d = SyncPlan.decide(local: local, remote: remote)
        XCTAssertFalse(d.updateLocal)
        XCTAssertTrue(d.push)
    }

    /// 予定を消したことが、ちゃんと向こうにも伝わる
    func testDeletionOnNewerSideWins() {
        let local = snap([:], 200, [Item(id: "a")])
        let remote = snap([:], 100, [Item(id: "a"), Item(id: "b")])

        let d = SyncPlan.decide(local: local, remote: remote)
        XCTAssertEqual(d.merged.schedule.map(\.id), ["a"])
        XCTAssertFalse(d.updateLocal)
        XCTAssertTrue(d.push)
    }

    /// 2台で同じ日に別の記録を付けたら「できた」が残る
    func testDoneSurvivesAgainstSkip() {
        let local = snap(["2026-09-20": ["a": .skip]], 999)
        let remote = snap(["2026-09-20": ["a": .done]], 1)

        let d = SyncPlan.decide(local: local, remote: remote)
        XCTAssertEqual(d.merged.records["2026-09-20"]?["a"], .done)
        XCTAssertTrue(d.updateLocal, "手元の skip を done に直す")
    }

    /// どちらから見ても同じ結果になる（順番で答えが変わってはいけない）
    func testMergeIsSymmetric() {
        let a = snap(["d1": ["x": .done]], 100, [Item(id: "x")])
        let b = snap(["d2": ["x": .skip]], 100, [Item(id: "x")])
        XCTAssertEqual(SyncPlan.decide(local: a, remote: b).merged.records,
                       SyncPlan.decide(local: b, remote: a).merged.records)
    }
}
