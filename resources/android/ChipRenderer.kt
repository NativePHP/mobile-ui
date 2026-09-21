package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.FilterChipDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.MaterialIcon
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.plugins.native_ui.NativeUITheme

/**
 * Material3 FilterChip. Echo-prevention (plan K), theme-sourced colors
 * (Model 3).
 */
object ChipRenderer {
    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val serverValue = p.getBool("value")
        val label       = p.getString("label")
        val iconName    = p.getString("icon")
        val onChangeCb  = p.getCallbackId("on_change")
        val onPressCb   = p.getCallbackId("on_press").let { if (it != 0) it else node.onPress }
        val disabled    = p.getBool("disabled")
        val a11yLabel   = p.getString("a11y_label")
        val a11yHint    = p.getString("a11y_hint")

        val theme = if (isSystemInDarkTheme()) NativeUITheme.dark else NativeUITheme.light

        var isSelected by remember(node.id) { mutableStateOf(serverValue) }
        var lastSentValue by remember(node.id) { mutableStateOf(serverValue) }

        LaunchedEffect(serverValue) {
            if (serverValue != lastSentValue) {
                isSelected = serverValue
                lastSentValue = serverValue
            }
        }

        val colors = FilterChipDefaults.filterChipColors(
            containerColor = theme.surfaceVariant,
            labelColor = theme.onSurface,
            iconColor = theme.onSurface,
            selectedContainerColor = theme.primary,
            selectedLabelColor = theme.onPrimary,
            selectedLeadingIconColor = theme.onPrimary,
        )

        val border = FilterChipDefaults.filterChipBorder(
            enabled = !disabled,
            selected = isSelected,
            borderColor = theme.outline,
            selectedBorderColor = theme.primary,
        )

        val chipModifier = modifier.nuiA11y(a11yLabel, a11yHint)

        FilterChip(
            selected = isSelected,
            onClick = {
                if (onPressCb != 0) {
                    // Server-driven: the press handler owns selection. Toggling
                    // locally would make the chip fight the state it is handed
                    // back, so a filter chip would flicker off on its own tap.
                    NativeUIBridge.sendPressEvent(onPressCb, node.id)
                } else {
                    val new = !isSelected
                    isSelected = new
                    lastSentValue = new
                    if (onChangeCb != 0) {
                        NativeUIBridge.sendToggleChangeEvent(onChangeCb, node.id, new)
                    }
                }
            },
            label = { Text(label, fontFamily = nuiDefaultFontFamily()) },
            modifier = chipModifier,
            enabled = !disabled,
            leadingIcon = if (iconName.isNotEmpty()) {
                { MaterialIcon(name = iconName, contentDescription = null, size = 18.dp) }
            } else null,
            colors = colors,
            border = border,
        )
    }
}
