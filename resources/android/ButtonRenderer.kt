package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.MaterialIcon
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import androidx.compose.foundation.isSystemInDarkTheme
import com.nativephp.plugins.native_ui.NativeUITheme
import com.nativephp.plugins.native_ui.NativeUITokens

/**
 * Material3 Button renderer.
 *
 * Maps semantic `variant` prop to the matching M3 primitive:
 *   - primary     → [Button] (filled) with theme.primary / onPrimary
 *   - secondary   → [FilledTonalButton] with theme.secondary / onSecondary
 *   - destructive → [Button] with theme.error / onError
 *   - ghost       → [TextButton] with theme.primary as content color
 *
 * All colors come from [LocalNativeUITheme]. No per-instance color/radius/shadow
 * overrides are honored — that's intentional (plan doc Model 3). For full visual
 * control, use `<pressable>`.
 */
object ButtonRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val variant = p.getString("variant", "primary")
        val size = p.getString("size", "md")
        val label = p.getString("label")
        val disabled = p.getBool("disabled")
        val loading = p.getBool("loading")
        val icon = p.getString("leading_icon")
        val iconTrailing = p.getString("trailing_icon")
        val a11yLabel = p.getString("a11y_label")
        val a11yHint = p.getString("a11y_hint")
        val pressCb = p.getCallbackId("on_press").let { if (it != 0) it else node.onPress }
        val hasMenu = p.getBool("has_menu")
        val fontName = p.getString("font_name")
        val customFontFamily = (if (fontName.isNotEmpty()) NativeUIFontResolver.resolve(LocalContext.current, fontName) else null)
            ?: nuiThemeDefaultFontFamily(LocalContext.current)

        // Read the active token set from the shared store. Using the singleton
        // rather than a CompositionLocal because nothing in the render tree
        // currently provides one — the store is backed by `mutableStateOf`, so
        // Compose recomposes automatically when PHP pushes a theme update.
        val theme = if (isSystemInDarkTheme()) NativeUITheme.dark else NativeUITheme.light
        val metrics = sizeMetrics(size, theme)
        // Leading — button labels are single-line, so this is usually a no-op.
        val lineHeight = nuiLineHeightUnit(p.getFloat("line_height_px", 0f), p.getFloat("line_height", 0f), metrics.textSize.value)

        // When `:menu` is set, tap toggles the dropdown anchored to the
        // button. The PHP-side @press handler is shadowed (menu wins).
        var menuExpanded by remember { mutableStateOf(false) }
        val onClick: () -> Unit = if (hasMenu) {
            { menuExpanded = true }
        } else {
            { if (pressCb != 0) NativeUIBridge.sendPressEvent(pressCb, node.id) }
        }

        val buttonModifier = modifier
            .defaultMinSize(minHeight = metrics.minHeight)
            .nuiA11y(a11yLabel, a11yHint)
            .let { m ->
                // Correct stateDescription use — actual widget state (the
                // spinner is visual-only), not an a11y hint.
                if (loading) m.semantics { stateDescription = "Loading" } else m
            }

        val content: @Composable () -> Unit = {
            ButtonContent(
                label = label,
                icon = icon,
                iconTrailing = iconTrailing,
                loading = loading,
                iconSize = metrics.iconSize,
                textSize = metrics.textSize,
                fontFamily = customFontFamily,
                lineHeight = lineHeight,
            )
        }

        val enabled = !disabled && !loading

        // The variant switch is wrapped in a small composable lambda so we
        // can render it twice — once raw (no menu) and once anchored
        // inside a Box (with DropdownMenu) when `:menu` is attached.
        val buttonByVariant: @Composable () -> Unit = {
            when (variant) {
                // Disabled state (all variants): `surface-variant` fill +
                // `on-surface-variant` label from the theme, replacing M3's
                // default onSurface-at-38% which read too faint. iOS uses the
                // same token pair, so disabled looks identical cross-platform.
                "secondary" -> FilledTonalButton(
                    onClick = onClick,
                    enabled = enabled,
                    modifier = buttonModifier,
                    contentPadding = metrics.contentPadding,
                    // Solid fill of the secondary token, matching iOS. No
                    // renderer-imposed alpha: transparency belongs to the
                    // theme config (e.g. `'secondary' => 'fuchsia-500/70'`).
                    colors = ButtonDefaults.filledTonalButtonColors(
                        containerColor = theme.secondary,
                        contentColor = theme.onSecondary,
                        disabledContainerColor = theme.surfaceVariant,
                        disabledContentColor = theme.onSurfaceVariant,
                    ),
                    content = { content() },
                )

                "destructive" -> Button(
                    onClick = onClick,
                    enabled = enabled,
                    modifier = buttonModifier,
                    contentPadding = metrics.contentPadding,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = theme.destructive,
                        contentColor = theme.onDestructive,
                        disabledContainerColor = theme.surfaceVariant,
                        disabledContentColor = theme.onSurfaceVariant,
                    ),
                    content = { content() },
                )

                "success" -> Button(
                    onClick = onClick,
                    enabled = enabled,
                    modifier = buttonModifier,
                    contentPadding = metrics.contentPadding,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = theme.success,
                        contentColor = theme.onSuccess,
                        disabledContainerColor = theme.surfaceVariant,
                        disabledContentColor = theme.onSurfaceVariant,
                    ),
                    content = { content() },
                )

                "ghost" -> TextButton(
                    onClick = onClick,
                    enabled = enabled,
                    modifier = buttonModifier,
                    contentPadding = metrics.contentPadding,
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = theme.primary,
                        disabledContentColor = theme.onSurfaceVariant,
                    ),
                    content = { content() },
                )

                // "primary" (default) and any unknown value fall through to filled primary.
                else -> Button(
                    onClick = onClick,
                    enabled = enabled,
                    modifier = buttonModifier,
                    contentPadding = metrics.contentPadding,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = theme.primary,
                        contentColor = theme.onPrimary,
                        disabledContainerColor = theme.surfaceVariant,
                        disabledContentColor = theme.onSurfaceVariant,
                    ),
                    content = { content() },
                )
            }
        }

        if (hasMenu) {
            // Box anchors the DropdownMenu to the button. The Box has no
            // visible footprint of its own — it wraps the button so the
            // menu can position itself relative to the button's bounds.
            Box {
                buttonByVariant()
                ExpressiveMenu(
                    expanded = menuExpanded,
                    onDismissRequest = { menuExpanded = false },
                ) {
                    node.children
                        .filter { it.type == "top_bar_action" }
                        .forEach { item ->
                            renderAttachedMenuItem(item) { menuExpanded = false }
                        }
                }
            }
        } else {
            buttonByVariant()
        }
    }

    // ─── Internals ───────────────────────────────────────────────────────────

    private data class SizeMetrics(
        val minHeight: Dp,
        val contentPadding: PaddingValues,
        val iconSize: Dp,
        val textSize: TextUnit,
    )

    private fun sizeMetrics(size: String, theme: NativeUITokens): SizeMetrics = when (size) {
        "sm" -> SizeMetrics(
            minHeight = 32.dp,
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
            iconSize = 16.dp,
            textSize = theme.fontSm,
        )
        "lg" -> SizeMetrics(
            minHeight = 48.dp,
            contentPadding = PaddingValues(horizontal = 20.dp, vertical = 12.dp),
            iconSize = 22.dp,
            textSize = theme.fontLg,
        )
        else -> SizeMetrics(
            // Match iOS (16h / 8v, content-driven height) instead of Material's
            // chunky ButtonDefaults.ContentPadding (24h) + 40dp min, which made
            // Android md buttons noticeably wider and taller than iOS.
            minHeight = 36.dp,
            contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
            iconSize = 18.dp,
            textSize = theme.fontMd,
        )
    }

    @Composable
    private fun ButtonContent(
        label: String,
        icon: String,
        iconTrailing: String,
        loading: Boolean,
        iconSize: Dp,
        textSize: TextUnit,
        fontFamily: FontFamily? = null,
        lineHeight: TextUnit = TextUnit.Unspecified,
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            if (loading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(iconSize),
                    strokeWidth = 2.dp,
                    color = LocalContentColor.current,
                )
                if (label.isNotEmpty()) {
                    Text(text = label, fontSize = textSize, fontFamily = fontFamily, lineHeight = lineHeight, maxLines = 1, softWrap = false)
                }
                return@Row
            }

            if (icon.isNotEmpty()) {
                MaterialIcon(
                    name = icon,
                    contentDescription = null,
                    size = iconSize,
                    tint = LocalContentColor.current,
                )
            }
            if (label.isNotEmpty()) {
                // maxLines + softWrap: button labels are short single-line by
                // convention. Without these, Compose wraps mid-word when the
                // parent flex-wrap row squeezes the button below its natural
                // width, producing fragments like "Destruct\nive". With them,
                // the button claims its full content width and flex-wrap kicks
                // the whole button to the next row.
                Text(text = label, fontSize = textSize, fontFamily = fontFamily, lineHeight = lineHeight, maxLines = 1, softWrap = false)
            }
            if (iconTrailing.isNotEmpty()) {
                MaterialIcon(
                    name = iconTrailing,
                    contentDescription = null,
                    size = iconSize,
                    tint = LocalContentColor.current,
                )
            }
        }
    }
}
