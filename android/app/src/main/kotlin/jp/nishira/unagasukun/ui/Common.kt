package jp.nishira.unagasukun.ui

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import jp.nishira.unagasukun.R
import jp.nishira.unagasukun.core.Tag

/** 画面の上の紺の帯。タイトルと、右に「＋ 追加」（iOS の header と同じ） */
@Composable
fun HeaderBar(title: String, onAdd: (() -> Unit)? = null) {
    Row(
        modifier = Modifier.fillMaxWidth().background(Uk.navy).statusBarsPadding()
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(title, color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.weight(1f))
        if (onAdd != null) {
            Row(
                modifier = Modifier.clip(CircleShape).background(Uk.navyLight).clickable(onClick = onAdd)
                    .padding(horizontal = 12.dp, vertical = 7.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Default.Add, contentDescription = null, tint = Color.White, modifier = Modifier.size(16.dp))
                Spacer(Modifier.width(4.dp))
                Text(stringResource(R.string.add), color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Medium)
            }
        }
    }
}

/** 「今日の予定 3」のような見出し */
@Composable
fun SectionTitle(title: String, count: Int, modifier: Modifier = Modifier) {
    Row(modifier = modifier.padding(top = 4.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = Uk.muted, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        Spacer(Modifier.width(6.dp))
        Text(
            "$count", color = Uk.muted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold,
            modifier = Modifier.clip(CircleShape).background(Uk.skip.copy(alpha = 0.35f)).padding(horizontal = 7.dp, vertical = 2.dp),
        )
    }
}

/** 押すと畳める見出し。右端の山形で開閉が分かる */
@Composable
fun CollapsibleTitle(title: String, count: Int, collapsed: Boolean, onToggle: () -> Unit) {
    val a11y = if (collapsed) stringResource(R.string.expand_fmt, title) else stringResource(R.string.collapse_fmt, title)
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onToggle).padding(vertical = 4.dp)
            .semantics { contentDescription = a11y },
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SectionTitle(title, count)
        Spacer(Modifier.weight(1f))
        Icon(
            if (collapsed) Icons.Default.KeyboardArrowDown else Icons.Default.KeyboardArrowUp,
            contentDescription = null, tint = Uk.muted, modifier = Modifier.size(18.dp),
        )
    }
}

/** 小さな印（進行中・🔥 3日 など） */
@Composable
fun InfoChip(text: String) {
    Text(
        text, color = Uk.muted, fontSize = 12.sp,
        modifier = Modifier.clip(CircleShape).background(Uk.bg).padding(horizontal = 8.dp, vertical = 3.dp),
    )
}

/** 塗りのボタン（「できた」の緑など） */
@Composable
fun FilledButton(text: String, color: Color, modifier: Modifier = Modifier, enabled: Boolean = true, onClick: () -> Unit) {
    Box(
        modifier = modifier.clip(RoundedCornerShape(9.dp)).background(if (enabled) color else color.copy(alpha = 0.5f))
            .clickable(enabled = enabled, onClick = onClick).padding(vertical = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.Medium)
    }
}

/** 枠だけのボタン（「今日は休む」） */
@Composable
fun OutlineButton(text: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Box(
        modifier = modifier.clip(RoundedCornerShape(9.dp)).background(Uk.card)
            .border(1.dp, Uk.skip, RoundedCornerShape(9.dp)).clickable(onClick = onClick).padding(vertical = 10.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(text, color = Uk.muted, fontSize = 15.sp, fontWeight = FontWeight.Medium)
    }
}

/** 選ぶチップ（紺＝選択中・薄い地＝未選択）。曜日の型・間隔・早めのお知らせ・分数で共通 */
@Composable
fun ChoiceChip(text: String, selected: Boolean, modifier: Modifier = Modifier, shape: Shape = CircleShape,
               height: Dp? = null, onClick: () -> Unit) {
    val m = modifier.clip(shape).background(if (selected) Uk.navy else Uk.bg).clickable(onClick = onClick)
        .let { if (height != null) it.height(height) else it }
        .padding(horizontal = 12.dp, vertical = if (height != null) 0.dp else 6.dp)
    Box(m, contentAlignment = Alignment.Center) {
        Text(text, color = if (selected) Color.White else Uk.muted, fontSize = 13.sp, fontWeight = FontWeight.Medium,
            maxLines = 1, textAlign = TextAlign.Center)
    }
}

/** 記録を付けるチップ（できた／休んだ）。付いていれば色で塗る */
@Composable
fun MarkChip(text: String, on: Boolean, color: Color, onClick: () -> Unit) {
    Text(
        text, color = if (on) Color.White else Uk.muted, fontSize = 13.sp, fontWeight = FontWeight.Medium,
        modifier = Modifier.clip(CircleShape).background(if (on) color else Uk.bg).clickable(onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 7.dp),
    )
}

/** カードの枠と地（ラベルの色を薄く混ぜる・枠はラベル色）。**ラベルの無いカードにも同じ太さの枠** */
fun Modifier.card(colors: UkColors, tagKey: String?, radius: Dp = 12.dp, strokeColor: Color? = null, strokeWidth: Dp? = null): Modifier {
    val shape = RoundedCornerShape(radius)
    return this.clip(shape).background(colors.cardBg(tagKey))
        .border(strokeWidth ?: colors.cardStrokeWidth(tagKey), strokeColor ?: colors.cardStroke(tagKey), shape)
}

/** 無地のカード（カレンダーの箱など） */
fun Modifier.plainCard(colors: UkColors, radius: Dp = 12.dp, bg: Color = colors.card): Modifier {
    val shape = RoundedCornerShape(radius)
    return this.clip(shape).background(bg).border(1.5.dp, colors.plainStroke, shape)
}

/** 説明の小さな文（薄い灰色） */
@Composable
fun Hint(text: String, color: Color = Uk.skip, modifier: Modifier = Modifier) {
    Text(text, color = color, fontSize = 12.sp, modifier = modifier, lineHeight = 17.sp)
}

// ---- ラベル ----

/** ラベルの色つきチップ（名前の右に置く小さな印） */
@Composable
fun TagChip(tag: Tag) {
    val c = Uk.tagColor(tag.color)
    Row(
        modifier = Modifier.clip(CircleShape).background(c.copy(alpha = 0.14f)).padding(horizontal = 8.dp, vertical = 3.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.size(7.dp).clip(CircleShape).background(c))
        Spacer(Modifier.width(5.dp))
        Text(tag.name, color = Uk.text, fontSize = 12.sp, fontWeight = FontWeight.Medium)
    }
}

/** 一覧の行に置く、名前の前の小さな点 */
@Composable
fun RowScope.TagDot(tag: Tag?) {
    if (tag != null) {
        Box(Modifier.size(8.dp).clip(CircleShape).background(Uk.tagColor(tag.color)))
        Spacer(Modifier.width(10.dp))
    }
}

/** 今日の画面の上の絞り込み。「すべて」＋使っているラベルだけ */
@Composable
fun TagFilterBar(tags: List<Tag>, selected: String, onSelect: (String) -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().background(Uk.bg).horizontalScroll(rememberScrollState())
            .padding(horizontal = 16.dp, vertical = 8.dp),
        horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        FilterChipUk(null, selected == "", onClick = { onSelect("") })
        for (t in tags) FilterChipUk(t, selected == t.id, onClick = { onSelect(if (selected == t.id) "" else t.id) })
    }
}

@Composable
private fun FilterChipUk(tag: Tag?, on: Boolean, onClick: () -> Unit) {
    val color = if (tag != null) Uk.tagColor(tag.color) else Uk.tint
    Row(
        modifier = Modifier.clip(CircleShape).background(if (on) color else Uk.card)
            .border(1.dp, if (on) color else Uk.skip.copy(alpha = 0.7f), CircleShape)
            .clickable(onClick = onClick).padding(horizontal = 11.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (tag != null) {
            Box(Modifier.size(7.dp).clip(CircleShape).background(if (on) Color.White else Uk.tagColor(tag.color)))
            Spacer(Modifier.width(5.dp))
        }
        Text(tag?.name ?: stringResource(R.string.all), color = if (on) Color.White else Uk.text,
            fontSize = 13.sp, fontWeight = FontWeight.Medium)
    }
}

/** 登録フォームでラベルを選ぶ列。「なし」＋ラベル */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun TagPickerRow(tags: List<Tag>, selected: String?, onSelect: (String?) -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        PickChip(null, selected == null) { onSelect(null) }
        for (t in tags) PickChip(t, selected == t.id) { onSelect(t.id) }
    }
}

@Composable
private fun PickChip(tag: Tag?, on: Boolean, onClick: () -> Unit) {
    val color = if (tag != null) Uk.tagColor(tag.color) else Uk.muted
    Row(
        modifier = Modifier.clip(CircleShape).background(if (on) color else Uk.bg)
            .border(1.dp, if (on) color else Uk.skip, CircleShape)
            .clickable(onClick = onClick).padding(horizontal = 11.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (tag != null) {
            Box(Modifier.size(7.dp).clip(CircleShape).background(if (on) Color.White else Uk.tagColor(tag.color)))
            Spacer(Modifier.width(5.dp))
        }
        Text(tag?.name ?: stringResource(R.string.none), color = if (on) Color.White else Uk.text,
            fontSize = 13.sp, fontWeight = FontWeight.Medium)
    }
}

/** 設定画面などの「節」。見出し＋白いカード＋脚注 */
@Composable
fun SettingsSection(header: String? = null, footer: String? = null, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        if (header != null) {
            Text(header, color = Uk.muted, fontSize = 13.sp, fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(start = 4.dp, bottom = 6.dp))
        }
        Column(Modifier.fillMaxWidth().plainCard(Uk).padding(horizontal = 14.dp, vertical = 6.dp)) { content() }
        if (footer != null) Hint(footer, modifier = Modifier.padding(start = 4.dp, top = 6.dp))
    }
}

/** 設定の 1 行（押せる文） */
@Composable
fun SettingsRow(text: String, color: Color? = null, enabled: Boolean = true, onClick: () -> Unit) {
    Text(
        text, color = (color ?: Uk.tint).copy(alpha = if (enabled) 1f else 0.4f), fontSize = 15.sp,
        modifier = Modifier.fillMaxWidth().clickable(enabled = enabled, onClick = onClick).padding(vertical = 11.dp),
    )
}

@Composable
fun stroke(color: Color, width: Dp = 1.dp) = BorderStroke(width, color)
