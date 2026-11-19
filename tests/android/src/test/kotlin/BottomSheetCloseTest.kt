package com.nativephp.plugins.native_ui.ui

import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.nativephp.mobile.ui.nativerender.*
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class BottomSheetCloseTest {
    @get:Rule val compose = createComposeRule()

    private val sheet = mutableStateOf(sheet(visible = true, detents = "large"))

    @Before fun open() {
        compose.setContent { MaterialTheme { BottomSheetRenderer.Render(sheet.value, Modifier) } }
        compose.onNodeWithTag("node-2").assertExists()
    }

    @Test fun aSheetClosedWithNewDetentsDoesNotOpenAgain() {
        compose.runOnIdle { sheet.value = sheet(visible = false, detents = "medium") }
        compose.waitForIdle()
        compose.onNodeWithTag("node-2").assertDoesNotExist()
    }

    @Test fun aSheetGrabbedWhileSlidingAwayStillLeaves() {
        compose.mainClock.autoAdvance = false
        compose.runOnIdle { sheet.value = sheet(visible = false, detents = "large") }
        compose.mainClock.advanceTimeBy(100)
        compose.onNodeWithTag("node-2").performTouchInput { down(center); moveBy(Offset(0f, -100f)) }
        compose.mainClock.advanceTimeBy(1000)
        compose.onNodeWithTag("node-2").assertDoesNotExist()
    }

    private fun sheet(visible: Boolean, detents: String) = NativeUINode(
        1, "bottom_sheet", null, null, GenericProps(mapOf("visible" to visible, "detents" to detents, "on_dismiss" to 9)), 0, 0,
        listOf(NativeUINode(2, "", null, null, GenericProps(), 0, 0, emptyList())))
}
