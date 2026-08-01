package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
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
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.platform.LocalContext
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

        // Echo-prevention sync — same shape as the outlined variant.
        var text by remember { mutableStateOf(props.serverValue) }
        var lastSentValue by remember { mutableStateOf(props.serverValue) }

        LaunchedEffect(props.serverValue) {
            if (props.serverValue != lastSentValue) {
                text = props.serverValue
                lastSentValue = props.serverValue
            }
        }

        BasicTextField(
            value = text,
            onValueChange = { newText ->
                if (props.disabled || props.readOnly) return@BasicTextField
                text = newText
                lastSentValue = newText
                props.dispatchChange?.invoke(newText)
            },
            // Full width by default (parity with the iOS renderer's
            // maxWidth: .infinity); an explicit width in `modifier` (FIXED
            // layout mode) still wins since it comes later in the chain.
            modifier = Modifier.fillMaxWidth().then(modifier),
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
                // Stack the placeholder and the real field in a centered Box.
                // Without this, Compose lays both out top-start independently —
                // if their intrinsic line heights differ even slightly, the
                // visible cursor and the placeholder glyph drift apart
                // vertically, showing the cursor visibly above the placeholder.
                Box(contentAlignment = Alignment.CenterStart) {
                    if (text.isEmpty() && props.placeholder.isNotEmpty()) {
                        Text(
                            text = props.placeholder,
                            color = placeholderColor,
                            fontSize = props.textSize.sp
                        )
                    }
                    innerTextField()
                }
            },
            keyboardActions = KeyboardActions(onAny = { props.dispatchSubmit?.invoke(text) })
        )
    }
}
