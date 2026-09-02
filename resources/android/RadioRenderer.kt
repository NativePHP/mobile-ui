package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.selection.selectable
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.NativeAppearanceState
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.plugins.native_ui.NativeUITheme

/**
 * Material3 Radio — child of [RadioGroupRenderer]. Selection state and the
 * change callback are owned by the group; this renderer just displays the
 * button + label and relays taps.
 *
 * Standalone radios (outside a group) render as always-unselected.
 */
object RadioRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        // Standalone — no selection state available.
        Render(node, modifier, selectedValue = null, groupDisabled = false, onSelect = null)
    }

    @Composable
    fun Render(
        node: NativeUINode,
        modifier: Modifier,
        selectedValue: String?,
        groupDisabled: Boolean,
        onSelect: ((String) -> Unit)?,
    ) {
        val p = node.props
        val value    = p.getString("value")
        val label    = p.getString("label")
        val disabled = groupDisabled || p.getBool("disabled")
        val isSelected = selectedValue == value

        val theme = if (NativeAppearanceState.isDark()) NativeUITheme.dark else NativeUITheme.light

        val colors = RadioButtonDefaults.colors(
            selectedColor = theme.primary,
            unselectedColor = theme.onSurfaceVariant,
            disabledSelectedColor = theme.primary.copy(alpha = 0.38f),
            disabledUnselectedColor = theme.onSurfaceVariant.copy(alpha = 0.38f),
        )

        // selectable on the row merges descendants into ONE TalkBack focus
        // stop with a RadioButton role; the inner RadioButton gets
        // onClick = null so there's no nested second tap target.
        Row(
            modifier = modifier
                .fillMaxWidth()
                .selectable(
                    selected = isSelected,
                    enabled = !disabled,
                    role = Role.RadioButton,
                    onClick = { onSelect?.invoke(value) },
                ),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            RadioButton(
                selected = isSelected,
                onClick = null,
                enabled = !disabled,
                colors = colors,
            )
            if (label.isNotEmpty()) {
                Text(text = label, fontFamily = nuiDefaultFontFamily(), color = theme.onSurface)
            }
        }
    }
}
