package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CheckboxDefaults
import androidx.compose.material3.MaterialTheme
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
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.plugins.native_ui.NativeUITheme

/**
 * Material3 Checkbox renderer.
 *
 * Echo-prevention (plan K). Theme-sourced colors — no per-instance overrides
 * (Model 3).
 */
object CheckboxRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val serverValue = p.getBool("value")
        val label       = p.getString("label")
        val onChangeCb  = p.getCallbackId("on_change")
        val disabled    = p.getBool("disabled")
        val a11yLabel   = p.getString("a11y_label")
        val a11yHint    = p.getString("a11y_hint")
        val isError     = p.getBool("is_error")
        val supporting  = p.getString("supporting")

        val theme = if (isSystemInDarkTheme()) NativeUITheme.dark else NativeUITheme.light

        // Error state rides the hint channel unless an explicit hint is
        // set (same convention as the text inputs).
        val errorText = if (isError && supporting.isNotEmpty()) supporting else ""
        val effectiveA11yHint = a11yHint.ifEmpty { errorText }

        var checked by remember(node.id) { mutableStateOf(serverValue) }
        var lastSentValue by remember(node.id) { mutableStateOf(serverValue) }

        LaunchedEffect(serverValue) {
            if (serverValue != lastSentValue) {
                checked = serverValue
                lastSentValue = serverValue
            }
        }

        val colors = CheckboxDefaults.colors(
            checkedColor = if (isError) theme.destructive else theme.primary,
            uncheckedColor = if (isError) theme.destructive else theme.outline,
            checkmarkColor = theme.onPrimary,
            disabledCheckedColor = theme.primary.copy(alpha = 0.38f),
            disabledUncheckedColor = theme.outline.copy(alpha = 0.38f),
        )

        val onChanged = { new: Boolean ->
            checked = new
            lastSentValue = new
            if (onChangeCb != 0) {
                NativeUIBridge.sendCheckboxChangeEvent(onChangeCb, node.id, new)
            }
        }

        // toggleable on the row merges descendants into ONE TalkBack focus
        // stop and makes the label itself a tap target; the inner Checkbox
        // gets onCheckedChange = null so there's no nested second target.
        Column(modifier = modifier) {
            Row(
                modifier = Modifier
                    .nuiA11y(a11yLabel, effectiveA11yHint)
                    .toggleable(
                        value = checked,
                        enabled = !disabled,
                        role = Role.Checkbox,
                        onValueChange = onChanged,
                    ),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                Checkbox(
                    checked = checked,
                    onCheckedChange = null,
                    enabled = !disabled,
                    colors = colors,
                )
                if (label.isNotEmpty()) {
                    Text(text = label, fontFamily = nuiDefaultFontFamily(), color = theme.onSurface)
                }
            }

            if (supporting.isNotEmpty()) {
                Text(
                    text = supporting,
                    fontFamily = nuiDefaultFontFamily(),
                    color = if (isError) theme.destructive else theme.onSurfaceVariant,
                    style = MaterialTheme.typography.bodySmall,
                )
            }
        }
    }
}
