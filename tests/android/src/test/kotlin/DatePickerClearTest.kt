package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.nativephp.mobile.ui.nativerender.*
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A clearable compact picker draws an X beside its calendar icon while it
 * holds a date. Tapping the X sends `''` through the change callback and
 * leaves the dialog closed; tapping the rest of the field, or clicking it
 * through TalkBack, opens the dialog.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class DatePickerClearTest {
    @get:Rule val compose = createComposeRule()

    @After fun reset() {
        NativeUIBridge.events.clear()
    }

    @Test fun tappingTheXClearsTheDateAndLeavesTheDialogClosed() {
        render(picker(1, "value" to "2026-11-06", "clearable" to true))

        compose.onNodeWithContentDescription("Clear").performClick()

        compose.runOnIdle { assertEquals(listOf("select:5:"), NativeUIBridge.events) }
        compose.onNodeWithText("Done").assertDoesNotExist()
        compose.onNodeWithContentDescription("Clear").assertDoesNotExist()
    }

    @Test fun tappingTheFieldOpensTheDialog() {
        render(picker(1, "value" to "2026-11-06", "clearable" to true))

        compose.onNodeWithText("Nov 6, 2026").performTouchInput { click(centerLeft + percentOffset(0.25f, 0f)) }

        compose.onNodeWithText("Done").assertExists()
        compose.runOnIdle { assertEquals(emptyList<String>(), NativeUIBridge.events) }
    }

    @Test fun clickingTheFieldThroughAccessibilityOpensTheDialog() {
        render(picker(1, "value" to "2026-11-06", "clearable" to true))

        compose.onNodeWithText("Nov 6, 2026").performSemanticsAction(SemanticsActions.OnClick)

        compose.onNodeWithText("Done").assertExists()
    }

    @Test fun drawsNoXWithoutADateClearableOrAnEnabledField() {
        render(
            picker(1, "clearable" to true),
            picker(2, "value" to "2026-11-06"),
            picker(3, "value" to "2026-11-06", "clearable" to true, "disabled" to true),
        )

        compose.onNodeWithContentDescription("Clear").assertDoesNotExist()
    }

    @Test fun labelsTheXWithTheClearLabel() {
        render(picker(1, "value" to "2026-11-06", "clearable" to true, "clear_label" to "Remove date"))

        compose.onNodeWithContentDescription("Remove date").assertExists()
    }

    private fun render(vararg pickers: NativeUINode) {
        compose.setContent {
            MaterialTheme {
                Column { pickers.forEach { DatePickerRenderer.Render(it, Modifier) } }
            }
        }
    }

    private fun picker(id: Int, vararg props: Pair<String, Any>) = NativeUINode(
        id, "", null, null,
        GenericProps(mapOf("locale" to "en-US", "on_change" to 5, "confirm_label" to "Done") + props),
        0, 0, emptyList(),
    )
}
