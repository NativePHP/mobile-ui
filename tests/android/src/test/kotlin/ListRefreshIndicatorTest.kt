package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.nativerender.GenericProps
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.plugins.native_ui.NativeUIRefreshIndicators
import com.nativephp.plugins.native_ui.REFRESH_INDICATOR_TAG
import com.nativephp.plugins.native_ui.RefreshIndicatorScope
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ListRefreshIndicatorTest {
    @get:Rule val compose = createComposeRule()

    private var seen: RefreshIndicatorScope? = null

    @After fun forgetIndicators() = NativeUIRefreshIndicators.reset()

    @Test fun aListNamingNoIndicatorKeepsTheStockOne() {
        registerProbe()
        showList(mapOf("on_refresh" to 7))

        compose.onAllNodesWithTag(REFRESH_INDICATOR_TAG).assertCountEquals(0)
        compose.onAllNodesWithTag("probe").assertCountEquals(0)
    }

    @Test fun anIndicatorNoPluginRegisteredFallsBackToTheStockOne() {
        registerProbe()
        showList(mapOf("on_refresh" to 7, "refresh_indicator" to "missing"))

        compose.onAllNodesWithTag(REFRESH_INDICATOR_TAG).assertCountEquals(0)
        compose.onAllNodesWithTag("probe").assertCountEquals(0)
    }

    @Test fun theRegisteredIndicatorDrawsInsideTheDiscWithItsOptions() {
        registerProbe()
        showList(mapOf(
            "on_refresh" to 7,
            "refresh_indicator" to "probe",
            "refresh_indicator_options" to """{"asset":"animations/splash.lottie","speed":1.5,"loop":true}""",
        ))

        compose.onNodeWithTag("probe").assertExists()
        val options = seen!!.options
        assertEquals("animations/splash.lottie", options["asset"])
        assertEquals(1.5, (options["speed"] as Number).toDouble(), 0.0)
        assertEquals(true, options["loop"])
    }

    @Test fun malformedOptionsReachTheIndicatorAsNone() {
        registerProbe()
        showList(mapOf("on_refresh" to 7, "refresh_indicator" to "probe", "refresh_indicator_options" to "not json"))

        compose.onNodeWithTag("probe").assertExists()
        assertTrue(seen!!.options.isEmpty())
    }

    @Test fun theIndicatorFollowsThePullThenKnowsItIsRefreshing() {
        registerProbe()
        showList(mapOf("on_refresh" to 7, "refresh_indicator" to "probe"))
        assertEquals(0f, seen!!.progress(), 0.001f)
        assertFalse(seen!!.isRefreshing)

        compose.onNodeWithTag("list").performTouchInput {
            down(Offset(centerX, 10f))
            repeat(5) { moveBy(Offset(0f, 10f)) }
        }
        compose.waitForIdle()
        val pulled = seen!!.progress()
        assertTrue("progress $pulled is part way", pulled > 0f && pulled < 1f)

        compose.mainClock.autoAdvance = false
        compose.onNodeWithTag("list").performTouchInput {
            repeat(10) { moveBy(Offset(0f, 40f)) }
            up()
        }
        compose.mainClock.advanceTimeBy(100)
        assertTrue(seen!!.isRefreshing)
    }

    @Test fun theDiscRestsBelowTheTopOfTheListWhileRefreshing() {
        registerProbe()
        showList(mapOf("on_refresh" to 7, "refresh_indicator" to "probe"))
        compose.mainClock.autoAdvance = false
        compose.onNodeWithTag("list").performTouchInput {
            down(Offset(centerX, 10f))
            repeat(10) { moveBy(Offset(0f, 40f)) }
            up()
        }
        compose.mainClock.advanceTimeBy(1000)

        val list = compose.onNodeWithTag("list").getBoundsInRoot()
        val disc = compose.onNodeWithTag(REFRESH_INDICATOR_TAG).getBoundsInRoot()
        assertEquals(48f, (disc.right - disc.left).value, 0.5f)
        assertEquals(48f, (disc.bottom - disc.top).value, 0.5f)
        assertEquals(80f - 48f, (disc.top - list.top).value, 0.5f)
    }

    private fun registerProbe() {
        NativeUIRefreshIndicators.register("probe") { scope ->
            seen = scope
            Box(Modifier.testTag("probe"))
        }
    }

    private fun showList(props: Map<String, Any>) {
        compose.setContent {
            val rows = (0 until 30).map { index ->
                NativeUINode(index + 100, "text", null, null, GenericProps(), 0, 0, emptyList())
            }
            val node = NativeUINode(1, "list", null, null, GenericProps(props), 0, 0, rows)
            MaterialTheme {
                ListRenderer.Render(node, Modifier.width(300.dp).height(400.dp).testTag("list"))
            }
        }
    }
}
