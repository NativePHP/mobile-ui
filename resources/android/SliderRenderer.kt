package com.nativephp.plugins.native_ui.ui

import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import com.nativephp.mobile.ui.NativeAppearanceState
import com.nativephp.mobile.ui.nativerender.NativeUIBridge
import com.nativephp.mobile.ui.nativerender.NativeUINode
import com.nativephp.plugins.native_ui.NativeUITheme
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs

/**
 * Material3 Slider — continuous / stepped value selection.
 *
 * Value binding with echo-prevention (plan K) and sync-mode dispatch
 * (plan L — `native:model.live` / `.blur` / `.debounce.Xms`). All colors
 * from [NativeUITheme] — per-instance overrides intentionally not honored.
 */
object SliderRenderer {
    @Composable
    fun Render(node: NativeUINode, modifier: Modifier) {
        val p = node.props
        val serverValue = p.getFloat("value")
        val min         = p.getFloat("min", 0f)
        val max         = p.getFloat("max", 1f)
        val step        = p.getFloat("step")
        val onChangeCb  = p.getCallbackId("on_change")
        val disabled    = p.getBool("disabled")
        val syncMode    = p.getString("sync_mode", "live").lowercase()
        val debounceMs  = p.getInt("debounce_ms").let { if (it > 0) it else 300 }
        val a11yLabel   = p.getString("a11y_label")
        val a11yHint    = p.getString("a11y_hint")

        val theme = if (NativeAppearanceState.isDark()) NativeUITheme.dark else NativeUITheme.light
        val scope = rememberCoroutineScope()

        var value by remember(node.id) { mutableFloatStateOf(serverValue) }
        var lastSentValue by remember(node.id) { mutableFloatStateOf(serverValue) }
        // Hold the debounce Job across recompositions. Using `remember { null }`
        // would lose the reference on each recomposition; a boxed state value
        // survives and lets us cancel() the in-flight job reliably.
        var debounceJob by remember { mutableStateOf<Job?>(null) }

        // Echo-prevention — accept programmatic server updates, ignore echoes.
        LaunchedEffect(serverValue) {
            if (abs(serverValue - lastSentValue) > 0.0001f) {
                value = serverValue
                lastSentValue = serverValue
            }
        }

        val steps = if (step > 0f && max > min) {
            ((max - min) / step).toInt() - 1
        } else 0

        val colors = SliderDefaults.colors(
            thumbColor = theme.primary,
            activeTrackColor = theme.primary,
            inactiveTrackColor = theme.outline,
        )

        fun commit(v: Float) {
            lastSentValue = v
            if (onChangeCb != 0) {
                NativeUIBridge.sendSliderChangeEvent(onChangeCb, node.id, v)
            }
        }

        Slider(
            value = value,
            onValueChange = { newValue ->
                value = newValue
                when (syncMode) {
                    "blur" -> {
                        // Deferred — onValueChangeFinished will flush.
                    }
                    "debounce" -> {
                        debounceJob?.cancel()
                        val captured = newValue
                        val delayMs = debounceMs.coerceAtLeast(20).toLong()
                        debounceJob = scope.launch {
                            delay(delayMs)
                            commit(captured)
                        }
                    }
                    else -> { // "live"
                        commit(newValue)
                    }
                }
            },
            onValueChangeFinished = {
                debounceJob?.cancel()
                debounceJob = null
                if (abs(value - lastSentValue) > 0.0001f) {
                    commit(value)
                }
            },
            modifier = modifier.nuiA11y(a11yLabel, a11yHint),
            enabled = !disabled,
            valueRange = min..max,
            steps = steps.coerceAtLeast(0),
            colors = colors,
        )
    }
}
