package jp.nishira.unagasukun.core

/**
 * 「今日の予定」でのカードの置きどころ。**拡張機能 sidepanel.js の `groupOf()` をそのまま移した。**
 * 数字が小さいほど上に出る。
 *
 * 「時間が過ぎたのに記録がない」は上から 2 番目（2026-10-04）。通知が鳴るのは時刻のある予定で、
 * 鳴ったあと記録が付くまでは必ずこの組に入る。「いつでも」の下に沈めると、開いても探すことになる。
 * **責めないための赤は使わない**という方針は変えない（枠は橙のまま）
 */
enum class TodayGroup(val order: Int) {
    /** 時間帯のまっただ中 */
    ACTIVE(0),
    /** 時間が過ぎたのに記録がない。**通知が鳴ったあとのものはここに来る** */
    OVERDUE(1),
    /** 「いつでも」と、目安日が来ている「◯日ごと」。いま着手できるもの */
    READY(2),
    /** まだ時間が来ていない */
    UPCOMING(3),
    /** 「◯日ごと」の予告中。アプリでは目安日の当日から出すので entries() には現れない（拡張機能との対応で残す） */
    HEADS_UP(4),
    /** できた・休んだ */
    RESOLVED(5),
}

data class TodayEntry(
    val item: Item,
    /** 今日の記録。まだなら null */
    val mark: Mark?,
    val group: TodayGroup,
)

data class TodayLists(val todo: List<TodayEntry>, val done: List<TodayEntry>)

object Today {

    /**
     * 今日の画面に出すものを「これから」と「対応済み」に分けて返す。
     *
     * 並びは 進行中 → 未対応 → いつでも → これから → 予告中 で、各組の中は時刻順。
     * **拡張機能・iPhone 版と同じ並びでなければならない。**
     */
    fun entries(
        schedule: List<Item>, records: Records, now: Long, tagOrder: List<String> = emptyList(),
    ): TodayLists {
        val key = Logic.dateKey(now)
        val rec = records[key] ?: emptyMap()
        val z = Logic.zdt(now)
        val nowHM = "%02d:%02d".format(z.hour, z.minute)

        val entries = ArrayList<TodayEntry>()

        for (item in schedule) {
            if (item.origId != null || Logic.isArchived(item) || !item.enabled) continue

            val mark = rec[item.id]
            val group = groupOf(item, mark, records, now, nowHM)

            // 今日の予定でないものは出さない（記録が付いているものは「対応済み」に出す）
            if (group != TodayGroup.RESOLVED) {
                val due = when {
                    // 目安日の当日（と過ぎた日）だけ出す。前日から出すと「今日やる」と読めて紛らわしい
                    Logic.isInterval(item) -> (Logic.intervalDueInfo(item, records, now)?.daysUntil ?: 0) <= 0
                    Logic.isOneOff(item) -> item.date == key
                    else -> Logic.isScheduledOn(item.days, now)
                }
                if (!due) continue
            }

            entries.add(TodayEntry(item, mark, group))
        }

        // 並びは 組 → 時刻 → ラベル → 登録順。
        // 同じ時刻（とくに「いつでも」どうし）は、同じラベルが隣り合うようにまとめる。
        // ラベルの順は「ラベルを整える」で並べた順。ラベル無しは最後
        val rank = tagOrder.withIndex().associate { it.value to it.index }
        fun tagRank(item: Item): Int = item.tagId?.let { rank[it] } ?: Int.MAX_VALUE
        val order = schedule.withIndex().associate { it.value.id to it.index }
        val sorted = entries.sortedWith(
            compareBy<TodayEntry> { it.group.order }
                .thenBy { it.item.time ?: "" }
                .thenBy { tagRank(it.item) }
                .thenBy { order[it.item.id] ?: 0 }
        )

        return TodayLists(
            todo = sorted.filter { it.group != TodayGroup.RESOLVED },
            done = sorted.filter { it.group == TodayGroup.RESOLVED },
        )
    }

    private fun groupOf(item: Item, mark: Mark?, records: Records, now: Long, nowHM: String): TodayGroup {
        if (mark != null) return TodayGroup.RESOLVED

        // 時間帯のまっただ中（終了時刻つきの予定）
        val time = item.time
        val end = item.endTime
        if (time != null && end != null && Logic.isValidEndTime(time, end) && time <= nowHM && nowHM < end) {
            return TodayGroup.ACTIVE
        }

        // ◯日ごと：目安日以降は「いつでも」と同じ扱い。まだ先なら一番下
        if (Logic.isInterval(item)) {
            val info = Logic.intervalDueInfo(item, records, now)
            return if ((info?.daysUntil ?: 0) > 0) TodayGroup.HEADS_UP else TodayGroup.READY
        }

        // 「いつでも」は時間切れの概念がないので、未対応にはならない
        if (Logic.isAnytime(item)) return TodayGroup.READY

        return if ((item.time ?: "") > nowHM) TodayGroup.UPCOMING else TodayGroup.OVERDUE
    }
}
