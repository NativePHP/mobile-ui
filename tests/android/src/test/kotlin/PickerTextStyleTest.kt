package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.unit.TextUnit
import com.nativephp.mobile.ui.nativerender.*
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A compact date picker and a select draw their value at the size, letter
 * spacing and line height of their placeholder.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class PickerTextStyleTest {
    @get:Rule val compose = createComposeRule()

    @Test fun drawsAPickedDateLikeThePlaceholder() {
        render(
            { DatePickerRenderer.Render(node(1, "value" to "2026-11-11"), Modifier) },
            { DatePickerRenderer.Render(node(2, "placeholder" to "Optional"), Modifier) },
        )

        assertEquals(metricsOf("Optional"), metricsOf("Nov 11, 2026"))
    }

    @Test fun drawsAPickedOptionLikeThePlaceholder() {
        val options = listOf("Car", "Truck")
        render(
            { SelectRenderer.Render(node(1, "value" to "Truck", "options" to options), Modifier) },
            { SelectRenderer.Render(node(2, "placeholder" to "Optional", "options" to options), Modifier) },
        )

        assertEquals(metricsOf("Optional"), metricsOf("Truck"))
    }

    private fun render(vararg fields: @Composable () -> Unit) {
        compose.setContent {
            MaterialTheme {
                Column { fields.forEach { it() } }
            }
        }
    }

    // Unmerged, or the placeholder resolves to the field it is drawn in.
    private fun metricsOf(text: String): List<TextUnit> {
        val layouts = mutableListOf<TextLayoutResult>()
        compose.onNodeWithText(text, useUnmergedTree = true)
            .performSemanticsAction(SemanticsActions.GetTextLayoutResult) { it(layouts) }
        return layouts.single().layoutInput.style.run { listOf(fontSize, letterSpacing, lineHeight) }
    }

    private fun node(id: Int, vararg props: Pair<String, Any>) = NativeUINode(
        id, "", null, null,
        GenericProps(mapOf("locale" to "en-US") + props),
        0, 0, emptyList(),
    )
}
