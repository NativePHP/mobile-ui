package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.InputMode
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalInputModeManager
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import com.nativephp.mobile.ui.nativerender.*
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.ParameterizedRobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(ParameterizedRobolectricTestRunner::class)
@Config(sdk = [35])
class FocusedButtonTest(private val variant: String, private val mode: String, private val keepsFocus: Boolean) {
    @get:Rule val compose = createComposeRule()

    companion object {
        @JvmStatic
        @ParameterizedRobolectricTestRunner.Parameters(name = "{0}-{1}-keepsFocus={2}")
        fun cases(): List<Array<Any>> = listOf("filled", "outlined").flatMap { variant ->
            listOf("live", "blur", "debounce").flatMap { mode ->
                listOf(false, true).map { keeps -> arrayOf<Any>(variant, mode, keeps) }
            }
        }
    }

    @After fun reset() {
        KeyboardFocusPolicy.fieldFocused(this, false)
        KeyboardFocusPolicy.fieldBlurred(this)
        KeyboardFocusPolicy.clearFocus = null
        NativeUIBridge.events.clear()
    }

    @Test fun latestTextReachesTheCurrentCallbackBeforeTheSeparateButtonPress() {
        val callback = mutableStateOf(41)
        var clearFocusCalls = 0
        compose.setContent {
            val focusManager = LocalFocusManager.current
            val inputModeManager = LocalInputModeManager.current
            SideEffect {
                inputModeManager.requestInputMode(InputMode.Touch)
                KeyboardFocusPolicy.clearFocus = { clearFocusCalls++; focusManager.clearFocus() }
            }
            MaterialTheme {
                Column {
                    val field = node(7, mapOf("label" to "Token", "sync_mode" to mode,
                        "debounce_ms" to 5000, "on_change" to callback.value,
                        "keep_focus_on_submit" to keepsFocus))
                    if (variant == "filled") FilledTextInputRenderer.Render(field, Modifier)
                    else OutlinedTextInputRenderer.Render(field, Modifier)
                    ButtonRenderer.Render(node(8, mapOf("label" to "Save", "on_press" to 99)), Modifier)
                }
            }
        }
        compose.runOnIdle { NativeUIBridge.events.clear() }
        compose.onNode(hasSetTextAction()).performClick().performTextInput("first")
        compose.runOnIdle { callback.value = 42 }
        compose.waitForIdle()
        compose.onNode(hasSetTextAction()).performTextReplacement("latest token")
        compose.onNodeWithText("Save").performClick()
        compose.runOnIdle {
            val modelAndPress = NativeUIBridge.events.filter { it.startsWith("change:") || it.startsWith("press:") }
            assertEquals(listOf("change:42:latest token", "press:99"), modelAndPress.takeLast(2))
            assertEquals(modelAndPress.toString(), 1, modelAndPress.count { it == "change:42:latest token" })
        }
        if (keepsFocus) compose.onNode(hasSetTextAction()).assertIsFocused()
        compose.runOnIdle { assertEquals(if (keepsFocus) 0 else 1, clearFocusCalls) }
        compose.mainClock.advanceTimeBy(6000)
        compose.runOnIdle {
            assertEquals(1, NativeUIBridge.events.count { it == "change:42:latest token" })
        }
    }

    private fun node(id: Int, props: Map<String, Any>) = NativeUINode(
        id, "", null, null, GenericProps(props), 0, 0, emptyList())
}
