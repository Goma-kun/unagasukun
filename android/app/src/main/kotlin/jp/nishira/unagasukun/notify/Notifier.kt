package jp.nishira.unagasukun.notify

import android.Manifest
import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import jp.nishira.unagasukun.MainActivity
import jp.nishira.unagasukun.R
import jp.nishira.unagasukun.core.PlannedNotification

/**
 * 通知の見た目と権限の面倒を見る（iOS の Notifier.swift に当たる）。
 * チャンネルは1つ。音は iOS と同じ自作の「うながす」音（G・D・F・C の和音）
 */
object Notifier {
    const val channelId = "reminders"
    const val extraItemId = "itemId"

    fun ensureChannel(context: Context) {
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val ch = NotificationChannel(channelId, context.getString(R.string.notif_channel), NotificationManager.IMPORTANCE_HIGH)
        ch.setSound(
            Uri.parse("android.resource://${context.packageName}/raw/unagasu"),
            AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION).build(),
        )
        ch.enableVibration(true)
        nm.createNotificationChannel(ch)
    }

    /** 通知が実際に届く状態か（アプリの通知がオン＋Android 13 以降は POST_NOTIFICATIONS の許可） */
    fun enabled(context: Context): Boolean {
        if (!NotificationManagerCompat.from(context).areNotificationsEnabled()) return false
        if (Build.VERSION.SDK_INT >= 33) {
            return ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        }
        return true
    }

    /** 正確な時刻のアラームを張れるか（Android 12 以降は許可が要る。14 以降は既定で不許可） */
    fun canScheduleExact(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < 31) return true
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        return am.canScheduleExactAlarms()
    }

    /** アプリの通知設定を開く（断られたあとの導線） */
    fun openNotificationSettings(context: Context) {
        val intent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
            .putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        context.startActivity(intent)
    }

    /** 「アラームとリマインダー」の許可画面を開く（Android 12 以降） */
    fun openExactAlarmSettings(context: Context) {
        if (Build.VERSION.SDK_INT < 31) return
        val intent = Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:${context.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        try { context.startActivity(intent) } catch (_: Exception) {
            context.startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        }
    }

    /** 1件出す。題は種類ごと（いまは／まもなく／終わりました）、本文は詳細メモ（120字まで）。押すと今日の画面のそのカードへ */
    fun show(context: Context, p: PlannedNotification) {
        if (!enabled(context)) return
        ensureChannel(context)
        val title = when (p.kind) {
            PlannedNotification.Kind.MAIN -> context.getString(R.string.notif_main, p.title)
            PlannedNotification.Kind.PRE -> context.getString(R.string.notif_pre, p.title)
            PlannedNotification.Kind.END -> context.getString(R.string.notif_end, p.title)
        }
        val open = Intent(context, MainActivity::class.java)
            .setAction(Intent.ACTION_VIEW)
            .putExtra(extraItemId, p.itemId)
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
        val pi = PendingIntent.getActivity(
            context, p.id.hashCode(), open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val b = NotificationCompat.Builder(context, channelId)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .setSound(Uri.parse("android.resource://${context.packageName}/raw/unagasu"))
        val d = p.detail
        if (!d.isNullOrEmpty()) {
            val body = d.take(120)
            b.setContentText(body).setStyle(NotificationCompat.BigTextStyle().bigText(body))
        }
        try {
            NotificationManagerCompat.from(context).notify(p.id.hashCode(), b.build())
        } catch (_: SecurityException) {
            // 許可が無い。enabled() で見ているが、取り消された直後の取りこぼしは黙って捨てる
        }
    }
}
