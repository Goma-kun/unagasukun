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

    /// 手元で消した記録は、向こうの写しで戻ってはいけない
    /// （「できた」を押し直したらすぐ戻った・2026-09-24 本人報告）
    func testClearedRecordStaysCleared() {
        var local = snap(["2026-09-23": ["a": .done]], 100)
        local.setMark(nil, item: "a", on: "2026-09-23", at: 200)
        local.updatedAt = 200
        let remote = snap(["2026-09-23": ["a": .done]], 100)   // 向こうにはまだ「できた」がある

        let d = SyncPlan.decide(local: local, remote: remote)
        XCTAssertNil(d.merged.records["2026-09-23"]?["a"])
        XCTAssertFalse(d.updateLocal)
        XCTAssertTrue(d.push, "消したことを上げる")
        XCTAssertEqual(SyncPlan.decide(local: remote, remote: local).merged.records, d.merged.records,
                       "どちらから混ぜても同じ")
    }

    /// 消したあとに付け直したら、新しいほうが勝つ
    func testReMarkAfterClearWins() {
        var a = snap([:], 0)
        a.setMark(nil, item: "a", on: "2026-09-23", at: 300)
        var b = snap([:], 0)
        b.setMark(.skip, item: "a", on: "2026-09-23", at: 400)

        XCTAssertEqual(SyncPlan.decide(local: a, remote: b).merged.records["2026-09-23"]?["a"], .skip)
        XCTAssertEqual(SyncPlan.decide(local: b, remote: a).merged.records["2026-09-23"]?["a"], .skip)
    }

    /// 履歴の無い古い記録（拡張機能からの取り込み）は、これまでどおり足し合わせで残る
    func testLegacyRecordsStillMerge() {
        let local = snap(["2026-09-20": ["a": .done]], 100)
        let remote = snap(["2026-09-21": ["a": .skip]], 100)
        let m = SyncPlan.decide(local: local, remote: remote).merged
        XCTAssertEqual(m.records["2026-09-20"]?["a"], .done)
        XCTAssertEqual(m.records["2026-09-21"]?["a"], .skip)
    }

    /// 履歴を足す前に保存したファイルも読める
    func testDecodesSnapshotWithoutLog() throws {
        let json = #"{"schedule":[],"records":{"2026-09-20":{"a":"done"}},"updatedAt":5}"#
        let s = try JSONDecoder().decode(Snapshot.self, from: Data(json.utf8))
        XCTAssertTrue(s.recordLog.isEmpty)
        XCTAssertEqual(s.records["2026-09-20"]?["a"], .done)

        var t = s
        t.setMark(nil, item: "a", on: "2026-09-20", at: 9)
        let back = try JSONDecoder().decode(Snapshot.self, from: JSONEncoder().encode(t))
        XCTAssertEqual(back, t, "「消した」の履歴も往復で残る")
    }

    /// どちらから見ても同じ結果になる（順番で答えが変わってはいけない）
    func testMergeIsSymmetric() {
        let a = snap(["d1": ["x": .done]], 100, [Item(id: "x")])
        let b = snap(["d2": ["x": .skip]], 100, [Item(id: "x")])
        XCTAssertEqual(SyncPlan.decide(local: a, remote: b).merged.records,
                       SyncPlan.decide(local: b, remote: a).merged.records)
    }
}
