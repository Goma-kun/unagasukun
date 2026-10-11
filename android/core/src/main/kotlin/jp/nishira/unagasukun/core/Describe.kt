package jp.nishira.unagasukun.core

import kotlin.math.max

/**
 * 予定の繰り返しを言い切る（iOS の Describe.swift と同じ）。
 *
 * 登録フォームのプレビュー帯と、登録済み一覧の両方がこれを使う。
 * **同じ予定が場所によって違う言い方をされると、同じものだと分からなくなる。**
 * 言葉は `L10n.strings`（端末の言語）から取る
 */
object Describe {

    /** 曜日の短い名前（端末の言語で。ja は「日・月…」、en は「Sun・Mon…」） */
    val weekdayNames: List<String> get() = DateText.weekdayNames()

    /** タイルの行頭など幅 16dp に収める曜日（ja は「日」、en は「S」） */
    val weekdayInitials: List<String> get() = DateText.weekdayInitials()

    val sep: String get() = L10n.strings.sep

    /** 「毎日 07:30」「毎週 月・水 20:00」「3日ごと・次は 9/24(木)」「1回だけ 9/25(金)」「いつでも」 */
    fun schedule(item: Item, records: Records = emptyMap(), now: Long = System.currentTimeMillis()): String {
        val s = L10n.strings
        val parts = ArrayList<String>()

        if (Logic.isInterval(item)) {
            parts.add(rhythm(item.intervalDays ?: 0))
            Logic.intervalDueInfo(item, records, now)?.let { info ->
                val due = Logic.day(now, max(0, info.daysUntil))
                parts.add(s.nextIs(short(due)))
            }
        } else if (Logic.isOneOff(item)) {
            val d = Logic.parseDateKey(item.date)
            parts.add(if (d != null) s.onceOn(short(d)) else s.once)
        } else {
            val days = item.days
            if (!days.isNullOrEmpty() && days.toSet().size < 7) {
                parts.add(s.weeklyOn(days.sorted().joinToString(s.sep) { weekdayNames[it] }))
            } else {
                // 曜日を7つ全部選んだものは「毎日」。拡張機能の repeatText() と同じ言い方にする
                parts.add(s.daily)
            }
        }

        if (Logic.isAnytime(item)) {
            parts.add(s.anytime)
            item.targetMin?.let { parts.add(s.targetMin(it)) }
        } else {
            val t = item.time
            if (t != null) {
                val e = item.endTime
                if (e != null && Logic.isValidEndTime(t, e)) parts.add(s.timeRange(t, e)) else parts.add(t)
            }
        }

        return parts.joinToString(s.sep)
    }

    /**
     * 「3日に1回（間は2日空きます）」。
     * 「3日ごと」は読みが1つでも、「3日おき」「3日空けて」で考える人には1日ずれて伝わる。
     * **拡張機能の `intervalText` / `intervalGap` と同じ言い方**
     */
    fun rhythm(n: Int): String = L10n.strings.rhythm(n)

    /** 「9/24(木)」（en: "Thu, 9/24"） */
    fun short(ms: Long): String = DateText.short(ms)

    /** 「2026/10/30(金)」（en: "Fri, 10/30/2026"） */
    fun long(ms: Long): String = DateText.long(ms)

    /** 「2026年10月」（en: "October 2026"） */
    fun monthTitle(ms: Long): String = DateText.monthTitle(ms)

    /** 「10月」（en: "Oct"） */
    fun monthShort(ms: Long): String = DateText.monthShort(ms)

    /** 時刻の見出し。「いつでも」「09:00」「14:00〜16:00」（拡張機能の timeText() と同じ） */
    fun timeText(item: Item): String {
        if (Logic.isAnytime(item)) return L10n.strings.anytime
        val t = item.time ?: return "—"
        val e = item.endTime
        return if (e != null && Logic.isValidEndTime(t, e)) L10n.strings.timeRange(t, e) else t
    }
}
