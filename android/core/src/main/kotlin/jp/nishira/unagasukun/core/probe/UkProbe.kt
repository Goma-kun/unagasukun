package jp.nishira.unagasukun.core.probe

import jp.nishira.unagasukun.core.Item
import jp.nishira.unagasukun.core.Logic
import jp.nishira.unagasukun.core.Mark
import jp.nishira.unagasukun.core.Records
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import kotlinx.serialization.json.put
import kotlin.system.exitProcess

// JS版と答えを突き合わせるためだけの入口（iOS の uk-probe と同じ入出力）。
// 標準入力に {"cases":[...]} を受け取り、1件ずつ Logic を呼んで結果をJSONで返す。
// アプリからは使わない。../../test/parity_android.mjs が使う。

private fun JsonElement?.str(): String? = (this as? JsonPrimitive)?.takeIf { it.isString }?.content
private fun JsonElement?.int(): Int? = (this as? JsonPrimitive)?.takeIf { !it.isString }?.let { it.longOrNull?.toInt() ?: it.doubleOrNull?.toInt() }
private fun JsonElement?.dbl(): Double? = (this as? JsonPrimitive)?.takeIf { !it.isString }?.doubleOrNull
private fun JsonElement?.bool(): Boolean? = (this as? JsonPrimitive)?.takeIf { !it.isString }?.booleanOrNull
private fun JsonElement?.ints(): List<Int>? = (this as? JsonArray)?.mapNotNull { it.int() }
private fun JsonElement?.obj(): JsonObject? = this as? JsonObject

private fun item(d: JsonObject?): Item {
    val o = d ?: JsonObject(emptyMap())
    return Item(
        id = o["id"].str() ?: "",
        label = o["label"].str() ?: "",
        time = o["time"].str(),
        date = o["date"].str(),
        days = o["days"].ints(),
        enabled = o["enabled"].bool() ?: (o["enabled"] == null),
        anytime = o["anytime"].bool() ?: false,
        targetMin = o["targetMin"].int(),
        intervalDays = o["intervalDays"].int(),
        noticeDays = o["noticeDays"].int(),
        anchorDate = o["anchorDate"].str(),
        archived = o["archived"].bool() ?: false,
        origId = o["origId"].str(),
        endTime = o["endTime"].str(),
    )
}

private fun records(d: JsonObject?): Records {
    val out = HashMap<String, Map<String, Mark>>()
    for ((k, v) in d ?: return out) {
        val inner = v.obj() ?: continue
        val marks = HashMap<String, Mark>()
        for ((id, m) in inner) Mark.of(m.str())?.let { marks[id] = it }
        out[k] = marks
    }
    return out
}

private fun nowOf(c: JsonObject): Long = c["now"].dbl()?.toLong() ?: 0L

/** 無限大と NaN は JSON に載らないので、両側とも文字列で表す。整数で収まるなら整数で出す */
private fun msOut(v: Double): JsonElement = when {
    v.isNaN() -> JsonPrimitive("NaN")
    v.isInfinite() -> JsonPrimitive("Infinity")
    v == Math.floor(v) -> JsonPrimitive(v.toLong())
    else -> JsonPrimitive(v)
}

private fun run(c: JsonObject): JsonElement {
    val fn = c["fn"].str() ?: ""
    val it = item(c["item"].obj())
    val rec = records(c["records"].obj())
    val now = nowOf(c)
    val sched = (c["schedule"] as? JsonArray)?.map { item(it.obj()) } ?: emptyList()

    return when (fn) {
        "dateKey" -> JsonPrimitive(Logic.dateKey(now))
        "isScheduledOn" -> JsonPrimitive(Logic.isScheduledOn(c["days"].ints(), now))
        "isOneOff" -> JsonPrimitive(Logic.isOneOff(it))
        "isAnytime" -> JsonPrimitive(Logic.isAnytime(it))
        "isInterval" -> JsonPrimitive(Logic.isInterval(it))
        "isArchived" -> JsonPrimitive(Logic.isArchived(it))
        "intervalNoticeDays" -> JsonPrimitive(Logic.intervalNoticeDays(it))
        "intervalAnchorKey" -> Logic.intervalAnchorKey(it, rec, now)?.let { JsonPrimitive(it) } ?: JsonNull
        "intervalDueInfo" -> Logic.intervalDueInfo(it, rec, now)?.let { info ->
            buildJsonObject {
                put("daysUntil", info.daysUntil)
                put("sinceDone", info.sinceDone?.let { JsonPrimitive(it) } ?: JsonNull)
            }
        } ?: JsonNull
        "nextOccurrence" -> Logic.nextOccurrence(it, now, rec)?.let { JsonPrimitive(it) } ?: JsonNull
        "isTooLate" -> JsonPrimitive(Logic.isTooLate(c["scheduledMs"].dbl() ?: 0.0, c["now"].dbl() ?: 0.0))
        "isValidEndTime" -> JsonPrimitive(Logic.isValidEndTime(c["time"].str(), c["endTime"].str()))
        "blockEndMs" -> msOut(Logic.blockEndMs(c["endTime"].str() ?: "", now))
        "listSortMs" -> msOut(Logic.listSortMs(it, now, rec))
        "streakFor" -> JsonPrimitive(Logic.streakFor(rec, c["itemId"].str() ?: "", now, c["days"].ints()))
        "doneCountRecent" -> JsonPrimitive(Logic.doneCountRecent(rec, c["itemId"].str() ?: "", now, c["windowDays"].int() ?: 0))
        "avgDoneIntervalDays" -> Logic.avgDoneIntervalDays(rec, c["itemId"].str() ?: "", now, c["windowDays"].int() ?: 0)
            ?.let { JsonPrimitive(it) } ?: JsonNull
        "itemsOnDay" -> JsonArray(Logic.itemsOnDay(sched, rec, c["key"].str() ?: "").map { JsonPrimitive(it.id) })
        "pastDoneCandidates" -> JsonArray(Logic.pastDoneCandidates(it, rec, now, c["maxDays"].int() ?: 7).map { JsonPrimitive(it) })
        "dayMark" -> {
            val ids = (c["ids"] as? JsonArray)?.mapNotNull { it.str() } ?: emptyList()
            Logic.dayMark(rec, c["key"].str() ?: "", ids)?.let { JsonPrimitive(it.rawValue) } ?: JsonNull
        }
        "isStreakMilestone" -> JsonPrimitive(Logic.isStreakMilestone(c["streak"].int() ?: 0))
        "allDoneToday" -> JsonPrimitive(Logic.allDoneToday(sched, rec, now))
        "preNoticeSettings" -> {
            val s = Logic.preNoticeSettings(c["on"].bool(), c["minutes"].int())
            buildJsonObject { put("on", s.on); put("minutes", s.minutes) }
        }
        "preNoticeAt" -> Logic.preNoticeAt(c["nextMs"].dbl(), c["on"].bool(), c["minutes"].int(), c["now"].dbl() ?: 0.0)
            ?.let { msOut(it) } ?: JsonNull
        else -> buildJsonObject { put("error", "unknown fn: $fn") }
    }
}

fun main() {
    val input = generateSequence(::readLine).joinToString("\n")
    val root = try { Json.parseToJsonElement(input).jsonObject } catch (e: Exception) {
        System.err.println("NG: 入力を読めません"); exitProcess(1)
    }
    val cases = root["cases"]?.jsonArray ?: run { System.err.println("NG: cases がありません"); exitProcess(1) }
    val results = JsonArray(cases.map { run(it.jsonObject) })
    print(Json.encodeToString(JsonObject.serializer(), JsonObject(mapOf("results" to results))))
}
