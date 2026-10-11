package jp.nishira.unagasukun.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Edit
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
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import jp.nishira.unagasukun.AppModel
import jp.nishira.unagasukun.R
import jp.nishira.unagasukun.core.ActualNote
import jp.nishira.unagasukun.core.Item

/**
 * 「実際は…」の行。休んだ予定と、時間が過ぎて記録が無い予定に付ける（拡張機能・iOS と同じ）。
 * 狙いは成績表ではなく**予定の側を直す材料**。責める言葉は使わない。付けなくても何も起きない
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ActualNoteRow(model: AppModel, item: Item, key: String, openByDefault: Boolean = true) {
    val note = model.note(item, key)
    var editing by remember(key, item.id) { mutableStateOf(false) }
    var freeText by remember(key, item.id) { mutableStateOf(false) }
    var text by remember(key, item.id) { mutableStateOf("") }
    val choices = ActualNote.choices

    fun save(v: String?) { model.setNote(v, item, key); editing = false; freeText = false; text = "" }

    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        if (note != null && !editing) {
            val a11y = stringResource(R.string.actually_a11y, note)
            Row(
                Modifier.clickable {
                    text = if (choices.contains(note)) "" else note
                    freeText = !choices.contains(note)
                    editing = true
                }.semantics { contentDescription = a11y },
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(stringResource(R.string.actually_fmt, note), color = Uk.text, fontSize = 13.sp)
                Spacer(Modifier.width(6.dp))
                Icon(Icons.Default.Edit, contentDescription = null, tint = Uk.muted, modifier = Modifier.width(13.dp))
            }
        } else if (note == null && !openByDefault && !editing) {
            Text(stringResource(R.string.actually_label), color = Uk.muted, fontSize = 12.sp,
                modifier = Modifier.clickable { editing = true }.padding(vertical = 2.dp))
        } else {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text(stringResource(R.string.actually_label), color = Uk.muted, fontSize = 12.sp)
                Spacer(Modifier.weight(1f))
                if (note != null) {
                    Text(stringResource(R.string.remove), color = Uk.muted, fontSize = 12.sp,
                        modifier = Modifier.clickable { save(null) }.padding(horizontal = 6.dp))
                }
                if (editing || !openByDefault) {
                    Text(stringResource(R.string.close), color = Uk.muted, fontSize = 12.sp,
                        modifier = Modifier.clickable { editing = false; freeText = false }.padding(horizontal = 6.dp))
                }
            }
            if (freeText) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                    OutlinedTextField(
                        value = text, onValueChange = { if (it.length <= ActualNote.maxLength) text = it },
                        placeholder = { Text(stringResource(R.string.what_doing), fontSize = 13.sp) },
                        singleLine = true, modifier = Modifier.weight(1f),
                        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Done),
                        keyboardActions = KeyboardActions(onDone = { if (text.isNotBlank()) save(text) }),
                    )
                    TextButton(onClick = { save(text) }, enabled = text.isNotBlank()) { Text(stringResource(R.string.record_save), fontSize = 13.sp) }
                    Text(stringResource(R.string.back), color = Uk.muted, fontSize = 13.sp,
                        modifier = Modifier.clickable { freeText = false }.padding(4.dp))
                }
            } else {
                // 4つの選択肢＋「その他…」。狭い画面では折り返す
                FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    for (c in choices) NoteChip(c, selected = c == note) { save(c) }
                    NoteChip(stringResource(R.string.other_choice), selected = false) { freeText = true }
                }
            }
        }
    }
}

@Composable
private fun NoteChip(title: String, selected: Boolean, onClick: () -> Unit) {
    Text(
        title, color = if (selected) Color.White else Uk.muted, fontSize = 12.sp, fontWeight = FontWeight.Medium,
        modifier = Modifier.defaultMinSize(minWidth = 88.dp).clip(CircleShape)
            .background(if (selected) Uk.tint else Uk.bg)
            .clickable(onClick = onClick).padding(horizontal = 10.dp, vertical = 6.dp),
        textAlign = TextAlign.Center,
    )
}
