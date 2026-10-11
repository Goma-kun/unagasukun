package jp.nishira.unagasukun.core

import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZonedDateTime
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * extension/logic.js の「スケジュール計算ロジック」ブロックをそのまま移したもの（iOS の Logic.swift の写し）。
 *
 * **judgement の意味づけは logic.js のコメントが正本。** ここを直すときは向こうも直す。
 * 両方が同じ答えを返すことは ../test/parity_android.mjs が実際に突き合わせて確かめる。
 *
 * 時刻はぜんぶ **エポックからのミリ秒（Long）** で持つ。JS の `Date.getTime()` と同じ単位にしておくと、
 * 突き合わせの入出力がそのまま比べられる。年月日の組み立ては端末のタイムゾーン（`ZoneId.systemDefault()`）。
 */
object Logic {

    // ---- 暦の足回り ----

    val zone: ZoneId get() = ZoneId.systemDefault()

    fun zdt(ms: Long): ZonedDateTime = Instant.ofEpochMilli(ms).atZone(zone)

    fun localDate(ms: Long): LocalDate = zdt(ms).toLocalDate()

    private fun ms(d: LocalDate): Long = d.atStartOfDay(zone).toInstant().toEpochMilli()

    /** JS の `getDay()`（日曜=0）に合わせる。java.time は月曜=1 … 日曜=7 */
    fun jsWeekday(ms: Long): Int = localDate(ms).dayOfWeek.value % 7

    fun jsWeekday(d: LocalDate): Int = d.dayOfWeek.value % 7

    /** その日の 00:00 */
    fun startOfDay(ms: Long): Long = ms(localDate(ms))

    /** 日数を足した日の 00:00。月をまたぐ繰り上がりは java.time に任せる */
    fun day(ms: Long, plus: Int): Long = ms(localDate(ms).plusDays(plus.toLong()))

    /**
     * その日の指定時刻。JS の `new Date(y, m, d, hh, mm)` と同じで、
     * 24時以降や60分以降は翌日へ繰り上がる（終了時刻 "24:00" がこれに当たる）。
     * その日の 00:00 に時と分を**足す**ことで、範囲外も自然に繰り上がる
     */
    fun at(ms: Long, hour: Int, minute: Int): Long =
        localDate(ms).atStartOfDay().plusHours(hour.toLong()).plusMinutes(minute.toLong())
            .atZone(zone).toInstant().toEpochMilli()

    /** その日の 23:59:59.999（JS の `new Date(y, m, d, 23, 59, 59, 999)` と同じ） */
    fun endOfDay(ms: Long): Long = at(ms, 23, 59) + 59_999

    const val dayMs: Long = 24L * 60 * 60 * 1000

    /**
     * "HH:MM" の**形**だけを見て (時, 分) に。範囲は見ない。
     * JS 版の `/^\d{2}:\d{2}$/` に対応する。`isValidEndTime` と `blockEndMs` はここまでしか見ておらず、
     * 終了時刻 "24:00"（その日の終わり）を通す。**範囲を足すと拡張機能と答えが変わる**
     */
    fun parseTimeParts(s: String?): Pair<Int, Int>? {
        if (s == null || s.length != 5 || s[2] != ':') return null
        val h = s.substring(0, 2); val m = s.substring(3, 5)
        if (!h.all { it in '0'..'9' } || !m.all { it in '0'..'9' }) return null
        return h.toInt() to m.toInt()
    }

    /** 発火時刻として妥当な "HH:MM"。`nextOccurrence` だけがここまで見る（JS も同じ） */
    fun parseTime(s: String?): Pair<Int, Int>? {
        val (h, m) = parseTimeParts(s) ?: return null
        return if (h <= 23 && m <= 59) h to m else null
    }

    /** "YYYY-MM-DD" をその日の 00:00（ms）に。形式が違えば null */
    fun parseDateKey(s: String?): Long? = parseDateKeyLocal(s)?.let { ms(it) }

    /** "YYYY-MM-DD" を LocalDate に。月や日の範囲外は JS の Date と同じく繰り上げる */
    fun parseDateKeyLocal(s: String?): LocalDate? {
        if (s == null || !isDateKey(s)) return null
        val p = s.split("-")
        val y = p[0].toInt(); val m = p[1].toInt(); val d = p[2].toInt()
        return LocalDate.of(y, 1, 1).plusMonths((m - 1).toLong()).plusDays((d - 1).toLong())
    }

    fun isDateKey(s: String): Boolean {
        val p = s.split("-")
        if (p.size != 3 || p[0].length != 4 || p[1].length != 2 || p[2].length != 2) return false
        return p.all { part -> part.all { it in '0'..'9' } }
    }

    // ---- 日付キー ----

    /** その日付のキー（実績記録に使う）。例: "2026-08-13" */
    fun dateKey(ms: Long): String = dateKey(localDate(ms))

    fun dateKey(d: LocalDate): String = "%04d-%02d-%02d".format(d.year, d.monthValue, d.dayOfMonth)

    // ---- 予定の種類 ----

    /** その日にこの予定があるか（days が空＝毎日） */
    fun isScheduledOn(days: List<Int>?, ms: Long): Boolean {
        if (days.isNullOrEmpty()) return true
        return days.contains(jsWeekday(ms))
    }

    /** 1回だけの予定か（日付があり、曜日の繰り返しがない） */
    fun isOneOff(item: Item): Boolean = !item.date.isNullOrEmpty() && item.days.isNullOrEmpty()

    /** 時刻を固定しない予定か */
    fun isAnytime(item: Item): Boolean = item.anytime

    /** 「◯日ごと」の予定か（済ませた日を基準に数え直す） */
    fun isInterval(item: Item): Boolean = (item.intervalDays ?: 0) > 0

    /** 保管済みの予定か（日付が過ぎた1回だけ。一覧・通知には出さないが名前を引ける） */
    fun isArchived(item: Item): Boolean = item.archived

    /** 何日前から「今日の予定」に出すか（未設定は3日前から）。拡張機能の設定で、アプリの今日の予定では見ない */
    fun intervalNoticeDays(item: Item): Int {
        val n = item.noticeDays ?: return 3
        return if (n >= 0) n else 3
    }

    // ---- 「◯日ごと」 ----

    /** 基準日（YYYY-MM-DD）。records の最新の「できた」と anchorDate の新しいほう */
    fun intervalAnchorKey(item: Item, records: Records, now: Long): String? {
        val anchor = item.anchorDate?.takeIf { isDateKey(it) }
        var d = startOfDay(now)
        repeat(366) {
            val k = dateKey(d)
            // anchorDate のほうが新しいと分かった時点で records を遡っても勝てない
            if (anchor != null && anchor >= k) return anchor
            if (records[k]?.get(item.id) == Mark.DONE) return k
            d = day(d, -1)
        }
        return anchor
    }

    /** 目安日まであと何日か。基準が無ければ「そろそろ」扱い（daysUntil 0） */
    fun intervalDueInfo(item: Item, records: Records, now: Long): IntervalDue? {
        if (!isInterval(item)) return null
        val anchor = intervalAnchorKey(item, records, now) ?: return IntervalDue(0, null)
        val today = startOfDay(now)
        val anchorDay = parseDateKey(anchor) ?: return IntervalDue(0, null)
        val due = day(anchorDay, item.intervalDays ?: 0)
        return IntervalDue(
            daysUntil = ((due - today).toDouble() / dayMs).roundToInt(),
            sinceDone = ((today - anchorDay).toDouble() / dayMs).roundToInt(),
        )
    }

    // ---- 次に来る日時 ----

    /** 予定が次に来る日時（ms）。無効な予定や空振りなら null */
    fun nextOccurrence(item: Item, now: Long, records: Records = emptyMap()): Long? {
        // 時刻を固定しない予定は発火時刻を持たない（アラームを張らない）
        if (isAnytime(item)) return null
        if (!item.enabled) return null
        val (hh, mm) = parseTime(item.time) ?: return null

        // ◯日ごと：目安日の指定時刻に1回だけ知らせる。
        // 目安日を過ぎても翌日以降は鳴らさない（催促を重ねない＝責めない設計）
        if (isInterval(item)) {
            val info = intervalDueInfo(item, records, now) ?: return null
            if (info.daysUntil < 0) return null
            val cand = at(day(now, info.daysUntil), hh, mm)
            return if (cand > now) cand else null
        }

        if (isOneOff(item)) {
            val base = parseDateKey(item.date) ?: return null
            val cand = at(base, hh, mm)
            return if (cand > now) cand else null
        }

        for (add in 0 until 8) {
            val cand = at(day(now, add), hh, mm)
            if (cand <= now) continue
            if (isScheduledOn(item.days, cand)) return cand
        }
        return null
    }

    /** 発火が遅すぎたか（30分以上遅れは「いま知らせても意味がない」） */
    fun isTooLate(scheduledMs: Double, nowMs: Double): Boolean = nowMs - scheduledMs > 30 * 60 * 1000

    fun isTooLate(scheduledMs: Long, nowMs: Long): Boolean = nowMs - scheduledMs > 30L * 60 * 1000

    /** 終了時刻が開始時刻より後か（"HH:MM" 同士は文字列比較で正しく比べられる） */
    fun isValidEndTime(time: String?, endTime: String?): Boolean {
        if (endTime == null || parseTimeParts(endTime) == null || time == null) return false
        return endTime > time
    }

    /** 開始日時の予定の終了時刻（同じ日の endTime）。形が違えば NaN */
    fun blockEndMs(endTime: String, startMs: Long): Double {
        val (hh, mm) = parseTimeParts(endTime) ?: return Double.NaN
        return at(startMs, hh, mm).toDouble()
    }

    // ---- 並び順 ----

    /** 登録済み一覧の並び順キー（ミリ秒）。実行予定のないものは無限大で一番下 */
    fun listSortMs(item: Item, now: Long, records: Records = emptyMap()): Double {
        // ◯日ごとは「目安日ならいつでも」なので目安日の終わりを使う。過ぎていたら「今日やれる」ので今日の終わり
        if (isInterval(item)) {
            if (!item.enabled) return Double.POSITIVE_INFINITY
            val info = intervalDueInfo(item, records, now) ?: return Double.POSITIVE_INFINITY
            return endOfDay(day(now, max(0, info.daysUntil))).toDouble()
        }
        if (!isAnytime(item)) {
            val next = nextOccurrence(item, now, records) ?: return Double.POSITIVE_INFINITY
            return next.toDouble()
        }
        if (!item.enabled) return Double.POSITIVE_INFINITY
        if (isOneOff(item)) {
            val base = parseDateKey(item.date) ?: return Double.POSITIVE_INFINITY
            val end = endOfDay(base)
            return if (end > now) end.toDouble() else Double.POSITIVE_INFINITY
        }
        for (add in 0 until 8) {
            val cand = endOfDay(day(now, add))
            if (isScheduledOn(item.days, cand)) return cand.toDouble()
        }
        return Double.POSITIVE_INFINITY
    }

    // ---- ふりかえりの集計 ----

    /** 連続記録。スキップは連続を切らないが日数にも数えない（責めない設計） */
    fun streakFor(records: Records, itemId: String, now: Long, days: List<Int>?): Int {
        var streak = 0
        var d = startOfDay(now)
        // 今日まだ「できた」でなければ昨日から数え始める（今日の分はまだ失敗ではない）
        if (records[dateKey(d)]?.get(itemId) != Mark.DONE) d = day(d, -1)
        repeat(366) {
            if (isScheduledOn(days, d)) {
                val rec = records[dateKey(d)]?.get(itemId)
                if (rec == Mark.DONE) streak += 1
                else if (rec != Mark.SKIP) return streak
            }
            d = day(d, -1)
        }
        return streak
    }

    /** 直近 windowDays 日（今日を含む）の「できた」回数。達成率は出さない */
    fun doneCountRecent(records: Records, itemId: String, now: Long, windowDays: Int): Int {
        var count = 0
        var d = startOfDay(now)
        repeat(windowDays) {
            if (records[dateKey(d)]?.get(itemId) == Mark.DONE) count += 1
            d = day(d, -1)
        }
        return count
    }

    /** 直近 windowDays 日の「できた」日どうしの平均間隔（日）。2回未満なら null */
    fun avgDoneIntervalDays(records: Records, itemId: String, now: Long, windowDays: Int): Int? {
        val dates = ArrayList<Long>()
        var d = startOfDay(now)
        repeat(windowDays) {
            if (records[dateKey(d)]?.get(itemId) == Mark.DONE) dates.add(d)
            d = day(d, -1)
        }
        if (dates.size < 2) return null
        val span = (dates[0] - dates[dates.size - 1]).toDouble() / dayMs
        return (span / (dates.size - 1)).roundToInt()
    }

    // ---- カレンダー ----

    /**
     * これから来る日の予定（カレンダーで先の日を押したとき用）。
     * `itemsOnDay` は過去向けで「◯日ごと」を毎日出すが、未来では次の目安日から間隔ごとにだけ出す。
     * 休み中・保管済みは出さない。並びは時刻順（いつでも→時刻）
     */
    fun plannedOnDay(schedule: List<Item>, records: Records, key: String, now: Long): List<Item> {
        val dayMs0 = parseDateKey(key) ?: return emptyList()
        val today = startOfDay(now)
        return schedule.filter { item ->
            if (item.origId != null || isArchived(item) || !item.enabled) return@filter false
            if (isOneOff(item)) return@filter item.date == key
            if (isInterval(item)) {
                val n = item.intervalDays ?: 0
                if (n <= 0) return@filter false
                val info = intervalDueInfo(item, records, now) ?: return@filter false
                val due = day(today, max(0, info.daysUntil))
                val gap = ((dayMs0 - due).toDouble() / dayMs).roundToInt()
                return@filter gap >= 0 && gap % n == 0
            }
            isScheduledOn(item.days, dayMs0)
        }.sortedBy { it.time ?: "" }
    }

    /** その日にあった予定（1回だけ・保管済みを含む）。やりなおしコピーは出さない */
    fun itemsOnDay(schedule: List<Item>, records: Records, key: String): List<Item> {
        val dayMs0 = parseDateKey(key) ?: return emptyList()
        val rec = records[key] ?: emptyMap()
        return schedule.filter { item ->
            if (item.origId != null) return@filter false
            if (rec[item.id] != null) return@filter true
            if (isOneOff(item)) return@filter item.date == key
            if (isInterval(item)) {
                // 「どの日にやってもよい」予定なので、登録時の「最後にやった日」より後なら毎日出す
                val anchor = item.anchorDate?.takeIf { isDateKey(it) }
                return@filter item.enabled && (anchor == null || key > anchor)
            }
            item.enabled && isScheduledOn(item.days, dayMs0)
        }
    }

    /**
     * ◯日ごとの予定を「前に済ませていた」とあとから付けるときの候補日。
     * 昨日から遡って最大 maxDays 日ぶん、基準日（最後にやった日）の翌日まで。新しい順
     */
    fun pastDoneCandidates(item: Item, records: Records, now: Long, maxDays: Int = 7): List<String> {
        if (!isInterval(item)) return emptyList()
        val limit = if (maxDays > 0) maxDays else 7
        val anchor = intervalAnchorKey(item, records, now)
        val out = ArrayList<String>()
        var d = startOfDay(now)
        for (i in 0 until limit) {
            d = day(d, -1)
            val k = dateKey(d)
            if (anchor != null && k <= anchor) break
            out.add(k)
        }
        return out
    }

    /**
     * カレンダーの日の印。できなかった日に印は付けない（沈黙が中立）。
     * ids に無い記録は数えない（消した予定の色だけが残る食い違いを防ぐ）
     */
    fun dayMark(records: Records, key: String, ids: List<String>): Mark? {
        val rec = records[key] ?: return null
        val vals = rec.filterKeys { ids.contains(it) }.values
        if (vals.contains(Mark.DONE)) return Mark.DONE
        return if (vals.contains(Mark.SKIP)) Mark.SKIP else null
    }

    // ---- こっそりお祝い（隠し機能。掲載文・説明には書かない） ----

    /** ストリークの節目か。祝うだけで、切れても何も言わない */
    fun isStreakMilestone(streak: Int): Boolean = streak in listOf(3, 7, 14, 30, 50, 100, 200, 365)

    /** 今日の予定がぜんぶ「できた」か。スキップが混ざった日は祝わない */
    fun allDoneToday(schedule: List<Item>, records: Records, now: Long): Boolean {
        val key = dateKey(now)
        val rec = records[key] ?: emptyMap()
        var count = 0
        for (item in schedule) {
            if (item.origId != null || isArchived(item) || !item.enabled) continue
            val due = when {
                isInterval(item) -> (intervalDueInfo(item, records, now)?.daysUntil ?: 0) <= 0
                isOneOff(item) -> item.date == key
                else -> isScheduledOn(item.days, now)
            }
            if (!due && rec[item.id] == null) continue
            count += 1
            if (rec[item.id] != Mark.DONE) return false
        }
        return count > 0
    }

    // ---- 予告（時間が近づいたら知らせる） ----

    /** 既定は10分前。Googleカレンダーの既定に寄せた */
    val preNoticeDefault = PreNotice(on = true, minutes = 10)

    fun preNoticeSettings(on: Boolean?, minutes: Int?): PreNotice {
        val isOn = on ?: preNoticeDefault.on
        val m = minutes ?: 0
        val valid = m > 0 && m <= 120
        return PreNotice(isOn, if (valid) m else preNoticeDefault.minutes)
    }

    /**
     * 予告を出す時刻（ミリ秒）。出さない場合は null。
     * さかのぼって出さない（寝ていて過ぎた予告を起動直後に浴びせない＝責めない設計）
     */
    fun preNoticeAt(nextMs: Double?, on: Boolean?, minutes: Int?, nowMs: Double): Double? {
        val s = preNoticeSettings(on, minutes)
        if (!s.on || nextMs == null || !nextMs.isFinite()) return null
        val at = nextMs - s.minutes.toDouble() * 60000
        return if (at <= nowMs) null else at
    }
}
