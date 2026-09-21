import XCTest
@testable import UnagasukunCore

final class MergeTests: XCTestCase {

    /// 同期でいちばんやってはいけないのが「記録が消える」こと。
    /// 片方にしかない記録は、必ず両方に残らなければならない
    func testRecordsAreUnionedNotOverwritten() {
        let a = Snapshot(records: ["2026-09-20": ["i1": .done]], updatedAt: 200)
        let b = Snapshot(records: ["2026-09-21": ["i1": .done]], updatedAt: 100)

        let m = Merge.snapshots(a, b)
        XCTAssertEqual(m.records["2026-09-20"]?["i1"], .done, "古いほうの記録も残る")
        XCTAssertEqual(m.records["2026-09-21"]?["i1"], .done)
    }

    /// 同じ日の同じ予定に別々の記録が付いたら「できた」を残す
    func testDoneWinsOverSkip() {
        let a = Snapshot(records: ["2026-09-20": ["i1": .done]], updatedAt: 100)
        let b = Snapshot(records: ["2026-09-20": ["i1": .skip]], updatedAt: 999)

        XCTAssertEqual(Merge.snapshots(a, b).records["2026-09-20"]?["i1"], .done)
        XCTAssertEqual(Merge.snapshots(b, a).records["2026-09-20"]?["i1"], .done, "順番を変えても同じ")
    }

    /// 予定のほうは新しいほうを丸ごと採る（消した予定が復活しないように）
    func testScheduleTakesTheNewerSide() {
        let old = Snapshot(schedule: [Item(id: "i1"), Item(id: "i2")], updatedAt: 100)
        let new = Snapshot(schedule: [Item(id: "i1")], updatedAt: 200)

        XCTAssertEqual(Merge.snapshots(old, new).schedule.map(\.id), ["i1"])
        XCTAssertEqual(Merge.snapshots(new, old).schedule.map(\.id), ["i1"], "順番を変えても同じ")
    }

    func testMergeIsOrderIndependentForRecords() {
        let a = Snapshot(records: ["d": ["x": .skip]], updatedAt: 1)
        let b = Snapshot(records: ["d": ["y": .done]], updatedAt: 2)
        XCTAssertEqual(Merge.snapshots(a, b).records, Merge.snapshots(b, a).records)
    }
}

final class NotificationPlanTests: XCTestCase {

    private func now() -> Date {
        var c = DateComponents(); c.year = 2026; c.month = 9; c.day = 21; c.hour = 10
        return Calendar.current.date(from: c)!
    }

    func testDailyPlanIsSortedAndCapped() {
        let items = (0..<10).map { Item(id: "i\($0)", label: "予定\($0)", time: "08:00") }
        let plan = NotificationPlan.build(schedule: items, records: [:], now: now(),
                                          preNoticeOn: false, horizonDays: 30)

        XCTAssertEqual(plan.count, NotificationPlan.iosPendingLimit, "iOSの上限でちょうど切れる")
        XCTAssertEqual(plan, plan.sorted { $0.fireAt == $1.fireAt ? $0.id < $1.id : $0.fireAt < $1.fireAt })
    }

    /// 済ませた予定の通知は出さない（責めない設計）
    func testDoneItemGetsNoNotificationThatDay() {
        let item = Item(id: "i1", label: "薬", time: "20:00")
        let today = Logic.dateKey(now())

        let withoutRecord = NotificationPlan.build(schedule: [item], records: [:], now: now(),
                                                   preNoticeOn: false, horizonDays: 1)
        let withDone = NotificationPlan.build(schedule: [item], records: [today: ["i1": .done]],
                                              now: now(), preNoticeOn: false, horizonDays: 1)
        XCTAssertGreaterThan(withoutRecord.count, withDone.count)
    }

    /// 「◯日ごと」は済ませた日で目安日が動くので、先の回を決め打たない
    func testIntervalItemPlansOnlyOneOccurrence() {
        let item = Item(id: "i1", label: "点滴", time: "09:00",
                        intervalDays: 3, anchorDate: "2026-09-20")
        let plan = NotificationPlan.build(schedule: [item], records: [:], now: now(),
                                          preNoticeOn: false, horizonDays: 30)
        XCTAssertEqual(plan.filter { $0.kind == .main }.count, 1)
    }

    func testPreNoticeIsAddedWhenOn() {
        let item = Item(id: "i1", label: "散歩", time: "20:00")
        let plan = NotificationPlan.build(schedule: [item], records: [:], now: now(),
                                          preNoticeOn: true, preNoticeMin: 10, horizonDays: 1)
        let main = plan.first { $0.kind == .main }!
        let pre = plan.first { $0.kind == .pre }!
        XCTAssertEqual(main.fireAt.timeIntervalSince(pre.fireAt), 600, "ちょうど10分前")
    }

    func testDisabledAndArchivedAreSkipped() {
        let items = [
            Item(id: "off", time: "08:00", enabled: false),
            Item(id: "arch", time: "08:00", archived: true),
            Item(id: "copy", time: "08:00", origId: "i1"),
        ]
        XCTAssertTrue(NotificationPlan.build(schedule: items, records: [:], now: now(),
                                             preNoticeOn: false, horizonDays: 3).isEmpty)
    }
}

final class SnapshotStoreTests: XCTestCase {
    func testSaveAndLoadRoundTrip() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let store = SnapshotStore(url: dir.appendingPathComponent("snapshot.json"))
        XCTAssertEqual(try store.load(), Snapshot(), "無い状態でも落ちない")

        let snap = Snapshot(schedule: [Item(id: "i1", label: "薬", time: "20:00")],
                            records: ["2026-09-21": ["i1": .done]], updatedAt: 123)
        try store.save(snap)
        XCTAssertEqual(try store.load(), snap)
    }
}

/// 記録が消えたときに戻せる場所があるか。
/// Merge も SyncPlan もテストしてあるが、それでも間違えたときの逃げ道は別に要る。
final class BackupTests: XCTestCase {

    private func makeStore() -> (SnapshotStore, URL) {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return (SnapshotStore(url: dir.appendingPathComponent("snapshot.json")), dir)
    }

    func testBackupRoundTrip() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let snap = Snapshot(schedule: [Item(id: "a", label: "薬")],
                            records: ["2026-09-21": ["a": .done]], updatedAt: 1)
        try store.saveBackup(snap)

        let files = store.backups()
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(try store.loadBackup(files[0]), snap)
    }

    /// 古いものから消えて、**新しい順**に並ぶ
    func testKeepsNewestFive() throws {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }

        let base = Date(timeIntervalSince1970: 1_700_000_000)
        for i in 0..<8 {
            try store.saveBackup(Snapshot(updatedAt: Double(i)),
                                 at: base.addingTimeInterval(Double(i)))
        }
        let files = store.backups()
        XCTAssertEqual(files.count, SnapshotStore.backupLimit)
        XCTAssertEqual(try store.loadBackup(files[0]).updatedAt, 7, "いちばん新しいものが先頭")
        XCTAssertEqual(try store.loadBackup(files.last!).updatedAt, 3, "古い3件は消えている")
    }

    func testBackupsAreEmptyBeforeAnySave() {
        let (store, dir) = makeStore()
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertTrue(store.backups().isEmpty, "無い状態でも落ちない")
    }
}
