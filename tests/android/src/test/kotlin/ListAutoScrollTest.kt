package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.junit4.StateRestorationTester
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.nativerender.GenericProps
import com.nativephp.mobile.ui.nativerender.NativeUINode
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.ParameterizedRobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(ParameterizedRobolectricTestRunner::class)
@Config(sdk = [35])
class ListAutoScrollTest(private val virtual: Boolean) {
    @get:Rule val compose = createComposeRule()

    companion object {
        @JvmStatic
        @ParameterizedRobolectricTestRunner.Parameters(name = "virtual={0}")
        fun cases() = listOf(arrayOf(false), arrayOf(true))
    }

    private val count = mutableIntStateOf(4)
    private val request = mutableIntStateOf(12)
    private val shown = mutableStateOf(true)

    @Test fun waitsForTheRequestedRowAndDoesNotReapplyItAfterContentChanges() {
        showList()
        assertTopRow(0)
        compose.runOnIdle { count.intValue = 8 }
        assertTopRow(0)
        compose.runOnIdle { count.intValue = 12 }
        assertTopRow(0)
        compose.runOnIdle { count.intValue = 30 }
        assertTopRow(12)

        compose.onNodeWithTag("list").performScrollToIndex(0)
        compose.runOnIdle { count.intValue = 4 }
        compose.runOnIdle { count.intValue = 30 }
        assertTopRow(0)
        compose.runOnIdle { count.intValue = 0 }
        compose.runOnIdle { count.intValue = 30 }
        assertTopRow(0)
    }

    @Test fun disablingThenRestoringTheSameRequestRearmsIt() {
        count.intValue = 30
        request.intValue = -3
        showList()
        assertTopRow(0)

        compose.runOnIdle { request.intValue = 12 }
        assertTopRow(12)
        compose.runOnIdle { request.intValue = -1 }
        compose.onNodeWithTag("list").performScrollToIndex(5)
        assertTopRow(5)
        compose.runOnIdle { request.intValue = 12 }
        assertTopRow(12)
        compose.runOnIdle { request.intValue = 9 }
        assertTopRow(9)
    }

    @Test fun restoringSavedStateKeepsTheReadersPositionInsteadOfReapplyingTheRequest() {
        count.intValue = 30
        val restoration = StateRestorationTester(compose)
        showList(restoration)
        assertTopRow(12)

        compose.onNodeWithTag("list").performScrollToIndex(5)
        restoration.emulateSavedInstanceStateRestore()
        assertTopRow(5)
    }

    @Test fun aRequestChangedWhileTheListIsSavedIsHonouredWhenItReturns() {
        count.intValue = 30
        showList()
        assertTopRow(12)
        compose.onNodeWithTag("list").performScrollToIndex(5)

        compose.runOnIdle { shown.value = false }
        compose.runOnIdle { request.intValue = 9 }
        compose.runOnIdle { shown.value = true }
        assertTopRow(9)
    }

    private fun showList(restoration: StateRestorationTester = StateRestorationTester(compose)) {
        restoration.setContent {
            val rows = (0 until count.intValue).map { index ->
                NativeUINode(index + 100, "text", null, null, GenericProps(), 0, 0, emptyList())
            }
            val node = NativeUINode(1, if (virtual) "virtual_list" else "list", null, null,
                GenericProps(mapOf("count" to count.intValue, "auto_scroll_to" to request.intValue)), 0, 0, rows)
            val modifier = Modifier.width(300.dp).height(200.dp).testTag("list")
            val saved = rememberSaveableStateHolder()
            if (shown.value) saved.SaveableStateProvider("list") {
                MaterialTheme {
                    if (virtual) VirtualListRenderer.Render(node, modifier)
                    else ListRenderer.Render(node, modifier)
                }
            }
        }
    }

    private fun assertTopRow(index: Int) {
        val list = compose.onNodeWithTag("list").getUnclippedBoundsInRoot()
        val row = compose.onNodeWithTag("node-${index + 100}").assertIsDisplayed().getUnclippedBoundsInRoot()
        assertEquals("row $index is at the top", list.top.value, row.top.value, 1f)
    }
}
