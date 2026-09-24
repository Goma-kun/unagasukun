import Foundation

/// 端末に登録する通知1件ぶん。
public struct PlannedNotification: Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// 予定の時刻そのもの
        case main
        /// 時間が近づいたときの予告（拡張の v1.7.0 と同じ考え方）
        case pre
    }
    public var id: String
    public var itemId: String
    public var kind: Kind
    public var fireAt: Date
    public var title: String
    /// 詳細メモ。通知の本文に出す（無ければ本文なし）
    public var detail: String? = nil
}

public enum NotificationPlan {

    /// iOS が1つのアプリに対して抱えてくれる予約通知の上限。
    /// **超えたぶんは黙って捨てられる**ので、こちらで先に切る。
    public static let iosPendingLimit = 64

    /// いま登録すべき通知を、発火の早い順に返す。
    ///
    /// 拡張機能は `chrome.alarms` を「発火したら次回ぶんを張り直す」方式で回しているが、
    /// iOS はアプリが起きていないと張り直せない。そのため
    /// **先の回までまとめて予約しておき、アプリが開かれるたびに入れ替える。**
    ///
    /// - Parameter horizonDays: 何日先まで予約するか
    public static func build(
        schedule: [Item],
        records: Records,
        now: Date,
        preNoticeOn: Bool? = nil,
        preNoticeMin: Int? = nil,
        horizonDays: Int = 30,
        limit: Int = iosPendingLimit
    ) -> [PlannedNotification] {
        var out: [PlannedNotification] = []
        let horizon = Logic.day(now, plus: horizonDays)

        for item in schedule {
            if item.origId != nil || Logic.isArchived(item) || !item.enabled { continue }

            // その予定の次の回から順に、期限まで拾う。
            // 「◯日ごと」は済ませた日で目安日が動くので、先の回を今から決め打てない。
            // その1回だけを予約して、記録が付いたときに張り直す
            var cursor = now
            var guardCount = 0
            while guardCount < horizonDays + 8 {
                guardCount += 1
                guard let next = Logic.nextOccurrence(item, cursor, records), next <= horizon else { break }

                // 済ませた予定の予告は出さない（責めない設計）
                let alreadyDone = records[Logic.dateKey(next)]?[item.id] == .done
                if !alreadyDone {
                    out.append(PlannedNotification(
                        id: "main:\(item.id):\(Int(Logic.ms(next)))",
                        itemId: item.id, kind: .main, fireAt: next, title: item.label,
                        detail: item.detail
                    ))
                    if let preMs = Logic.preNoticeAt(Logic.ms(next), on: preNoticeOn,
                                                     minutes: preNoticeMin, nowMs: Logic.ms(now)) {
                        out.append(PlannedNotification(
                            id: "pre:\(item.id):\(Int(preMs))",
                            itemId: item.id, kind: .pre,
                            fireAt: Date(timeIntervalSince1970: preMs / 1000), title: item.label,
                            detail: item.detail
                        ))
                    }
                }

                if Logic.isInterval(item) { break }   // 目安日が動くので先を決め打たない
                cursor = next
            }
        }

        out.sort { $0.fireAt == $1.fireAt ? $0.id < $1.id : $0.fireAt < $1.fireAt }
        return Array(out.prefix(limit))
    }
}
