package jp.nishira.unagasukun.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.roundToInt

/**
 * iOS の Theme.swift と同じ色（ライトは拡張機能の sidepanel.css と同じ）。
 * **同じ製品に見えることが大事**なので、色を変えるときは向こうも一緒に変える。
 *
 * 紺の文字を黒い背景に置くと消えるので、「背景の紺（navy）」と「前景の紺（tint）」を分けて持つのがダーク対応の要
 */
class UkColors(val dark: Boolean) {
    private fun pick(light: Long, darkHex: Long) = Color(if (dark) darkHex else light)

    /** ヘッダーの地。ダークでも紺のまま（白文字が載るので問題ない） */
    val navy = pick(0xFF1B2A4A, 0xFF1B2A4A)
    val navyLight = pick(0xFF2E4370, 0xFF3A5080)
    val accent = pick(0xFFE8A13A, 0xFFE8A13A)
    val bg = pick(0xFFF7F8FA, 0xFF121826)
    val card = pick(0xFFFFFFFF, 0xFF1E2638)
    val text = pick(0xFF23293A, 0xFFE6E9F0)
    val muted = pick(0xFF7A8299, 0xFF9AA3B8)
    val done = pick(0xFF3A9E57, 0xFF3FA862)
    val skip = pick(0xFFB0B6C6, 0xFF4A5468)
    val danger = pick(0xFFC0392B, 0xFFE05A4C)
    /** ボタンやカーソル、選択の枠など「前景の紺」。ライトでは紺、ダークでは薄い青 */
    val tint = pick(0xFF1B2A4A, 0xFF8FB4FF)
    val white = Color.White

    /** ラベルの無いカードの枠 */
    val plainStroke: Color get() = skip.copy(alpha = 0.4f)

    private fun tagHex(key: String): Pair<Long, Long> = when (key) {
        // ダークは彩度を上げてある。暗い地に混ぜると、くすんだ色は茶色や灰色に沈むため
        "red" -> 0xD65A4AL to 0xFF6B5EL
        "orange" -> 0xE07B2EL to 0xFF9A2EL
        "yellow" -> 0xC9A227L to 0xFFD23FL
        "green" -> 0x4C9F70L to 0x3DD68CL
        "teal" -> 0x2E9AA6L to 0x2ED3E0L
        "blue" -> 0x3B78D8L to 0x5AA2FFL
        "purple" -> 0x8A5CC7L to 0xB57BFFL
        "pink" -> 0xD4569AL to 0xFF6FB5L
        else -> 0x7A8299L to 0x9AA3B8L
    }

    /** ラベルの8色。ライトは白いカードの上で沈まない濃さ、ダークは暗いカードの上で浮く明るさ */
    fun tagColor(key: String): Color {
        val (l, d) = tagHex(key)
        return Color(0xFF000000 or (if (dark) d else l))
    }

    /**
     * カードの地。**ラベルが付いていたら、その色をほんの少し混ぜる**。
     * ベタ塗りにはしない（本文も「できた」の緑も載るので）。地は2割に抑え、鮮やかさは枠線と時刻の文字に持たせる
     */
    fun cardBg(key: String?): Color {
        if (key.isNullOrEmpty() || key == "none") return card
        val (l, d) = tagHex(key)
        return Color(0xFF000000 or if (dark) mix(0x1E2638L, d, 0.20) else mix(0xFFFFFFL, l, 0.16))
    }

    /** カードの枠線。ラベルがあればその色、無ければ薄い灰色。ラベルの無いカードにも同じ太さの枠を付ける */
    fun cardStroke(key: String?): Color {
        if (key.isNullOrEmpty() || key == "none") return plainStroke
        return tagColor(key).copy(alpha = 0.95f)
    }

    /** 枠の太さ。ラベル付きは少し太くして色をはっきり見せる */
    fun cardStrokeWidth(key: String?): Dp = if (key.isNullOrEmpty() || key == "none") 1.5.dp else 2.dp

    /** 時刻（「いつでも」「09:00」）の文字色。ラベルがあればその色、無ければいつもの青 */
    fun timeColor(key: String?): Color = if (key.isNullOrEmpty() || key == "none") tint else tagColor(key)

    /** 2色を混ぜる（ratio の分だけ b に寄せる）。半透明を重ねるのではなく混ぜた不透明色を作る */
    private fun mix(a: Long, b: Long, ratio: Double): Long {
        fun ch(shift: Int): Long {
            val x = ((a shr shift) and 0xFF).toDouble(); val y = ((b shr shift) and 0xFF).toDouble()
            return (x + (y - x) * ratio).roundToInt().toLong()
        }
        return (ch(16) shl 16) or (ch(8) shl 8) or ch(0)
    }
}

val LocalUkColors = staticCompositionLocalOf { UkColors(dark = false) }

/** いまの色一式。`Uk.bg` のように使う */
val Uk: UkColors
    @Composable get() = LocalUkColors.current

@Composable
fun UkTheme(content: @Composable () -> Unit) {
    val dark = isSystemInDarkTheme()
    val c = UkColors(dark)
    val scheme = if (dark) darkColorScheme(
        primary = c.tint, onPrimary = c.navy, background = c.bg, onBackground = c.text,
        surface = c.card, onSurface = c.text, surfaceVariant = c.card, onSurfaceVariant = c.muted,
        secondary = c.navyLight, onSecondary = c.white, error = c.danger, outline = c.skip,
    ) else lightColorScheme(
        primary = c.tint, onPrimary = c.white, background = c.bg, onBackground = c.text,
        surface = c.card, onSurface = c.text, surfaceVariant = c.bg, onSurfaceVariant = c.muted,
        secondary = c.navyLight, onSecondary = c.white, error = c.danger, outline = c.skip,
    )
    CompositionLocalProvider(LocalUkColors provides c) {
        MaterialTheme(colorScheme = scheme, content = content)
    }
}
