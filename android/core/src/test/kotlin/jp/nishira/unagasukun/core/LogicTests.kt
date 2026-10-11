package jp.nishira.unagasukun.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.LocalDateTime

/** 移植そのものの突き合わせは ../test/parity_android.mjs が担う。ここには「Kotlin 側だけで壊れうるところ」を置く */
class LogicTests {
    private fun d(y: Int, m: Int, day: Int, h: Int = 0, min: Int = 0): Long =
        LocalDateTime.of(y, m, day, h, min).atZone(Logic.zone).toInstant().toEpochMilli()

    @Test fun dateKeyIsZeroPadded() {
        assertEquals("2026-01-05", Logic.dateKey(d(2026, 1, 5)))
    }

    @Test fun weekdayMatchesJavaScript() {
        assertEquals(4, Logic.jsWeekday(d(2026, 8, 13)))
        assertEquals(0, Logic.jsWeekday(d(2026, 8, 16)))
    }

    @Test fun parseTimeRejectsOutOfRange() {
        assertNotNull(Logic.parseTime("23:59"))
        assertNull(Logic.parseTime("24:00"))
        assertNull(Logic.parseTime("9:00"))
        assertNull(Logic.parseTime(null))
        assertEquals(24 to 0, Logic.parseTimeParts("24:00"))
    }

    @Test fun endOfDayIsLastMillisecond() {
        val end = Logic.endOfDay(d(2026, 8, 13))
        assertTrue(end < d(2026, 8, 14))
        assertTrue(end > d(2026, 8, 13, 23, 59))
        assertEquals(d(2026, 8, 14) - 1, end)
    }

    @Test fun atRollsOverLikeJavaScriptDate() {
        assertEquals(d(2026, 8, 14), Logic.at(d(2026, 8, 13, 10), 24, 0))
        assertEquals(d(2026, 8, 14, 2, 10), Logic.at(d(2026, 8, 13), 25, 70))
    }

    @Test fun dayPlusCrossesMonth() {
        assertEquals("2026-09-04", Logic.dateKey(Logic.day(d(2026, 8, 30), 5)))
        assertEquals("2026-02-28", Logic.dateKey(Logic.day(d(2026, 3, 1), -1)))
    }

    @Test fun parseDateKeyRollsOverAndRejectsGarbage() {
        assertNull(Logic.parseDateKey("x"))
        assertNull(Logic.parseDateKey("2026-8-13"))
        assertEquals("2026-08-13", Logic.dateKey(Logic.parseDateKey("2026-08-13")!!))
        assertEquals("2027-01-01", Logic.dateKey(Logic.parseDateKey("2026-13-01")!!))
    }
}
