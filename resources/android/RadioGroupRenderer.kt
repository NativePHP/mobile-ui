package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.height
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.NativeAppearanceState
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.mobile.ui.nativerender.RenderNode
import com.nativephp.mobile.ui.nativerender.buildModifier
import com.nativephp.plugins.native_ui.NativeUITheme

/**
 * Material3 RadioGroup — vertical stack of radio children with single-
 * selection state held by the group. Echo-prevention (plan K) + theme-sourced
 * colors (Model 3).
 */
object RadioGroupRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val serverValue = p.getString("value")
        val label       = p.getString("label")
        val onChangeCb  = p.getCallbackId("on_change")
        val groupDisabled = p.getBool("disabled")
        val a11yLabel   = p.getString("a11y_label")
        val a11yHint    = p.getString("a11y_hint")

        val theme = if (NativeAppearanceState.isDark()) NativeUITheme.dark else NativeUITheme.light

        var selectedValue by remember(node.id) { mutableStateOf(serverValue) }
        var lastSentValue by remember(node.id) { mutableStateOf(serverValue) }

        LaunchedEffect(serverValue) {
            if (serverValue != lastSentValue) {
                selectedValue = serverValue
                lastSentValue = serverValue
            }
        }

        val groupModifier = modifier.nuiA11y(a11yLabel, a11yHint)

        Column(modifier = groupModifier) {
            if (label.isNotEmpty()) {
                Text(text = label, fontFamily = nuiDefaultFontFamily(), color = theme.onSurfaceVariant)
                Spacer(Modifier.height(8.dp))
            }
            node.children.forEach { child ->
                if (child.type == "radio") {
                    RadioRenderer.Render(
                        node = child,
                        modifier = buildModifier(child),
                        selectedValue = selectedValue,
                        groupDisabled = groupDisabled,
                        onSelect = { value ->
                            selectedValue = value
                            lastSentValue = value
                            if (onChangeCb != 0) {
                                NativeUIBridge.sendRadioChangeEvent(onChangeCb, node.id, value)
                            }
                        },
                    )
                } else {
                    RenderNode(child)
                }
            }
        }
    }
}
