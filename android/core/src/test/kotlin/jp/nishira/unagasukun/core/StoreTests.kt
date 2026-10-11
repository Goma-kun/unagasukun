package jp.nishira.unagasukun.core

import kotlinx.serialization.encodeToString
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.time.LocalDateTime

/** iOS の StoreTests.swift を移したもの（同期の SyncPlan は Android に無いので除く） */
class MergeTests {
    @Test fun recordsAreUnionedNotOverwritten() {
        val a = Snapshot(records = mapOf("2026-09-20" to mapOf("i1" to Mark.DONE)), updatedAt = 200.0)
        val b = Snapshot(records = mapOf("2026-09-21" to mapOf("i1" to Mark.DONE)), updatedAt = 100.0)
        val m = Merge.snapshots(a, b)
        assertEquals(Mark.DONE, m.records["2026-09-20"]?.get("i1"))
        assertEquals(Mark.DONE, m.records["2026-09-21"]?.get("i1"))
    }

    @Test fun doneWinsOverSkip() {
        val a = Snapshot(records = mapOf("2026-09-20" to mapOf("i1" to Mark.DONE)), updatedAt = 100.0)
        val b = Snapshot(records = mapOf("2026-09-20" to mapOf("i1" to Mark.SKIP)), updatedAt = 999.0)
        assertEquals(Mark.DONE, Merge.snapshots(a, b).records["2026-09-20"]?.get("i1"))
        assertEquals(Mark.DONE, Merge.snapshots(b, a).records["2026-09-20"]?.get("i1"))
    }

    @Test fun scheduleTakesTheNewerSide() {
        val old = Snapshot(schedule = listOf(Item("i1"), Item("i2")), updatedAt = 100.0)
        val new = Snapshot(schedule = listOf(Item("i1")), updatedAt = 200.0)
        assertEquals(listOf("i1"), Merge.snapshots(old, new).schedule.map { it.id })
        assertEquals(listOf("i1"), Merge.snapshots(new, old).schedule.map { it.id })
    }

    @Test fun mergeIsOrderIndependentForRecords() {
        val a = Snapshot(records = mapOf("d" to mapOf("x" to Mark.SKIP)), updatedAt = 1.0)
        val b = Snapshot(records = mapOf("d" to mapOf("y" to Mark.DONE)), updatedAt = 2.0)
        assertEquals(Merge.snapshots(a, b).records, Merge.snapshots(b, a).records)
    }

    @Test fun deletionTravelsThroughLog() {
        var a = Snapshot(records = mapOf("2026-09-20" to mapOf("i1" to Mark.DONE)), updatedAt = 100.0)
        val b = a
        a = a.withMark(null, "i1", "2026-09-20", at = 150.0).copy(updatedAt = 150.0)
        assertNull(Merge.snapshots(a, b).records["2026-09-20"]?.get("i1"))
        assertNull(Merge.snapshots(b, a).records["2026-09-20"]?.get("i1"))
    }
}

class NotificationPlanTests {
    private fun now(): Long = LocalDateTime.of(2026, 9, 21, 10, 0).atZone(Logic.zone).toInstant().toEpochMilli()

    @Test fun dailyPlanIsSortedAndCapped() {
        val items = (0 until 10).map { Item("i$it", "予定$it", time = "08:00") }
        val plan = NotificationPlan.build(items, emptyMap(), now(), preNoticeOn = false, horizonDays = 30)
        assertEquals(NotificationPlan.pendingLimit, plan.size)
        assertEquals(plan, plan.sortedWith(compareBy<PlannedNotification> { it.fireAt }.thenBy { it.id }))
    }

    @Test fun doneItemGetsNoNotificationThatDay() {
        val item = Item("i1", "薬", time = "20:00")
        val today = Logic.dateKey(now())
        val without = NotificationPlan.build(listOf(item), emptyMap(), now(), preNoticeOn = false, horizonDays = 1)
        val withDone = NotificationPlan.build(listOf(item), mapOf(today to mapOf("i1" to Mark.DONE)), now(), preNoticeOn = false, horizonDays = 1)
        assertTrue(without.size > withDone.size)
    }

    @Test fun perItemPreNotice() {
        val hospital = Item("h", "はなちゃん病院", time = "14:00", preNoticeMin = 60)
        val plan = NotificationPlan.build(listOf(hospital), emptyMap(), now(), preNoticeOn = true, preNoticeMin = 10, horizonDays = 1)
        assertEquals(listOf(PlannedNotification.Kind.PRE, PlannedNotification.Kind.MAIN), plan.map { it.kind })
        val z = Logic.zdt(plan[0].fireAt)
        assertEquals(listOf(13, 0), listOf(z.hour, z.minute))

        val quiet = Item("q", "静か", time = "20:00", preNoticeMin = 0)
        assertEquals(listOf(PlannedNotification.Kind.MAIN),
            NotificationPlan.build(listOf(quiet), emptyMap(), now(), preNoticeOn = true, preNoticeMin = 10, horizonDays = 1).map { it.kind })

        val usual = Item("u", "ふつう", time = "20:00")
        assertEquals(listOf(PlannedNotification.Kind.PRE, PlannedNotification.Kind.MAIN),
            NotificationPlan.build(listOf(usual), emptyMap(), now(), preNoticeOn = true, preNoticeMin = 10, horizonDays = 1).map { it.kind })
    }

    @Test fun blockGetsStartAndEndNotifications() {
        val item = Item("i1", "ヤマト集荷", time = "14:00", endTime = "16:00")
        val plan = NotificationPlan.build(listOf(item), emptyMap(), now(), preNoticeOn = false, horizonDays = 1)
        assertEquals(listOf(PlannedNotification.Kind.MAIN, PlannedNotification.Kind.END), plan.map { it.kind })
        val z = Logic.zdt(plan[1].fireAt)
        assertEquals(listOf(16, 0), listOf(z.hour, z.minute))

        val done = NotificationPlan.build(listOf(item), mapOf(Logic.dateKey(now()) to mapOf("i1" to Mark.DONE)), now(), preNoticeOn = false, horizonDays = 1)
        assertTrue(done.isEmpty())

        val bad = Item("i2", "x", time = "14:00", endTime = "13:00")
        assertEquals(listOf(PlannedNotification.Kind.MAIN),
            NotificationPlan.build(listOf(bad), emptyMap(), now(), preNoticeOn = false, horizonDays = 1).map { it.kind })
    }

    @Test fun intervalItemPlansOnlyOneOccurrence() {
        val item = Item("i1", "点滴", time = "09:00", intervalDays = 3, anchorDate = "2026-09-20")
        val plan = NotificationPlan.build(listOf(item), emptyMap(), now(), preNoticeOn = false, horizonDays = 30)
        assertEquals(1, plan.count { it.kind == PlannedNotification.Kind.MAIN })
    }

    @Test fun preNoticeIsAddedWhenOn() {
        val item = Item("i1", "散歩", time = "20:00")
        val plan = NotificationPlan.build(listOf(item), emptyMap(), now(), preNoticeOn = true, preNoticeMin = 10, horizonDays = 1)
        val main = plan.first { it.kind == PlannedNotification.Kind.MAIN }
        val pre = plan.first { it.kind == PlannedNotification.Kind.PRE }
        assertEquals(600_000L, main.fireAt - pre.fireAt)
    }

    @Test fun disabledAndArchivedAreSkipped() {
        val items = listOf(
            Item("off", time = "08:00", enabled = false),
            Item("arch", time = "08:00", archived = true),
            Item("copy", time = "08:00", origId = "i1"),
        )
        assertTrue(NotificationPlan.build(items, emptyMap(), now(), preNoticeOn = false, horizonDays = 3).isEmpty())
    }

    @Test fun titleGetsTagName() {
        val item = Item("a", "牛乳", tagId = "tag-shopping")
        assertEquals("買い物：牛乳", NotificationPlan.title(item, mapOf("tag-shopping" to "買い物")))
        assertEquals("牛乳", NotificationPlan.title(item, emptyMap()))
    }
}

class SnapshotStoreTests {
    private fun tempDir(): File = Files.createTempDirectory("uk").toFile()

    @Test fun saveAndLoadRoundTrip() {
        val dir = tempDir()
        try {
            val store = SnapshotStore(File(dir, "snapshot.json"))
            assertEquals(Snapshot(), store.load())
            val snap = Snapshot(schedule = listOf(Item("i1", "薬", time = "20:00")),
                records = mapOf("2026-09-21" to mapOf("i1" to Mark.DONE)), updatedAt = 123.0)
            store.save(snap)
            assertEquals(snap, store.load())
            // ms は整数で書かれている（指数表記を残さない）
            val text = File(dir, "snapshot.json").readText()
            assertTrue(text, text.contains("\"updatedAt\":123"))
            assertTrue(text, text.contains("\"enabled\":true"))
        } finally { dir.deleteRecursively() }
    }

    @Test fun backupsKeepNewestFive() {
        val dir = tempDir()
        try {
            val store = SnapshotStore(File(dir, "snapshot.json"))
            assertTrue(store.backups().isEmpty())
            val base = 1_700_000_000_000L
            for (i in 0 until 8) store.saveBackup(Snapshot(updatedAt = i.toDouble()), at = base + i)
            val files = store.backups()
            assertEquals(SnapshotStore.backupLimit, files.size)
            assertEquals(7.0, store.loadBackup(files[0]).updatedAt, 0.0)
            assertEquals(3.0, store.loadBackup(files.last()).updatedAt, 0.0)
        } finally { dir.deleteRecursively() }
    }
}

class ImportTests {
    @Test fun decodesExtensionJSONWithMissingBools() {
        val json = """
        {"app":"unagasukun","version":"1.8.0","exportedAt":1790154253562,
         "schedule":[{"id":"a","label":"薬","time":"08:00","days":[],"createdAt":1786724536272},
                     {"id":"b","label":"点滴","time":"09:00","intervalDays":4,"anchorDate":"2026-09-21","detail":"左脚"}],
         "records":{"2026-09-22":{"a":"done"}},
         "notes":{"2026-09-22":{"a":"ok"}}}
        """
        val f = UkJson.decodeFromString(ExportFile.serializer(), json)
        assertEquals(2, f.schedule.size)
        assertTrue(f.schedule[0].enabled)
        assertFalse(f.schedule[0].anytime)
        assertEquals(4, f.schedule[1].intervalDays)
        assertEquals("左脚", f.schedule[1].detail)
    }

    @Test fun importAddsMissingItemsAndKeepsLocalOnes() {
        val local = Snapshot(schedule = listOf(Item("a", "手元で直した名前")),
            records = mapOf("2026-09-20" to mapOf("a" to Mark.SKIP)), updatedAt = 1.0)
        val imported = ExportFile(schedule = listOf(Item("a", "拡張の名前"), Item("b", "点滴")),
            records = mapOf("2026-09-20" to mapOf("a" to Mark.DONE), "2026-09-21" to mapOf("b" to Mark.DONE)))
        val m = Merge.importing(local, imported)
        assertEquals(listOf("a", "b"), m.schedule.map { it.id })
        assertEquals("手元で直した名前", m.schedule[0].label)
        assertEquals(Mark.DONE, m.records["2026-09-20"]?.get("a"))
        assertEquals(Mark.DONE, m.records["2026-09-21"]?.get("b"))
    }

    @Test fun importBringsNotes() {
        val json = """{"schedule":[],"records":{},"notes":{"2026-09-20":{"a":"休憩"},"2026-09-21":{"a":"別の作業"}}}"""
        val f = UkJson.decodeFromString(ExportFile.serializer(), json)
        val local = Snapshot().withNote("気分が乗らず", "a", "2026-09-21", at = 1.0)
        val m = Merge.importing(local, f)
        assertEquals("休憩", m.notes["2026-09-20"]?.get("a"))
        assertEquals("気分が乗らず", m.notes["2026-09-21"]?.get("a"))
    }

    @Test fun importIntoEmptyTakesEverything() {
        val imported = ExportFile(schedule = listOf(Item("x"), Item("y")), records = mapOf("d" to mapOf("x" to Mark.DONE)))
        val m = Merge.importing(Snapshot(), imported)
        assertEquals(2, m.schedule.size)
        assertEquals(1, m.records.size)
    }

    /** iOS の snapshot.json（小数つきの ms・recordLog の mark が null）も読める */
    @Test fun decodesIosSnapshot() {
        val json = """{"schedule":[{"id":"a","label":"x","enabled":true,"anytime":false,"archived":false}],
            "records":{},"updatedAt":1759999999999.123,"recordLog":{"2026-09-20|a":{"mark":null,"at":1759999999999.5}},
            "notes":{},"noteLog":{},"tags":[]}"""
        val s = UkJson.decodeFromString(Snapshot.serializer(), json)
        assertEquals(1759999999999.123, s.updatedAt, 0.0)
        assertNull(s.recordLog["2026-09-20|a"]?.mark)
    }
}

class TagTests {
    @Test fun snapshotWithoutTagsDecodesAndUsesDefaults() {
        val s = UkJson.decodeFromString(Snapshot.serializer(), """{"schedule":[{"id":"a","label":"x"}],"records":{}}""")
        assertEquals(emptyList<Tag>(), s.tags)
        assertEquals(Tag.defaults(), s.effectiveTags)
        assertNull(s.schedule[0].tagId)
    }

    @Test fun itemTagIdRoundTripsAndOldTagIdResolvesToNil() {
        var s = Snapshot(schedule = listOf(Item("a", "牛乳", tagId = "tag-shopping")))
        val back = UkJson.decodeFromString(Snapshot.serializer(), UkJson.encodeToString(s))
        assertEquals("tag-shopping", back.schedule[0].tagId)
        assertEquals("買い物", back.tag(back.schedule[0])?.name)
        s = s.copy(tags = listOf(Tag("t1", "猫", "teal")))
        assertNull(s.tag(s.schedule[0]))
    }

    @Test fun mergeTakesTagsFromTheNewerSide() {
        val old = Snapshot(updatedAt = 1.0, tags = listOf(Tag("t1", "古い", "red")))
        val new = Snapshot(updatedAt = 2.0, tags = listOf(Tag("t1", "新しい", "blue")))
        assertEquals("新しい", Merge.snapshots(old, new).tags.first().name)
        assertEquals("新しい", Merge.snapshots(new, old).tags.first().name)
    }

    @Test fun importKeepsLocalTags() {
        val local = Snapshot(tags = listOf(Tag("t1", "猫", "teal")))
        val file = UkJson.decodeFromString(ExportFile.serializer(), """{"schedule":[],"records":{}}""")
        assertEquals(1, Merge.importing(local, file).tags.size)
    }
}
