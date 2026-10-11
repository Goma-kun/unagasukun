package jp.nishira.unagasukun.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.NotificationsOff
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.DarkMode
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import jp.nishira.unagasukun.AppModel
import jp.nishira.unagasukun.R
import jp.nishira.unagasukun.core.CheerLogic
import jp.nishira.unagasukun.core.Describe
import jp.nishira.unagasukun.core.Item
import jp.nishira.unagasukun.core.Logic
import jp.nishira.unagasukun.core.Mark
import jp.nishira.unagasukun.core.TodayEntry
import jp.nishira.unagasukun.core.TodayGroup
import jp.nishira.unagasukun.notify.Notifier
import kotlinx.coroutines.delay
import kotlin.random.Random

/** 今日の画面（iOS の TodayView と同じ構成） */
@Composable
fun TodayScreen(model: AppModel, onAdd: () -> Unit, onEdit: (Item) -> Unit, bottomInset: androidx.compose.ui.unit.Dp) {
    val context = LocalContext.current
    val now = model.now
    val lists = model.today(now)
    val tagsInUse = model.tagsInUse()
    var tagFilter by remember { mutableStateOf(model.prefs.todayTagFilter) }
    // 消したラベルで絞ったままにならないよう、無いラベルなら「すべて」に戻す
    val filter = if (tagsInUse.any { it.id == tagFilter }) tagFilter else ""
    val todo = if (filter.isEmpty()) lists.todo else lists.todo.filter { it.item.tagId == filter }
    val done = if (filter.isEmpty()) lists.done else lists.done.filter { it.item.tagId == filter }
    val registered = model.registered(now).filter { filter.isEmpty() || it.tagId == filter }
    val past = model.pastOneOffs(now).filter { filter.isEmpty() || it.tagId == filter }

    var collapseDone by remember { mutableStateOf(model.prefs.collapseDone) }
    var collapseRegistered by remember { mutableStateOf(model.prefs.collapseRegistered) }
    var collapsePast by remember { mutableStateOf(model.prefs.collapsePast) }

    var notice by remember { mutableStateOf<String?>(null) }
    var noticeEmoji by remember { mutableStateOf<String?>(null) }
    var noticeStamp by remember { mutableStateOf(0L) }
    var party by remember { mutableStateOf(0L) }
    val listState = rememberLazyListState()

    fun show(text: String, emoji: String? = null) { notice = text; noticeEmoji = emoji; noticeStamp = System.currentTimeMillis() }
    LaunchedEffect(noticeStamp) { if (notice != null) { delay(4000); notice = null; noticeEmoji = null } }

    // 通知を押して開いたら、その予定まで送る（枠を太く光らせ、4 秒で印は消える）
    LaunchedEffect(model.highlightedId) {
        val id = model.highlightedId ?: return@LaunchedEffect
        val idx = todo.indexOfFirst { it.item.id == id }
        if (idx >= 0) listState.animateScrollToItem(idx + 1)
        delay(4000)
        if (model.highlightedId == id) model.highlightedId = null
    }

    Box(Modifier.fillMaxSize().background(Uk.bg)) {
        Column(Modifier.fillMaxSize()) {
            HeaderBar(stringResource(R.string.app_name), onAdd = onAdd)
            if (!model.notificationsWorking) {
                Banner(Icons.Default.NotificationsOff, stringResource(R.string.notif_off_banner), stringResource(R.string.notif_turn_on)) {
                    Notifier.openNotificationSettings(context)
                }
            } else if (!model.exactAlarmAllowed) {
                Banner(Icons.Default.NotificationsOff, stringResource(R.string.exact_alarm_banner), stringResource(R.string.exact_alarm_allow)) {
                    Notifier.openExactAlarmSettings(context)
                }
            }
            if (tagsInUse.isNotEmpty()) {
                TagFilterBar(tagsInUse, filter) { tagFilter = it; model.prefs.todayTagFilter = it }
            }

            LazyColumn(
                state = listState, modifier = Modifier.fillMaxSize(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 16.dp + bottomInset + 72.dp),
                verticalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                if (todo.isEmpty() && done.isEmpty()) {
                    item { EmptyState() }
                } else {
                    if (todo.isNotEmpty()) {
                        item { SectionTitle(stringResource(R.string.today_plans), todo.size) }
                        items(todo, key = { "todo-" + it.item.id }) { entry ->
                            TodoCard(model, entry, now, onEdit = onEdit, onNotice = { show(it) }, onDone = { item ->
                                val c = model.cheerAfterDone(item, now)
                                show(c.text, c.emoji)
                                if (c.party) party = System.currentTimeMillis()
                            })
                        }
                    }
                    if (done.isNotEmpty()) {
                        item {
                            CollapsibleTitle(stringResource(R.string.done_today), done.size, collapseDone) {
                                collapseDone = !collapseDone; model.prefs.collapseDone = collapseDone
                            }
                        }
                        if (!collapseDone) items(done, key = { "done-" + it.item.id }) { DoneCard(model, it, now) }
                    }
                }
                if (registered.isNotEmpty()) {
                    item {
                        CollapsibleTitle(stringResource(R.string.registered), registered.size, collapseRegistered) {
                            collapseRegistered = !collapseRegistered; model.prefs.collapseRegistered = collapseRegistered
                        }
                    }
                    if (!collapseRegistered) {
                        item { Hint(stringResource(R.string.registered_hint)) }
                        items(registered, key = { "reg-" + it.id }) { RegisteredRow(model, it, model.describe(it, now)) { onEdit(it) } }
                    }
                }
                if (past.isNotEmpty()) {
                    item {
                        CollapsibleTitle(stringResource(R.string.past_plans), past.size, collapsePast) {
                            collapsePast = !collapsePast; model.prefs.collapsePast = collapsePast
                        }
                    }
                    if (!collapsePast) {
                        item { Hint(stringResource(R.string.past_hint)) }
                        items(past, key = { "past-" + it.id }) { PastOneOffRow(model, it) { onEdit(it) } }
                    }
                }
            }
        }

        if (party != 0L) PetParty(party)

        // 操作の結果を短く知らせる帯（お祝いの一言・次の目安日）
        AnimatedVisibility(
            visible = notice != null, modifier = Modifier.align(Alignment.BottomCenter).padding(bottom = bottomInset + 16.dp),
            enter = slideInVertically { it } + fadeIn(), exit = slideOutVertically { it } + fadeOut(),
        ) {
            Row(
                Modifier.padding(horizontal = 24.dp).clip(RoundedCornerShape(10.dp)).background(Uk.navy)
                    .padding(horizontal = 14.dp, vertical = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                noticeEmoji?.let { Text(it, fontSize = 22.sp); Spacer(Modifier.width(8.dp)) }
                Text(notice ?: "", color = Color.White, fontSize = 13.sp, textAlign = TextAlign.Center)
            }
        }
    }
}

/** 通知が届かない状態を黙っていない。**責めずに、直し方だけ示す** */
@Composable
private fun Banner(icon: androidx.compose.ui.graphics.vector.ImageVector, text: String, action: String, onClick: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().background(Uk.accent.copy(alpha = 0.22f)).clickable(onClick = onClick)
            .padding(horizontal = 16.dp, vertical = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(icon, contentDescription = null, tint = Uk.text, modifier = Modifier.size(18.dp))
        Spacer(Modifier.width(8.dp))
        Text(text, color = Uk.text, fontSize = 13.sp, modifier = Modifier.weight(1f))
        Spacer(Modifier.width(8.dp))
        Text(action, color = Uk.text, fontSize = 13.sp, fontWeight = FontWeight.Medium)
    }
}

/** 何も無い日を責めない。「予定がない」とだけ言う */
@Composable
private fun EmptyState() {
    Column(Modifier.fillMaxWidth().padding(vertical = 60.dp), horizontalAlignment = Alignment.CenterHorizontally) {
        Icon(Icons.Outlined.CheckCircle, contentDescription = null, tint = Uk.skip, modifier = Modifier.size(44.dp))
        Spacer(Modifier.height(10.dp))
        Text(stringResource(R.string.empty_today), color = Uk.muted, fontSize = 15.sp)
        Spacer(Modifier.height(6.dp))
        Text(stringResource(R.string.empty_hint), color = Uk.skip, fontSize = 13.sp)
    }
}

// ---- カード ----

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun TodoCard(model: AppModel, entry: TodayEntry, now: Long, onEdit: (Item) -> Unit,
                     onNotice: (String) -> Unit, onDone: (Item) -> Unit) {
    val item = entry.item
    val tag = model.tag(item)
    val key = tag?.color
    val pastCandidates = if (Logic.isInterval(item)) model.pastDoneCandidates(item, now) else emptyList()
    var pastOpen by remember(item.id) { mutableStateOf(false) }
    val highlighted = model.highlightedId == item.id

    val subtitles = ArrayList<String>()
    when (entry.group) {
        TodayGroup.ACTIVE -> subtitles.add(stringResource(R.string.in_progress))
        TodayGroup.OVERDUE -> subtitles.add(stringResource(R.string.not_done_yet))
        else -> {}
    }
    model.nextDueText(item, now)?.let { subtitles.add(it) }
    val s = model.streak(item, now)
    if (s > 0) subtitles.add(pluralStringResource(R.plurals.streak_days, s, s))

    // 時間が過ぎたものは枠の色でも分かるようにする。**赤は使わない。**
    val borderColor = when {
        highlighted -> Uk.tint
        entry.group == TodayGroup.ACTIVE -> Uk.done
        entry.group == TodayGroup.OVERDUE -> Uk.accent
        else -> Uk.cardStroke(key)
    }
    val borderWidth = when {
        highlighted -> 3.dp
        entry.group == TodayGroup.ACTIVE || entry.group == TodayGroup.OVERDUE -> 1.5.dp
        key == null -> if (entry.group == TodayGroup.UPCOMING) 1.dp else 1.5.dp
        else -> Uk.cardStrokeWidth(key)
    }

    Column(
        Modifier.fillMaxWidth().card(Uk, key, strokeColor = borderColor, strokeWidth = borderWidth).padding(14.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        // 見出し（時刻＋名前）。押しても編集に入れる
        val a11y = stringResource(R.string.edit_plan_a11y)
        Row(
            Modifier.fillMaxWidth().clickable { onEdit(item) }.semantics { contentDescription = a11y },
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(Describe.timeText(item), color = Uk.timeColor(key), fontSize = 20.sp, fontWeight = FontWeight.SemiBold,
                fontFamily = FontFamily.SansSerif)
            Spacer(Modifier.width(10.dp))
            Text(item.label, color = Uk.text, fontSize = 16.sp, modifier = Modifier.weight(1f))
            Icon(Icons.Default.MoreVert, contentDescription = null, tint = Uk.muted, modifier = Modifier.size(20.dp))
        }

        val d = item.detail
        if (!d.isNullOrEmpty()) Text(d, color = Uk.muted, fontSize = 13.sp, lineHeight = 18.sp)

        if (tag != null || subtitles.isNotEmpty() || pastCandidates.isNotEmpty()) {
            FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                if (tag != null) TagChip(tag)
                for (t in subtitles) InfoChip(t)
                // 済ませたのに付け忘れた日を、あとから「できた」にする入口
                if (pastCandidates.isNotEmpty()) {
                    Text(
                        stringResource(R.string.did_earlier), color = if (pastOpen) Uk.tint else Uk.muted, fontSize = 12.sp, fontWeight = FontWeight.Medium,
                        modifier = Modifier.clip(CircleShape)
                            .border(1.dp, if (pastOpen) Uk.tint else Uk.skip, CircleShape)
                            .clickable { pastOpen = !pastOpen }.padding(horizontal = 10.dp, vertical = 5.dp),
                    )
                }
            }
        }

        if (pastOpen && pastCandidates.isNotEmpty()) {
            val yesterday = Logic.dateKey(Logic.day(now, -1))
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Hint(stringResource(R.string.past_done_hint), color = Uk.muted)
                FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    for (k in pastCandidates) {
                        val text = Logic.parseDateKey(k)?.let { Describe.short(it) } ?: k
                        Text(
                            if (k == yesterday) stringResource(R.string.yesterday_fmt, text) else text,
                            color = Uk.text, fontSize = 13.sp, fontWeight = FontWeight.Medium,
                            modifier = Modifier.clip(CircleShape).background(Uk.bg)
                                .border(1.dp, Uk.skip, CircleShape)
                                .clickable { val m = model.recordPastDone(item, k, now); pastOpen = false; onNotice(m) }
                                .padding(horizontal = 12.dp, vertical = 7.dp),
                        )
                    }
                }
            }
        }

        // 時間が過ぎて記録が無い予定には「実際は…」（畳んだ状態で置く）
        if (entry.group == TodayGroup.OVERDUE) {
            ActualNoteRow(model, item, Logic.dateKey(now), openByDefault = false)
        }

        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            FilledButton(stringResource(R.string.done), Uk.done, Modifier.weight(1f)) {
                model.record(item, Mark.DONE, now); onDone(item)
            }
            OutlineButton(stringResource(R.string.skip_today), Modifier.weight(1f)) { model.record(item, Mark.SKIP, now) }
        }
    }
}

@Composable
private fun DoneCard(model: AppModel, entry: TodayEntry, now: Long) {
    val item = entry.item
    Column(
        Modifier.fillMaxWidth().plainCard(Uk, radius = 10.dp, bg = Uk.card.copy(alpha = 0.7f)).padding(horizontal = 14.dp, vertical = 11.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Icon(
                if (entry.mark == Mark.DONE) Icons.Default.CheckCircle else Icons.Outlined.DarkMode,
                contentDescription = null, tint = if (entry.mark == Mark.DONE) Uk.done else Uk.skip, modifier = Modifier.size(20.dp),
            )
            Spacer(Modifier.width(10.dp))
            TagDot(model.tag(item))
            Text(item.label, color = Uk.muted, fontSize = 15.sp, modifier = Modifier.weight(1f))
            Text(stringResource(R.string.undo), color = if (Uk.dark) Uk.tint else Uk.navyLight, fontSize = 13.sp,
                modifier = Modifier.clickable { model.undo(item, now) }.padding(4.dp))
        }
        // 休んだ予定には「実際は…」。付けなくてもよい
        if (entry.mark == Mark.SKIP) ActualNoteRow(model, item, Logic.dateKey(now))
    }
}

/** 日付が過ぎた1回だけの予定の1行。名前を押すと編集、右の2つで記録を付け直す */
@Composable
private fun PastOneOffRow(model: AppModel, item: Item, onEdit: () -> Unit) {
    val key = item.date ?: ""
    val dateText = Logic.parseDateKey(item.date)?.let { Describe.short(it) } ?: key
    val mark = model.mark(item, key)
    val status = when (mark) {
        Mark.DONE -> stringResource(R.string.status_done, dateText)
        Mark.SKIP -> stringResource(R.string.status_skipped, dateText)
        null -> stringResource(R.string.status_none, dateText)
    }
    val tagKey = model.tag(item)?.color
    Row(
        Modifier.fillMaxWidth().card(Uk, tagKey).padding(horizontal = 14.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp),
    ) {
        Column(Modifier.weight(1f).clickable(onClick = onEdit)) {
            Text(item.label, color = Uk.text, fontSize = 15.sp)
            Text(status, color = Uk.muted, fontSize = 12.sp)
        }
        MarkChip(stringResource(R.string.done), mark == Mark.DONE, Uk.done) { model.toggle(item, Mark.DONE, key) }
        MarkChip(stringResource(R.string.skipped), mark == Mark.SKIP, Uk.skip) { model.toggle(item, Mark.SKIP, key) }
    }
}

/** 登録済み一覧の1行。今日の画面に出ていないものだけが並ぶ */
@Composable
private fun RegisteredRow(model: AppModel, item: Item, detail: String, onEdit: () -> Unit) {
    val tagKey = model.tag(item)?.color
    Row(
        Modifier.fillMaxWidth().card(Uk, tagKey, radius = 10.dp).clickable(onClick = onEdit).padding(horizontal = 14.dp, vertical = 11.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        TagDot(model.tag(item))
        Column(Modifier.weight(1f)) {
            Text(item.label, color = if (item.enabled) Uk.text else Uk.muted, fontSize = 15.sp)
            Text(detail, color = Uk.muted, fontSize = 12.sp)
        }
        if (!item.enabled) {
            Text(stringResource(R.string.paused), color = Uk.muted, fontSize = 11.sp,
                modifier = Modifier.clip(CircleShape).background(Uk.bg).padding(horizontal = 7.dp, vertical = 2.dp))
            Spacer(Modifier.width(6.dp))
        }
        Icon(Icons.Default.KeyboardArrowRight, contentDescription = null, tint = Uk.skip, modifier = Modifier.size(18.dp))
    }
}

/** 今日の予定がぜんぶ済んだときだけ、動物6匹が下からふわっと浮かんで消える（3.4秒で跡形なし） */
@Composable
private fun PetParty(stamp: Long) {
    val pets = remember(stamp) {
        val r = Random(stamp)
        (0 until 6).map { Triple(CheerLogic.animals.random(r), 0.08f + r.nextFloat() * 0.84f, it * 180) }
    }
    BoxWithConstraints(Modifier.fillMaxSize()) {
        val h = maxHeight; val w = maxWidth
        for ((emoji, x, delayMs) in pets) {
            var flying by remember(stamp) { mutableStateOf(false) }
            LaunchedEffect(stamp) { delay(delayMs.toLong()); flying = true }
            val t by animateFloatAsState(if (flying) 1f else 0f, tween(2600), label = "pet")
            Text(
                emoji, fontSize = 26.sp,
                modifier = Modifier.offset(x = w * x, y = h + 20.dp - (h * 0.78f + 20.dp) * t).alpha(1f - t),
            )
        }
    }
}
