package com.nativephp.plugins.native_ui.ui

import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.nativerender.*
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A snapping pan (`pan-y-snap`) settles on the point nearest where the
 * finger's speed would carry it. A finger that stopped before it lifted
 * has no speed left, so it settles on the point nearest where it is.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class GestureAreaSnapTest {
    @get:Rule val compose = createComposeRule()

    /** A settle cut short by the last test's teardown leaves the pan where it was. */
    @Before fun rest() {
        SharedValueStore.set(PanId, 0f)
    }

    @After fun reset() {
        NativeUIBridge.events.clear()
    }

    @Test fun dragHeldStillThenLetGoShortOfHalfwaySpringsBack() {
        render()
        compose.onNodeWithTag("node-2").performTouchInput {
            drag()
            // No moves while the finger rests, as on a device.
            advanceEventTime(200)
            up()
        }
        compose.runOnIdle {
            assertEquals(0f, SharedValueStore.valueOf(PanId), 0.01f)
            assertEquals(listOf("change:8:0.0,0.0"), events())
        }
    }

    @Test fun flickLetGoShortOfHalfwayCarriesToTheFarPoint() {
        render()
        compose.onNodeWithTag("node-2").performTouchInput {
            drag()
            up()
        }
        compose.runOnIdle {
            assertEquals(600f, SharedValueStore.valueOf(PanId), 0.01f)
            assertEquals(listOf("change:8:0.0,600.0"), events())
        }
    }

    @Test fun flickAfterAPauseStillCarriesToTheFarPoint() {
        render()
        compose.onNodeWithTag("node-2").performTouchInput {
            drag()
            advanceEventTime(200)
            repeat(3) { moveBy(Offset(0f, 25.dp.toPx())) }
            up()
        }
        compose.runOnIdle { assertEquals(600f, SharedValueStore.valueOf(PanId), 0.01f) }
    }

    /** About 190dp down (200 less touch slop) at 25dp a frame: under halfway, but quick. */
    private fun TouchInjectionScope.drag() {
        down(center)
        repeat(8) { moveBy(Offset(0f, 25.dp.toPx())) }
    }

    private fun render() {
        compose.setContent { GestureAreaRenderer.Render(area(), Modifier) }
    }

    private fun events() = NativeUIBridge.events.filter { it.startsWith("change:8:") }

    private fun area() = NativeUINode(
        1, "", null, null,
        GenericProps(mapOf("pan-y-id" to PanId, "pan-y-initial" to 0f, "pan-y-snap" to "-600,0,600", "on_drag_end" to 8)),
        0, 0, listOf(NativeUINode(2, "", null, null, GenericProps(emptyMap()), 0, 0, emptyList())),
    )

    private companion object {
        /** Its own SharedValue, so no other test's pan moves it. */
        const val PanId = 4401
    }
}
