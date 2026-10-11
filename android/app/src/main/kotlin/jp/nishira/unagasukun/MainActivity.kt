package jp.nishira.unagasukun

import android.Manifest
import android.content.Intent
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CalendarMonth
import androidx.compose.material.icons.filled.FormatListBulleted
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import jp.nishira.unagasukun.core.Item
import jp.nishira.unagasukun.notify.Notifier
import jp.nishira.unagasukun.ui.CalendarScreen
import jp.nishira.unagasukun.ui.FloatingAddButton
import jp.nishira.unagasukun.ui.PlanFormScreen
import jp.nishira.unagasukun.ui.SettingsScreen
import jp.nishira.unagasukun.ui.TagEditorDialog
import jp.nishira.unagasukun.ui.TodayScreen
import jp.nishira.unagasukun.ui.Uk
import jp.nishira.unagasukun.ui.UkTheme
import kotlinx.coroutines.delay

/** 開くフォーム。追加と編集で 1 つにまとめる（iOS の FormTarget と同じ） */
sealed class FormTarget {
    data class Add(val preset: Item?) : FormTarget()
    data class Edit(val item: Item) : FormTarget()
}

class MainActivity : ComponentActivity() {
    private val model: AppModel by viewModels()
    private var pendingItemId by mutableStateOf<String?>(null)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        pendingItemId = intent?.getStringExtra(Notifier.extraItemId)
        setContent { UkTheme { Root() } }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        pendingItemId = intent.getStringExtra(Notifier.extraItemId)
    }

    @Composable
    private fun Root() {
        var tab by remember { mutableStateOf(0) }
        var form by remember { mutableStateOf<FormTarget?>(null) }
        var editingTags by remember { mutableStateOf(false) }
        val lifecycleOwner = LocalLifecycleOwner.current

        // 通知の許可は、最初の予定を登録したとき（＝通知が意味を持った瞬間）に聞く
        val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { model.refreshNotificationState(); model.reschedule() }
        var askedOnce by remember { mutableStateOf(false) }
        fun askNotificationIfNeeded() {
            if (Build.VERSION.SDK_INT >= 33 && !askedOnce && !model.notificationsWorking) {
                askedOnce = true
                permission.launch(Manifest.permission.POST_NOTIFICATIONS)
            }
        }

        // 前面に戻るたびに通知の状態を見直し、張り直す（設定アプリで切られていることがあるため）。「いま」も進める
        DisposableEffect(lifecycleOwner) {
            val obs = LifecycleEventObserver { _, e ->
                if (e == Lifecycle.Event.ON_RESUME) { model.now = System.currentTimeMillis(); model.refreshNotificationState(); model.reschedule() }
            }
            lifecycleOwner.lifecycle.addObserver(obs)
            onDispose { lifecycleOwner.lifecycle.removeObserver(obs) }
        }
        LaunchedEffect(Unit) { while (true) { delay(30_000); model.now = System.currentTimeMillis() } }

        // 通知を押して開いたら今日のタブでそのカードへ
        LaunchedEffect(pendingItemId) {
            val id = pendingItemId ?: return@LaunchedEffect
            tab = 0
            model.highlightedId = id
            pendingItemId = null
        }

        Scaffold(
            containerColor = Uk.bg,
            bottomBar = {
                NavigationBar(containerColor = Uk.card) {
                    val items = listOf(
                        Triple(stringResource(R.string.tab_today), Icons.Default.FormatListBulleted, 0),
                        Triple(stringResource(R.string.tab_calendar), Icons.Default.CalendarMonth, 1),
                        Triple(stringResource(R.string.tab_settings), Icons.Default.Settings, 2),
                    )
                    for ((name, icon, i) in items) {
                        NavigationBarItem(
                            selected = tab == i, onClick = { tab = i },
                            icon = { Icon(icon, contentDescription = null) }, label = { Text(name) },
                            colors = NavigationBarItemDefaults.colors(
                                selectedIconColor = Uk.tint, selectedTextColor = Uk.tint, indicatorColor = Uk.tint.copy(alpha = 0.12f),
                                unselectedIconColor = Uk.muted, unselectedTextColor = Uk.muted,
                            ),
                        )
                    }
                }
            },
        ) { inner ->
            Box(Modifier.fillMaxSize().padding(bottom = inner.calculateBottomPadding())) {
                when (tab) {
                    0 -> TodayScreen(model, onAdd = { form = FormTarget.Add(null) }, onEdit = { form = FormTarget.Edit(it) }, bottomInset = 0.dp)
                    1 -> CalendarScreen(model, onAdd = { day -> form = FormTarget.Add(day?.let { Item(id = "preset", date = it) }) }, onEdit = { form = FormTarget.Edit(it) }, bottomInset = 0.dp)
                    else -> SettingsScreen(model, onEditTags = { editingTags = true }, bottomInset = 0.dp)
                }
                // 右上の「追加」は左手だと遠い。浮かぶ「＋」を今日とカレンダーに出す（設定では出さない）。
                // カレンダーを開いているときは、選んでいる日の「1回だけ」として開く
                if (tab != 2) {
                    FloatingAddButton(model.prefs, bottomInset = 0.dp) {
                        form = FormTarget.Add(if (tab == 1) model.presetForCalendarDay else null)
                    }
                }
            }
        }

        form?.let { target ->
            PlanFormScreen(
                model,
                editing = (target as? FormTarget.Edit)?.item,
                preset = (target as? FormTarget.Add)?.preset,
                onClose = { form = null; askNotificationIfNeeded() },
            )
        }
        if (editingTags) TagEditorDialog(model) { editingTags = false }
    }
}

