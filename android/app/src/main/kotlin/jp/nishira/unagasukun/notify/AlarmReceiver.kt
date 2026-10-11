package jp.nishira.unagasukun.notify

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** 予定の時刻に鳴る。通知を出して次を張る */
class AlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        try {
            Scheduler.fire(context)
        } finally {
            pending.finish()
        }
    }
}
