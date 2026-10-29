package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextRange
import com.nativephp.mobile.ui.nativerender.*
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.ParameterizedRobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * Where the caret goes when PHP pushes a new value into a text input: where
 * the `selection` prop says (code points), or the end of the text as before.
 */
@RunWith(ParameterizedRobolectricTestRunner::class)
@Config(sdk = [35])
class TextInputCaretTest(private val variant: String) {
    @get:Rule val compose = createComposeRule()

    companion object {
        @JvmStatic
        @ParameterizedRobolectricTestRunner.Parameters(name = "{0}")
        fun cases(): List<Array<Any>> = listOf("outlined", "filled", "bare").map { arrayOf<Any>(it) }
    }

    private val props = mutableStateOf<Map<String, Any>>(emptyMap())

    @After fun reset() {
        KeyboardFocusPolicy.fieldFocused(this, false)
        KeyboardFocusPolicy.fieldBlurred(this)
        KeyboardFocusPolicy.clearFocus = null
        NativeUIBridge.events.clear()
    }

    @Test fun aPushPutsTheCaretWherePhpSays() {
        render("hi @si there", caret = -1)
        push("hi @simonhamp there", caret = 13)
        assertEquals(TextRange(13), caret())
    }

    @Test fun aPushCanSelectARange() {
        render("hi @si there", caret = -1)
        push("hi @simonhamp there", caret = 3, end = 13)
        assertEquals(TextRange(3, 13), caret())
    }

    @Test fun aPushWithNothingToPlaceLeavesTheCaretAtTheEnd() {
        render("hi @si there", caret = -1)
        push("hi @simonhamp there", caret = -1)
        assertEquals(TextRange(19), caret())
    }

    @Test fun offsetsAreCodePointsAndClamped() {
        // The skin-toned thumb is two code points and four UTF-16 units.
        render("👍🏽 @si there", caret = -1)
        push("👍🏽 @simonhamp there", caret = 14)
        assertEquals(TextRange(16), caret())

        push("short", caret = 99)
        assertEquals(TextRange(5), caret())
    }

    @Test fun thePlacedCaretIsReportedToPhp() {
        render("hi @si there", caret = -1, extra = mapOf("on_selection_change" to 43))
        compose.runOnIdle { NativeUIBridge.events.clear() }
        push("hi @simonhamp there", caret = 13, extra = mapOf("on_selection_change" to 43))
        compose.runOnIdle {
            assertTrue(NativeUIBridge.events.toString(), "change:43:13,13\u001Fhi @simonhamp there" in NativeUIBridge.events)
        }
    }

    @Test fun anEchoOfWhatWasTypedNeverMovesTheCaret() {
        render("", caret = -1)
        compose.onNode(hasSetTextAction()).performClick().performTextInput("abc")
        push("abc", caret = 0)
        assertEquals(TextRange(3), caret())
    }

    @Test fun aPressElsewhereSeesWhereTheCaretIsNow() {
        compose.setContent {
            val focusManager = LocalFocusManager.current
            SideEffect { KeyboardFocusPolicy.clearFocus = { focusManager.clearFocus() } }
            MaterialTheme {
                Column {
                    val field = NativeUINode(7, "", null, null, GenericProps(mapOf(
                        "value" to "", "on_change" to 41, "sync_mode" to "debounce", "debounce_ms" to 5000,
                        "on_selection_change" to 43, "selection_debounce_ms" to 5000,
                        "keep_focus_on_submit" to true)), 0, 0, emptyList())
                    when (variant) {
                        "filled" -> FilledTextInputRenderer.Render(field, Modifier)
                        "bare" -> BareTextInputRenderer.Render(field, Modifier)
                        else -> OutlinedTextInputRenderer.Render(field, Modifier)
                    }
                    ButtonRenderer.Render(NativeUINode(8, "", null, null, GenericProps(mapOf("label" to "Pick", "on_press" to 99)), 0, 0, emptyList()), Modifier)
                }
            }
        }
        compose.onNode(hasSetTextAction()).performClick().performTextInput("hi @des")
        compose.runOnIdle { NativeUIBridge.events.clear() }
        compose.onNodeWithText("Pick").performClick()
        compose.runOnIdle {
            val events = NativeUIBridge.events.filter { it.startsWith("change:43:") || it.startsWith("press:") }
            assertEquals(listOf("change:43:7,7\u001Fhi @des", "press:99"), events)
        }
    }

    @Test fun aSecureFieldKeepsTheCaretAtTheEnd() {
        render("one", caret = -1, extra = mapOf("secure" to true))
        push("one two", caret = 2, extra = mapOf("secure" to true))
        assertEquals(TextRange(7), caret())
    }

    private fun render(value: String, caret: Int, extra: Map<String, Any> = emptyMap()) {
        props.value = fieldProps(value, caret, caret, extra)
        compose.setContent {
            MaterialTheme {
                val field = NativeUINode(7, "", null, null, GenericProps(props.value), 0, 0, emptyList())
                when (variant) {
                    "filled" -> FilledTextInputRenderer.Render(field, Modifier)
                    "bare" -> BareTextInputRenderer.Render(field, Modifier)
                    else -> OutlinedTextInputRenderer.Render(field, Modifier)
                }
            }
        }
        compose.onNode(hasSetTextAction()).performClick()
    }

    private fun push(value: String, caret: Int, end: Int = caret, extra: Map<String, Any> = emptyMap()) {
        compose.runOnIdle { props.value = fieldProps(value, caret, end, extra) }
        compose.waitForIdle()
    }

    private fun fieldProps(value: String, start: Int, end: Int, extra: Map<String, Any>): Map<String, Any> =
        mapOf("value" to value, "on_change" to 41, "selection_start" to start, "selection_end" to end) + extra

    private fun caret(): TextRange =
        compose.onNode(hasSetTextAction()).fetchSemanticsNode().config[SemanticsProperties.TextSelectionRange]
}
