package jp.nishira.unagasukun.ui

import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import jp.nishira.unagasukun.AppModel
import jp.nishira.unagasukun.BuildConfig
import jp.nishira.unagasukun.R
import jp.nishira.unagasukun.notify.Notifier

private const val privacyUrl = "https://github.com/Goma-kun/unagasukun/blob/main/PRIVACY.md"
private const val supportUrl = "https://nishira.jp/"

/** 設定（iOS の SettingsView から iCloud の節を除き、データの書き出し／取り込みとアプリについてを置いた） */
@Composable
fun SettingsScreen(model: AppModel, onEditTags: () -> Unit, bottomInset: Dp) {
    val context = LocalContext.current
    var confirmingRestore by remember { mutableStateOf(false) }
    var dataResult by remember { mutableStateOf<String?>(null) }
    var fabStamp by remember { mutableStateOf(0) }
    val minuteChoices = listOf(3, 5, 10, 15, 30, 60)

    val importLauncher = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri != null) dataResult = model.importFile(uri)
    }
    val exportLauncher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri: Uri? ->
        if (uri != null) dataResult = model.exportTo(uri)
    }

    Column(Modifier.fillMaxSize().background(Uk.bg)) {
        HeaderBar(stringResource(R.string.tab_settings))
        Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(16.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {

            SettingsSection(header = stringResource(R.string.reminders),
                footer = stringResource(if (model.preNoticeOn) R.string.remind_early_on else R.string.remind_early_off)) {
                ToggleRow(stringResource(R.string.remind_early), model.preNoticeOn) { model.changePreNoticeOn(it) }
                if (model.preNoticeOn) {
                    Column(Modifier.padding(vertical = 8.dp)) {
                        ChipGrid(minuteChoices.map { context.getString(R.string.min_before, it) }, minuteChoices.indexOf(model.preNoticeMin), columns = 3, height = 34.dp) {
                            model.changePreNoticeMin(minuteChoices[it])
                        }
                    }
                }
            }

            if (!model.notificationsWorking) {
                SettingsSection(footer = stringResource(R.string.notif_off_footer)) {
                    SettingsRow(stringResource(R.string.notif_turn_on)) { Notifier.openNotificationSettings(context) }
                }
            }
            if (android.os.Build.VERSION.SDK_INT >= 31) {
                SettingsSection(header = stringResource(R.string.exact_alarm_title),
                    footer = stringResource(if (model.exactAlarmAllowed) R.string.exact_alarm_ok else R.string.exact_alarm_footer)) {
                    SettingsRow(stringResource(R.string.open_settings)) { Notifier.openExactAlarmSettings(context) }
                }
            }

            SettingsSection(header = stringResource(R.string.add_button), footer = stringResource(R.string.fab_hint)) {
                val atDefault = fabStamp >= 0 && model.prefs.fabX == 0f && model.prefs.fabY == 1f
                SettingsRow(stringResource(R.string.fab_reset), enabled = !atDefault) { model.prefs.fabX = 0f; model.prefs.fabY = 1f; fabStamp++ }
            }

            SettingsSection(header = stringResource(R.string.data), footer = stringResource(R.string.data_hint)) {
                SettingsRow(stringResource(R.string.export_data)) { exportLauncher.launch(model.exportFileName()) }
                SettingsRow(stringResource(R.string.import_data)) { importLauncher.launch(arrayOf("application/json", "text/plain", "*/*")) }
                dataResult?.let { Text(it, color = Uk.muted, fontSize = 13.sp, modifier = Modifier.padding(vertical = 8.dp)) }
            }

            SettingsSection(header = stringResource(R.string.labels)) {
                SettingsRow(stringResource(R.string.edit_labels), onClick = onEditTags)
            }

            val backups = model.backupCount()
            if (backups > 0) {
                SettingsSection(header = stringResource(R.string.just_in_case), footer = stringResource(R.string.backup_footer, backups)) {
                    SettingsRow(stringResource(R.string.restore_backup)) { confirmingRestore = true }
                }
            }

            SettingsSection(header = stringResource(R.string.about)) {
                Text(stringResource(R.string.version_fmt, BuildConfig.VERSION_NAME + " (" + BuildConfig.VERSION_CODE + ")"), color = Uk.text, fontSize = 15.sp, modifier = Modifier.fillMaxWidth().padding(vertical = 11.dp))
                SettingsRow(stringResource(R.string.privacy_policy)) { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(privacyUrl))) }
                SettingsRow(stringResource(R.string.support)) { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(supportUrl))) }
            }
            Spacer(Modifier.height(bottomInset + 24.dp))
        }
    }

    if (confirmingRestore) {
        AlertDialog(onDismissRequest = { confirmingRestore = false },
            title = { Text(stringResource(R.string.restore_q)) }, text = { Text(stringResource(R.string.restore_msg)) },
            confirmButton = { TextButton(onClick = { model.restoreNewestBackup(); confirmingRestore = false }) { Text(stringResource(R.string.restore), color = Uk.danger) } },
            dismissButton = { TextButton(onClick = { confirmingRestore = false }) { Text(stringResource(R.string.cancel)) } })
    }
}
