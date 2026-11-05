package com.nativephp.plugins.native_ui

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.keyframes
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.pulltorefresh.PullToRefreshDefaults
import androidx.compose.material3.pulltorefresh.PullToRefreshState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.dp
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import java.util.concurrent.ConcurrentHashMap

/**
 * What a registered pull-to-refresh indicator draws from.
 *
 * @property progress how far the content is pulled, from 0 at rest to 1 at
 *   the refresh threshold; read it while drawing so a pull doesn't recompose
 * @property isRefreshing whether the refresh the pull triggered is running
 * @property options the `refresh-indicator-options` the screen gave, decoded
 *   from JSON (strings, numbers, booleans, lists and maps)
 */
class RefreshIndicatorScope(
    val progress: () -> Float,
    val isRefreshing: Boolean,
    val options: Map<String, Any?>,
)

/**
 * Pull-to-refresh indicators other plugins provide, by the name a list's
 * `refresh-indicator` attribute gives. Register from the plugin's
 * `android.init_function`, before the first composition:
 *
 *     NativeUIRefreshIndicators.register("lottie") { scope -> … }
 *
 * The list draws the indicator on the stock indicator's disc, which slides
 * with the pull and is clipped to the list's top edge; the indicator only
 * fills the disc. A list naming an indicator nobody registered keeps the
 * stock spinner.
 */
object NativeUIRefreshIndicators {
    private val indicators = ConcurrentHashMap<String, @Composable (RefreshIndicatorScope) -> Unit>()

    fun register(name: String, content: @Composable (RefreshIndicatorScope) -> Unit) {
        indicators[name] = content
    }

    internal fun find(name: String): (@Composable (RefreshIndicatorScope) -> Unit)? =
        if (name.isEmpty()) null else indicators[name]

    internal fun reset() = indicators.clear()
}

internal const val REFRESH_INDICATOR_TAG = "refresh-indicator"

/** A little larger than the stock 40dp disc, so artwork stays legible inside its padding. */
private val REFRESH_INDICATOR_SIZE = 48.dp

private val REFRESH_INDICATOR_PADDING = 6.dp

/** The bounce marking a pull past the threshold: up to this scale and back. */
private const val REFRESH_INDICATOR_BOUNCE_SCALE = 1.15f
private const val REFRESH_INDICATOR_BOUNCE_MILLIS = 200

/**
 * The indicator a list's `refresh_indicator` names, on the stock disc, or
 * the stock indicator when no plugin registered that name.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun BoxScope.NativeUIRefreshIndicator(
    name: String,
    options: String,
    state: PullToRefreshState,
    isRefreshing: Boolean,
) {
    val content = NativeUIRefreshIndicators.find(name)
    if (content == null) {
        PullToRefreshDefaults.Indicator(
            state = state,
            isRefreshing = isRefreshing,
            modifier = Modifier.align(Alignment.TopCenter),
        )
        return
    }

    val decoded = remember(options) { decodeRefreshIndicatorOptions(options) }
    // PullToRefreshBox refreshes on a release past the threshold, where the
    // distance fraction passes 1.
    val armed by remember(state) { derivedStateOf { state.distanceFraction > 1f } }
    val haptic = LocalHapticFeedback.current
    val scale = remember { Animatable(1f) }
    LaunchedEffect(armed && !isRefreshing) {
        if (armed && !isRefreshing) {
            haptic.performHapticFeedback(HapticFeedbackType.GestureThresholdActivate)
            scale.animateTo(1f, keyframes {
                durationMillis = REFRESH_INDICATOR_BOUNCE_MILLIS
                REFRESH_INDICATOR_BOUNCE_SCALE at REFRESH_INDICATOR_BOUNCE_MILLIS * 2 / 5
            })
        } else {
            scale.snapTo(1f)
        }
    }

    PullToRefreshDefaults.IndicatorBox(
        state = state,
        isRefreshing = isRefreshing,
        modifier = Modifier.align(Alignment.TopCenter).size(REFRESH_INDICATOR_SIZE),
        containerColor = PullToRefreshDefaults.indicatorContainerColor,
    ) {
        // Inside the box, so its bounds follow the disc as it slides.
        Box(
            Modifier
                .fillMaxSize()
                .graphicsLayer {
                    scaleX = scale.value
                    scaleY = scale.value
                }
                .testTag(REFRESH_INDICATOR_TAG)
                .padding(REFRESH_INDICATOR_PADDING),
            contentAlignment = Alignment.Center,
        ) {
            content(RefreshIndicatorScope({ state.distanceFraction.coerceIn(0f, 1f) }, isRefreshing, decoded))
        }
    }
}

private fun decodeRefreshIndicatorOptions(json: String): Map<String, Any?> {
    if (json.isEmpty()) return emptyMap()
    return try {
        jsonObjectToMap(JSONObject(json))
    } catch (_: JSONException) {
        emptyMap()
    }
}

private fun jsonObjectToMap(json: JSONObject): Map<String, Any?> =
    json.keys().asSequence().associateWith { jsonValue(json.get(it)) }

private fun jsonValue(value: Any?): Any? = when (value) {
    JSONObject.NULL -> null
    is JSONObject -> jsonObjectToMap(value)
    is JSONArray -> (0 until value.length()).map { jsonValue(value.get(it)) }
    else -> value
}
