package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.NativeAppearanceState
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.plugins.native_ui.NativeUITheme

/**
 * Material3 Switch renderer.
 *
 * Binary on/off with echo-prevention (plan K). Theme-sourced colors — no
 * per-instance tint/label color overrides (Model 3). When `label` is set,
 * renders as a label-left / switch-right row.
 */
object ToggleRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val label       = p.getString("label")
        val serverValue = p.getBool("value")
        val onChangeCb  = p.getCallbackId("on_change")
        val disabled    = p.getBool("disabled")
        val a11yLabel   = p.getString("a11y_label")
        val a11yHint    = p.getString("a11y_hint")

        val theme = if (NativeAppearanceState.isDark()) NativeUITheme.dark else NativeUITheme.light

        var checked by remember(node.id) { mutableStateOf(serverValue) }
        var lastSentValue by remember(node.id) { mutableStateOf(serverValue) }

        // Echo-prevention — accept programmatic updates, ignore echoes of our
        // own commits.
        LaunchedEffect(serverValue) {
            if (serverValue != lastSentValue) {
                checked = serverValue
                lastSentValue = serverValue
            }
        }

        val colors = SwitchDefaults.colors(
            checkedThumbColor = theme.onPrimary,
            checkedTrackColor = theme.primary,
            checkedBorderColor = theme.primary,
            uncheckedThumbColor = theme.outline,
            uncheckedTrackColor = theme.surfaceVariant,
            uncheckedBorderColor = theme.outline,
        )

        val onChanged = { new: Boolean ->
            checked = new
            lastSentValue = new
            if (onChangeCb != 0) {
                NativeUIBridge.sendToggleChangeEvent(onChangeCb, node.id, new)
            }
        }

        val rowModifier = modifier.nuiA11y(a11yLabel, a11yHint)

        if (label.isNotEmpty()) {
            // toggleable on the row merges descendants into ONE TalkBack focus
            // stop and makes the label itself a tap target; the inner Switch
            // gets onCheckedChange = null so there's no nested second target.
            Row(
                modifier = rowModifier.toggleable(
                    value = checked,
                    enabled = !disabled,
                    role = Role.Switch,
                    onValueChange = onChanged,
                ),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(text = label, fontFamily = nuiDefaultFontFamily(), modifier = Modifier.weight(1f), color = theme.onSurface)
                Spacer(modifier = Modifier.width(8.dp))
                Switch(
                    checked = checked,
                    onCheckedChange = null,
                    enabled = !disabled,
                    colors = colors,
                )
            }
        } else {
            Switch(
                checked = checked,
                onCheckedChange = onChanged,
                modifier = rowModifier,
                enabled = !disabled,
                colors = colors,
            )
        }
    }
}
