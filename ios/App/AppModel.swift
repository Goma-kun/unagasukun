import Foundation
import SwiftUI

/// 画面が見ている状態のぜんぶ。予定と記録を持ち、変わるたびに保存して通知を張り直す。
@MainActor
final class AppModel: ObservableObject {

    @Published private(set) var snapshot: Snapshot
    @Published var preNoticeOn: Bool {
        didSet { UserDefaults.standard.set(preNoticeOn, forKey: "preNoticeOn"); reschedule() }
    }
    @Published var preNoticeMin: Int {
        didSet { UserDefaults.standard.set(preNoticeMin, forKey: "preNoticeMin"); reschedule() }
    }

    private let store: SnapshotStore?
    private let notifier: Notifier

    init(store: SnapshotStore? = try? SnapshotStore(url: SnapshotStore.defaultURL()),
         notifier: Notifier = Notifier()) {
        self.store = store
        self.notifier = notifier
        self.snapshot = (try? store?.load()) .flatMap { $0 } ?? Snapshot()

        let d = UserDefaults.standard
        // 未設定のときは拡張機能と同じ既定（10分前・オン）
        self.preNoticeOn = d.object(forKey: "preNoticeOn") as? Bool ?? Logic.preNoticeDefault.on
        self.preNoticeMin = d.object(forKey: "preNoticeMin") as? Int ?? Logic.preNoticeDefault.minutes
    }

    // MARK: - 読むほう

    func today(now: Date = Date()) -> (todo: [TodayEntry], done: [TodayEntry]) {
        Today.entries(schedule: snapshot.schedule, records: snapshot.records, now: now)
    }

    func streak(for item: Item, now: Date = Date()) -> Int {
        Logic.streakFor(snapshot.records, item.id, now, item.days)
    }

    /// 「◯日ごと」の次の目安日。それ以外は nil
    func nextDueText(for item: Item, now: Date = Date()) -> String? {
        guard Logic.isInterval(item), let info = Logic.intervalDueInfo(item, snapshot.records, now)
        else { return nil }
        if info.daysUntil > 0 { return "あと\(info.daysUntil)日" }
        if info.daysUntil == 0 { return "今日が目安" }
        return "\(-info.daysUntil)日すぎています"
    }

    // MARK: - 書くほう

    func add(_ item: Item) {
        let isFirst = snapshot.schedule.isEmpty
        snapshot.schedule.append(item)
        commit()
        // 最初の1件を登録した時点で通知の許可を聞く。
        // 断られても一覧は使えるので、機能は止めない
        if isFirst {
            Task {
                if await notifier.requestPermission() { reschedule() }
            }
        }
    }

    func remove(_ item: Item) {
        snapshot.schedule.removeAll { $0.id == item.id }
        commit()
    }

    func record(_ item: Item, _ mark: Mark, now: Date = Date()) {
        let key = Logic.dateKey(now)
        var day = snapshot.records[key] ?? [:]
        day[item.id] = mark
        snapshot.records[key] = day
        commit()
    }

    /// 押し間違いを戻す。**記録を消すのは取り消しのときだけ**
    func undo(_ item: Item, now: Date = Date()) {
        let key = Logic.dateKey(now)
        snapshot.records[key]?.removeValue(forKey: item.id)
        if snapshot.records[key]?.isEmpty == true { snapshot.records.removeValue(forKey: key) }
        commit()
    }

    private func commit() {
        snapshot.updatedAt = Date().timeIntervalSince1970 * 1000
        try? store?.save(snapshot)
        reschedule()
    }

    /// 予定や記録が変わったら通知を丸ごと張り直す。
    /// iOS は予約ぶんを個別に直せないので、消して入れ直すのがいちばん確実
    func reschedule(now: Date = Date()) {
        let plan = NotificationPlan.build(
            schedule: snapshot.schedule, records: snapshot.records, now: now,
            preNoticeOn: preNoticeOn, preNoticeMin: preNoticeMin
        )
        Task { await notifier.replaceAll(with: plan) }
    }
}
