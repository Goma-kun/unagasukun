package jp.nishira.unagasukun.core

import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.format.TextStyle
import java.util.Locale

/**
 * core が組み立てる文（Describe の言い切り・お祝いの一言・既定ラベルの名前・「実際は」の選択肢）の言葉。
 *
 * core は Android に依存しないので、文字列リソースを直接引けない。
 * 既定は日本語（`JapaneseStrings`）。アプリは起動時に `L10n.strings` を端末の言語のものに差し替える。
 * iOS 版の Localizable.xcstrings と同じ文にしてある
 */
interface CoreStrings {
    val locale: Locale

    /** 並べるときの区切り。ja は「・」、en は " · " */
    val sep: String
    fun nextIs(date: String): String
    val once: String
    fun onceOn(date: String): String
    fun weeklyOn(names: String): String
    val daily: String
    val anytime: String
    fun targetMin(m: Int): String
    fun timeRange(start: String, end: String): String
    /** 「3日に1回（間は2日空きます）」「1日に1回（毎日）」 */
    fun rhythm(n: Int): String

    /** ふだんの応援ことば（拡張機能の praise1〜5 と同じ） */
    val praises: List<String>
    val allDoneToday: String
    fun streakMilestone(n: Int): String

    /** 既定ラベルの名前（key: shopping/health/cat/home/work/learn） */
    fun tagName(key: String): String
    /** 「実際は…」の選択肢。拡張機能と同じ4つ。責める言葉は使わない */
    val actualChoices: List<String>
}

object JapaneseStrings : CoreStrings {
    override val locale: Locale = Locale.JAPAN
    override val sep = "・"
    override fun nextIs(date: String) = "次は $date"
    override val once = "1回だけ"
    override fun onceOn(date: String) = "1回だけ $date"
    override fun weeklyOn(names: String) = "毎週 $names"
    override val daily = "毎日"
    override val anytime = "いつでも"
    override fun targetMin(m: Int) = "目安 ${m}分"
    override fun timeRange(start: String, end: String) = "$start〜$end"
    override fun rhythm(n: Int) = if (n > 1) "${n}日に1回（間は${n - 1}日空きます）" else "1日に1回（毎日）"
    override val praises = listOf(
        "済みにしました。おつかれさま！",
        "いいペースです。この調子！",
        "またひとつ前に進みました",
        "ちゃんと続いています。すばらしい！",
        "今日の分、きちんと積み上がりました",
    )
    override val allDoneToday = "今日のよてい、ぜんぶできました！おめでとう🎉"
    override fun streakMilestone(n: Int) = "${n}日つづいています。おめでとう！"
    override fun tagName(key: String) = when (key) {
        "shopping" -> "買い物"; "health" -> "薬・健康"; "cat" -> "猫"
        "home" -> "家事"; "work" -> "仕事"; "learn" -> "学び"; else -> key
    }
    override val actualChoices = listOf("別の作業", "休憩", "ブラウジング", "気分が乗らず")
}

object EnglishStrings : CoreStrings {
    override val locale: Locale = Locale.US
    override val sep = " · "
    override fun nextIs(date: String) = "Next: $date"
    override val once = "Once"
    override fun onceOn(date: String) = "Once on $date"
    override fun weeklyOn(names: String) = "Weekly on $names"
    override val daily = "Daily"
    override val anytime = "Anytime"
    override fun targetMin(m: Int) = "About $m min"
    override fun timeRange(start: String, end: String) = "$start–$end"
    override fun rhythm(n: Int) = if (n > 1) "Every $n days (${n - 1}-day gap)" else "Once a day (daily)"
    override val praises = listOf(
        "Marked as done. Nice work!",
        "Good pace. Keep it up!",
        "One more step forward",
        "You’re keeping it up. Wonderful!",
        "Today’s share, neatly stacked up",
    )
    override val allDoneToday = "Everything for today is done! Congratulations 🎉"
    override fun streakMilestone(n: Int) = if (n == 1) "1 day in a row. Congratulations!" else "$n days in a row. Congratulations!"
    override fun tagName(key: String) = when (key) {
        "shopping" -> "Shopping"; "health" -> "Health"; "cat" -> "Cat"
        "home" -> "Chores"; "work" -> "Work"; "learn" -> "Learning"; else -> key
    }
    override val actualChoices = listOf("Other work", "Taking a break", "Browsing", "Not in the mood")
}

/** いま使う言葉。アプリが起動時に端末の言語で差し替える。テストは既定（日本語）のまま */
object L10n {
    @Volatile var strings: CoreStrings = JapaneseStrings

    fun forLocale(locale: Locale): CoreStrings =
        if (locale.language == "ja") JapaneseStrings else EnglishStrings
}

/**
 * 日付の書き方。ja「10/10(土)」 en "Sat, 10/10"（iOS の Describe と同じ考え。月名も端末の言語で）
 */
object DateText {
    private fun isJa(locale: Locale) = locale.language == "ja"

    /** 「9/24(木)」（en: "Thu, 9/24"） */
    fun short(d: LocalDate, locale: Locale = L10n.strings.locale): String =
        if (isJa(locale)) DateTimeFormatter.ofPattern("M/d(E)", Locale.JAPAN).format(d)
        else DateTimeFormatter.ofPattern("EEE, M/d", Locale.US).format(d)

    /** 「2026/10/30(金)」（en: "Fri, 10/30/2026"） */
    fun long(d: LocalDate, locale: Locale = L10n.strings.locale): String =
        if (isJa(locale)) DateTimeFormatter.ofPattern("yyyy/M/d(E)", Locale.JAPAN).format(d)
        else DateTimeFormatter.ofPattern("EEE, M/d/yyyy", Locale.US).format(d)

    /** 「2026年10月」（en: "October 2026"） */
    fun monthTitle(d: LocalDate, locale: Locale = L10n.strings.locale): String =
        if (isJa(locale)) DateTimeFormatter.ofPattern("yyyy年M月", Locale.JAPAN).format(d)
        else DateTimeFormatter.ofPattern("MMMM yyyy", Locale.US).format(d)

    /** 「10月」（en: "Oct"） */
    fun monthShort(d: LocalDate, locale: Locale = L10n.strings.locale): String =
        if (isJa(locale)) DateTimeFormatter.ofPattern("M月", Locale.JAPAN).format(d)
        else DateTimeFormatter.ofPattern("MMM", Locale.US).format(d)

    /** 曜日の短い名前（日曜はじめ）。ja は「日・月…」、en は「Sun・Mon…」 */
    fun weekdayNames(locale: Locale = L10n.strings.locale): List<String> =
        (0 until 7).map { java.time.DayOfWeek.of(if (it == 0) 7 else it).getDisplayName(TextStyle.SHORT, locale) }

    /** タイルの行頭など幅の無いところ用（ja「日」、en「S」） */
    fun weekdayInitials(locale: Locale = L10n.strings.locale): List<String> =
        (0 until 7).map { java.time.DayOfWeek.of(if (it == 0) 7 else it).getDisplayName(TextStyle.NARROW, locale) }

    fun short(ms: Long): String = short(Logic.localDate(ms))
    fun long(ms: Long): String = long(Logic.localDate(ms))
    fun monthTitle(ms: Long): String = monthTitle(Logic.localDate(ms))
    fun monthShort(ms: Long): String = monthShort(Logic.localDate(ms))
}
