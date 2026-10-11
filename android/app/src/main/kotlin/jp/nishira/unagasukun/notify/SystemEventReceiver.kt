package jp.nishira.unagasukun.notify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 再起動・時刻や時間帯の変更・アプリの更新・「アラームとリマインダー」の許可の変化のあとは
 * AlarmManager の予約が消えたりずれたりするので、張り直す
 */
class SystemEventReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        try {
            Scheduler.reschedule(context)
        } finally {
            pending.finish()
        }
    }
}
