package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.width
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.LayoutInfo
import androidx.compose.ui.layout.positionInRoot
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
 * A bare multiline field that gets shorter keeps its caret in view, as iOS
 * does. Compose's BasicTextField only scrolls to the caret when the caret
 * moves, so without help the caret's line sat below the field's new bottom
 * until the next keystroke. Checked against where the text is really drawn,
 * and against the `@caretChange` report.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class TextInputCaretShrinkTest {
    @get:Rule val compose = createComposeRule()

    private val caretCb = 45

    @After fun reset() {
        KeyboardFocusPolicy.fieldBlurred(this)
        NativeUIBridge.events.clear()
    }

    private data class Caret(val y: Float, val h: Float, val line: Int, val fieldH: Float)

    private fun carets(): List<Caret> = NativeUIBridge.events
        .filter { it.startsWith("change:$caretCb:") }
        .map { it.removePrefix("change:$caretCb:").split(",") }
        .map { Caret(it[1].toFloat(), it[3].toFloat(), it[4].toInt(), it[6].toFloat()) }

    private var boxHeight by mutableIntStateOf(400)

    private fun render(extra: Map<String, Any>) {
        compose.setContent {
            MaterialTheme {
                val field = NativeUINode(8, "", null, null, GenericProps(mapOf(
                    "value" to "", "on_change" to 41, "multiline" to true,
                    "selection_debounce_ms" to 16, "line_height_px" to 24, "size" to "md",
                ) + extra), 0, 0, emptyList())
                Column(Modifier.width(300.dp).height(boxHeight.dp)) {
                    BareTextInputRenderer.Render(field, Modifier)
                }
            }
        }
    }

    private fun type(text: String) {
        compose.onNode(hasSetTextAction()).performClick().performTextInput(text)
        settle()
    }

    private fun settle() {
        compose.mainClock.advanceTimeBy(1_000)
        compose.waitForIdle()
    }

    /**
     * How far the field has really scrolled its text, in px. The text is
     * drawn by a layout node inside the field that is as tall as all of
     * its lines and placed at minus the scroll, which BasicTextField keeps
     * private, so it's found by walking the field's layout nodes.
     */
    private fun realScrollPx(): Float {
        val fieldInfo = compose.onNode(hasSetTextAction()).fetchSemanticsNode().layoutInfo
        val fieldTop = fieldInfo.coordinates.positionInRoot().y
        val text = descendants(fieldInfo).filter { it.isPlaced }.maxBy { it.height }
        return fieldTop - text.coordinates.positionInRoot().y
    }

    private fun descendants(info: LayoutInfo): List<LayoutInfo> {
        val getter = info.javaClass.methods.first { it.name.startsWith("getChildren") && it.parameterCount == 0 }
        @Suppress("UNCHECKED_CAST")
        val children = getter.invoke(info) as List<LayoutInfo>
        return children + children.flatMap { descendants(it) }
    }

    private fun fieldHeightPx(): Float =
        compose.onNode(hasSetTextAction()).fetchSemanticsNode().layoutInfo.height.toFloat()

    private fun lineHeightPx(): Float {
        val result = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
        compose.onNode(hasSetTextAction()).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) { it(result) }
        val layout = result.first()
        return layout.getLineBottom(0) - layout.getLineTop(0)
    }

    private fun assertCaretOnTheLastVisibleLine() {
        val scroll = realScrollPx()
        val field = fieldHeightPx()
        val line = lineHeightPx()
        val result = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
        compose.onNode(hasSetTextAction()).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) { it(result) }
        val layout = result.first()
        val lastLine = layout.lineCount - 1
        val caretTop = layout.getLineTop(lastLine) - scroll
        val caretBottom = layout.getLineBottom(lastLine) - scroll
        val where = "caret $caretTop..$caretBottom in a ${field}px field, scrolled $scroll, line $line"
        assertTrue(where, scroll > 0f)
        assertTrue(where, caretTop >= -1f)
        assertTrue(where, caretBottom <= field + 1f)
        // Scrolled only as far as it needed: the caret's line is the last
        // one the field shows.
        assertTrue(where, caretBottom > field - line - 1f)
    }

    @Test fun aFilledFieldThatGetsShorterScrollsTheCaretBackIntoView() {
        render(mapOf("fills_height" to true, "min_lines" to 1, "max_lines" to 2, "on_caret_change" to caretCb))
        type((1..12).joinToString("\n") { "line $it" })
        assertEquals(0f, realScrollPx().coerceAtLeast(0f), 0.5f)

        boxHeight = 120
        settle()

        compose.onNode(hasSetTextAction()).assertHeightIsEqualTo(120.dp)
        assertCaretOnTheLastVisibleLine()

        // The report follows the real scroll: the caret's line is inside
        // the field, at its bottom.
        val caret = carets().last()
        assertEquals(11, caret.line)
        assertEquals(120f, caret.fieldH, 1f)
        assertTrue(caret.toString(), caret.y >= -0.5f)
        assertTrue(caret.toString(), caret.y + caret.h <= caret.fieldH + 1f)
        assertTrue(caret.toString(), caret.y + caret.h > caret.fieldH - caret.h - 1f)
        val density = compose.onNode(hasSetTextAction()).fetchSemanticsNode().layoutInfo.density.density
        val layoutTop = run {
            val result = mutableListOf<androidx.compose.ui.text.TextLayoutResult>()
            compose.onNode(hasSetTextAction()).performSemanticsAction(androidx.compose.ui.semantics.SemanticsActions.GetTextLayoutResult) { it(result) }
            result.first().getCursorRect(result.first().layoutInput.text.length).top
        }
        assertEquals((layoutTop - realScrollPx()) / density, caret.y, 0.6f)
    }

    @Test fun worksWithoutACaretCallback() {
        render(mapOf("fills_height" to true, "min_lines" to 1, "max_lines" to 2))
        type((1..12).joinToString("\n") { "line $it" })

        boxHeight = 120
        settle()

        assertCaretOnTheLastVisibleLine()
        assertTrue(carets().isEmpty())
    }

    @Test fun leavesACaretThatIsStillInViewAlone() {
        render(mapOf("fills_height" to true, "min_lines" to 1, "max_lines" to 2, "on_caret_change" to caretCb))
        type("one\ntwo")

        boxHeight = 200
        settle()

        assertEquals(0f, realScrollPx().coerceAtLeast(0f), 0.5f)
        val caret = carets().last()
        assertEquals(1, caret.line)
        assertTrue(caret.toString(), caret.y > 0f && caret.y + caret.h <= caret.fieldH)
    }
}
