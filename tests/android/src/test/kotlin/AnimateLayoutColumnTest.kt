package com.nativephp.plugins.native_ui.ui

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.nativephp.mobile.ui.nativerender.FlexContainer
import com.nativephp.mobile.ui.nativerender.GenericProps
import com.nativephp.mobile.ui.nativerender.LocalAnimateLayoutChildren
import com.nativephp.mobile.ui.nativerender.NativeUINode
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * `animate-layout` on a plain column (core's FlexContainer, compiled from the
 * Mobile checkout, so this needs one with `LocalAnimateLayoutChildren`).
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AnimateLayoutColumnTest {
    @get:Rule val compose = createComposeRule()

    private val ids = mutableStateOf(listOf(1, 2, 3))

    private fun show(animate: Boolean) {
        compose.setContent {
            val children = ids.value.map { NativeUINode(it, "text", null, null, GenericProps(), 0, 0, emptyList()) }
            CompositionLocalProvider(LocalAnimateLayoutChildren provides animate) {
                FlexContainer(childNodes = children) {}
            }
        }
    }

    private fun top(id: Int) = compose.onNodeWithTag("node-$id").getUnclippedBoundsInRoot().top.value

    @Test fun keyedChildrenSlideToTheirNewPlace() {
        show(animate = true)
        assertEquals(240f, top(3), 0.5f)
        compose.mainClock.autoAdvance = false
        compose.runOnIdle { ids.value = listOf(3, 1, 2) }
        val seen = mutableListOf<Float>()
        repeat(12) { compose.mainClock.advanceTimeByFrame(); seen += top(3) }
        assertTrue("row 3 passes between its places: $seen", seen.any { it > 1f && it < 239f })
        compose.mainClock.autoAdvance = true
        compose.waitForIdle()
        assertEquals(0f, top(3), 0.5f)
        assertEquals(120f, top(1), 0.5f)
    }

    @Test fun withoutTheFlagChildrenJump() {
        show(animate = false)
        compose.mainClock.autoAdvance = false
        compose.runOnIdle { ids.value = listOf(3, 1, 2) }
        val seen = mutableListOf<Float>()
        repeat(12) { compose.mainClock.advanceTimeByFrame(); seen += top(3) }
        assertTrue("row 3 jumps: $seen", seen.drop(1).all { it < 0.5f })
    }

    @Test fun aNewChildLandsInItsPlaceWithoutMovingTheOthers() {
        show(animate = true)
        compose.runOnIdle { ids.value = listOf(1, 2, 3, 4) }
        compose.waitForIdle()
        assertEquals(360f, top(4), 0.5f)
        assertEquals(240f, top(3), 0.5f)
    }
}
