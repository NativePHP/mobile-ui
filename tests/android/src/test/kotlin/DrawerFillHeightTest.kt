package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.height
import com.nativephp.mobile.ui.nativerender.*
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class DrawerFillHeightTest {
    @get:Rule val compose = createComposeRule()

    @Test fun anHFullRootReachesTheBottomOfTheDrawer() {
        open(fill(2))
        val root = compose.onNodeWithTag("node-2").getUnclippedBoundsInRoot()
        assertNear(viewport().top, root.top)
        assertNear(viewport().bottom, root.bottom)
    }

    @Test fun aSiblingThatDoesNotFillKeepsItsOwnHeight() {
        open(fill(2), plain(3))
        assertNear(viewport().height, compose.onNodeWithTag("node-2").getUnclippedBoundsInRoot().height)
        compose.onNodeWithTag("node-3").assertHeightIsEqualTo(120.dp)
    }

    @Test fun aRootTallerThanTheDrawerStillGrowsAndScrolls() {
        open(fill(2), height = 100.dp)
        compose.onNodeWithTag("node-2").assertHeightIsEqualTo(120.dp)
        compose.onNode(drawerScroll).performTouchInput { swipeUp() }
        assertNear(viewport().bottom, compose.onNodeWithTag("node-2").getUnclippedBoundsInRoot().bottom)
    }

    private val drawerScroll = SemanticsMatcher.keyIsDefined(SemanticsProperties.VerticalScrollAxisRange)

    /** The drawer's scrolling column: the height an `h-full` child should reach. */
    private fun viewport() = compose.onNode(drawerScroll).getUnclippedBoundsInRoot()

    private fun open(vararg children: NativeUINode, height: Dp? = null) {
        compose.setContent {
            Box(if (height != null) Modifier.height(height) else Modifier) {
                NativeLayoutDrawerHost(NativeUINode(1, "native_drawer", null, null, GenericProps(), 0, 0, children.toList())) {}
            }
        }
        compose.onNodeWithContentDescription("Open menu").performClick()
        compose.waitForIdle()
    }

    private fun assertNear(expected: Dp, actual: Dp) = assertEquals(expected.value, actual.value, 0.5f)

    /** `w-full h-full`, like a drawer root column with `justify-between`. */
    private fun fill(id: Int) = NativeUINode(
        id, "column", NodeLayout.EMPTY.copy(widthMode = SizeMode.FILL, heightMode = SizeMode.FILL), null, GenericProps(), 0, 0, emptyList())

    private fun plain(id: Int) = NativeUINode(id, "column", null, null, GenericProps(), 0, 0, emptyList())
}
