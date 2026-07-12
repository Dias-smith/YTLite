package com.ytlite.player.ui.library

import org.junit.Assert.assertEquals
import org.junit.Test

class ReorderablePlaylistLogicTest {

    @Test
    fun clampDragOffsetY_limitsMovementWithinGroupBounds() {
        val itemHeight = 76f
        assertEquals(0f, clampDragOffsetY(100f, draggingIndex = 0, itemCount = 1, itemHeight))
        assertEquals(152f, clampDragOffsetY(200f, draggingIndex = 0, itemCount = 3, itemHeight))
        assertEquals(-76f, clampDragOffsetY(-200f, draggingIndex = 1, itemCount = 3, itemHeight))
        assertEquals(0f, clampDragOffsetY(10f, draggingIndex = 2, itemCount = 3, itemHeight))
    }
}
