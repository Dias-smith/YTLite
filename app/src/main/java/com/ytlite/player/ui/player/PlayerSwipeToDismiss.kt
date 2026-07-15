package com.ytlite.player.ui.player

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.lazy.LazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.Velocity
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import kotlin.math.roundToInt

@Stable
class PlayerSwipeToDismissState internal constructor(
    private val density: androidx.compose.ui.unit.Density,
    private val scope: CoroutineScope,
    private val isListAtTop: () -> Boolean,
    private val onDismiss: () -> Unit,
) {
    var dragOffset by mutableFloatStateOf(0f)
        private set

    private val dismissThresholdPx = with(density) { 120.dp.toPx() }
    private var dismissRequested = false

    private fun requestDismiss() {
        if (dismissRequested) return
        dismissRequested = true
        dragOffset = 0f
        onDismiss()
    }

    val nestedScrollConnection = object : NestedScrollConnection {
        override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
            if (dragOffset <= 0f || available.y >= 0f) return Offset.Zero
            val consumed = minOf(dragOffset, -available.y)
            dragOffset -= consumed
            return Offset(0f, -consumed)
        }

        override fun onPostScroll(
            consumed: Offset,
            available: Offset,
            source: NestedScrollSource,
        ): Offset {
            if (!isListAtTop() || available.y <= 0f) return Offset.Zero
            dragOffset += available.y
            return Offset(0f, available.y)
        }

        override suspend fun onPreFling(available: Velocity): Velocity {
            if (dragOffset >= dismissThresholdPx && available.y > 0f) {
                requestDismiss()
                return available
            }
            return Velocity.Zero
        }

        override suspend fun onPostFling(consumed: Velocity, available: Velocity): Velocity {
            if (!dismissRequested) {
                settle()
            }
            return Velocity.Zero
        }
    }

    fun dragBy(amount: Float) {
        if (!isListAtTop() && dragOffset <= 0f) return
        dragOffset = (dragOffset + amount).coerceAtLeast(0f)
    }

    fun settle() {
        if (dismissRequested) return
        if (dragOffset >= dismissThresholdPx) {
            requestDismiss()
            return
        }
        if (dragOffset <= 0f) return
        val start = dragOffset
        scope.launch {
            val animatable = Animatable(start)
            animatable.animateTo(
                targetValue = 0f,
                animationSpec = tween(durationMillis = 200),
            ) {
                dragOffset = value
            }
        }
    }
}

@Composable
fun rememberPlayerSwipeToDismissState(
    listState: LazyListState,
    onDismiss: () -> Unit,
): PlayerSwipeToDismissState {
    val density = LocalDensity.current
    val scope = rememberCoroutineScope()
    val atTop by remember {
        derivedStateOf {
            listState.firstVisibleItemIndex == 0 && listState.firstVisibleItemScrollOffset == 0
        }
    }
    val currentAtTop by rememberUpdatedState(atTop)
    val currentOnDismiss by rememberUpdatedState(onDismiss)

    return remember(density, scope) {
        PlayerSwipeToDismissState(
            density = density,
            scope = scope,
            isListAtTop = { currentAtTop },
            onDismiss = { currentOnDismiss() },
        )
    }
}

fun Modifier.playerSwipeToDismiss(
    state: PlayerSwipeToDismissState,
    enabled: Boolean,
): Modifier {
    if (!enabled) return this
    return this
        .nestedScroll(state.nestedScrollConnection)
        .offset {
            IntOffset(0, state.dragOffset.roundToInt())
        }
}

fun Modifier.playerSwipeToDismissHeader(
    state: PlayerSwipeToDismissState,
    enabled: Boolean,
): Modifier {
    if (!enabled) return this
    return pointerInput(state) {
        detectVerticalDragGestures(
            onVerticalDrag = { change, dragAmount ->
                state.dragBy(dragAmount)
                if (state.dragOffset > 0f) {
                    change.consume()
                }
            },
            onDragEnd = { state.settle() },
            onDragCancel = { state.settle() },
        )
    }
}
