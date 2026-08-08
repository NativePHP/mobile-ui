package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuAnchorType
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.TextStyle
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.plugins.native_ui.NativeUITheme

/**
 * Material3 Select — dropdown popover over a string option list. Uses
 * `ExposedDropdownMenuBox` for anchoring + keyboard-accessible selection.
 *
 * Echo-prevention (plan K), theme-sourced colors (Model 3).
 */
object SelectRenderer {
    @OptIn(ExperimentalMaterial3Api::class)
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val serverValue = p.getString("value")
        val label       = p.getString("label")
        val placeholder = p.getString("placeholder")
        val options     = p.getStringList("options")
        val onChangeCb  = p.getCallbackId("on_change")
        val disabled    = p.getBool("disabled")
        val a11yLabel   = p.getString("a11y_label")
        val a11yHint    = p.getString("a11y_hint")
        val isError     = p.getBool("is_error")
        val supporting  = p.getString("supporting")

        val theme = if (isSystemInDarkTheme()) NativeUITheme.dark else NativeUITheme.light

        var expanded by remember { mutableStateOf(false) }
        var selectedValue by remember(node.id) { mutableStateOf(serverValue) }
        var lastSentValue by remember(node.id) { mutableStateOf(serverValue) }

        LaunchedEffect(serverValue) {
            if (serverValue != lastSentValue) {
                selectedValue = serverValue
                lastSentValue = serverValue
            }
        }

        val anchorModifier = modifier.nuiA11y(a11yLabel, a11yHint)

        ExposedDropdownMenuBox(
            expanded = expanded,
            onExpandedChange = { if (!disabled) expanded = it },
            modifier = anchorModifier,
        ) {
            OutlinedTextField(
                value = selectedValue,
                onValueChange = {},
                readOnly = true,
                enabled = !disabled,
                label = if (label.isNotEmpty()) ({ Text(label, fontFamily = nuiDefaultFontFamily()) }) else null,
                placeholder = if (placeholder.isNotEmpty()) ({ Text(placeholder, fontFamily = nuiDefaultFontFamily()) }) else null,
                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded) },
                isError = isError,
                supportingText = supportingSlot(supporting),
                modifier = Modifier.menuAnchor(ExposedDropdownMenuAnchorType.PrimaryNotEditable),
                textStyle = TextStyle(color = theme.onSurface),
                colors = OutlinedTextFieldDefaults.colors(
                    errorBorderColor = theme.destructive,
                    errorLabelColor = theme.destructive,
                    errorSupportingTextColor = theme.destructive,
                    errorTrailingIconColor = theme.destructive,
                    focusedTextColor = theme.onSurface,
                    unfocusedTextColor = theme.onSurface,
                    focusedBorderColor = theme.primary,
                    unfocusedBorderColor = theme.outline,
                    disabledBorderColor = theme.outline.copy(alpha = 0.5f),
                    focusedLabelColor = theme.primary,
                    unfocusedLabelColor = theme.onSurfaceVariant,
                    focusedTrailingIconColor = theme.onSurfaceVariant,
                    unfocusedTrailingIconColor = theme.onSurfaceVariant,
                    focusedPlaceholderColor = theme.onSurfaceVariant,
                    unfocusedPlaceholderColor = theme.onSurfaceVariant,
                ),
            )
            ExposedDropdownMenu(
                expanded = expanded,
                onDismissRequest = { expanded = false },
            ) {
                options.forEach { option ->
                    DropdownMenuItem(
                        text = { Text(option, fontFamily = nuiDefaultFontFamily(), color = theme.onSurface) },
                        onClick = {
                            selectedValue = option
                            lastSentValue = option
                            expanded = false
                            if (onChangeCb != 0) {
                                NativeUIBridge.sendSelectChangeEvent(onChangeCb, node.id, option)
                            }
                        },
                    )
                }
            }
        }
    }
}
