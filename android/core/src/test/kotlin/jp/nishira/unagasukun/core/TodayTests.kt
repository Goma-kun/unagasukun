package jp.nishira.unagasukun.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import kotlin.random.Random

/** iOS の TodayTests.swift を移したもの。並びは拡張機能（sidepanel.js の groupOf）と同じでなければならない */
class TodayTests {
    private fun at(h: Int, m: Int = 0): Long =
        LocalDateTime.of(2026, 9, 21, h, m).atZone(Logic.zone).toInstant().toEpochMilli()

    @Test fun groupOrder() {
        val now = at(15)
        val schedule = listOf(
            Item("past", "朝の分", time = "07:30"),
            Item("future", "夜の分", time = "20:00"),
            Item("any", "いつでも", anytime = true),
            Item("block", "作業", time = "14:00", endTime = "16:00"),
            Item("due", "点滴", time = "09:00", intervalDays = 3, noticeDays = 3, anchorDate = "2026-09-18"),
            Item("soon", "明日の点滴", time = "09:00", intervalDays = 3, noticeDays = 3, anchorDate = "2026-09-19"),
        )
        val (todo, done) = Today.entries(schedule, emptyMap(), now)
        assertTrue(done.isEmpty())
        assertEquals(listOf("block", "past", "any", "due", "future"), todo.map { it.item.id })
        assertEquals(TodayGroup.READY, todo.first { it.item.id == "due" }.group)
        assertEquals(TodayGroup.OVERDUE, todo.first { it.item.id == "past" }.group)
        assertEquals(TodayGroup.ACTIVE, todo.first { it.item.id == "block" }.group)
    }

    @Test fun sameTimeItemsAreGroupedByTag() {
        val schedule = listOf(
            Item("buy1", "牛乳", anytime = true, tagId = "shop"),
            Item("play", "映画", anytime = true, tagId = "play"),
            Item("buy2", "洗剤", anytime = true, tagId = "shop"),
            Item("none", "ラベルなし", anytime = true),
            Item("late", "夜の買い物", time = "20:00", tagId = "shop"),
            Item("early", "朝の遊び", time = "19:00", tagId = "play"),
        )
        val (todo, _) = Today.entries(schedule, emptyMap(), at(15), tagOrder = listOf("shop", "play"))
        assertEquals(listOf("buy1", "buy2", "play", "none", "early", "late"), todo.map { it.item.id })
    }

    @Test fun recordedItemsMoveToDone() {
        val now = at(15)
        val schedule = listOf(Item("a", time = "07:30"), Item("b", time = "20:00"))
        val (todo, done) = Today.entries(schedule, mapOf(Logic.dateKey(now) to mapOf("a" to Mark.DONE)), now)
        assertEquals(listOf("b"), todo.map { it.item.id })
        assertEquals(listOf("a"), done.map { it.item.id })
        assertEquals(TodayGroup.RESOLVED, done.first().group)
    }

    @Test fun anytimeNeverBecomesOverdue() {
        val (todo, _) = Today.entries(listOf(Item("a", "本を読む", anytime = true)), emptyMap(), at(23, 50))
        assertEquals(TodayGroup.READY, todo.first().group)
    }

    @Test fun intervalAppearsOnlyFromDueDay() {
        val item = Item("drip", "点滴", time = "09:00", intervalDays = 4, noticeDays = 3, anchorDate = "2026-09-18")
        assertTrue(Today.entries(listOf(item), emptyMap(), at(15)).todo.isEmpty())
        val dueDay = LocalDateTime.of(2026, 9, 22, 15, 0).atZone(Logic.zone).toInstant().toEpochMilli()
        assertEquals(listOf("drip"), Today.entries(listOf(item), emptyMap(), dueDay).todo.map { it.item.id })
        val late = LocalDateTime.of(2026, 9, 24, 15, 0).atZone(Logic.zone).toInstant().toEpochMilli()
        assertEquals(listOf("drip"), Today.entries(listOf(item), emptyMap(), late).todo.map { it.item.id })
    }

    @Test fun disabledAndArchivedAreHidden() {
        val schedule = listOf(Item("off", time = "07:30", enabled = false), Item("arch", time = "07:30", archived = true))
        val (todo, done) = Today.entries(schedule, emptyMap(), at(15))
        assertTrue(todo.isEmpty() && done.isEmpty())
    }
}

class LookBackTests {
    private fun d(y: Int, m: Int, day: Int): LocalDate = LocalDate.of(y, m, day)
    private fun ms(y: Int, m: Int, day: Int): Long = d(y, m, day).atStartOfDay(Logic.zone).toInstant().toEpochMilli()

    @Test fun monthGridPadsToSunday() {
        val cells = LookBack.monthGrid(d(2026, 9, 15))
        assertEquals(2 + 30, cells.size)
        assertNull(cells[0]); assertNull(cells[1])
        assertEquals("2026-09-01", Logic.dateKey(cells[2]!!))
        assertEquals("2026-09-30", Logic.dateKey(cells.last()!!))
    }

    @Test fun tileWeeksEndThisWeek() {
        val now = ms(2026, 9, 21)
        val weeks = LookBack.tileWeeks(now, 12)
        assertEquals(13, weeks.size)
        assertTrue(weeks.all { it.size == 7 })
        assertEquals("2026-09-20", Logic.dateKey(weeks.last()[0]))
        assertEquals("2026-09-26", Logic.dateKey(weeks.last().last()))
        assertEquals("2026-09-19", Logic.dateKey(weeks[11].last()))
        assertTrue(weeks.all { Logic.jsWeekday(it[0]) == 0 })
        val past = LookBack.tileWeeks(now, 12, includeCurrent = false)
        assertEquals(12, past.size)
        assertEquals("2026-09-19", Logic.dateKey(past.last().last()))
    }

    @Test fun monthLabelColumns() {
        val weeks = LookBack.tileWeeks(ms(2026, 9, 22), 12)
        assertEquals("2026-06-28", Logic.dateKey(weeks[0][0]))
        val labels = LookBack.monthLabelColumns(weeks)
        assertEquals(listOf(1, 5, 10), labels.map { it.column })
        assertEquals(listOf(7, 8, 9), labels.map { it.sunday.monthValue })
        val weeks2 = LookBack.tileWeeks(ms(2026, 9, 15), 12)
        assertEquals("2026-06-21", Logic.dateKey(weeks2[0][0]))
        assertEquals(listOf(0, 2, 6, 11), LookBack.monthLabelColumns(weeks2).map { it.column })
    }

    @Test fun futureTilesAreEmpty() {
        val records = mapOf("2026-09-25" to mapOf("a" to Mark.DONE))
        assertNull(LookBack.tileMark(Item("a"), records, d(2026, 9, 25), ms(2026, 9, 21)))
    }

    @Test fun oneOffItemsAreNotTiled() {
        val schedule = listOf(Item("once", date = "2026-09-20"), Item("daily", time = "07:00"))
        assertEquals(listOf("daily"), LookBack.tileItems(schedule).map { it.id })
    }
}

class DescribeTests {
    @Test fun rhythmSaysOncePerNDaysAndGap() {
        assertEquals("4日に1回（間は3日空きます）", Describe.rhythm(4))
        assertEquals("3日に1回（間は2日空きます）", Describe.rhythm(3))
        assertEquals("1日に1回（毎日）", Describe.rhythm(1))
    }

    @Test fun scheduleTextUsesRhythm() {
        val item = Item("a", "点滴", time = "09:00", intervalDays = 4, anchorDate = "2026-09-21")
        val now = LocalDateTime.of(2026, 9, 22, 10, 0).atZone(Logic.zone).toInstant().toEpochMilli()
        assertEquals("4日に1回（間は3日空きます）・次は 9/25(金)・09:00", Describe.schedule(item, now = now))
    }

    @Test fun englishDates() {
        val d = LocalDate.of(2026, 10, 10)
        assertEquals("10/10(土)", DateText.short(d, java.util.Locale.JAPAN))
        assertEquals("Sat, 10/10", DateText.short(d, java.util.Locale.US))
        assertEquals("October 2026", DateText.monthTitle(d, java.util.Locale.US))
        assertEquals("2026年10月", DateText.monthTitle(d, java.util.Locale.JAPAN))
        assertEquals(listOf("日", "月", "火", "水", "木", "金", "土"), DateText.weekdayNames(java.util.Locale.JAPAN))
        assertEquals("S", DateText.weekdayInitials(java.util.Locale.US)[0])
    }
}

class DayListsTests {
    @Test fun intervalNotDueGoesToOthers() {
        val daily = Item("d", "独り言", anytime = true)
        val drip = Item("drip", "点滴", intervalDays = 4, anchorDate = "2026-09-25")
        val a = LookBack.dayLists(listOf(daily, drip), emptyMap(), "2026-09-26")
        assertEquals(listOf("d"), a.main.map { it.id })
        assertEquals(listOf("drip"), a.others.map { it.id })
        val b = LookBack.dayLists(listOf(daily, drip), emptyMap(), "2026-09-29")
        assertEquals(listOf("d", "drip"), b.main.map { it.id })
        assertTrue(b.others.isEmpty())
        val c = LookBack.dayLists(listOf(daily, drip), mapOf("2026-09-26" to mapOf("drip" to Mark.DONE)), "2026-09-26")
        assertEquals(listOf("d", "drip"), c.main.map { it.id })
    }
}

class PlannedOnDayTests {
    private fun d(y: Int, m: Int, day: Int): Long =
        LocalDateTime.of(y, m, day, 10, 0).atZone(Logic.zone).toInstant().toEpochMilli()

    @Test fun oneOffWeeklyAndDisabled() {
        val now = d(2026, 9, 26)
        val schedule = listOf(
            Item("once", "集荷", time = "14:00", date = "2026-09-28"),
            Item("mon", "ジム", time = "10:30", days = listOf(1)),
            Item("off", "休み中", time = "06:00", enabled = false),
            Item("any", "いつでも", days = listOf(1), anytime = true),
        )
        assertEquals(listOf("any", "mon", "once"), Logic.plannedOnDay(schedule, emptyMap(), "2026-09-28", now).map { it.id })
        assertTrue(Logic.plannedOnDay(schedule, emptyMap(), "2026-09-29", now).isEmpty())
    }

    @Test fun intervalRepeatsFromDueDate() {
        val now = d(2026, 9, 26)
        val drip = Item("drip", "点滴", intervalDays = 4, anchorDate = "2026-09-25")
        assertTrue(Logic.plannedOnDay(listOf(drip), emptyMap(), "2026-09-28", now).isEmpty())
        assertEquals(listOf("drip"), Logic.plannedOnDay(listOf(drip), emptyMap(), "2026-09-29", now).map { it.id })
        assertTrue(Logic.plannedOnDay(listOf(drip), emptyMap(), "2026-09-30", now).isEmpty())
        assertEquals(listOf("drip"), Logic.plannedOnDay(listOf(drip), emptyMap(), "2026-10-03", now).map { it.id })
        assertEquals(listOf("drip"), Logic.plannedOnDay(listOf(drip), emptyMap(), "2026-10-07", now).map { it.id })
    }

    @Test fun overdueIntervalStartsToday() {
        val now = d(2026, 9, 26)
        val drip = Item("drip", "点滴", intervalDays = 3, anchorDate = "2026-09-10")
        assertEquals(listOf("drip"), Logic.plannedOnDay(listOf(drip), emptyMap(), "2026-09-26", now).map { it.id })
        assertEquals(listOf("drip"), Logic.plannedOnDay(listOf(drip), emptyMap(), "2026-09-29", now).map { it.id })
        assertTrue(Logic.plannedOnDay(listOf(drip), emptyMap(), "2026-09-28", now).isEmpty())
    }
}

class CheerTests {
    private fun at(y: Int, m: Int, d: Int): Long =
        LocalDateTime.of(y, m, d, 12, 0).atZone(Logic.zone).toInstant().toEpochMilli()

    @Test fun allDoneWinsAndThrowsParty() {
        val a = Item("a", time = "07:00"); val b = Item("b", time = "20:00")
        val now = at(2026, 9, 24)
        val records = mapOf(Logic.dateKey(now) to mapOf("a" to Mark.DONE, "b" to Mark.DONE))
        val c = CheerLogic.afterDone(b, listOf(a, b), records, now, Random(0))
        assertTrue(c.party)
        assertTrue(c.emoji != null)
        assertTrue(c.text.contains("ぜんぶできました"))
    }

    @Test fun skipMixedDayIsNotAParty() {
        val a = Item("a", time = "07:00"); val b = Item("b", time = "20:00")
        val now = at(2026, 9, 24)
        val records = mapOf(Logic.dateKey(now) to mapOf("a" to Mark.SKIP, "b" to Mark.DONE))
        val c = CheerLogic.afterDone(b, listOf(a, b), records, now, Random(7))
        assertFalse(c.party)
        assertTrue(CheerLogic.praises.contains(c.text))
    }

    @Test fun streakMilestone() {
        val a = Item("a", time = "07:00"); val other = Item("o", time = "21:00")
        val now = at(2026, 9, 24)
        val records = (0 until 3).associate { Logic.dateKey(Logic.day(now, -it)) to mapOf("a" to Mark.DONE) }
        val c = CheerLogic.afterDone(a, listOf(a, other), records, now, Random(0))
        assertEquals("3日つづいています。おめでとう！", c.text)
        assertFalse(c.party)
    }

    @Test fun oneOffHasNoMilestone() {
        val a = Item("a", time = "07:00", date = "2026-09-24"); val other = Item("o", time = "21:00")
        val now = at(2026, 9, 24)
        val records = (0 until 3).associate { Logic.dateKey(Logic.day(now, -it)) to mapOf("a" to Mark.DONE) }
        val c = CheerLogic.afterDone(a, listOf(a, other), records, now, Random(7))
        assertTrue(CheerLogic.praises.contains(c.text))
    }
}
