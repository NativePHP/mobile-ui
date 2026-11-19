package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.nativerender.GenericProps
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.NodeLayout
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * `native:lazy-stack` on Android. Each child is a 120dp box tagged
 * `node-<id>` (see the NodeView stand-in), in a 300dp-tall stack.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class LazyStackPositionTest {
    @get:Rule val compose = createComposeRule()

    private val ids = mutableStateOf((100 until 110).toList())
    private var props = GenericProps()
    private var gap = 0f

    @Test fun aReaderAtTheTopSeesChildrenAddedAbove() {
        show()
        assertAtTop(100)

        compose.runOnIdle { ids.value = listOf(99) + ids.value }
        assertAtTop(99)

        compose.runOnIdle { ids.value = listOf(97, 98) + ids.value }
        assertAtTop(97)
    }

    @Test fun aReaderScrolledDownKeepsTheirChildWhenChildrenAreAddedAbove() {
        show()
        stack().performScrollToIndex(5)
        assertAtTop(105)

        compose.runOnIdle { ids.value = listOf(98, 99) + ids.value }
        assertAtTop(105)

        // And when the oldest are trimmed off the end, as a capped feed does.
        compose.runOnIdle { ids.value = listOf(97) + ids.value.dropLast(2) }
        assertAtTop(105)
    }

    @Test fun contentPaddingAndGapPlaceTheChildren() {
        props = GenericProps(
            mapOf(
                "content_padding_top" to 16f,
                "content_padding_left" to 8f,
                "content_padding_bottom" to 16f,
                "content_padding_right" to 8f,
            )
        )
        gap = 10f
        show()

        val box = compose.onNodeWithTag("stack").getUnclippedBoundsInRoot()
        val first = compose.onNodeWithTag("node-100").getUnclippedBoundsInRoot()
        val second = compose.onNodeWithTag("node-101").getUnclippedBoundsInRoot()
        assertEquals(box.top.value + 16f, first.top.value, 1f)
        assertEquals(box.left.value + 8f, first.left.value, 1f)
        assertEquals(first.bottom.value + 10f, second.top.value, 1f)
    }

    @Test fun insideAScrollViewItFallsBackToAPlainColumn() {
        compose.setContent {
            MaterialTheme {
                Column(Modifier.height(300.dp).verticalScroll(rememberScrollState())) {
                    LazyStackRenderer.Render(node(), Modifier.width(300.dp).testTag("stack"))
                }
            }
        }
        // Every child is composed, since there's no viewport to be lazy in.
        compose.onNodeWithTag("node-109").assertExists()
    }

    private fun node(): NativeUINode {
        val rows = ids.value.map { id ->
            NativeUINode(id, "text", null, null, GenericProps(), 0, 0, emptyList())
        }
        val layout = if (gap > 0f) NodeLayout(0f, 0, 0f, 0, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0, 0, 0, gap) else null
        return NativeUINode(1, "lazy_stack", layout, null, props, 0, 0, rows)
    }

    private fun show() {
        compose.setContent {
            MaterialTheme {
                LazyStackRenderer.Render(node(), Modifier.width(300.dp).height(300.dp).testTag("stack"))
            }
        }
    }

    private fun stack() = compose.onNode(hasScrollToIndexAction())

    private fun assertAtTop(id: Int) {
        val box = compose.onNodeWithTag("stack").getUnclippedBoundsInRoot()
        val row = compose.onNodeWithTag("node-$id").assertIsDisplayed().getUnclippedBoundsInRoot()
        assertEquals("child $id is at the top", box.top.value, row.top.value, 1f)
    }
}
