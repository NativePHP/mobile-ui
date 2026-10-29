package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.verticalScroll
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.nativerender.*
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A swipe over a pressable fires the gesture area's `@swipe` and not the
 * pressable's `@press` as well, as on iOS, without taking a drag away from
 * an enclosing scroll container or the area's own pan.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class GestureAreaSwipeTest {
    @get:Rule val compose = createComposeRule()

    @After fun reset() {
        NativeUIBridge.events.clear()
    }

    @Test fun swipeOverAPressableInsideTheAreaOnlySwipes() {
        compose.setContent { GestureAreaRenderer.Render(area(pressable()), Modifier) }
        compose.onNodeWithTag("node-2").performTouchInput { swipeLeft() }
        compose.runOnIdle { assertEquals(listOf("change:5:left"), events()) }
    }

    @Test fun tapOnAPressableInsideTheAreaStillPresses() {
        compose.setContent { GestureAreaRenderer.Render(area(pressable()), Modifier) }
        compose.onNodeWithTag("node-2").performTouchInput { click() }
        compose.runOnIdle { assertEquals(listOf("press:9"), events()) }
    }

    @Test fun swipeInsideAPressableAroundTheAreaOnlySwipes() {
        compose.setContent {
            Box(Modifier.clickable { NativeUIBridge.events += "outer press" }) {
                GestureAreaRenderer.Render(area(node(3)), Modifier)
            }
        }
        compose.onNodeWithTag("node-3", useUnmergedTree = true).performTouchInput { swipeRight() }
        compose.runOnIdle { assertEquals(listOf("change:5:right"), events()) }
    }

    @Test fun twoFingerSwipeOverAPressableOnlySwipes() {
        compose.setContent { GestureAreaRenderer.Render(area(pressable(), fingers = 2), Modifier) }
        compose.onNodeWithTag("node-2").performTouchInput {
            down(0, centerRight - Offset(20f, 20f))
            down(1, centerRight - Offset(20f, -20f))
            repeat(10) {
                updatePointerBy(0, Offset(-width / 12f, 0f))
                updatePointerBy(1, Offset(-width / 12f, 0f))
                move()
            }
            up(0)
            up(1)
        }
        compose.runOnIdle { assertEquals(listOf("change:5:left"), events()) }
    }

    @Test fun verticalDragStillScrollsAnEnclosingScrollContainer() {
        val scroll = ScrollState(0)
        compose.setContent {
            Column(Modifier.height(200.dp).verticalScroll(scroll)) {
                GestureAreaRenderer.Render(area(pressable()), Modifier)
                Spacer(Modifier.height(1000.dp))
            }
        }
        compose.onNodeWithTag("node-2").performTouchInput { swipeUp() }
        compose.runOnIdle {
            assertTrue("scrolled to ${scroll.value}", scroll.value > 0)
            assertTrue(events().toString(), "press:9" !in events())
        }
    }

    @Test fun areaWithAPanStillPansWhenItAlsoSwipes() {
        compose.setContent {
            GestureAreaRenderer.Render(area(pressable(), props = mapOf("pan-x-id" to 4101)), Modifier)
        }
        compose.onNodeWithTag("node-2").performTouchInput { swipeLeft() }
        compose.runOnIdle {
            assertTrue("panned to ${SharedValueStore.valueOf(4101)}", SharedValueStore.valueOf(4101) < -100f)
            assertEquals(listOf("change:5:left"), events())
        }
    }

    /**
     * This test's swipe and press events. Another test's debounced text
     * change can land in the shared bridge log while one of these runs.
     */
    private fun events() = NativeUIBridge.events.filter {
        it.startsWith("change:5:") || it == "press:9" || it == "outer press"
    }

    private fun area(child: NativeUINode, fingers: Int = 1, props: Map<String, Any> = emptyMap()) =
        node(1, mapOf("on_swipe" to 5, "swipe-fingers" to fingers) + props, children = listOf(child))

    private fun pressable() = node(2, onPress = 9)

    private fun node(
        id: Int,
        props: Map<String, Any> = emptyMap(),
        onPress: Int = 0,
        children: List<NativeUINode> = emptyList(),
    ) = NativeUINode(id, "", null, null, GenericProps(props), onPress, 0, children)
}
