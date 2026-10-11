package jp.nishira.unagasukun.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlinx.serialization.json.Json
import java.util.UUID
import kotlin.math.abs
import kotlin.math.floor

/**
 * 予定1件。拡張機能の `schedule` 配列の要素をそのまま写したもの（iOS の Model.swift と同じ形）。
 * 判定の意味は extension/logic.js のコメントが正本。ここでは形だけ持つ。
 *
 * 拡張機能の JSON は false のときにキーごと省くことがある（`anytime` `archived` `enabled`）ので、
 * 全部に既定値を持たせて「無ければ既定」で読む。知らないキー（createdAt など）は読み飛ばす。
 */
@Serializable
data class Item(
    val id: String,
    val label: String = "",
    /** "HH:MM"。時刻を固定しない予定は null */
    val time: String? = null,
    /** "YYYY-MM-DD"。1回だけの予定だけが持つ */
    val date: String? = null,
    /** 0=日 〜 6=土。空または null で（date も無ければ）毎日 */
    val days: List<Int>? = null,
    val enabled: Boolean = true,
    /** 時刻を決めず、1日の目安分数だけ決める予定 */
    val anytime: Boolean = false,
    val targetMin: Int? = null,
    /** 「◯日ごと」。済ませた日から数え直す */
    val intervalDays: Int? = null,
    /** 目安日の何日前から今日の予定に出すか（未設定は3）。拡張機能用の設定で、アプリは当日から出す */
    val noticeDays: Int? = null,
    /** 登録時に入れる「最後にやった日」 */
    val anchorDate: String? = null,
    /** 日付が過ぎた1回だけの予定。一覧にも通知にも出さないが、名前を引くために残す */
    val archived: Boolean = false,
    /** やりなおしコピー。記録は元の予定に付くので集計から外す */
    val origId: String? = null,
    val endTime: String? = null,
    /** 詳細メモ（任意）。今日のカードと通知の本文に出す */
    val detail: String? = null,
    /** ラベル（`Snapshot.tags` の id）。1つの予定に1つ */
    val tagId: String? = null,
    /** この予定だけの「早めのお知らせ」（分）。null は設定どおり、0 は出さない。拡張機能は見ない */
    val preNoticeMin: Int? = null,
)

/**
 * ラベル。名前と色の組で、予定の仕分けに使う（買い物・薬・猫 など）。
 * `countsStreak` を切ると、その予定は 🔥 とタイルに数えない（責めない設計）。
 */
@Serializable
data class Tag(
    val id: String = UUID.randomUUID().toString(),
    val name: String = "",
    /** `colorKeys` のどれか。見た目の色は App 側（Theme）が決める */
    val color: String = colorKeys[0],
    /** 🔥 とタイルに数えるか。既定は数える */
    val countsStreak: Boolean = true,
) {
    companion object {
        /** 8色のパレット。似た色を並べない順で持つ */
        val colorKeys = listOf("red", "orange", "yellow", "green", "teal", "blue", "purple", "pink")
        const val nameMaxLength = 12

        /**
         * 最初から用意しておくラベル。id を固定にしてあるので、端末が違っても同じものになる（iOS と同じ id）。
         * 名前は端末の言語で出す（`strings` が訳す）。
         */
        fun defaults(strings: CoreStrings = L10n.strings): List<Tag> = listOf(
            Tag("tag-shopping", strings.tagName("shopping"), "orange", countsStreak = false),
            Tag("tag-health", strings.tagName("health"), "red"),
            Tag("tag-cat", strings.tagName("cat"), "teal"),
            Tag("tag-home", strings.tagName("home"), "green"),
            Tag("tag-work", strings.tagName("work"), "blue"),
            Tag("tag-learn", strings.tagName("learn"), "purple"),
        )
    }
}

/** その日の記録。"できた" は DONE、"今日は休む" は SKIP */
@Serializable
enum class Mark {
    @SerialName("done") DONE,
    @SerialName("skip") SKIP;

    val rawValue: String get() = if (this == DONE) "done" else "skip"

    companion object {
        fun of(s: String?): Mark? = when (s) { "done" -> DONE; "skip" -> SKIP; else -> null }
    }
}

/** 日付キー("YYYY-MM-DD") → 予定ID → 記録 */
typealias Records = Map<String, Map<String, Mark>>

/** 日付 → 予定ID → 「実際は…」の文 */
typealias Notes = Map<String, Map<String, String>>

/** 予告ポップアップの設定 */
data class PreNotice(val on: Boolean, val minutes: Int)

/** 「◯日ごと」の予定がいま何日目か */
data class IntervalDue(
    /** 目安日まであと何日。0=今日、負=過ぎている */
    val daysUntil: Int,
    /** 最後にやってから何日。基準が無ければ null */
    val sinceDone: Int?,
)

/**
 * ミリ秒の時刻（Double）。iOS は `Date().timeIntervalSince1970 * 1000` の小数つき、拡張機能は `Date.now()` の整数。
 * 読むときはどちらも受け、書くときは整数で収まるなら整数で書く（1.76E12 のような指数表記を JSON に残さない）
 */
object MsDoubleSerializer : KSerializer<Double> {
    override val descriptor: SerialDescriptor = PrimitiveSerialDescriptor("Ms", PrimitiveKind.DOUBLE)
    override fun serialize(encoder: Encoder, value: Double) {
        if (value.isFinite() && value == floor(value) && abs(value) < 9.0e15) encoder.encodeLong(value.toLong())
        else encoder.encodeDouble(value)
    }
    override fun deserialize(decoder: Decoder): Double = decoder.decodeDouble()
}

/** 保存・取り込みに使う JSON の設定。false の既定値も書く（iOS と同じ）・null は省く・知らないキーは読み飛ばす */
val UkJson: Json = Json {
    ignoreUnknownKeys = true
    encodeDefaults = true
    explicitNulls = false
    isLenient = true
}
