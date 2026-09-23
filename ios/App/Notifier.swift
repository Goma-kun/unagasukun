import Foundation
import UserNotifications

/// アプリを開いている間に来た通知も、黙って捨てずに出す。
/// **iOS の既定は「前面のときは出さない」。** 予定の時刻にアプリを見ていた人だけ
/// お知らせを受け取れないのは、この道具の趣旨に合わない
final class ForegroundNotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}

/// 予約通知の面倒を見る。
///
/// 拡張機能は `chrome.alarms` を「鳴ったら次回を張り直す」で回せるが、
/// **iOS はアプリが動いていないと張り直せない。**
/// だから先の回までまとめて予約し、アプリが開かれるたびに入れ替える。
struct Notifier {

    private let center = UNUserNotificationCenter.current()

    /// 通知の許可を聞く。**断られても機能は止めない**（一覧は使えるため）
    @discardableResult
    func requestPermission() async -> Bool {
        (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// まだ許可を聞いていない／断られている間は**何も予約しない。**
    /// `center.add()` は許可されていないと、そこで勝手にダイアログを出す。
    /// 何のアプリか分からないうちに聞かれると人は断るので、聞く場所はこちらで決める
    func replaceAll(with plan: [PlannedNotification]) async {
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional else { return }

        center.removeAllPendingNotificationRequests()

        for p in plan {
            let content = UNMutableNotificationContent()
            switch p.kind {
            case .main:
                content.title = "いまは「\(p.title)」の時間です"
            case .pre:
                content.title = "まもなく「\(p.title)」の時間です"
            }
            // うながすくん独自の音（App/unagasu.caf・自作）。G・D・F・C の和音を12弦ギター風＋ピアノ風で合成し、
            // 共鳴しない残響を薄くかけたもの。本人が「これがいい」と選んだ（2026-09-23）。
            // 予告も同じ音（短い版は「短かった」とのことで、同じにした）
            content.sound = UNNotificationSound(named: UNNotificationSoundName("unagasu.caf"))

            let parts = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: p.fireAt
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let request = UNNotificationRequest(identifier: p.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    /// いま何件が予約されているか（確認用）
    func pendingCount() async -> Int {
        await center.pendingNotificationRequests().count
    }
}
