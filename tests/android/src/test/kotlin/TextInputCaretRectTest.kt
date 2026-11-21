package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.ui.Modifier
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
 * `@caretChange` on the bare multiline field: where the caret is drawn, in
 * dp from the top-left of what the field shows, and `fills_height`, which
 * makes the field as tall as its parent instead of as tall as its lines.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class TextInputCaretRectTest {
    @get:Rule val compose = createComposeRule()

    private val caretCb = 44

    @After fun reset() {
        KeyboardFocusPolicy.fieldBlurred(this)
        NativeUIBridge.events.clear()
    }

    private data class Caret(val x: Float, val y: Float, val w: Float, val h: Float, val line: Int, val fieldW: Float, val fieldH: Float)

    private fun carets(): List<Caret> = NativeUIBridge.events
        .filter { it.startsWith("change:$caretCb:") }
        .map { it.removePrefix("change:$caretCb:").split(",") }
        .map { Caret(it[0].toFloat(), it[1].toFloat(), it[2].toFloat(), it[3].toFloat(), it[4].toInt(), it[5].toFloat(), it[6].toFloat()) }

    private fun render(extra: Map<String, Any> = emptyMap(), boxHeight: Int? = null) {
        compose.setContent {
            MaterialTheme {
                val field = NativeUINode(7, "", null, null, GenericProps(mapOf(
                    "value" to "", "on_change" to 41, "multiline" to true,
                    "on_caret_change" to caretCb, "selection_debounce_ms" to 16,
                    "line_height_px" to 24, "size" to "md",
                ) + extra), 0, 0, emptyList())
                if (boxHeight != null) {
                    Column(Modifier.width(300.dp).height(boxHeight.dp)) {
                        BareTextInputRenderer.Render(field, Modifier)
                    }
                } else {
                    Box(Modifier.width(300.dp)) { BareTextInputRenderer.Render(field, Modifier) }
                }
            }
        }
    }

    private fun type(text: String) {
        compose.onNode(hasSetTextAction()).performClick().performTextInput(text)
        compose.mainClock.advanceTimeBy(100)
        compose.waitForIdle()
    }

    @Test fun reportsTheCaretsLineAndPosition() {
        render(mapOf("min_lines" to 1, "max_lines" to 10))
        type("one\ntwo\nthree")

        val caret = carets().last()
        assertEquals(2, caret.line)
        // Two lines above the caret's line (Robolectric's font metrics, so
        // measured in the caret's own line height rather than 24dp).
        assertTrue(caret.toString(), caret.h > 10f)
        assertTrue(caret.toString(), caret.y > 1.5f * caret.h && caret.y < 2.5f * caret.h)
        assertTrue(caret.x > 0f)
        assertEquals(300f, caret.fieldW, 1f)
    }

    @Test fun takesTheFieldsScrollingOff() {
        render(mapOf("min_lines" to 3, "max_lines" to 3))
        type((1..8).joinToString("\n") { "line $it" })

        val caret = carets().last()
        assertEquals(7, caret.line)
        // The field scrolled to keep the caret in view, so its line is the
        // last visible one (the third), not the eighth from the top.
        assertTrue(caret.toString(), caret.fieldH > 2.5f * caret.h && caret.fieldH < 3.5f * caret.h)
        assertTrue(caret.toString(), caret.y > 1.5f * caret.h)
        assertTrue(caret.toString(), caret.y + caret.h <= caret.fieldH + 1f)
    }

    @Test fun sendsNothingUnchangedTwice() {
        render()
        type("hello")
        val before = carets().size
        compose.mainClock.advanceTimeBy(500)
        compose.waitForIdle()
        assertEquals(before, carets().size)
    }

    @Test fun sendsNothingWithoutFocus() {
        render()
        compose.mainClock.advanceTimeBy(500)
        compose.waitForIdle()
        assertTrue(carets().isEmpty())
    }

    @Test fun sendsNothingForASingleLineField() {
        render(mapOf("multiline" to false))
        type("hello")
        assertTrue(carets().isEmpty())
    }

    @Test fun fillsTheHeightItIsGiven() {
        render(mapOf("fills_height" to true, "min_lines" to 2, "max_lines" to 2), boxHeight = 400)
        compose.onNode(hasSetTextAction()).assertHeightIsEqualTo(400.dp)
    }

    @Test fun staysAsTallAsItsLinesWithoutFill() {
        render(mapOf("min_lines" to 2, "max_lines" to 2), boxHeight = 400)
        val bounds = compose.onNode(hasSetTextAction()).getUnclippedBoundsInRoot()
        val height = bounds.bottom - bounds.top
        assertTrue("$height", height < 100.dp)
    }

    @Test fun aFilledFieldScrollsItsTextPastTheLinesThatFit() {
        render(mapOf("fills_height" to true, "min_lines" to 1, "max_lines" to 2), boxHeight = 120)
        type((1..10).joinToString("\n") { "line $it" })

        compose.onNode(hasSetTextAction()).assertHeightIsEqualTo(120.dp)
        val caret = carets().last()
        assertEquals(9, caret.line)
        assertTrue(caret.toString(), caret.y + caret.h <= 121f)
        assertTrue(caret.toString(), caret.y > 60f)
    }
}
