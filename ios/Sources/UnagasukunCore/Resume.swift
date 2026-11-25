import Foundation

/// 「しばらく休む」の再開日。休みにするときに日を決めておくと、その日に自動で戻る（2026-11-26 本人要望）。
///
/// 判定のロジック（Logic・Today）は `enabled` だけを見るまま変えていない（拡張機能の logic.js との
/// 突き合わせを崩さないため）。代わりに、アプリが開いたとき・時計が進んだとき・同期のあとに
/// `wake` で `enabled` を戻す。アプリを開かない日のために、通知の予約と先の日の予定だけは
/// 再開日を先読みする（`NotificationPlan.build` と `Logic.plannedOnDay`）
public enum Resume {
    /// 再開日が来た予定を動いている状態に戻した一覧。戻すものが無ければ nil
    public static func wake(_ schedule: [Item], now: Date) -> [Item]? {
        let today = Logic.dateKey(now)
        var changed = false
        let out = schedule.map { item -> Item in
            guard !item.enabled, let key = item.resumeDate, Logic.isDateKey(key), key <= today else { return item }
            var woke = item
            woke.enabled = true
            woke.resumeDate = nil
            changed = true
            return woke
        }
        return changed ? out : nil
    }

    /// 休み中で、再開日がこれから来る予定か（今日の時点ではまだ休み）
    public static func pending(_ item: Item, now: Date) -> String? {
        guard !item.enabled, let key = item.resumeDate, Logic.isDateKey(key), key > Logic.dateKey(now) else { return nil }
        return key
    }

    /// その日には動いているか。休み中でも、再開日以降なら動いている扱い
    public static func isOn(_ item: Item, key: String) -> Bool {
        if item.enabled { return true }
        guard let r = item.resumeDate, Logic.isDateKey(r) else { return false }
        return key >= r
    }
}
