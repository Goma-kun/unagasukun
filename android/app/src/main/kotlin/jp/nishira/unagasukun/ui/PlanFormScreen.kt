package jp.nishira.unagasukun.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowLeft
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import jp.nishira.unagasukun.AppModel
import jp.nishira.unagasukun.R
import jp.nishira.unagasukun.core.Describe
import jp.nishira.unagasukun.core.Item
import jp.nishira.unagasukun.core.Logic
import jp.nishira.unagasukun.core.LookBack
import java.time.LocalDate
import java.util.UUID

enum class RepeatMode { ONCE, WEEKLY, INTERVAL }

/**
 * 予定の登録と編集（iOS の PlanFormView と同じ）。繰り返しは**先頭の3択**。
 * 選んだ結果は**必ずプレビュー帯で言い切る**（「3日ごとって何日空くの？」を日付で潰す）
 */
@Composable
fun PlanFormScreen(model: AppModel, editing: Item?, preset: Item?, onClose: () -> Unit) {
    val base = editing ?: preset
    val todayKey = Logic.dateKey(System.currentTimeMillis())

    var label by remember { mutableStateOf(base?.label ?: "") }
    var detail by remember { mutableStateOf(base?.detail ?: "") }
    var tagId by remember { mutableStateOf(base?.tagId) }
    var enabled by remember { mutableStateOf(base?.enabled ?: true) }
    var noTime by remember { mutableStateOf(base?.let { Logic.isAnytime(it) } ?: false) }
    var time by remember { mutableStateOf(base?.time?.let { Logic.parseTime(it) } ?: (9 to 0)) }
    var hasEnd by remember { mutableStateOf(base?.endTime?.let { Logic.parseTime(it) } != null) }
    var endTime by remember { mutableStateOf(base?.endTime?.let { Logic.parseTime(it) } ?: (10 to 0)) }
    var preNotice by remember { mutableStateOf(base?.preNoticeMin) }
    var mode by remember {
        mutableStateOf(when {
            base == null -> RepeatMode.ONCE
            Logic.isInterval(base) -> RepeatMode.INTERVAL
            !base.days.isNullOrEmpty() -> RepeatMode.WEEKLY
            Logic.isOneOff(base) -> RepeatMode.ONCE
            else -> RepeatMode.WEEKLY   // 旧来の「毎日」は曜日を全部選んだ状態として見せる
        })
    }
    var dateKey by remember { mutableStateOf(base?.date?.takeIf { Logic.isDateKey(it) } ?: todayKey) }
    var dateKeys by remember { mutableStateOf(setOf(base?.date?.takeIf { Logic.isDateKey(it) } ?: todayKey)) }
    var days by remember {
        mutableStateOf<Set<Int>>(when {
            base == null -> emptySet()
            !base.days.isNullOrEmpty() -> base.days!!.toSet()
            Logic.isInterval(base) || Logic.isOneOff(base) -> emptySet()
            else -> (0..6).toSet()
        })
    }
    var intervalDays by remember { mutableStateOf(base?.intervalDays?.takeIf { it > 0 } ?: 3) }
    var editingTags by remember { mutableStateOf(false) }
    var confirmingDelete by remember { mutableStateOf(false) }
    var pickingTime by remember { mutableStateOf<Int?>(null) }   // 0=開始 1=終了

    fun hhmm(t: Pair<Int, Int>) = "%02d:%02d".format(t.first, t.second)
    val endValid = !hasEnd || Logic.isValidEndTime(hhmm(time), hhmm(endTime))
    fun ensureEndAfterStart() {
        if (endValid && hhmm(endTime) > hhmm(time)) return
        endTime = if (time.first < 23) (time.first + 1) to time.second else 23 to 59
    }
    val canSave = label.isNotBlank() && !(mode == RepeatMode.WEEKLY && days.isEmpty())
        && !(mode == RepeatMode.ONCE && editing == null && dateKeys.isEmpty()) && (noTime || endValid)

    val context = androidx.compose.ui.platform.LocalContext.current
    fun beforeText(m: Int): String = if (m % 60 == 0) context.resources.getQuantityString(R.plurals.hours_before, m / 60, m / 60)
        else context.getString(R.string.min_before, m)

    fun save() {
        var item = Item(id = editing?.id ?: UUID.randomUUID().toString(), label = label.trim(), enabled = enabled,
            origId = editing?.origId, archived = editing?.archived ?: false, targetMin = editing?.targetMin,
            detail = detail.trim().ifEmpty { null }, tagId = tagId)
        if (noTime) item = item.copy(anytime = true)
        else item = item.copy(time = hhmm(time), endTime = if (hasEnd) hhmm(endTime) else null, preNoticeMin = preNotice)
        item = when (mode) {
            RepeatMode.ONCE -> item.copy(date = if (editing == null) (dateKeys.sorted().firstOrNull() ?: todayKey) else dateKey)
            RepeatMode.WEEKLY -> item.copy(days = days.sorted())
            // **編集のときは基準日を作り直さない。** 名前を直しただけで目安日が飛ばないように
            RepeatMode.INTERVAL -> item.copy(intervalDays = intervalDays, anchorDate = editing?.anchorDate ?: todayKey, noticeDays = 0)
        }
        if (editing == null) {
            model.add(item)
            // 「1回だけ」で複数の日を選んだら、残りの日にも同じ予定を作る（予定ごとに別の ID）
            if (mode == RepeatMode.ONCE) for (k in dateKeys.sorted().drop(1)) model.add(item.copy(id = UUID.randomUUID().toString(), date = k))
        } else model.update(item)
        onClose()
    }

    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Column(Modifier.fillMaxSize().background(Uk.bg)) {
            // 上の帯: やめる／題／追加・保存
            Row(Modifier.fillMaxWidth().background(Uk.navy).statusBarsPadding().padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = onClose) { Text(stringResource(R.string.cancel), color = Color.White, fontSize = 15.sp) }
                Text(stringResource(if (editing == null) R.string.add_plan else R.string.edit_plan), color = Color.White, fontSize = 17.sp,
                    fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
                TextButton(onClick = { save() }, enabled = canSave) {
                    Text(stringResource(if (editing == null) R.string.add else R.string.save), color = Color.White.copy(alpha = if (canSave) 1f else 0.4f), fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                }
            }
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).imePadding().navigationBarsPadding().padding(16.dp),
                verticalArrangement = Arrangement.spacedBy(18.dp)) {

                SettingsSection {
                    OutlinedTextField(value = label, onValueChange = { label = it }, singleLine = true, modifier = Modifier.fillMaxWidth().padding(vertical = 6.dp),
                        placeholder = { Text(stringResource(R.string.what_to_do)) })
                    OutlinedTextField(value = detail, onValueChange = { if (it.length <= 300) detail = it }, minLines = 2, maxLines = 5,
                        modifier = Modifier.fillMaxWidth().padding(bottom = 6.dp),
                        placeholder = { Text(stringResource(R.string.details_hint), fontSize = 13.sp) })
                }

                SettingsSection(header = stringResource(R.string.labels), footer = stringResource(R.string.label_hint)) {
                    Column(Modifier.padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        TagPickerRow(model.tags, tagId) { tagId = it }
                        Text(stringResource(R.string.edit_labels), color = Uk.tint, fontSize = 13.sp, modifier = Modifier.clickable { editingTags = true })
                    }
                }

                SettingsSection(header = stringResource(R.string.repeat)) {
                    Column(Modifier.padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                        Segmented(listOf(RepeatMode.ONCE to stringResource(R.string.once), RepeatMode.WEEKLY to stringResource(R.string.weekly), RepeatMode.INTERVAL to stringResource(R.string.every_n_days)), mode) { mode = it }
                        when (mode) {
                            RepeatMode.ONCE -> {
                                if (editing == null) {
                                    MonthPickerGrid(dateKeys, multi = true) { dateKeys = it }
                                    Hint(stringResource(R.string.multi_date_hint), color = Uk.muted)
                                } else {
                                    MonthPickerGrid(setOf(dateKey), multi = false) { it.firstOrNull()?.let { k -> dateKey = k } }
                                }
                            }
                            RepeatMode.WEEKLY -> WeekdayChips(days) { days = it }
                            RepeatMode.INTERVAL -> IntervalChips(intervalDays) { intervalDays = it }
                        }
                    }
                }

                SettingsSection(header = stringResource(R.string.time), footer = if (!noTime && hasEnd) stringResource(R.string.block_footer) else null) {
                    ToggleRow(stringResource(R.string.anytime_toggle), noTime) { noTime = it }
                    if (!noTime) {
                        TimeRow(stringResource(if (hasEnd) R.string.start else R.string.time), hhmm(time)) { pickingTime = 0 }
                        ToggleRow(stringResource(R.string.set_end), hasEnd) { hasEnd = it; if (it) ensureEndAfterStart() }
                        if (hasEnd) {
                            TimeRow(stringResource(R.string.end), hhmm(endTime)) { pickingTime = 1 }
                            if (!endValid) Text(stringResource(R.string.end_after_start), color = Uk.danger, fontSize = 13.sp, modifier = Modifier.padding(vertical = 4.dp))
                        }
                        // 早めのお知らせ。「設定どおり」が既定で、設定画面の分数に従う。何分前なのかをその場で見せる
                        Column(Modifier.padding(vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text(stringResource(R.string.early_reminder), color = Uk.muted, fontSize = 13.sp)
                            val defaultName = if (model.preNoticeOn) stringResource(R.string.default_fmt, beforeText(model.preNoticeMin)) else stringResource(R.string.default_none)
                            val choices = listOf<Pair<String, Int?>>(defaultName to null, stringResource(R.string.none) to 0,
                                beforeText(15) to 15, beforeText(30) to 30, beforeText(60) to 60, beforeText(120) to 120, beforeText(180) to 180)
                            ChipGrid(choices.map { it.first }, choices.indexOfFirst { it.second == preNotice }, columns = 4, height = 32.dp) { preNotice = choices[it].second }
                        }
                    }
                }

                // 言い切り
                Column(Modifier.fillMaxWidth().plainCard(Uk).padding(14.dp)) {
                    Text(preview(model, mode, editing, dateKey, dateKeys, days, intervalDays, noTime, hasEnd, hhmm(time), hhmm(endTime), preNotice, ::beforeText),
                        color = Uk.tint, fontSize = 14.sp, lineHeight = 20.sp)
                }

                if (editing != null) {
                    SettingsSection(footer = stringResource(R.string.pause_footer)) {
                        ToggleRow(stringResource(R.string.pause_toggle), !enabled) { enabled = !it }
                    }
                    SettingsSection {
                        SettingsRow(stringResource(R.string.delete_plan), color = Uk.danger) { confirmingDelete = true }
                    }
                }
                Spacer(Modifier.height(24.dp))
            }
        }
    }

    if (editingTags) TagEditorDialog(model) { editingTags = false }

    if (confirmingDelete) {
        AlertDialog(onDismissRequest = { confirmingDelete = false },
            title = { Text(stringResource(R.string.delete_plan_q)) }, text = { Text(stringResource(R.string.records_kept)) },
            confirmButton = { TextButton(onClick = { editing?.let { model.remove(it) }; confirmingDelete = false; onClose() }) { Text(stringResource(R.string.delete), color = Uk.danger) } },
            dismissButton = { TextButton(onClick = { confirmingDelete = false }) { Text(stringResource(R.string.cancel)) } })
    }

    pickingTime?.let { which ->
        val initial = if (which == 0) time else endTime
        TimePickDialog(initial, onDismiss = { pickingTime = null }) { h, m ->
            if (which == 0) { time = h to m; if (hasEnd) ensureEndAfterStart() } else endTime = h to m
            pickingTime = null
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun TimePickDialog(initial: Pair<Int, Int>, onDismiss: () -> Unit, onPick: (Int, Int) -> Unit) {
    val state = rememberTimePickerState(initialHour = initial.first, initialMinute = initial.second, is24Hour = true)
    AlertDialog(onDismissRequest = onDismiss,
        text = { Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) { TimePicker(state = state) } },
        confirmButton = { TextButton(onClick = { onPick(state.hour, state.minute) }) { Text(stringResource(R.string.ok)) } },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } })
}

@Composable
fun ToggleRow(text: String, on: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().clickable { onChange(!on) }.padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(text, color = Uk.text, fontSize = 15.sp, modifier = Modifier.weight(1f))
        Switch(checked = on, onCheckedChange = onChange, colors = SwitchDefaults.colors(checkedTrackColor = Uk.done))
    }
}

@Composable
private fun TimeRow(title: String, value: String, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 10.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = Uk.text, fontSize = 15.sp, modifier = Modifier.weight(1f))
        Text(value, color = Uk.tint, fontSize = 17.sp, fontWeight = FontWeight.SemiBold,
            modifier = Modifier.clip(RoundedCornerShape(8.dp)).background(Uk.bg).padding(horizontal = 12.dp, vertical = 6.dp))
    }
}

/** 先頭の3択（1回だけ／毎週／◯日ごと） */
@Composable
private fun <T> Segmented(options: List<Pair<T, String>>, selected: T, onSelect: (T) -> Unit) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(9.dp)).background(Uk.bg).padding(3.dp), horizontalArrangement = Arrangement.spacedBy(3.dp)) {
        for ((v, name) in options) {
            val on = v == selected
            Box(Modifier.weight(1f).clip(RoundedCornerShape(7.dp)).background(if (on) Uk.card else Color.Transparent)
                .border(if (on) 1.dp else 0.dp, if (on) Uk.skip.copy(alpha = 0.5f) else Color.Transparent, RoundedCornerShape(7.dp))
                .clickable { onSelect(v) }.padding(vertical = 8.dp), contentAlignment = Alignment.Center) {
                Text(name, color = if (on) Uk.text else Uk.muted, fontSize = 14.sp, fontWeight = if (on) FontWeight.SemiBold else FontWeight.Medium)
            }
        }
    }
}

/** 「毎日／平日／週末」を名前で先に見せ、その下に曜日の丸 */
@Composable
private fun WeekdayChips(days: Set<Int>, onChange: (Set<Int>) -> Unit) {
    val presets = listOf(stringResource(R.string.daily) to (0..6).toSet(), stringResource(R.string.weekdays) to (1..5).toSet(), stringResource(R.string.weekends) to setOf(0, 6))
    val names = Describe.weekdayNames
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for ((name, set) in presets) ChoiceChip(name, days == set) { onChange(set) }
        }
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            for (d in 0 until 7) {
                val on = d in days
                Box(Modifier.size(38.dp).clip(CircleShape).background(if (on) Uk.navy else Uk.bg)
                    .clickable { onChange(if (on) days - d else days + d) }, contentAlignment = Alignment.Center) {
                    Text(names[d], color = if (on) Color.White else Uk.muted, fontSize = 13.sp, fontWeight = FontWeight.Medium)
                }
            }
        }
    }
}

@Composable
private fun IntervalChips(selected: Int, onSelect: (Int) -> Unit) {
    val choices = listOf(1, 2, 3, 4, 6, 7, 14, 30)
    ChipGrid(choices.map { pluralStringResource(R.plurals.n_days_chip, it, it) }, choices.indexOf(selected), columns = 4, height = 34.dp) { onSelect(choices[it]) }
}

/** 4列のチップ（間隔・早めのお知らせ・分数） */
@Composable
fun ChipGrid(names: List<String>, selectedIndex: Int, columns: Int, height: androidx.compose.ui.unit.Dp, onSelect: (Int) -> Unit) {
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        names.chunked(columns).forEachIndexed { rowI, row ->
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                row.forEachIndexed { i, name ->
                    val idx = rowI * columns + i
                    val on = idx == selectedIndex
                    Box(Modifier.weight(1f).height(height).clip(RoundedCornerShape(8.dp)).background(if (on) Uk.navy else Uk.bg)
                        .clickable { onSelect(idx) }.padding(horizontal = 4.dp), contentAlignment = Alignment.Center) {
                        Text(name, color = if (on) Color.White else Uk.muted, fontSize = 13.sp, fontWeight = FontWeight.Medium, maxLines = 1, softWrap = false, textAlign = TextAlign.Center)
                    }
                }
                repeat(columns - row.size) { Spacer(Modifier.weight(1f)) }
            }
        }
    }
}

/**
 * 月のマスから日を選ぶ。アプリのカレンダー画面と同じ並び（日曜はじまり）。
 * 複数選べるときは押すたびに付け外し。選んだ日は上に言い切る（「10/6(火)・10/7(水)（2日）」）
 */
@Composable
fun MonthPickerGrid(keys: Set<String>, multi: Boolean, onChange: (Set<String>) -> Unit) {
    val first = keys.sorted().firstOrNull()?.let { Logic.parseDateKeyLocal(it) } ?: LocalDate.now()
    var month by remember { mutableStateOf(first.withDayOfMonth(1)) }
    val todayKey = Logic.dateKey(System.currentTimeMillis())
    val names = Describe.weekdayNames
    val dates = keys.sorted().mapNotNull { Logic.parseDateKey(it) }
    val selectedText = when {
        multi && dates.isEmpty() -> stringResource(R.string.pick_days_hint)
        multi && dates.size == 1 -> Describe.short(dates[0]) + stringResource(R.string.pick_more_days)
        multi -> dates.take(4).joinToString(Describe.sep) { Describe.short(it) } + (if (dates.size > 4) stringResource(R.string.and_more) else "") +
            pluralStringResource(R.plurals.n_days_paren, dates.size, dates.size)
        dates.isEmpty() -> ""
        else -> Describe.long(dates[0])
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(selectedText, color = Uk.text, fontSize = 14.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
            if (!multi && keys != setOf(todayKey)) {
                Text(stringResource(R.string.today_btn), color = Uk.tint, fontSize = 12.sp,
                    modifier = Modifier.clickable { onChange(setOf(todayKey)); month = LocalDate.now().withDayOfMonth(1) })
            }
        }
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Default.KeyboardArrowLeft, contentDescription = null, tint = Uk.tint, modifier = Modifier.size(28.dp, 24.dp).clickable { month = month.minusMonths(1) })
            Spacer(Modifier.weight(1f))
            Text(Describe.monthTitle(month.atStartOfDay(Logic.zone).toInstant().toEpochMilli()), color = Uk.tint, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
            Spacer(Modifier.weight(1f))
            Icon(Icons.Default.KeyboardArrowRight, contentDescription = null, tint = Uk.tint, modifier = Modifier.size(28.dp, 24.dp).clickable { month = month.plusMonths(1) })
        }
        Row(Modifier.fillMaxWidth()) {
            for (i in 0 until 7) Text(names[i], color = if (i == 0) Uk.danger else if (i == 6) Uk.tint else Uk.muted, fontSize = 11.sp,
                textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
        }
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            for (row in LookBack.monthGrid(month).chunked(7)) {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(2.dp)) {
                    for (day in row) {
                        if (day == null) { Spacer(Modifier.weight(1f).height(34.dp)); continue }
                        val key = Logic.dateKey(day)
                        val selected = key in keys
                        val wd = Logic.jsWeekday(day)
                        Box(Modifier.weight(1f).height(34.dp).clip(RoundedCornerShape(7.dp)).background(if (selected) Uk.tint else Uk.bg)
                            .border(1.5.dp, if (key == todayKey) Uk.accent else Color.Transparent, RoundedCornerShape(7.dp))
                            .clickable { onChange(if (multi) (if (selected) keys - key else keys + key) else setOf(key)) },
                            contentAlignment = Alignment.Center) {
                            Text("${day.dayOfMonth}", fontSize = 13.sp, fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                                color = if (selected) (if (Uk.dark) Uk.navy else Color.White) else if (wd == 0) Uk.danger else if (wd == 6) Uk.tint else Uk.text)
                        }
                    }
                    repeat(7 - row.size) { Spacer(Modifier.weight(1f).height(34.dp)) }
                }
            }
        }
    }
}

/** **選んだ結果を言い切る。** 読み違えはここで潰す */
@Composable
private fun preview(model: AppModel, mode: RepeatMode, editing: Item?, dateKey: String, dateKeys: Set<String>, days: Set<Int>, intervalDays: Int,
                    noTime: Boolean, hasEnd: Boolean, hhmm: String, endHHMM: String, preNotice: Int?, beforeText: (Int) -> String): String {
    val names = Describe.weekdayNames
    fun dateText(ms: Long) = Describe.short(ms)
    val timeSentence = if (noTime) stringResource(R.string.pv_anytime) else {
        val base = if (hasEnd) stringResource(R.string.pv_block, hhmm, endHHMM) else stringResource(R.string.pv_at, hhmm)
        val pre = when {
            preNotice == null -> if (model.preNoticeOn) stringResource(R.string.pv_also_default, beforeText(model.preNoticeMin)) else ""
            preNotice == 0 -> stringResource(R.string.pv_no_early)
            else -> stringResource(R.string.pv_also, beforeText(preNotice))
        }
        base + pre
    }
    return when (mode) {
        RepeatMode.ONCE -> {
            if (editing != null) stringResource(R.string.pv_once, Logic.parseDateKey(dateKey)?.let { dateText(it) } ?: dateKey) + timeSentence
            else {
                val ds = dateKeys.sorted().mapNotNull { Logic.parseDateKey(it) }
                when {
                    ds.isEmpty() -> stringResource(R.string.pv_choose_date)
                    ds.size == 1 -> stringResource(R.string.pv_once, dateText(ds[0])) + timeSentence
                    else -> stringResource(R.string.pv_multi, ds.take(4).joinToString(Describe.sep) { dateText(it) } + (if (ds.size > 4) stringResource(R.string.and_more) else ""), ds.size) + timeSentence
                }
            }
        }
        RepeatMode.WEEKLY -> {
            if (days.isEmpty()) stringResource(R.string.pv_choose_weekday)
            else {
                val how = if (days.size == 7) stringResource(R.string.daily) else stringResource(R.string.weekly_on, days.sorted().joinToString(Describe.sep) { names[it] })
                stringResource(R.string.pv_repeats, how) + timeSentence
            }
        }
        RepeatMode.INTERVAL -> {
            // 「3日に1回」＋「間は2日空きます」＋実際の日付3つ、で読み違えの余地を消す
            val base = editing?.anchorDate?.let { Logic.parseDateKey(it) } ?: System.currentTimeMillis()
            val dates = (1..3).joinToString(" → ") { dateText(Logic.day(base, intervalDays * it)) }
            stringResource(R.string.pv_interval, Describe.rhythm(intervalDays), dates) + timeSentence
        }
    }
}
