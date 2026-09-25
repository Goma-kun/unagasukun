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

    /// iCloud 同期の状態。**うまくいっていないことを黙っていない**
    @Published private(set) var syncState: CloudSync.State = .off
    @Published var syncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(syncEnabled, forKey: "syncEnabled")
            Task { await syncNow() }
        }
    }

    private let store: SnapshotStore?
    private let notifier: Notifier
    private let cloud = CloudSync()
    private var pushTask: Task<Void, Never>?

    init(store: SnapshotStore? = try? SnapshotStore(url: SnapshotStore.defaultURL()),
         notifier: Notifier = Notifier()) {
        self.store = store
        self.notifier = notifier
        self.snapshot = (try? store?.load()) .flatMap { $0 } ?? Snapshot()

        let d = UserDefaults.standard
        // 未設定のときは拡張機能と同じ既定（10分前・オン）
        self.preNoticeOn = d.object(forKey: "preNoticeOn") as? Bool ?? Logic.preNoticeDefault.on
        self.preNoticeMin = d.object(forKey: "preNoticeMin") as? Int ?? Logic.preNoticeDefault.minutes
        // リマインダーやメモと同じで、既定はオン。**自分の iCloud に入るだけ**なので
        // 預かる側の都合で止める理由がない
        self.syncEnabled = d.object(forKey: "syncEnabled") as? Bool ?? true
    }

    // MARK: - iCloud 同期

    /// iCloud と揃える。**取ってきて混ぜてから上げる**。片方を捨てない
    func syncNow() async {
        guard syncEnabled else { syncState = .off; return }
        if let blocked = await cloud.availability() { syncState = blocked; return }

        syncState = .syncing
        do {
            let plan = SyncPlan.decide(local: snapshot, remote: try await cloud.pull())

            if plan.updateLocal {
                // **書き換える前の中身を残す。** 混ぜ方を間違えたときの逃げ道
                try? store?.saveBackup(snapshot)
                snapshot = plan.merged
                try? store?.save(snapshot)
                reschedule()
            }
            if plan.push {
                try await cloud.push(plan.merged)
            }
            syncState = .ok(Date())
        } catch {
            // 圏外などで失敗しても、手元は普通に使える
            syncState = .failed("同期できませんでした。次に開いたときにやり直します")
        }
    }

    /// 同期で書き換える直前に残した控え（新しい順）
    func backupCount() -> Int { store?.backups().count ?? 0 }

    /// いちばん新しい控えに戻す。**いまの中身も控えに残してから**戻す
    /// （戻すこと自体を取り消せないと、逃げ道が一方通行になる）
    func restoreNewestBackup() {
        guard let store, let newest = store.backups().first,
              let restored = try? store.loadBackup(newest) else { return }
        try? store.saveBackup(snapshot)
        snapshot = restored
        commit()
    }

    // MARK: - 拡張機能からの取り込み

    /// 拡張機能が書き出した JSON を取り込む。戻り値は画面に出す結果の文
    func importExtensionFile(_ url: URL) -> String {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let file = try JSONDecoder().decode(ExportFile.self, from: try Data(contentsOf: url))
            let before = (snapshot.schedule.count, snapshot.records.count)
            try? store?.saveBackup(snapshot)          // 取り込む前の中身も控えに残す
            snapshot = Merge.importing(local: snapshot, imported: file)
            commit()
            let added = snapshot.schedule.count - before.0
            let days = snapshot.records.count - before.1
            return "予定を\(added)件、記録を\(days)日ぶん取り込みました。ほかの端末にも数秒で揃います。"
        } catch {
            return "読み込めませんでした。うながすくん（拡張機能）の「データを書き出す」で作ったファイルを選んでください。"
        }
    }

    /// 変更のたびに上げる。続けて操作されたときに何度も上げないよう、少し待ってからにする
    private func schedulePush() {
        guard syncEnabled else { return }
        pushTask?.cancel()
        pushTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            await self.syncNow()
        }
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
            .filter { !shown.contains($0.id) && $0.origId == nil && !Logic.isArchived($0)
                      && !isPastOneOff($0, now: now) }
            .sorted { Logic.listSortMs($0, now, snapshot.records)
                        < Logic.listSortMs($1, now, snapshot.records) }
    }

    /// 日付が過ぎた「1回だけ」の予定か。拡張機能はこれを SW で「保管」に回して一覧から外す
    private func isPastOneOff(_ item: Item, now: Date) -> Bool {
        guard Logic.isOneOff(item), let d = item.date else { return false }
        return d < Logic.dateKey(now)
    }

    /// 日付が過ぎた「1回だけ」の予定（直近 `days` 日ぶん・新しい順）。
    /// 登録済みに残り続けると「まだやっていない」に見えるので別の欄に出し、
    /// できたかどうかをその場で付けられるようにする（2026-09-24 本人指摘）。それより前はカレンダーで
    func pastOneOffs(now: Date = Date(), days: Int = 14) -> [Item] {
        let floor = Logic.dateKey(Logic.day(now, plus: -days))
        return snapshot.schedule
            .filter { isPastOneOff($0, now: now) && $0.origId == nil && ($0.date ?? "") >= floor }
            .sorted { ($0.date ?? "") > ($1.date ?? "") }
    }

    // MARK: - ふりかえり

    /// その日にあった予定（1回だけ・保管済みを含む）
    func itemsOn(_ key: String) -> [Item] {
        Logic.itemsOnDay(snapshot.schedule, snapshot.records, key)
    }

    /// これから来る日の予定（カレンダーで先の日を押したとき）
    func plannedOn(_ key: String, now: Date = Date()) -> [Item] {
        Logic.plannedOnDay(snapshot.schedule, snapshot.records, key, now: now)
    }

    func mark(_ item: Item, on key: String) -> Mark? {
        snapshot.records[key]?[item.id]
    }

    /// カレンダーから記録を付け直す。同じものをもう一度押したら取り消し
    func toggle(_ item: Item, _ mark: Mark, on key: String) {
        let cleared = snapshot.records[key]?[item.id] == mark
        snapshot.setMark(cleared ? nil : mark, item: item.id, on: key)
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
        // 「あと2日」だけでは次がいつか分からないので、日付を先に出す（拡張と同じ並び）
        if info.daysUntil > 0 {
            return "\(Describe.short(Logic.day(now, plus: info.daysUntil)))・あと\(info.daysUntil)日"
        }
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

    /// 通知をオンにする導線。**まだ聞いていなければ聞く。断られていたら設定を開く。**
    /// macOS は一度 requestAuthorization しないと、システム設定の通知一覧にアプリ自体が並ばない。
    /// 「設定を開く」だけだと、行っても何も無い画面に着く
    func enableNotifications() async {
        if await notifier.authorizationStatus() == .notDetermined {
            _ = await notifier.requestPermission()
            reschedule()
        } else {
            Platform.openNotificationSettings()
        }
        await refreshNotificationState()
    }

    /// 通知が届く状態かを見に行く。アプリが前面に戻るたびに呼ぶ
    /// （設定アプリで切られていることがあるため）
    func refreshNotificationState() async {
        let status = await notifier.authorizationStatus()
        notificationsWorking = (status == .authorized || status == .provisional)
    }

    /// 既にある予定を差し替える。ID は変えない（記録が ID で結びついているため）
    func update(_ item: Item) {
        guard let i = snapshot.schedule.firstIndex(where: { $0.id == item.id }) else { return }
        snapshot.schedule[i] = item
        commit()
    }

    func remove(_ item: Item) {
        snapshot.schedule.removeAll { $0.id == item.id }
        commit()
    }

    func record(_ item: Item, _ mark: Mark, now: Date = Date()) {
        snapshot.setMark(mark, item: item.id, on: Logic.dateKey(now))
        commit()
    }

    /// 「できた」を付けたあとの一言（こっそりお祝い）。記録を付けてから呼ぶ
    func cheerAfterDone(_ item: Item, now: Date = Date()) -> Cheer {
        CheerLogic.afterDone(item, schedule: snapshot.schedule, records: snapshot.records, now: now)
    }

    /// 「◯日ごと」で、済ませたのに付け忘れた日を選べる候補（昨日から新しい順・最大7日）
    func pastDoneCandidates(for item: Item, now: Date = Date()) -> [String] {
        Logic.pastDoneCandidates(item, snapshot.records, now)
    }

    /// 過去の日に「できた」を付ける。◯日ごとは基準日が動くので、次の目安日を言い切って返す
    /// （カードが今日の予定から消えることがあり、黙って消えると「無くなった」に見える）
    @discardableResult
    func recordPastDone(_ item: Item, on key: String, now: Date = Date()) -> String {
        snapshot.setMark(.done, item: item.id, on: key)
        commit()

        let dayText = Logic.parseDateKey(key).map(Describe.short) ?? key
        guard let info = Logic.intervalDueInfo(item, snapshot.records, now) else {
            return "\(dayText) にできたと記録しました"
        }
        let due = Describe.short(Logic.day(now, plus: info.daysUntil))
        if info.daysUntil > Logic.intervalNoticeDays(item) {
            return "\(dayText) にできたと記録しました。次の目安日は \(due) です"
        } else if info.daysUntil > 0 {
            return "\(dayText) にできたと記録しました。次の目安日は \(due) なので、今日の予定に残ります"
        }
        return "\(dayText) にできたと記録しました。目安日（\(due)）が来ているので、今日の予定に残ります"
    }

    /// 押し間違いを戻す。**記録を消すのは取り消しのときだけ**
    func undo(_ item: Item, now: Date = Date()) {
        snapshot.setMark(nil, item: item.id, on: Logic.dateKey(now))
        commit()
    }

    private func commit() {
        snapshot.updatedAt = Date().timeIntervalSince1970 * 1000
        try? store?.save(snapshot)
        reschedule()
        schedulePush()
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
