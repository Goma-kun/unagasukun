package jp.nishira.unagasukun.core

import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import java.io.File
import java.nio.file.Files
import java.nio.file.StandardCopyOption

/**
 * 予定と記録の入れ物。**拡張機能の `chrome.storage.local`・iOS の snapshot.json と同じ形のまま持つ。**
 * 端末ごとに独自の形にすると、取り込み・書き出しのたびに変換が要り、変換のたびに食い違いが生まれる。
 */
@Serializable
data class Snapshot(
    val schedule: List<Item> = emptyList(),
    val records: Records = emptyMap(),
    /** 「新しいほう」を選ぶのに使う（ms） */
    @Serializable(with = MsDoubleSerializer::class) val updatedAt: Double = 0.0,
    /** 記録の操作履歴。"YYYY-MM-DD|予定ID" → 最後の操作。「消した」も伝わるよう時刻つきで残す */
    val recordLog: Map<String, RecordEntry> = emptyMap(),
    /** 「実際は…」の一言。日付 → 予定ID → 文（拡張機能の `notes` と同じ形） */
    val notes: Notes = emptyMap(),
    /** notes の操作履歴 */
    val noteLog: Map<String, NoteEntry> = emptyMap(),
    /** ラベル一覧。空なら `Tag.defaults` を使う */
    val tags: List<Tag> = emptyList(),
) {
    /** 使うラベル一覧。まだ自分で触っていなければ既定の6つ */
    val effectiveTags: List<Tag> get() = if (tags.isEmpty()) Tag.defaults() else tags

    /** 予定に付いているラベル（無ければ null。消したラベルの id が残っていても null） */
    fun tag(item: Item): Tag? {
        val id = item.tagId ?: return null
        return effectiveTags.firstOrNull { it.id == id }
    }

    /** 中身が同じか。`updatedAt` は見ない */
    fun sameContent(other: Snapshot): Boolean =
        schedule == other.schedule && records == other.records && recordLog == other.recordLog
            && notes == other.notes && noteLog == other.noteLog && tags == other.tags

    /**
     * 記録を付ける・付け直す・消す入口。**アプリからの記録の変更は必ずここを通す**
     * （`records` を直接いじると履歴が残らない）。`mark` が null なら消す
     */
    fun withMark(mark: Mark?, itemId: String, day: String, at: Double = System.currentTimeMillis().toDouble()): Snapshot {
        val d = (records[day] ?: emptyMap()).toMutableMap()
        if (mark != null) d[itemId] = mark else d.remove(itemId)
        val rec = records.toMutableMap()
        if (d.isEmpty()) rec.remove(day) else rec[day] = d
        val log = recordLog.toMutableMap()
        log[logKey(day, itemId)] = RecordEntry(mark, at)
        return copy(records = rec, recordLog = log)
    }

    /** 「実際は…」を付ける・直す・消す入口。空文字や空白だけなら消す。30字まで */
    fun withNote(text: String?, itemId: String, day: String, at: Double = System.currentTimeMillis().toDouble()): Snapshot {
        val trimmed = text?.trim() ?: ""
        val value: String? = if (trimmed.isEmpty()) null else trimmed.take(ActualNote.maxLength)
        val d = (notes[day] ?: emptyMap()).toMutableMap()
        if (value != null) d[itemId] = value else d.remove(itemId)
        val n = notes.toMutableMap()
        if (d.isEmpty()) n.remove(day) else n[day] = d
        val log = noteLog.toMutableMap()
        log[logKey(day, itemId)] = NoteEntry(value, at)
        return copy(notes = n, noteLog = log)
    }

    companion object {
        fun logKey(day: String, id: String) = "$day|$id"
    }
}

/** 「実際は…」の1操作。`text` が null なら「消した」 */
@Serializable
data class NoteEntry(
    val text: String? = null,
    @Serializable(with = MsDoubleSerializer::class) val at: Double = 0.0,
)

/** 「実際は…」の選択肢。拡張機能と同じ4つ。**責める言葉は使わない** */
object ActualNote {
    val choices: List<String> get() = L10n.strings.actualChoices
    const val maxLength = 30
}

/** 記録の1操作。`mark` が null なら「消した」 */
@Serializable
data class RecordEntry(
    val mark: Mark? = null,
    /** 操作した時刻（ms） */
    @Serializable(with = MsDoubleSerializer::class) val at: Double = 0.0,
) {
    companion object {
        /** 新しい操作が勝つ。同時刻なら「できた」＞「休んだ」＞「消した」 */
        fun isNewer(e: RecordEntry, cur: RecordEntry): Boolean {
            if (e.at != cur.at) return e.at > cur.at
            return rank(e.mark) > rank(cur.mark)
        }
        private fun rank(m: Mark?) = when (m) { Mark.DONE -> 2; Mark.SKIP -> 1; null -> 0 }
    }
}

/** 拡張機能から書き出したファイルの形。`schedule`・`records`・`notes`（実際は…）を読む */
@Serializable
data class ExportFile(
    val schedule: List<Item> = emptyList(),
    val records: Records = emptyMap(),
    val notes: Notes? = null,
    /** 書き出すときに付ける印（拡張機能と同じキー）。読むときは見ない */
    val app: String? = null,
    @Serializable(with = MsDoubleSerializer::class) val exportedAt: Double? = null,
)

object Merge {
    /**
     * 2台ぶんを1つにまとめる。**records は足し合わせ、schedule は新しいほうを採る。**
     * 同じ日の同じ予定に別々の記録が付いた場合は「できた」を優先する
     */
    fun snapshots(a: Snapshot, b: Snapshot): Snapshot {
        val newer = if (a.updatedAt >= b.updatedAt) a else b

        val records = a.records.mapValues { it.value.toMutableMap() }.toMutableMap()
        for ((day, marks) in b.records) {
            val merged = records.getOrPut(day) { mutableMapOf() }
            for ((id, mark) in marks) {
                if (merged[id] == Mark.DONE) continue   // 「できた」は譲らない
                merged[id] = mark
            }
        }

        // 操作履歴があるものは、足し合わせより履歴を信じる（新しい操作が勝つ。「消した」も伝わる）
        val log = a.recordLog.toMutableMap()
        for ((k, e) in b.recordLog) {
            val cur = log[k]
            if (cur == null || RecordEntry.isNewer(e, cur)) log[k] = e
        }
        for ((k, e) in log) {
            val sep = k.indexOf('|'); if (sep < 0) continue
            val day = k.substring(0, sep); val id = k.substring(sep + 1)
            val d = records.getOrPut(day) { mutableMapOf() }
            if (e.mark != null) d[id] = e.mark else d.remove(id)
            if (d.isEmpty()) records.remove(day)
        }
        // 1年より古い履歴は捨てる
        val cutoff = maxOf(a.updatedAt, b.updatedAt) - 365.0 * 86_400_000
        val prunedLog = log.filterValues { it.at >= cutoff }

        val notes = a.notes.mapValues { it.value.toMutableMap() }.toMutableMap()
        for ((day, texts) in b.notes) {
            val merged = notes.getOrPut(day) { mutableMapOf() }
            for ((id, t) in texts) if (merged[id] == null) merged[id] = t
        }
        val nlog = a.noteLog.toMutableMap()
        for ((k, e) in b.noteLog) {
            val cur = nlog[k]
            if (cur == null || e.at > cur.at) nlog[k] = e
        }
        for ((k, e) in nlog) {
            val sep = k.indexOf('|'); if (sep < 0) continue
            val day = k.substring(0, sep); val id = k.substring(sep + 1)
            val d = notes.getOrPut(day) { mutableMapOf() }
            if (e.text != null) d[id] = e.text else d.remove(id)
            if (d.isEmpty()) notes.remove(day)
        }
        val prunedNlog = nlog.filterValues { it.at >= cutoff }

        return Snapshot(
            schedule = newer.schedule,
            records = records,
            updatedAt = maxOf(a.updatedAt, b.updatedAt),
            recordLog = prunedLog,
            notes = notes,
            noteLog = prunedNlog,
            tags = newer.tags,
        )
    }

    /**
     * 拡張機能（や iPhone 版の書き出し）から取り込む。**予定は「足す」。**
     * - 手元に同じ ID があれば手元を残す（手元で直した内容を上書きしない）
     * - 記録は足し合わせ、同じ日は「できた」を残す
     */
    fun importing(local: Snapshot, imported: ExportFile, now: Double = System.currentTimeMillis().toDouble()): Snapshot {
        val have = local.schedule.map { it.id }.toSet()
        val schedule = local.schedule + imported.schedule.filter { it.id !in have }

        val records = local.records.mapValues { it.value.toMutableMap() }.toMutableMap()
        for ((day, marks) in imported.records) {
            val merged = records.getOrPut(day) { mutableMapOf() }
            for ((id, mark) in marks) if (merged[id] != Mark.DONE) merged[id] = mark
        }
        // 「実際は…」は手元に無い日だけ足す
        val notes = local.notes.mapValues { it.value.toMutableMap() }.toMutableMap()
        for ((day, texts) in imported.notes ?: emptyMap()) {
            val merged = notes.getOrPut(day) { mutableMapOf() }
            for ((id, t) in texts) if (merged[id] == null) merged[id] = t
        }
        return Snapshot(schedule, records, now, local.recordLog, notes, local.noteLog, local.tags)
    }
}

/** 端末のディスクに置く。アプリ専用領域の中の1ファイル（`filesDir/Unagasukun/snapshot.json`） */
class SnapshotStore(private val file: File) {

    fun load(): Snapshot {
        if (!file.exists()) return Snapshot()
        return UkJson.decodeFromString(Snapshot.serializer(), file.readText())
    }

    /** 書き込みは一時ファイル経由。途中で落ちても、読めないファイルを残さない */
    fun save(snapshot: Snapshot) {
        file.parentFile?.mkdirs()
        val tmp = File(file.path + ".tmp")
        tmp.writeText(UkJson.encodeToString(snapshot))
        Files.move(tmp.toPath(), file.toPath(), StandardCopyOption.REPLACE_EXISTING, StandardCopyOption.ATOMIC_MOVE)
    }

    // ---- 控え ----

    private val backupDir: File get() = File(file.parentFile, "backups")

    /** 取り込みなどで手元を書き換える**直前**の中身を残しておく。残す数を超えた古いものから消す */
    fun saveBackup(snapshot: Snapshot, at: Long = System.currentTimeMillis()) {
        backupDir.mkdirs()
        File(backupDir, "snapshot-$at.json").writeText(UkJson.encodeToString(snapshot))
        pruneBackups()
    }

    /** 新しい順 */
    fun backups(): List<File> =
        (backupDir.listFiles() ?: emptyArray())
            .filter { it.name.startsWith("snapshot-") }
            .sortedByDescending { it.name }

    fun loadBackup(f: File): Snapshot = UkJson.decodeFromString(Snapshot.serializer(), f.readText())

    private fun pruneBackups() {
        for (old in backups().drop(backupLimit)) old.delete()
    }

    companion object {
        const val backupLimit = 5
    }
}
