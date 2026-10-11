package jp.nishira.unagasukun.core

import java.time.LocalDate

/** カレンダーとふりかえりのタイル（iOS の LookBack.swift と同じ） */
object LookBack {

    /**
     * 月のカレンダーに並べる日。週の頭（日曜）で揃えるため、先頭を null で埋める。
     * 末尾は埋めない（空の行を作らないため）
     */
    fun monthGrid(month: LocalDate): List<LocalDate?> {
        val first = month.withDayOfMonth(1)
        val lead = Logic.jsWeekday(first)   // 日曜=0
        val cells = ArrayList<LocalDate?>()
        repeat(lead) { cells.add(null) }
        for (i in 0 until first.lengthOfMonth()) cells.add(first.plusDays(i.toLong()))
        return cells
    }

    /**
     * ふりかえりのタイル。先週までの `count` 週に、**今週の列を足して**並べる（右端が今週）。
     * 今週のまだ来ていない日は画面側で点線の枠にして、四角の形は崩さない
     */
    fun tileWeeks(now: Long, count: Int = 12, includeCurrent: Boolean = true): List<List<LocalDate>> {
        val today = Logic.localDate(now)
        val thisWeekStart = today.minusDays(Logic.jsWeekday(today).toLong())
        val columns = if (includeCurrent) count + 1 else count
        return (0 until columns).map { w ->
            val start = thisWeekStart.minusDays(((count - w) * 7).toLong())
            (0 until 7).map { start.plusDays(it.toLong()) }
        }
    }

    data class MonthLabel(val column: Int, val sunday: LocalDate)

    /**
     * タイルの上に月名を出す列。月が変わった最初の週に付ける。
     * 左端の列は、隣の列で月が変わるなら付けない（「6月 7月」と詰まって読めないため）
     */
    fun monthLabelColumns(weeks: List<List<LocalDate>>): List<MonthLabel> {
        fun month(w: Int) = weeks[w][0].monthValue
        val out = ArrayList<MonthLabel>()
        for (w in weeks.indices) {
            val startsMonth = w == 0 || month(w) != month(w - 1)
            val nextStartsMonth = w + 1 < weeks.size && month(w + 1) != month(w)
            if (startsMonth && !(w == 0 && nextStartsMonth)) out.add(MonthLabel(w, weeks[w][0]))
        }
        return out
    }

    /**
     * タイル1マスの色分け。**「できた」だけ着色する。**
     * できなかった日には何も出さない（沈黙が中立）。予定のない曜日も同じ
     */
    fun tileMark(item: Item, records: Records, day: LocalDate, now: Long): Mark? {
        if (day > Logic.localDate(now)) return null   // 未来は空
        return records[Logic.dateKey(day)]?.get(item.id)
    }

    /** ふりかえりのタイルに出す予定（繰り返しのものだけ）。1回だけはカレンダー側で見てもらう */
    fun tileItems(schedule: List<Item>): List<Item> =
        schedule.filter { !Logic.isOneOff(it) && it.origId == null && !Logic.isArchived(it) }

    data class DayLists(val main: List<Item>, val others: List<Item>)

    /**
     * カレンダーで日を選んだときの一覧。
     * `Logic.itemsOnDay` は「◯日ごと」を毎日出すが、今日の予定に無いものまで同じ顔で並ぶと「今日やるの？」と読める。
     * その日に記録があるか、その日の時点で目安日が来ているものだけを `main` に、
     * 残りの「◯日ごと」は `others`（済ませていたら付けられる控えめな欄）に分ける。
     * **拡張機能の `itemsOnDay` は変えない**（突き合わせテストの対象なので、ここで分ける）
     */
    fun dayLists(schedule: List<Item>, records: Records, key: String): DayLists {
        val all = Logic.itemsOnDay(schedule, records, key)
        val day = Logic.parseDateKey(key) ?: return DayLists(all, emptyList())
        val rec = records[key] ?: emptyMap()
        val main = ArrayList<Item>(); val others = ArrayList<Item>()
        for (item in all) {
            val info = if (Logic.isInterval(item) && rec[item.id] == null) Logic.intervalDueInfo(item, records, day) else null
            if (info != null && info.daysUntil > 0) others.add(item) else main.add(item)
        }
        return DayLists(main, others)
    }
}
