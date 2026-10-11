package jp.nishira.unagasukun

import android.app.Application
import android.content.Context
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.AndroidViewModel
import jp.nishira.unagasukun.core.Cheer
import jp.nishira.unagasukun.core.CheerLogic
import jp.nishira.unagasukun.core.Describe
import jp.nishira.unagasukun.core.ExportFile
import jp.nishira.unagasukun.core.Item
import jp.nishira.unagasukun.core.Logic
import jp.nishira.unagasukun.core.LookBack
import jp.nishira.unagasukun.core.Mark
import jp.nishira.unagasukun.core.Merge
import jp.nishira.unagasukun.core.Snapshot
import jp.nishira.unagasukun.core.Tag
import jp.nishira.unagasukun.core.Today
import jp.nishira.unagasukun.core.TodayLists
import jp.nishira.unagasukun.core.UkJson
import jp.nishira.unagasukun.data.Prefs
import jp.nishira.unagasukun.notify.Notifier
import jp.nishira.unagasukun.notify.Scheduler
import kotlinx.serialization.encodeToString

/** 画面が見ている状態のぜんぶ（iOS の AppModel と同じ）。予定と記録を持ち、変わるたびに保存して通知を張り直す */
class AppModel(app: Application) : AndroidViewModel(app) {
    private val context: Context get() = getApplication()
    private val store = Prefs.store(context)
    val prefs = Prefs(context)

    var snapshot: Snapshot by mutableStateOf(runCatching { store.load() }.getOrDefault(Snapshot()))
        private set

    /** 通知が実際に届く状態か。**効いていないことを黙っていてはいけない**ので画面に出す */
    var notificationsWorking by mutableStateOf(Notifier.enabled(context))
        private set
    /** 正確な時刻のアラームが張れるか（Android 12 以降） */
    var exactAlarmAllowed by mutableStateOf(Notifier.canScheduleExact(context))
        private set

    var preNoticeOn by mutableStateOf(prefs.preNoticeOn)
        private set
    var preNoticeMin by mutableStateOf(prefs.preNoticeMin)
        private set

    /** カレンダーで選んでいる日（"YYYY-MM-DD"）。浮かぶ「＋」がこの日で登録フォームを開くために持つ */
    var calendarSelectedDay by mutableStateOf<String?>(null)
    /** 通知を押して開いたときに、そのカードへ連れていって光らせる相手。数秒で消す */
    var highlightedId by mutableStateOf<String?>(null)

    /** 画面を 30 秒ごとに進める「いま」。記録の判定（時間が過ぎたか）に使う */
    var now by mutableStateOf(System.currentTimeMillis())

    fun changePreNoticeOn(v: Boolean) { prefs.preNoticeOn = v; preNoticeOn = v; reschedule() }
    fun changePreNoticeMin(v: Int) { prefs.preNoticeMin = v; preNoticeMin = v; reschedule() }

    /** カレンダーの選択日で新規登録するときのひな型（その日の「1回だけ」）。選んでいなければ null */
    val presetForCalendarDay: Item? get() = calendarSelectedDay?.let { Item(id = "preset", date = it) }

    // ---- 読むほう ----

    fun today(now: Long = this.now): TodayLists =
        Today.entries(snapshot.schedule, snapshot.records, now, tagOrder = snapshot.tags.map { it.id })

    fun streak(item: Item, now: Long = this.now): Int {
        // 「🔥 に数えない」ラベル（買い物など）は 0 のまま。忘れても続けた日数は切れない
        if (tag(item)?.countsStreak == false) return 0
        return Logic.streakFor(snapshot.records, item.id, now, item.days)
    }

    /** 登録済み一覧に出すもの。**今日の画面に出ているものは重ねて出さない** */
    fun registered(now: Long = this.now): List<Item> {
        val t = today(now)
        val shown = (t.todo + t.done).map { it.item.id }.toSet()
        return snapshot.schedule
            .filter { it.id !in shown && it.origId == null && !Logic.isArchived(it) && !isPastOneOff(it, now) }
            .sortedBy { Logic.listSortMs(it, now, snapshot.records) }
    }

    private fun isPastOneOff(item: Item, now: Long): Boolean {
        if (!Logic.isOneOff(item)) return false
        val d = item.date ?: return false
        return d < Logic.dateKey(now)
    }

    /** 日付が過ぎた「1回だけ」の予定（直近 `days` 日ぶん・新しい順） */
    fun pastOneOffs(now: Long = this.now, days: Int = 14): List<Item> {
        val floor = Logic.dateKey(Logic.day(now, -days))
        return snapshot.schedule
            .filter { isPastOneOff(it, now) && it.origId == null && (it.date ?: "") >= floor }
            .sortedByDescending { it.date ?: "" }
    }

    fun dayLists(key: String) = LookBack.dayLists(snapshot.schedule, snapshot.records, key)
    fun plannedOn(key: String, now: Long = this.now) = Logic.plannedOnDay(snapshot.schedule, snapshot.records, key, now)
    fun mark(item: Item, key: String): Mark? = snapshot.records[key]?.get(item.id)
    fun dayMark(key: String): Mark? = Logic.dayMark(snapshot.records, key, snapshot.schedule.map { it.id })
    fun doneCount(item: Item, weeks: Int, now: Long = this.now) = Logic.doneCountRecent(snapshot.records, item.id, now, weeks * 7)
    fun describe(item: Item, now: Long = this.now) = Describe.schedule(item, snapshot.records, now)

    /** 「◯日ごと」の次の目安日。それ以外は null */
    fun nextDueText(item: Item, now: Long = this.now): String? {
        if (!Logic.isInterval(item)) return null
        val info = Logic.intervalDueInfo(item, snapshot.records, now) ?: return null
        val r = context.resources
        return when {
            info.daysUntil > 0 -> r.getQuantityString(R.plurals.days_left, info.daysUntil,
                Describe.short(Logic.day(now, info.daysUntil)), info.daysUntil)
            info.daysUntil == 0 -> r.getString(R.string.due_today)
            else -> r.getQuantityString(R.plurals.days_overdue, -info.daysUntil, -info.daysUntil)
        }
    }

    // ---- 書くほう ----

    fun add(item: Item) {
        snapshot = snapshot.copy(schedule = snapshot.schedule + item)
        commit()
    }

    /** 既にある予定を差し替える。ID は変えない（記録が ID で結びついているため） */
    fun update(item: Item) {
        val i = snapshot.schedule.indexOfFirst { it.id == item.id }
        if (i < 0) return
        snapshot = snapshot.copy(schedule = snapshot.schedule.toMutableList().also { it[i] = item })
        commit()
    }

    fun remove(item: Item) {
        snapshot = snapshot.copy(schedule = snapshot.schedule.filter { it.id != item.id })
        commit()
    }

    fun record(item: Item, mark: Mark, now: Long = this.now) {
        snapshot = snapshot.withMark(mark, item.id, Logic.dateKey(now))
        commit()
    }

    /** カレンダーから記録を付け直す。同じものをもう一度押したら取り消し */
    fun toggle(item: Item, mark: Mark, key: String) {
        val cleared = snapshot.records[key]?.get(item.id) == mark
        snapshot = snapshot.withMark(if (cleared) null else mark, item.id, key)
        commit()
    }

    /** 押し間違いを戻す。**記録を消すのは取り消しのときだけ** */
    fun undo(item: Item, now: Long = this.now) {
        snapshot = snapshot.withMark(null, item.id, Logic.dateKey(now))
        commit()
    }

    fun note(item: Item, key: String): String? = snapshot.notes[key]?.get(item.origId ?: item.id)

    fun setNote(text: String?, item: Item, key: String) {
        snapshot = snapshot.withNote(text, item.origId ?: item.id, key)
        commit()
    }

    /** 「できた」を付けたあとの一言（こっそりお祝い）。記録を付けてから呼ぶ */
    fun cheerAfterDone(item: Item, now: Long = this.now): Cheer =
        CheerLogic.afterDone(item, snapshot.schedule, snapshot.records, now)

    fun pastDoneCandidates(item: Item, now: Long = this.now): List<String> =
        Logic.pastDoneCandidates(item, snapshot.records, now)

    /** 過去の日に「できた」を付ける。◯日ごとは基準日が動くので、次の目安日を言い切って返す */
    fun recordPastDone(item: Item, key: String, now: Long = this.now): String {
        snapshot = snapshot.withMark(Mark.DONE, item.id, key)
        commit()
        val dayText = Logic.parseDateKey(key)?.let { Describe.short(it) } ?: key
        val info = Logic.intervalDueInfo(item, snapshot.records, now)
            ?: return context.getString(R.string.recorded_past_done, dayText)
        val due = Describe.short(Logic.day(now, info.daysUntil))
        return when {
            info.daysUntil > Logic.intervalNoticeDays(item) -> context.getString(R.string.recorded_next_due, dayText, due)
            info.daysUntil > 0 -> context.getString(R.string.recorded_next_due_stays, dayText, due)
            else -> context.getString(R.string.recorded_due_reached, dayText, due)
        }
    }

    // ---- ラベル ----

    val tags: List<Tag> get() = snapshot.effectiveTags
    fun tag(item: Item): Tag? = snapshot.tag(item)

    /** 予定が1つでも付いているラベルだけ（今日の絞り込みチップに出す） */
    fun tagsInUse(): List<Tag> {
        val used = snapshot.schedule.filter { it.origId == null && !Logic.isArchived(it) }.mapNotNull { it.tagId }.toSet()
        return tags.filter { it.id in used }
    }

    /** ラベル一覧を差し替える。消したラベルが付いていた予定は「ラベルなし」に戻す */
    fun setTags(newTags: List<Tag>) {
        val ids = newTags.map { it.id }.toSet()
        snapshot = snapshot.copy(
            tags = newTags,
            schedule = snapshot.schedule.map { if (it.tagId != null && it.tagId !in ids) it.copy(tagId = null) else it },
        )
        commit()
    }

    // ---- 取り込み・書き出し・控え ----

    fun backupCount(): Int = store.backups().size

    /** いちばん新しい控えに戻す。**いまの中身も控えに残してから**戻す */
    fun restoreNewestBackup() {
        val newest = store.backups().firstOrNull() ?: return
        val restored = runCatching { store.loadBackup(newest) }.getOrNull() ?: return
        runCatching { store.saveBackup(snapshot) }
        snapshot = restored
        commit()
    }

    /** 拡張機能・iPhone 版が書き出した JSON を取り込む。戻り値は画面に出す結果の文 */
    fun importFile(uri: Uri): String {
        return try {
            val text = context.contentResolver.openInputStream(uri)?.bufferedReader()?.readText() ?: throw IllegalStateException()
            val file = UkJson.decodeFromString(ExportFile.serializer(), text)
            val before = snapshot.schedule.size to snapshot.records.size
            runCatching { store.saveBackup(snapshot) }   // 取り込む前の中身も控えに残す
            snapshot = Merge.importing(snapshot, file)
            commit()
            context.getString(R.string.import_result, snapshot.schedule.size - before.first, snapshot.records.size - before.second)
        } catch (_: Exception) {
            context.getString(R.string.import_failed)
        }
    }

    /** 予定と記録を JSON に書き出す（拡張機能の「データを書き出す」と同じ形） */
    fun exportTo(uri: Uri): String {
        return try {
            val file = ExportFile(schedule = snapshot.schedule, records = snapshot.records, notes = snapshot.notes,
                app = "unagasukun", exportedAt = System.currentTimeMillis().toDouble())
            context.contentResolver.openOutputStream(uri, "wt")?.use { it.write(UkJson.encodeToString(file).toByteArray()) }
                ?: throw IllegalStateException()
            context.getString(R.string.export_done)
        } catch (_: Exception) {
            context.getString(R.string.export_failed)
        }
    }

    /** 書き出しのファイル名（拡張機能と同じ「unagasukun-YYYY-MM-DD.json」） */
    fun exportFileName(): String = "unagasukun-${Logic.dateKey(System.currentTimeMillis())}.json"

    // ---- 通知 ----

    /** 通知が届く状態かを見に行く。アプリが前面に戻るたびに呼ぶ（設定アプリで切られていることがあるため） */
    fun refreshNotificationState() {
        notificationsWorking = Notifier.enabled(context)
        exactAlarmAllowed = Notifier.canScheduleExact(context)
    }

    private fun commit() {
        snapshot = snapshot.copy(updatedAt = System.currentTimeMillis().toDouble())
        runCatching { store.save(snapshot) }
        reschedule()
    }

    /** 予定や記録が変わったら通知を張り直す */
    fun reschedule() {
        Scheduler.sync(context, snapshot)
    }
}
