package com.nativephp.plugins.native_ui.ui

import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.View
import androidx.activity.ComponentActivity
import androidx.compose.foundation.layout.Box
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import com.nativephp.mobile.ui.nativerender.*
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import org.robolectric.annotation.GraphicsMode

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
@GraphicsMode(GraphicsMode.Mode.NATIVE)
class BackgroundLayerStyleTest {
    @get:Rule val compose = createAndroidComposeRule<ComponentActivity>()

    @Before fun registerColumn() {
        NativeRendererRegistry.register("column", NodeRenderer { _, modifier -> Box(modifier) })
    }

    @Test fun theTopElementPaintsItsBackground() {
        show(column(bg = 0xFFFF0000.toInt()))
        assertNear(Color.Red, pixel(0.5f))
    }

    @Test fun theTopElementPaintsItsGradient() {
        show(column(props = mapOf("gradient_stops" to "#FFFF0000,#FF0000FF", "gradient_dx" to 0f, "gradient_dy" to 1f)))
        assertNear(Color.Red, pixel(0f))
        assertNear(Color.Blue, pixel(1f))
    }

    @Test @Config(qualifiers = "night")
    fun theTopElementPaintsItsDarkBackgroundInDarkMode() {
        show(column(bg = 0xFFFF0000.toInt(), props = mapOf("dark_bg_color" to "#FF00FF00")))
        assertNear(Color.Green, pixel(0.5f))
    }

    private fun show(child: NativeUINode) = compose.setContent {
        NativeUIBackgroundLayerHost(NativeUINode(1, "background_layer", null, null, GenericProps(), 0, 0, listOf(child))) {}
    }

    /**
     * The colour drawn at the horizontal centre, [fraction] of the way down.
     * Draws the content view itself: `captureToImage()` in this Compose
     * version waits for a frame commit Robolectric never delivers.
     */
    private fun pixel(fraction: Float): Color {
        val view = compose.activity.findViewById<View>(android.R.id.content)
        val bitmap = Bitmap.createBitmap(view.width, view.height, Bitmap.Config.ARGB_8888)
        compose.runOnIdle { view.draw(Canvas(bitmap)) }
        return Color(bitmap.getPixel(bitmap.width / 2, ((bitmap.height - 1) * fraction).toInt()))
    }

    /** Within a couple of steps per channel: a gradient's first and last rows are not pure. */
    private fun assertNear(expected: Color, actual: Color) = assertTrue(
        "expected $expected but was $actual",
        listOf(expected.red - actual.red, expected.green - actual.green, expected.blue - actual.blue, expected.alpha - actual.alpha)
            .all { kotlin.math.abs(it) < 0.02f },
    )

    private fun column(bg: Int = 0, props: Map<String, Any> = emptyMap()) =
        NativeUINode(2, "column", null, NodeStyle.EMPTY.copy(bgColor = bg), GenericProps(props), 0, 0, emptyList())
}
