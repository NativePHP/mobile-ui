package com.nativephp.plugins.native_ui.ui

import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import com.nativephp.mobile.ui.NativeAppearanceState
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.plugins.native_ui.NativeUITheme

/**
 * Material3 SingleChoiceSegmentedButtonRow. Echo-prevention on the selected
 * index (plan K), theme-sourced colors (Model 3).
 */
object ButtonGroupRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val options     = p.getStringList("options")
        val serverValue = p.getInt("value")
        val onChangeCb  = p.getCallbackId("on_change")
        val disabled    = p.getBool("disabled")
        val a11yLabel   = p.getString("a11y_label")

        if (options.isEmpty()) return

        val theme = if (NativeAppearanceState.isDark()) NativeUITheme.dark else NativeUITheme.light

        var selectedIndex by remember(node.id) { mutableStateOf(serverValue) }
        var lastSentValue by remember(node.id) { mutableStateOf(serverValue) }

        LaunchedEffect(serverValue) {
            if (serverValue != lastSentValue) {
                selectedIndex = serverValue
                lastSentValue = serverValue
            }
        }

        val rowModifier = modifier
            .let { m -> if (a11yLabel.isNotEmpty()) m.semantics { contentDescription = a11yLabel } else m }

        val colors = SegmentedButtonDefaults.colors(
            activeContainerColor = theme.primary,
            activeContentColor = theme.onPrimary,
            activeBorderColor = theme.primary,
            inactiveContainerColor = theme.surface,
            inactiveContentColor = theme.onSurface,
            inactiveBorderColor = theme.outline,
            disabledActiveContainerColor = theme.primary.copy(alpha = 0.38f),
            disabledActiveContentColor = theme.onPrimary,
            disabledInactiveContainerColor = theme.surface,
            disabledInactiveContentColor = theme.onSurface.copy(alpha = 0.38f),
        )

        SingleChoiceSegmentedButtonRow(modifier = rowModifier) {
            options.forEachIndexed { index, label ->
                SegmentedButton(
                    shape = SegmentedButtonDefaults.itemShape(index = index, count = options.size),
                    onClick = {
                        selectedIndex = index
                        lastSentValue = index
                        if (onChangeCb != 0) {
                            NativeUIBridge.sendTabChangeEvent(onChangeCb, node.id, index)
                        }
                    },
                    selected = index == selectedIndex,
                    enabled = !disabled,
                    colors = colors,
                    label = { Text(label, fontFamily = nuiDefaultFontFamily()) },
                )
            }
        }
    }
}
