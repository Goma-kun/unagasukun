package jp.nishira.unagasukun.notify

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import jp.nishira.unagasukun.core.Logic
import jp.nishira.unagasukun.core.NotificationPlan
import jp.nishira.unagasukun.core.PlannedNotification
import jp.nishira.unagasukun.core.Snapshot
import jp.nishira.unagasukun.data.Prefs

/**
 * `NotificationPlan.build` の結果を AlarmManager に張る。
 *
 * iOS は 64 件をまとめて予約するが、Android の AlarmManager は「次の1件」だけを張り、
 * 鳴ったら保存データから計画を作り直して次を張る（鎖）。こうすると
 * - 予定や記録が変わったときに古いアラームを1件ずつ消して回らなくてよい（張り直しは常に「次の1件」の上書き）
 * - 鳴る側は毎回ディスクの snapshot.json から計算するので、アプリが落ちていても正しい相手を鳴らせる
 * 張り直すきっかけ: アプリ起動・記録や予定の変更・BOOT_COMPLETED・TIME_SET/TIMEZONE_CHANGED・鳴ったあと
 */
object Scheduler {
    private const val requestCode = 1001
    const val actionFire = "jp.nishira.unagasukun.FIRE"

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, AlarmReceiver::class.java).setAction(actionFire)
        return PendingIntent.getBroadcast(context, requestCode, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun plan(context: Context, snapshot: Snapshot, now: Long): List<PlannedNotification> {
        val prefs = Prefs(context)
        return NotificationPlan.build(
            schedule = snapshot.schedule, records = snapshot.records, now = now,
            preNoticeOn = prefs.preNoticeOn, preNoticeMin = prefs.preNoticeMin,
            tagNames = snapshot.effectiveTags.associate { it.id to it.name },
        )
    }

    /**
     * 張り直しと送り出しを1か所で。前回の送り出し位置（firedUpTo）から今までに来た通知を出し、次の1件を張る。
     * 30分より遅れたものは「いま知らせても意味がない」ので出さない（拡張機能の isTooLate と同じ）。
     * アプリ起動時・記録の変更時にもここを通るので、アラームが遅れた分は開いたときに届く。
     * 出したぶんは firedUpTo を進めるので二重には出ない。`snapshot` を渡さなければディスクから読む
     */
    fun sync(context: Context, snapshot: Snapshot? = null, now: Long = System.currentTimeMillis()) {
        val snap = snapshot ?: runCatching { Prefs.store(context).load() }.getOrDefault(Snapshot())
        val prefs = Prefs(context)
        val from = prefs.firedUpTo
        // 計画は「from の時点」で作る。now で作ると、ちょうど今の分が nextOccurrence の `cand > now` で落ちる
        val base = if (from in 1 until now) from else now - 1
        val planned = plan(context, snap, base)
        val due = planned.filter { it.fireAt > from && it.fireAt <= now && !Logic.isTooLate(it.fireAt, now) }
        for (p in due) Notifier.show(context, p)
        prefs.firedUpTo = now

        val next = planned.firstOrNull { it.fireAt > now } ?: plan(context, snap, now).firstOrNull { it.fireAt > now }
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val pi = pendingIntent(context)
        if (next == null) { am.cancel(pi); return }
        if (Build.VERSION.SDK_INT >= 31 && !am.canScheduleExactAlarms()) {
            // 許可が無ければ近似（数分ずれることがある。設定画面で案内する）
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.fireAt, pi)
        } else {
            am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next.fireAt, pi)
        }
    }

    fun reschedule(context: Context, snapshot: Snapshot? = null) = sync(context, snapshot)
    fun fire(context: Context) = sync(context)
}
