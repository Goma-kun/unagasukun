package jp.nishira.unagasukun.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Add
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import jp.nishira.unagasukun.R
import jp.nishira.unagasukun.data.Prefs
import kotlin.math.roundToInt

/**
 * 浮かぶ「＋」。指で動かせて、置いた場所を端末ごとに覚える（割合で持つので縦横が変わっても画面の外に出ない）。
 * 既定は左下（Apple のリマインダーと同じ・左手の親指が届く）
 */
@Composable
fun FloatingAddButton(prefs: Prefs, bottomInset: Dp, onClick: () -> Unit) {
    val size = 52.dp
    val margin = 16.dp
    val density = LocalDensity.current
    var drag by remember { mutableStateOf(Offset.Zero) }
    var fx by remember { mutableStateOf(prefs.fabX) }
    var fy by remember { mutableStateOf(prefs.fabY) }
    val a11y = stringResource(R.string.add_plan_a11y)

    BoxWithConstraints(Modifier.fillMaxSize()) {
        val areaW = with(density) { (maxWidth - margin * 2 - size).toPx().coerceAtLeast(1f) }
        val areaH = with(density) { (maxHeight - margin * 2 - bottomInset - size).toPx().coerceAtLeast(1f) }
        val originX = with(density) { margin.toPx() }
        val originY = with(density) { margin.toPx() }
        val baseX = originX + areaW * fx
        val baseY = originY + areaH * fy
        Box(
            Modifier.offset { IntOffset((baseX + drag.x).roundToInt(), (baseY + drag.y).roundToInt()) }
                .size(size).shadow(6.dp, CircleShape).background(Uk.navyLight, CircleShape)
                .semantics { contentDescription = a11y }
                .pointerInput(Unit) { detectTapGestures { onClick() } }
                .pointerInput(areaW, areaH) {
                    detectDragGestures(
                        onDrag = { change, delta -> change.consume(); drag += delta },
                        onDragEnd = {
                            fx = ((baseX + drag.x - originX) / areaW).coerceIn(0f, 1f)
                            fy = ((baseY + drag.y - originY) / areaH).coerceIn(0f, 1f)
                            prefs.fabX = fx; prefs.fabY = fy
                            drag = Offset.Zero
                        },
                        onDragCancel = { drag = Offset.Zero },
                    )
                },
            contentAlignment = Alignment.Center,
        ) {
            Icon(Icons.Default.Add, contentDescription = null, tint = Color.White, modifier = Modifier.size(26.dp))
        }
    }
}
