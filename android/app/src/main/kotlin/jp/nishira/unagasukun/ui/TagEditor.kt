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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import jp.nishira.unagasukun.AppModel
import jp.nishira.unagasukun.R
import jp.nishira.unagasukun.core.Tag

/**
 * ラベルを整える画面。名前・色・「🔥 とタイルに数える」・削除・追加。
 * 「保存」を押すまで本体には触らない（途中でやめても元のまま）
 */
@Composable
fun TagEditorDialog(model: AppModel, onClose: () -> Unit) {
    var tags by remember { mutableStateOf(model.tags) }
    var confirmingDelete by remember { mutableStateOf<Tag?>(null) }

    Dialog(onDismissRequest = onClose, properties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false)) {
        Column(Modifier.fillMaxSize().background(Uk.bg)) {
            Row(Modifier.fillMaxWidth().background(Uk.navy).statusBarsPadding().padding(horizontal = 8.dp, vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = onClose) { Text(stringResource(R.string.cancel), color = Color.White, fontSize = 15.sp) }
                Text(stringResource(R.string.labels), color = Color.White, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, textAlign = TextAlign.Center, modifier = Modifier.weight(1f))
                TextButton(onClick = {
                    model.setTags(tags.map { it.copy(name = it.name.trim()) }.filter { it.name.isNotEmpty() })
                    onClose()
                }) { Text(stringResource(R.string.save), color = Color.White, fontSize = 15.sp, fontWeight = FontWeight.SemiBold) }
            }
            Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).imePadding().navigationBarsPadding().padding(16.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                for (tag in tags) {
                    SettingsSection(footer = if (!tag.countsStreak) stringResource(R.string.no_streak_hint) else null) {
                        OutlinedTextField(
                            value = tag.name, onValueChange = { v -> if (v.length <= Tag.nameMaxLength) tags = tags.map { if (it.id == tag.id) it.copy(name = v) else it } },
                            singleLine = true, modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
                            placeholder = { Text(stringResource(R.string.label_name)) },
                        )
                        Row(Modifier.fillMaxWidth().padding(vertical = 10.dp), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                            for (key in Tag.colorKeys) {
                                val on = tag.color == key
                                Box(Modifier.size(30.dp).clip(CircleShape).border(if (on) 2.5.dp else 0.dp, if (on) Uk.text else Color.Transparent, CircleShape)
                                    .padding(if (on) 3.dp else 0.dp).clip(CircleShape).background(Uk.tagColor(key))
                                    .clickable { tags = tags.map { if (it.id == tag.id) it.copy(color = key) else it } })
                            }
                        }
                        ToggleRow(stringResource(R.string.count_streak), tag.countsStreak) { v -> tags = tags.map { if (it.id == tag.id) it.copy(countsStreak = v) else it } }
                        SettingsRow(stringResource(R.string.delete_label), color = Uk.danger) { confirmingDelete = tag }
                    }
                }
                SettingsSection(footer = stringResource(R.string.label_delete_hint)) {
                    Row(Modifier.fillMaxWidth().clickable {
                        val used = tags.map { it.color }.toSet()
                        val color = Tag.colorKeys.firstOrNull { it !in used } ?: Tag.colorKeys[tags.size % Tag.colorKeys.size]
                        tags = tags + Tag(name = "", color = color)
                    }.padding(vertical = 11.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Add, contentDescription = null, tint = Uk.tint, modifier = Modifier.size(18.dp))
                        Spacer(Modifier.size(6.dp))
                        Text(stringResource(R.string.add_label), color = Uk.tint, fontSize = 15.sp)
                    }
                }
                Spacer(Modifier.height(24.dp))
            }
        }
    }

    confirmingDelete?.let { t ->
        AlertDialog(onDismissRequest = { confirmingDelete = null },
            title = { Text(stringResource(R.string.delete_label_q)) }, text = { Text(stringResource(R.string.delete_label_msg)) },
            confirmButton = { TextButton(onClick = { tags = tags.filter { it.id != t.id }; confirmingDelete = null }) { Text(stringResource(R.string.remove), color = Uk.danger) } },
            dismissButton = { TextButton(onClick = { confirmingDelete = null }) { Text(stringResource(R.string.cancel)) } })
    }
}
