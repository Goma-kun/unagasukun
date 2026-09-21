import Foundation
import SwiftUI

/// 画面が見ている状態のぜんぶ。予定と記録を持ち、変わるたびに保存して通知を張り直す。
@MainActor
final class AppModel: ObservableObject {

    @Published private(set) var snapshot: Snapshot
    /// 通知が実際に届く状態か。**効いていないことを黙っていてはいけない**ので画面に出す
    @Published private(set) var notificationsWorking = true
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

    /// 登録済み一覧に出すもの。**今日の画面に出ているものは重ねて出さない**
    /// （同じものが2か所にあると、どちらを操作すればいいか迷う）
    func registered(now: Date = Date()) -> [Item] {
        let shown = Set((today(now: now).todo + today(now: now).done).map(\.item.id))
        return snapshot.schedule
            .filter { !shown.contains($0.id) && $0.origId == nil && !Logic.isArchived($0) }
            .sorted { Logic.listSortMs($0, now, snapshot.records)
                        < Logic.listSortMs($1, now, snapshot.records) }
    }

    // MARK: - ふりかえり

    /// その日にあった予定（1回だけ・保管済みを含む）
    func itemsOn(_ key: String) -> [Item] {
        Logic.itemsOnDay(snapshot.schedule, snapshot.records, key)
    }

    func mark(_ item: Item, on key: String) -> Mark? {
        snapshot.records[key]?[item.id]
    }

    /// カレンダーから記録を付け直す。同じものをもう一度押したら取り消し
    func toggle(_ item: Item, _ mark: Mark, on key: String) {
        var day = snapshot.records[key] ?? [:]
        if day[item.id] == mark {
            day.removeValue(forKey: item.id)
        } else {
            day[item.id] = mark
        }
        if day.isEmpty { snapshot.records.removeValue(forKey: key) } else { snapshot.records[key] = day }
        commit()
    }

    /// カレンダーの日の印。いまある予定の記録だけを数える
    func dayMark(_ key: String) -> Mark? {
        Logic.dayMark(snapshot.records, key, snapshot.schedule.map(\.id))
    }

    func doneCount(_ item: Item, weeks: Int, now: Date = Date()) -> Int {
        Logic.doneCountRecent(snapshot.records, item.id, now, weeks * 7)
    }

    func describe(_ item: Item, now: Date = Date()) -> String {
        Describe.schedule(item, records: snapshot.records, now: now)
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
        // まだ聞いていなければ、ここで聞く。
        // 「予定が0件のときだけ」にすると、途中から使い始めた人に一生聞かないことになる
        _ = isFirst
        Task {
            if await notifier.authorizationStatus() == .notDetermined {
                _ = await notifier.requestPermission()
                reschedule()
            }
            await refreshNotificationState()
        }
    }

    /// 通知が届く状態かを見に行く。アプリが前面に戻るたびに呼ぶ
    /// （設定アプリで切られていることがあるため）
    func refreshNotificationState() async {
        let status = await notifier.authorizationStatus()
        notificationsWorking = (status == .authorized || status == .provisional)
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
