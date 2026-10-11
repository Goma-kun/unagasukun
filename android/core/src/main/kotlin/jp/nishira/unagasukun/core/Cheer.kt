package jp.nishira.unagasukun.core

import kotlin.random.Random

/**
 * 「できた」のあとに出す一言。拡張機能 v1.5.0 の「こっそりお祝い」をそのまま移した。
 * どこにも説明を書かない・記録に残さない・出なくても何も失わない（責めない設計の裏返し）
 */
data class Cheer(
    val text: String,
    /** 動物が1匹だけ顔を出す（ふだんは 25%・お祝いのときは必ず） */
    val emoji: String? = null,
    /** 今日の予定がぜんぶ「できた」。動物6匹がふわっと浮かぶ */
    val party: Boolean = false,
)

object CheerLogic {
    val animals = listOf("🐶", "🐱", "🐹", "🐰", "🐻", "🐧", "🦔", "🐿️", "🐥", "🦊")

    /** ふだんの応援ことば（拡張機能の praise1〜5 と同じ） */
    val praises: List<String> get() = L10n.strings.praises

    /**
     * 優先順位は ぜんぶ済み > 節目 > ふだん。**記録を付けたあと**に呼ぶ（今日の分を数えるため）。
     * 1回だけ・◯日ごとは節目を数えない（拡張機能と同じ）
     */
    fun afterDone(
        item: Item, schedule: List<Item>, records: Records, now: Long, random: Random = Random.Default,
    ): Cheer {
        val s = L10n.strings
        if (Logic.allDoneToday(schedule, records, now)) {
            return Cheer(s.allDoneToday, emoji = animals.random(random), party = true)
        }
        if (!Logic.isOneOff(item) && !Logic.isInterval(item)) {
            val streak = Logic.streakFor(records, item.origId ?: item.id, now, item.days)
            if (Logic.isStreakMilestone(streak)) {
                return Cheer(s.streakMilestone(streak), emoji = animals.random(random))
            }
        }
        val emoji = if (random.nextDouble() < 0.25) animals.random(random) else null
        return Cheer(s.praises.random(random), emoji)
    }
}
