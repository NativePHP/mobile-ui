package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.hapticfeedback.HapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.nativerender.*
import org.junit.After
import org.junit.Before
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A pan with a trigger (`pan-x-trigger`) follows a drag its own way only,
 * plays a haptic each time it goes out past the point, fires `@trigger`
 * when let go past it, and springs back to rest either way.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class GestureAreaTriggerTest {
    @get:Rule val compose = createComposeRule()

    private val haptics = mutableListOf<HapticFeedbackType>()

    /** A spring back cut short by the last test's teardown leaves the pan where it was. */
    @Before fun rest() {
        SharedValueStore.set(PanId, 0f)
    }

    @After fun reset() {
        NativeUIBridge.events.clear()
    }

    @Test fun pullLetGoPastThePointTriggersAndSpringsBack() {
        render()
        compose.onNodeWithTag("node-2").performTouchInput { pull(80) }
        compose.runOnIdle {
            assertEquals(listOf("press:7"), events())
            assertEquals(0f, SharedValueStore.valueOf(PanId), 0.01f)
        }
    }

    @Test fun pullFollowsTheFingerToThePointThenResists() {
        var slop = 0f
        compose.setContent {
            slop = with(LocalDensity.current) { LocalViewConfiguration.current.touchSlop.toDp().value }
            CompositionLocalProvider(LocalHapticFeedback provides recorder()) {
                GestureAreaRenderer.Render(area(), Modifier)
            }
        }
        // The drag starts once the finger passes touch slop, which it keeps.
        compose.onNodeWithTag("node-2").performTouchInput {
            down(center)
            moveBy(Offset(30.dp.toPx(), 0f))
            moveBy(Offset(20.dp.toPx(), 0f))
        }
        compose.runOnIdle { assertEquals(50f - slop, SharedValueStore.valueOf(PanId), 0.5f) }
        compose.onNodeWithTag("node-2").performTouchInput { moveBy(Offset(40.dp.toPx(), 0f)) }
        compose.runOnIdle { assertEquals(60f + (30f - slop) / 3f, SharedValueStore.valueOf(PanId), 0.5f) }
        compose.onNodeWithTag("node-2").performTouchInput { up() }
    }

    @Test fun pullLetGoShortOfThePointOnlySpringsBack() {
        render()
        compose.onNodeWithTag("node-2").performTouchInput { pull(40) }
        compose.runOnIdle {
            assertEquals(emptyList<String>(), events())
            assertEquals(0f, SharedValueStore.valueOf(PanId), 0.01f)
            assertEquals(emptyList<HapticFeedbackType>(), haptics)
        }
    }

    @Test fun hapticPlaysEachTimeThePullGoesOutPastThePoint() {
        render()
        compose.onNodeWithTag("node-2").performTouchInput {
            down(center)
            listOf(40, 40, -40, -20, 60).forEach { moveBy(Offset(it.dp.toPx(), 0f)) }
            up()
        }
        compose.runOnIdle {
            assertEquals(listOf(HapticFeedbackType.GestureThresholdActivate, HapticFeedbackType.GestureThresholdActivate), haptics)
            assertEquals(listOf("press:7"), events())
        }
    }

    @Test fun pullBackUnderThePointBeforeLettingGoDoesNotTrigger() {
        render()
        compose.onNodeWithTag("node-2").performTouchInput {
            down(center)
            listOf(40, 40, -50).forEach { moveBy(Offset(it.dp.toPx(), 0f)) }
            up()
        }
        compose.runOnIdle {
            assertEquals(emptyList<String>(), events())
            assertEquals(1, haptics.size)
        }
    }

    @Test fun dragTheOtherWayIsLeftToAnEnclosingScrollContainer() {
        val scroll = ScrollState(500)
        compose.setContent {
            CompositionLocalProvider(LocalHapticFeedback provides recorder()) {
                Row(Modifier.width(300.dp).horizontalScroll(scroll)) {
                    Spacer(Modifier.width(500.dp))
                    GestureAreaRenderer.Render(area(), Modifier)
                    Spacer(Modifier.width(500.dp))
                }
            }
        }
        compose.onNodeWithTag("node-2").performTouchInput { pull(-80) }
        compose.runOnIdle {
            assertTrue("scrolled to ${scroll.value}", scroll.value > 500)
            assertEquals(0f, SharedValueStore.valueOf(PanId), 0.01f)
            assertEquals(emptyList<String>(), events())
        }
    }

    /** Drags [dp] along x in steps, then lifts. */
    private fun TouchInjectionScope.pull(dp: Int) {
        down(center)
        repeat(8) { moveBy(Offset((dp / 8f).dp.toPx(), 0f)) }
        up()
    }

    private fun render() {
        compose.setContent {
            CompositionLocalProvider(LocalHapticFeedback provides recorder()) {
                GestureAreaRenderer.Render(area(), Modifier)
            }
        }
    }

    private fun recorder() = object : HapticFeedback {
        override fun performHapticFeedback(hapticFeedbackType: HapticFeedbackType) {
            haptics += hapticFeedbackType
        }
    }

    private fun events() = NativeUIBridge.events.filter { it.startsWith("press:7") }

    private fun area() = NativeUINode(
        1, "", null, null,
        GenericProps(mapOf("pan-x-id" to PanId, "pan-x-initial" to 0f, "pan-x-trigger" to 60f, "on_trigger" to 7)),
        0, 0, listOf(NativeUINode(2, "", null, null, GenericProps(emptyMap()), 0, 0, emptyList())),
    )

    private companion object {
        /** Its own SharedValue, so no other test's pan moves it. */
        const val PanId = 4301
    }
}
