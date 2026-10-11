package jp.nishira.unagasukun.core

/** 端末に登録する通知1件ぶん */
data class PlannedNotification(
    val id: String,
    val itemId: String,
    val kind: Kind,
    /** 発火時刻（ms） */
    val fireAt: Long,
    val title: String,
    /** 詳細メモ。通知の本文に出す（無ければ本文なし） */
    val detail: String? = null,
) {
    enum class Kind {
        /** 予定の時刻そのもの */
        MAIN,
        /** 時間が近づいたときの予告 */
        PRE,
        /** 時間帯（終了時刻つき）の終わり。「できましたか？」と聞く */
        END,
    }
}

object NotificationPlan {

    /** 通知の題。ラベルがあれば「買い物：牛乳」のように頭に付ける（何の用事か一目で分かるように） */
    fun title(item: Item, tagNames: Map<String, String>): String {
        val id = item.tagId
        val name = id?.let { tagNames[it] }
        return if (!name.isNullOrEmpty()) "$name：${item.label}" else item.label
    }

    /**
     * iOS の予約通知の上限（64）。Android の AlarmManager にそのままの上限は無いが、
     * 同じ件数で切っておけば端末が違っても「どこまで先が予約されているか」が揃う
     */
    const val pendingLimit = 64

    /**
     * いま登録すべき通知を、発火の早い順に返す。
     * 先の回までまとめて予約しておき、アプリが開かれるたび・記録が変わるたびに入れ替える。
     *
     * @param horizonDays 何日先まで予約するか
     */
    fun build(
        schedule: List<Item>,
        records: Records,
        now: Long,
        preNoticeOn: Boolean? = null,
        preNoticeMin: Int? = null,
        horizonDays: Int = 30,
        limit: Int = pendingLimit,
        tagNames: Map<String, String> = emptyMap(),
    ): List<PlannedNotification> {
        val out = ArrayList<PlannedNotification>()
        val horizon = Logic.day(now, horizonDays)

        for (item in schedule) {
            if (item.origId != null || Logic.isArchived(item) || !item.enabled) continue

            // その予定の次の回から順に、期限まで拾う。
            // 「◯日ごと」は済ませた日で目安日が動くので、先の回を今から決め打てない。
            // その1回だけを予約して、記録が付いたときに張り直す
            var cursor = now
            var guardCount = 0
            while (guardCount < horizonDays + 8) {
                guardCount += 1
                val next = Logic.nextOccurrence(item, cursor, records) ?: break
                if (next > horizon) break

                // 済ませた予定の予告は出さない（責めない設計）
                val alreadyDone = records[Logic.dateKey(next)]?.get(item.id) == Mark.DONE
                if (!alreadyDone) {
                    val title = title(item, tagNames)
                    out.add(PlannedNotification("main:${item.id}:$next", item.id, PlannedNotification.Kind.MAIN, next, title, item.detail))
                    // 予定ごとの早めのお知らせが決まっていればそれを優先（0 は出さない）。無ければ設定どおり
                    val own = item.preNoticeMin
                    val preMs: Long? = if (own != null) {
                        if (own > 0) { val at = next - own.toLong() * 60_000; if (at > now) at else null } else null
                    } else {
                        Logic.preNoticeAt(next.toDouble(), preNoticeOn, preNoticeMin, now.toDouble())?.toLong()
                    }
                    if (preMs != null) {
                        out.add(PlannedNotification("pre:${item.id}:$preMs", item.id, PlannedNotification.Kind.PRE, preMs, title, item.detail))
                    }
                    // 時間帯なら、終わりにもう1回。記録が付けば張り直しで消える
                    val end = item.endTime
                    if (end != null && Logic.isValidEndTime(item.time, end)) {
                        val endMs = Logic.blockEndMs(end, next)
                        if (!endMs.isNaN() && endMs > now) {
                            val e = endMs.toLong()
                            out.add(PlannedNotification("end:${item.id}:$e", item.id, PlannedNotification.Kind.END, e, title, item.detail))
                        }
                    }
                }

                if (Logic.isInterval(item)) break   // 目安日が動くので先を決め打たない
                cursor = next
            }
        }

        out.sortWith(compareBy<PlannedNotification> { it.fireAt }.thenBy { it.id })
        return out.take(limit)
    }
}
