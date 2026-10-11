package jp.nishira.unagasukun.data

import android.content.Context
import android.content.SharedPreferences
import jp.nishira.unagasukun.core.Logic
import jp.nishira.unagasukun.core.SnapshotStore
import java.io.File

/** 端末ごとの設定（iOS の UserDefaults に当たる）。画面の状態（畳んでいるか・絞り込み・「＋」の位置）もここ */
class Prefs(context: Context) {
    private val p: SharedPreferences = context.getSharedPreferences("unagasukun", Context.MODE_PRIVATE)

    var preNoticeOn: Boolean
        get() = p.getBoolean("preNoticeOn", Logic.preNoticeDefault.on)
        set(v) = p.edit().putBoolean("preNoticeOn", v).apply()

    var preNoticeMin: Int
        get() = p.getInt("preNoticeMin", Logic.preNoticeDefault.minutes)
        set(v) = p.edit().putInt("preNoticeMin", v).apply()

    /** 浮かぶ「＋」の位置（画面に対する割合 0〜1）。既定は左下 */
    var fabX: Float
        get() = p.getFloat("fabX", 0f)
        set(v) = p.edit().putFloat("fabX", v).apply()
    var fabY: Float
        get() = p.getFloat("fabY", 1f)
        set(v) = p.edit().putFloat("fabY", v).apply()

    var collapseRegistered: Boolean
        get() = p.getBoolean("collapseRegistered", false)
        set(v) = p.edit().putBoolean("collapseRegistered", v).apply()
    var collapsePast: Boolean
        get() = p.getBoolean("collapsePast", true)
        set(v) = p.edit().putBoolean("collapsePast", v).apply()
    var collapseDone: Boolean
        get() = p.getBoolean("collapseDone", false)
        set(v) = p.edit().putBoolean("collapseDone", v).apply()
    var todayTagFilter: String
        get() = p.getString("todayTagFilter", "") ?: ""
        set(v) = p.edit().putString("todayTagFilter", v).apply()

    /** 通知の送り出しの進み（ms）。これより前の予定は鳴らし終えたものとして扱う */
    var firedUpTo: Long
        get() = p.getLong("firedUpTo", 0L)
        set(v) = p.edit().putLong("firedUpTo", v).apply()

    companion object {
        /** 保存先。iOS と同じく「Unagasukun/snapshot.json」 */
        fun snapshotFile(context: Context): File = File(File(context.filesDir, "Unagasukun"), "snapshot.json")
        fun store(context: Context) = SnapshotStore(snapshotFile(context))
    }
}
