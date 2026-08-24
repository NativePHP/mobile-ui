package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.sp
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.argbToComposeColor
import com.nativephp.plugins.native_ui.NativeUITheme

/**
 * Chromeless text input — Compose `BasicTextField` with no decoration.
 *
 * Counterpart to iOS's `NativeUIBareTextInputRenderer`. Use when the
 * surrounding container provides the visible chrome (chat input pill,
 * search bar, inline edit field, etc.).
 *
 * Colors default to [NativeUITheme] tokens. Unlike outlined / filled
 * (Model 3, theme-only), the bare variant accepts a per-instance
 * `color` (with optional `dark_color` companion) so callers can
 * guarantee contrast against custom-painted chrome — chat-input pills
 * with `bg-white` need a dark text color regardless of system mode.
 *   - explicit attribute:  `color="#334155"`
 *   - tailwind class on the input: `class="text-slate-700"`
 *   - dark mode: `class="text-slate-700 dark:text-slate-300"`
 */
object BareTextInputRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val props = parseTextInputProps(node)
        val isDark = isSystemInDarkTheme()
        val theme = if (isDark) NativeUITheme.dark else NativeUITheme.light
        val customFontFamily = (if (props.fontName.isNotEmpty()) NativeUIFontResolver.resolve(LocalContext.current, props.fontName) else null)
            ?: nuiThemeDefaultFontFamily(LocalContext.current)
        val lineHeight = nuiLineHeightUnit(props.lineHeightPx, props.lineHeight, props.textSize.toFloat())

        // Per-instance color override. `color` is the light value;
        // `dark_color` is the dark companion (collector auto-maps from
        // a `dark:text-*` class). Either may be unset (0).
        val darkOverrideArgb = if (isDark) node.props.getColor("dark_color", 0) else 0
        val colorArgb = node.props.getColor("color", 0)
        val effectiveTextColor: Color = when {
            darkOverrideArgb != 0 -> argbToComposeColor(darkOverrideArgb)
            colorArgb != 0 -> argbToComposeColor(colorArgb)
            else -> theme.onSurface
        }
        val displayedTextColor = if (props.disabled) effectiveTextColor.copy(alpha = 0.6f) else effectiveTextColor

        // Placeholder follows the override too (faded by ~60%) so a
        // dark-text input on a light pill keeps a readable placeholder
        // in the same family.
        val placeholderColor = if (colorArgb != 0 || darkOverrideArgb != 0) {
            effectiveTextColor.copy(alpha = 0.6f)
        } else {
            theme.onSurfaceVariant
        }

        // Echo-prevention sync — same shape as the outlined variant, now over a
        // TextFieldValue so we own the caret. Initial caret sits at the end of
        // any pre-filled value (parity with the server-push below).
        val scope = rememberCoroutineScope()
        var value by remember { mutableStateOf(TextFieldValue(props.serverValue, TextRange(props.serverValue.length))) }
        var lastSentValue by remember { mutableStateOf(props.serverValue) }
        var wasFocused by remember { mutableStateOf(false) }

        // Caret / selection reporter — independent of the direct change/submit
        // dispatchers; no-op unless `on_selection_change` is wired and the
        // field isn't secure.
        val selectionReporter = remember(props.onSelectionChangeCb, props.selectionDebounceMs, props.secure) {
            SelectionReporter(scope = scope, props = props, nodeId = node.id)
        }

        LaunchedEffect(props.serverValue) {
            if (props.serverValue != lastSentValue) {
                // Programmatic server push: replace text, caret to the end, and
                // flush a single end-caret selection event (deduped) rather
                // than emitting stale pre-push offsets.
                val pushed = TextFieldValue(props.serverValue, TextRange(props.serverValue.length))
                value = pushed
                lastSentValue = props.serverValue
                selectionReporter.flush(pushed)
            }
        }

        BasicTextField(
            value = value,
            onValueChange = { newValue ->
                // Disabled fields never reach here. readOnly may still fire for
                // caret/selection moves (copy support) — persist those so the
                // selection is visible/reportable — but never accept a text edit.
                if (props.disabled) return@BasicTextField
                val textChanged = newValue.text != value.text
                if (props.readOnly && textChanged) return@BasicTextField
                value = newValue
                // Bare never applied a max_length cap and still doesn't — text
                // forwards verbatim (LIVE). Selection-only moves don't re-fire
                // the change event (parity with the String overload).
                if (textChanged) {
                    lastSentValue = newValue.text
                    props.dispatchChange?.invoke(newValue.text)
                }
                selectionReporter.onValueChanged(newValue)
            },
            // Full width by default (parity with the iOS renderer's
            // maxWidth: .infinity); an explicit width in `modifier` (FIXED
            // layout mode) still wins since it comes later in the chain.
            // onFocusChanged is Bare's blur hook (no InteractionSource here):
            // flush the pending selection on the focused → unfocused edge.
            modifier = Modifier
                .fillMaxWidth()
                .onFocusChanged { state ->
                    if (wasFocused && !state.isFocused) selectionReporter.flush(value)
                    wasFocused = state.isFocused
                }
                .then(modifier),
            enabled = !props.disabled,
            readOnly = props.readOnly,
            textStyle = LocalTextStyle.current.copy(
                color = displayedTextColor,
                fontSize = props.textSize.sp,
                fontFamily = customFontFamily,
                lineHeight = lineHeight
            ),
            cursorBrush = SolidColor(
                when {
                    props.isError -> theme.destructive
                    colorArgb != 0 || darkOverrideArgb != 0 -> effectiveTextColor
                    else -> theme.primary
                }
            ),
            singleLine = !props.multiline,
            decorationBox = { innerTextField ->
                if (value.text.isEmpty() && props.placeholder.isNotEmpty()) {
                    Text(
                        text = props.placeholder,
                        color = placeholderColor,
                        fontSize = props.textSize.sp
                    )
                }
                innerTextField()
            },
            // Filled and Outlined pass this since day one; Bare never did, so
            // `keyboard="number"` (and the derived capitalization) were
            // silently ignored on bare inputs — the plain text keyboard
            // always came up.
            keyboardOptions = keyboardOptionsFor(props),
            keyboardActions = KeyboardActions(onAny = {
                // Flush the settled caret before the submit event fires.
                selectionReporter.flush(value)
                props.dispatchSubmit?.invoke(value.text)
            })
        )
    }
}
