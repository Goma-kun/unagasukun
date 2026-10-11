package jp.nishira.unagasukun.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.KeyboardArrowDown
import androidx.compose.material.icons.filled.KeyboardArrowUp
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.PlatformTextStyle
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import jp.nishira.unagasukun.AppModel
import jp.nishira.unagasukun.R
import jp.nishira.unagasukun.core.Describe
import jp.nishira.unagasukun.core.Item
import jp.nishira.unagasukun.core.Logic
import jp.nishira.unagasukun.core.LookBack
import jp.nishira.unagasukun.core.Mark
import java.time.LocalDate

/**
 * カレンダー。過去は**できた日だけに色がつく**ふりかえり、未来はその日の予定の確認。
 * できなかった日は何も出さず、達成率も出さない（沈黙が中立＝責めない設計）
 */
@Composable
fun CalendarScreen(model: AppModel, onAdd: (String?) -> Unit, onEdit: (Item) -> Unit, bottomInset: Dp) {
    val todayKey = Logic.dateKey(model.now)
    var month by remember { mutableStateOf(LocalDate.now().withDayOfMonth(1)) }
    var selected by remember { mutableStateOf(model.calendarSelectedDay ?: todayKey) }
    var othersOpen by remember { mutableStateOf(false) }
    val tilePick = remember { mutableStateMapOf<String, String>() }

    LaunchedEffect(selected) { model.calendarSelectedDay = selected }
    androidx.compose.runtime.DisposableEffect(Unit) { onDispose { model.calendarSelectedDay = null } }

    Column(Modifier.fillMaxSize().background(Uk.bg)) {
        HeaderBar(stringResource(R.string.tab_calendar), onAdd = { onAdd(selected) })
        LazyColumn(
            Modifier.fillMaxSize(),
            contentPadding = PaddingValues(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 16.dp + bottomInset + 72.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            item {
                MonthCalendar(model, month, selected, todayKey,
                    onShift = { month = month.plusMonths(it.toLong()) },
                    onToday = { month = LocalDate.now().withDayOfMonth(1); selected = todayKey },
                    onSelect = { selected = it })
            }
            item {
                if (selected > todayKey) FutureDetail(model, selected, onEdit)
                else RecordDetail(model, selected, todayKey, othersOpen, { othersOpen = !othersOpen })
            }
            item { Tiles(model, todayKey, tilePick) }
        }
    }
}

@Composable
private fun MonthCalendar(model: AppModel, month: LocalDate, selected: String, todayKey: String,
                          onShift: (Int) -> Unit, onToday: () -> Unit, onSelect: (String) -> Unit) {
    val names = Describe.weekdayNames
    Column(Modifier.fillMaxWidth().plainCard(Uk).padding(14.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.KeyboardArrowLeft, contentDescription = null, tint = Uk.tint,
                modifier = Modifier.size(36.dp, 30.dp).clickable { onShift(-1) })
            Spacer(Modifier.weight(1f))
            val a11y = stringResource(R.string.this_month_a11y)
            Text(Describe.monthTitle(month.atStartOfDay(Logic.zone).toInstant().toEpochMilli()), color = Uk.tint, fontSize = 15.sp,
                fontWeight = FontWeight.SemiBold, modifier = Modifier.clickable(onClick = onToday).semantics { contentDescription = a11y })
            Spacer(Modifier.weight(1f))
            Icon(Icons.Default.KeyboardArrowRight, contentDescription = null, tint = Uk.tint,
                modifier = Modifier.size(36.dp, 30.dp).clickable { onShift(1) })
        }
        Row(Modifier.fillMaxWidth()) {
            for (i in 0 until 7) Text(names[i], color = Uk.muted, fontSize = 11.sp, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
        }
        val cells = LookBack.monthGrid(month)
        val rows = cells.chunked(7)
        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            for (row in rows) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(4.dp)) {
                    for (day in row) {
                        if (day == null) Spacer(Modifier.weight(1f).height(38.dp))
                        else DayCell(model, day, selected, todayKey, Modifier.weight(1f), onSelect)
                    }
                    repeat(7 - row.size) { Spacer(Modifier.weight(1f).height(38.dp)) }
                }
            }
        }
    }
}

@Composable
private fun DayCell(model: AppModel, day: LocalDate, selected: String, todayKey: String, modifier: Modifier, onSelect: (String) -> Unit) {
    val key = Logic.dateKey(day)
    val mark = model.dayMark(key)
    val isSelected = key == selected
    val isFuture = key > todayKey
    // 先の日は「その日だけの予定」か「◯日ごとの目安日」がある日にだけ、数字の下に小さな点
    val special = if (isFuture) model.plannedOn(key).filter { Logic.isOneOff(it) || Logic.isInterval(it) } else emptyList()
    val oneOff = special.firstOrNull { Logic.isOneOff(it) }
    val dotItem = oneOff ?: special.firstOrNull()
    val dotColor = dotItem?.let { model.tag(it) }?.let { Uk.tagColor(it.color) } ?: if (oneOff != null) Uk.accent else Uk.tint
    val bg = when (mark) { Mark.DONE -> Uk.done; Mark.SKIP -> Uk.skip.copy(alpha = 0.28f); null -> Uk.bg }
    val fg = if (mark == Mark.DONE) Color.White else if (isFuture) Uk.skip else Uk.text
    Box(
        modifier.height(38.dp).clip(RoundedCornerShape(8.dp)).background(bg)
            .border(if (isSelected) 2.dp else 0.dp, if (isSelected) Uk.tint else Color.Transparent, RoundedCornerShape(8.dp))
            .clickable { onSelect(key) },
        contentAlignment = Alignment.Center,
    ) {
        Text("${day.dayOfMonth}", color = fg, fontSize = 14.sp,
            fontWeight = if (mark == Mark.DONE || oneOff != null) FontWeight.SemiBold else FontWeight.Normal)
        if (special.isNotEmpty()) {
            Box(Modifier.align(Alignment.BottomCenter).padding(bottom = if (oneOff != null) 4.dp else 5.dp)
                .size(if (oneOff != null) 7.dp else 5.dp).clip(CircleShape).background(dotColor))
        }
    }
}

/** 先の日: その日の予定を時刻つきで並べるだけ。まだ来ていない日に記録のボタンは出さない */
@Composable
private fun FutureDetail(model: AppModel, key: String, onEdit: (Item) -> Unit) {
    val items = model.plannedOn(key)
    val dayText = Logic.parseDateKey(key)?.let { Describe.short(it) } ?: key
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(stringResource(R.string.plans_for, dayText), color = Uk.muted, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        if (items.isEmpty()) {
            Text(stringResource(R.string.nothing_that_day), color = Uk.skip, fontSize = 14.sp, modifier = Modifier.padding(vertical = 6.dp))
        } else {
            for (item in items) {
                val tagKey = model.tag(item)?.color
                Row(
                    Modifier.fillMaxWidth().card(Uk, tagKey, radius = 10.dp).clickable { onEdit(item) }.padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(Describe.timeText(item), color = Uk.timeColor(tagKey), fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    Spacer(Modifier.width(10.dp))
                    TagDot(model.tag(item))
                    Text(item.label, color = Uk.text, fontSize = 15.sp, modifier = Modifier.weight(1f))
                    if (Logic.isOneOff(item)) {
                        Text(stringResource(R.string.this_day_only), color = Uk.accent, fontSize = 11.sp, fontWeight = FontWeight.Medium,
                            modifier = Modifier.clip(CircleShape).background(Uk.accent.copy(alpha = 0.14f)).padding(horizontal = 7.dp, vertical = 2.dp))
                        Spacer(Modifier.width(6.dp))
                    }
                    Icon(Icons.Default.KeyboardArrowRight, contentDescription = null, tint = Uk.skip, modifier = Modifier.size(18.dp))
                }
            }
            Hint(stringResource(R.string.tap_to_edit_hint))
        }
    }
}

@Composable
private fun RecordDetail(model: AppModel, key: String, todayKey: String, othersOpen: Boolean, toggleOthers: () -> Unit) {
    val lists = model.dayLists(key)
    val dayText = Logic.parseDateKey(key)?.let { Describe.short(it) } ?: key
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        Text(stringResource(R.string.records_for, dayText), color = Uk.muted, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        if (lists.main.isEmpty()) {
            Text(stringResource(R.string.nothing_that_day), color = Uk.skip, fontSize = 14.sp, modifier = Modifier.padding(vertical = 6.dp))
        } else {
            for (item in lists.main) {
                val mark = model.mark(item, key)
                Column(Modifier.fillMaxWidth().plainCard(Uk, radius = 10.dp).padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(item.label, color = Uk.text, fontSize = 15.sp, modifier = Modifier.weight(1f))
                        MarkChip(stringResource(R.string.done), mark == Mark.DONE, Uk.done) { model.toggle(item, Mark.DONE, key) }
                        MarkChip(stringResource(R.string.skipped), mark == Mark.SKIP, Uk.skip) { model.toggle(item, Mark.SKIP, key) }
                    }
                    // 休んだ日・記録が無い日には「実際は…」（畳んだ状態）。付いていれば見せる
                    if (mark == Mark.SKIP || (mark == null && key < todayKey) || model.note(item, key) != null) {
                        ActualNoteRow(model, item, key, openByDefault = false)
                    }
                }
            }
            Hint(stringResource(R.string.tap_to_record_hint))
        }

        // この日の予定には無いが、済ませていたら付けられるもの（目安日が先の「◯日ごと」）
        if (lists.others.isNotEmpty()) {
            Row(Modifier.fillMaxWidth().clickable(onClick = toggleOthers).padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.not_planned), color = Uk.muted, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                Spacer(Modifier.width(6.dp))
                Text("${lists.others.size}", color = Uk.muted, fontSize = 11.sp, fontWeight = FontWeight.SemiBold,
                    modifier = Modifier.clip(CircleShape).background(Uk.skip.copy(alpha = 0.35f)).padding(horizontal = 6.dp, vertical = 1.dp))
                Spacer(Modifier.weight(1f))
                Icon(if (othersOpen) Icons.Default.KeyboardArrowUp else Icons.Default.KeyboardArrowDown, contentDescription = null, tint = Uk.muted, modifier = Modifier.size(16.dp))
            }
            if (othersOpen) {
                Hint(stringResource(R.string.not_planned_hint))
                for (item in lists.others) {
                    val mark = model.mark(item, key)
                    Row(Modifier.fillMaxWidth().plainCard(Uk, radius = 10.dp, bg = Uk.card.copy(alpha = 0.6f)).padding(horizontal = 12.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(item.label, color = Uk.muted, fontSize = 15.sp, modifier = Modifier.weight(1f))
                        MarkChip(stringResource(R.string.done), mark == Mark.DONE, Uk.done) { model.toggle(item, Mark.DONE, key) }
                        MarkChip(stringResource(R.string.skipped), mark == Mark.SKIP, Uk.skip) { model.toggle(item, Mark.SKIP, key) }
                    }
                }
            }
        }
    }
}

// ---- タイル ----

private val tileSize = 12.dp
private val tileGap = 3.dp

@Composable
private fun Tiles(model: AppModel, todayKey: String, tilePick: MutableMap<String, String>) {
    // **1度もできていないものは並べない。** 「🔥 とタイルに数えない」ラベルも並べない
    val items = LookBack.tileItems(model.snapshot.schedule)
        .filter { model.doneCount(it, 12) > 0 && model.tag(it)?.countsStreak != false }
    val weeks = LookBack.tileWeeks(model.now, 12)
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        if (items.isEmpty()) {
            Text(stringResource(R.string.tiles_empty), color = Uk.skip, fontSize = 13.sp, modifier = Modifier.padding(top = 4.dp))
            return@Column
        }
        Text(stringResource(R.string.history_title), color = Uk.muted, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        Hint(stringResource(R.string.tiles_hint))
        for (item in items) {
            Column(Modifier.fillMaxWidth().plainCard(Uk, radius = 10.dp).padding(12.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    Text(item.label, color = Uk.text, fontSize = 15.sp, modifier = Modifier.weight(1f))
                    val n = model.doneCount(item, 12)
                    // 事実の回数だけ。達成率は出さない
                    Text(pluralStringResource(R.plurals.times, n, n), color = Uk.muted, fontSize = 12.sp)
                }
                Text(model.describe(item), color = Uk.muted, fontSize = 12.sp)
                TileGrid(model, item, weeks, todayKey, tilePick[item.id]) { k -> if (tilePick[item.id] == k) tilePick.remove(item.id) else tilePick[item.id] = k }
                Legend()
                val pick = tilePick[item.id]
                val pickMs = pick?.let { Logic.parseDateKey(it) }
                if (pick != null && pickMs != null) {
                    val mark = model.mark(item, pick)
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(10.dp)).background(Uk.bg).padding(horizontal = 12.dp, vertical = 10.dp),
                        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(Describe.short(pickMs) + (if (pick == todayKey) stringResource(R.string.today_suffix) else ""),
                            color = Uk.text, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
                        MarkChip(stringResource(R.string.done), mark == Mark.DONE, Uk.done) { model.toggle(item, Mark.DONE, pick) }
                        MarkChip(stringResource(R.string.skipped), mark == Mark.SKIP, Uk.skip) { model.toggle(item, Mark.SKIP, pick) }
                    }
                }
            }
        }
    }
}

@Composable
private fun TileGrid(model: AppModel, item: Item, weeks: List<List<LocalDate>>, todayKey: String, picked: String?, onPick: (String) -> Unit) {
    val labels = LookBack.monthLabelColumns(weeks)
    val initials = Describe.weekdayInitials
    Column(verticalArrangement = Arrangement.spacedBy(tileGap)) {
        // 月名の行。月が変わった最初の週の上に出す
        // 行の高さ（14dp）に 9sp の文字を収める。フォントの上下の余白を外さないと下の行に食い込んで欠ける
        Row(horizontalArrangement = Arrangement.spacedBy(tileGap), verticalAlignment = Alignment.Bottom) {
            Spacer(Modifier.size(16.dp, 14.dp))
            for (w in weeks.indices) {
                Box(Modifier.size(tileSize, 14.dp), contentAlignment = Alignment.BottomStart) {
                    labels.firstOrNull { it.column == w }?.let {
                        Text(Describe.monthShort(it.sunday.atStartOfDay(Logic.zone).toInstant().toEpochMilli()), color = Uk.muted,
                            style = TextStyle(fontSize = 9.sp, lineHeight = 11.sp, platformStyle = PlatformTextStyle(includeFontPadding = false)),
                            maxLines = 1, softWrap = false,
                            // マスの幅（12dp）より長い月名は右にはみ出して描く（iOS の fixedSize と同じ）
                            modifier = Modifier.wrapContentWidth(Alignment.Start, unbounded = true))
                    }
                }
            }
        }
        for (r in 0 until 7) {
            Row(horizontalArrangement = Arrangement.spacedBy(tileGap), verticalAlignment = Alignment.CenterVertically) {
                Text(initials[r], color = Uk.muted, fontSize = 9.sp, textAlign = TextAlign.End, modifier = Modifier.width(16.dp))
                for (w in weeks.indices) {
                    val day = weeks[w][r]
                    val key = Logic.dateKey(day)
                    if (key > todayKey) {
                        val skip = Uk.skip
                        Box(Modifier.size(tileSize).drawBehind {
                            drawRoundRect(skip.copy(alpha = 0.5f), cornerRadius = CornerRadius(2.dp.toPx()),
                                style = Stroke(width = 1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(4f, 4f))))
                        })
                    } else {
                        val done = LookBack.tileMark(item, model.snapshot.records, day, model.now) == Mark.DONE
                        val stroke = if (key == todayKey) Uk.accent else if (key == picked) Uk.tint else Color.Transparent
                        val a11y = Describe.short(day.atStartOfDay(Logic.zone).toInstant().toEpochMilli())
                        Box(Modifier.size(tileSize).clip(RoundedCornerShape(2.dp)).background(if (done) Uk.done else Uk.skip.copy(alpha = 0.22f))
                            .border(1.5.dp, stroke, RoundedCornerShape(2.dp)).clickable { onPick(key) }.semantics { contentDescription = a11y })
                    }
                }
            }
        }
    }
}

/** 凡例（色の意味。小さく1行だけ） */
@Composable
private fun Legend() {
    Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
        LegendItem(Uk.done, stringResource(R.string.done))
        LegendItem(Uk.skip.copy(alpha = 0.22f), stringResource(R.string.no_record))
        val skip = Uk.skip
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Box(Modifier.size(10.dp).drawBehind {
                drawRoundRect(skip.copy(alpha = 0.5f), cornerRadius = CornerRadius(2.dp.toPx()),
                    style = Stroke(width = 1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(4f, 4f))))
            })
            Text(stringResource(R.string.upcoming), color = Uk.muted, fontSize = 10.sp)
        }
    }
}

@Composable
private fun LegendItem(color: Color, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
        Box(Modifier.size(10.dp).clip(RoundedCornerShape(2.dp)).background(color))
        Text(text, color = Uk.muted, fontSize = 10.sp)
    }
}
