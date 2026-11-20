package com.nativephp.plugins.native_ui.ui

import androidx.compose.foundation.gestures.Orientation
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.unit.dp
import com.nativephp.mobile.ui.nativerender.*
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * A photo viewer: a `bounded` gesture area with both pans and a pinch bound,
 * on the first page of a horizontal pager, inside a vertical drag to close.
 * A one-finger drag is the photo's only while it's zoomed far enough to have
 * room to move; at whole size the pager pages and the drag to close closes,
 * with the pans still bound. A pinch and a double tap work either way.
 *
 * The pager here is Compose's `HorizontalPager`, which the production pager
 * renders, and the drag to close runs `detectVerticalDragGestures`, which a
 * gesture area with a lone `pan-y-id` runs. Both renderers draw their
 * children with this module's `NodeView`, which can't hold a gesture area.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class GestureAreaBoundedPanTest {
    @get:Rule val compose = createComposeRule()

    private lateinit var pager: PagerState

    /** How far the drag to close has moved, in dp. */
    private var closing = 0f

    /**
     * The photo's own SharedValues, back at rest, and an empty log. A test
     * that fails with fingers down ends its pinch when the composition goes,
     * after its own teardown, and the report would land in the next test.
     */
    @Before fun rest() {
        SharedValueStore.set(PanX, 0f)
        SharedValueStore.set(PanY, 0f)
        SharedValueStore.set(Pinch, 1f)
        NativeUIBridge.events.clear()
    }

    @After fun reset() {
        NativeUIBridge.events.clear()
    }

    @Test fun horizontalDragAtWholeSizePagesThePager() {
        viewer()
        compose.onNodeWithTag("node-2").performTouchInput { dragBy(-200f, 0f) }
        compose.runOnIdle {
            assertEquals(0f, SharedValueStore.valueOf(PanX), 0.01f)
            assertTrue("pager at ${position()}", position() > 0.3f)
        }
        compose.onNodeWithTag("node-2").performTouchInput { up() }
        compose.runOnIdle {
            assertEquals(1, pager.currentPage)
            assertEquals(0f, SharedValueStore.valueOf(PanX), 0.01f)
            assertEquals(0f, SharedValueStore.valueOf(PanY), 0.01f)
            assertEquals(emptyList<String>(), events())
        }
    }

    @Test fun horizontalDragJustPastWholeSizeStillPagesThePager() {
        viewer()
        // A pinch let go at 1.01x leaves the 300dp-wide photo 1.5dp each way.
        compose.runOnIdle { SharedValueStore.set(Pinch, 1.01f) }
        compose.onNodeWithTag("node-2").performTouchInput { dragBy(-200f, 0f) }
        compose.runOnIdle {
            assertEquals(0f, SharedValueStore.valueOf(PanX), 0.01f)
            assertTrue("pager at ${position()}", position() > 0.3f)
        }
        compose.onNodeWithTag("node-2").performTouchInput { up() }
        compose.runOnIdle { assertEquals(1, pager.currentPage) }
    }

    @Test fun horizontalDragWhenZoomedPansThePhotoAndLeavesThePager() {
        viewer()
        // Written straight to the store, as a pinch does: nothing recomposes.
        compose.runOnIdle { SharedValueStore.set(Pinch, 2f) }
        compose.onNodeWithTag("node-2").performTouchInput { dragBy(-100f, 0f) }
        compose.runOnIdle {
            assertTrue("panned to ${SharedValueStore.valueOf(PanX)}", SharedValueStore.valueOf(PanX) < -70f)
            assertEquals(0f, position(), 0.001f)
        }
        compose.onNodeWithTag("node-2").performTouchInput { up() }
        compose.runOnIdle {
            assertEquals(0, pager.currentPage)
            assertEquals(0f, position(), 0.001f)
            assertEquals(1, events().size)
            assertTrue(events().toString(), events().single().startsWith("change:$DragEnd:-"))
        }
    }

    @Test fun verticalDragAtWholeSizeGoesToTheDragToClose() {
        viewer()
        compose.onNodeWithTag("node-2").performTouchInput { dragBy(0f, 80f) }
        compose.runOnIdle {
            assertTrue("closing by $closing", closing > 50f)
            assertEquals(0f, SharedValueStore.valueOf(PanY), 0.01f)
        }
        compose.onNodeWithTag("node-2").performTouchInput { up() }
        compose.runOnIdle {
            assertEquals(0f, SharedValueStore.valueOf(PanY), 0.01f)
            assertEquals(emptyList<String>(), events())
        }
    }

    @Test fun verticalDragWhenZoomedPansThePhotoAndLeavesTheDragToClose() {
        viewer()
        compose.runOnIdle { SharedValueStore.set(Pinch, 2f) }
        // At 2x the 120dp-high photo has 60dp to move each way.
        compose.onNodeWithTag("node-2").performTouchInput { dragBy(0f, 50f) }
        compose.runOnIdle {
            assertTrue("panned to ${SharedValueStore.valueOf(PanY)}", SharedValueStore.valueOf(PanY) > 30f)
            assertEquals(0f, closing, 0.01f)
        }
        compose.onNodeWithTag("node-2").performTouchInput { up() }
        compose.runOnIdle { assertEquals(0f, closing, 0.01f) }
    }

    /**
     * Room is judged once, as the drag passes touch slop. Steps bigger than
     * the slop, as a quick swipe makes, mustn't give the photo another go
     * once the pager has the drag, even if it has zoomed since.
     */
    @Test fun dragThePagerTookStaysWithItWhenThePhotoZoomsMidway() {
        viewer()
        compose.onNodeWithTag("node-2").performTouchInput { dragBy(-160f, 0f) }
        compose.runOnIdle { SharedValueStore.set(Pinch, 2f) }
        compose.onNodeWithTag("node-2").performTouchInput {
            repeat(4) { moveBy(Offset((-25).dp.toPx(), 0f)) }
        }
        compose.runOnIdle {
            assertEquals(0f, SharedValueStore.valueOf(PanX), 0.01f)
            assertTrue("pager at ${position()}", position() > 0.5f)
        }
        compose.onNodeWithTag("node-2").performTouchInput { up() }
    }

    @Test fun dragTheDragToCloseTookStaysWithItWhenThePhotoZoomsMidway() {
        viewer()
        compose.onNodeWithTag("node-2").performTouchInput { dragBy(0f, 160f) }
        compose.runOnIdle { SharedValueStore.set(Pinch, 2f) }
        compose.onNodeWithTag("node-2").performTouchInput {
            repeat(4) { moveBy(Offset(0f, 25.dp.toPx())) }
        }
        compose.runOnIdle {
            assertEquals(0f, SharedValueStore.valueOf(PanY), 0.01f)
            assertTrue("closing by $closing", closing > 200f)
        }
        compose.onNodeWithTag("node-2").performTouchInput { up() }
    }

    /** A second finger on the photo while the pager has the drag makes it a pinch, and the pager goes back. */
    @Test fun secondFingerDuringAPageMakesItAPinch() {
        viewer()
        compose.onNodeWithTag("node-2").performTouchInput {
            down(0, center)
            repeat(4) { moveBy(0, Offset((-15).dp.toPx(), 0f)) }
        }
        compose.runOnIdle { assertTrue("pager at ${position()}", position() > 0.1f) }
        compose.onNodeWithTag("node-2").performTouchInput {
            down(1, center + Offset(40.dp.toPx(), 0f))
            repeat(5) {
                updatePointerBy(1, Offset(10.dp.toPx(), 0f))
                move()
            }
        }
        compose.runOnIdle {
            assertTrue("zoomed to ${SharedValueStore.valueOf(Pinch)}", SharedValueStore.valueOf(Pinch) > 1.2f)
        }
        compose.onNodeWithTag("node-2").performTouchInput {
            up(1)
            up(0)
        }
        compose.runOnIdle { assertEquals(0f, position(), 0.001f) }
    }

    @Test fun pinchAtWholeSizeZoomsWithoutPaging() {
        viewer()
        compose.onNodeWithTag("node-2").performTouchInput { pinch(Offset(1f, 0f), from = 30f, by = 5f) }
        compose.runOnIdle {
            assertTrue("zoomed to ${SharedValueStore.valueOf(Pinch)}", SharedValueStore.valueOf(Pinch) > 1.5f)
            assertEquals(0f, position(), 0.001f)
            assertEquals(0f, closing, 0.01f)
        }
        compose.onNodeWithTag("node-2").performTouchInput {
            up(0)
            up(1)
        }
        compose.runOnIdle {
            assertEquals(0, pager.currentPage)
            assertTrue(events().toString(), events().any { it.startsWith("slider:$PinchEnd:") })
        }
    }

    /**
     * Pinching in at whole size leaves the scale at `pinch-min` and the photo
     * no room, but the fingers are still a pinch: the drag to close, which
     * follows the first finger alone, mustn't take it.
     */
    @Test fun pinchingInAtWholeSizeDoesNotStartTheDragToClose() {
        viewer()
        compose.onNodeWithTag("node-2").performTouchInput { pinch(Offset(0f, 1f), from = 60f, by = -5f) }
        compose.runOnIdle {
            assertEquals(1f, SharedValueStore.valueOf(Pinch), 0.001f)
            assertEquals(0f, closing, 0.01f)
        }
        compose.onNodeWithTag("node-2").performTouchInput {
            up(0)
            up(1)
        }
        compose.runOnIdle { assertEquals(0f, closing, 0.01f) }
    }

    @Test fun doubleTapAtWholeSizeZoomsAndAimsTheBoundPans() {
        viewer()
        // 60dp right of the middle: at 2x that point comes to the middle when
        // the pan is -120, inside the 150 the bounds allow.
        compose.onNodeWithTag("node-2").performTouchInput { doubleClick(center + Offset(60.dp.toPx(), 0f)) }
        compose.runOnIdle {
            assertEquals(2f, SharedValueStore.valueOf(Pinch), 0.01f)
            assertEquals(-120f, SharedValueStore.valueOf(PanX), 0.5f)
            assertEquals(0f, SharedValueStore.valueOf(PanY), 0.5f)
            assertEquals(listOf("slider:$PinchEnd:2.0"), events())
            assertEquals(0, pager.currentPage)
        }
    }

    @Test fun pinchAfterADoubleTapCarriesOnFromItsZoom() {
        viewer()
        compose.onNodeWithTag("node-2").performTouchInput { doubleClick(center) }
        compose.runOnIdle { assertEquals(2f, SharedValueStore.valueOf(Pinch), 0.01f) }
        // Fingers 100dp apart spread to 105: 1.05 times the double tap's 2x.
        compose.onNodeWithTag("node-2").performTouchInput {
            pinch(Offset(1f, 0f), from = 100f, by = 0.5f)
            up(0)
            up(1)
        }
        compose.runOnIdle {
            assertEquals(2.1f, SharedValueStore.valueOf(Pinch), 0.02f)
            assertEquals("slider:$PinchEnd:2.0", events().first())
            assertEquals(2.1f, events().last().substringAfterLast(':').toFloat(), 0.02f)
        }
    }

    /**
     * A swipe straight after a double tap back out is the pager's: the photo
     * is on its way to 1x, so it doesn't stop there half-zoomed and pan, and
     * the zoom lands and reports as it would have.
     */
    @Test fun dragStraightAfterADoubleTapOutPagesAndTheZoomFinishes() {
        viewer()
        compose.onNodeWithTag("node-2").performTouchInput { doubleClick(center + Offset(60.dp.toPx(), 0f)) }
        compose.runOnIdle { assertEquals(2f, SharedValueStore.valueOf(Pinch), 0.01f) }
        compose.onNodeWithTag("node-2").performTouchInput {
            doubleClick(center)
            advanceEventTime(50)
            dragBy(-200f, 0f)
            up()
        }
        compose.runOnIdle {
            assertEquals(1, pager.currentPage)
            assertEquals(1f, SharedValueStore.valueOf(Pinch), 0.001f)
            assertEquals(0f, SharedValueStore.valueOf(PanX), 0.01f)
            assertEquals(listOf("slider:$PinchEnd:2.0", "slider:$PinchEnd:1.0"), events())
        }
    }

    /**
     * A swipe that passes touch slop before a double tap's zoom in has moved
     * the photo is the pager's: the photo has no room yet, so the drag
     * doesn't freeze it barely zoomed. The zoom isn't stopped, and lands.
     */
    @Test fun dragBeforeADoubleTapInHasMovedPages() {
        viewer()
        compose.onNodeWithTag("node-2").performTouchInput {
            doubleClick(center)
            // Past slop on the second tap's own frame: the eased zoom is at
            // about 1.13x one frame later, which is room already.
            down(center)
            moveBy(Offset((-25).dp.toPx(), 0f), delayMillis = 0)
            repeat(7) { moveBy(Offset((-25).dp.toPx(), 0f)) }
            up()
        }
        compose.runOnIdle {
            assertEquals(1, pager.currentPage)
            assertEquals(0f, SharedValueStore.valueOf(PanX), 0.01f)
            assertEquals(2f, SharedValueStore.valueOf(Pinch), 0.001f)
            assertEquals(listOf("slider:$PinchEnd:2.0"), events())
        }
    }

    /**
     * 50ms in, the eased zoom in is most of the way to 2x and the photo has
     * room, so the swipe is the photo's: it stops the zoom where it is and
     * pans, and the zoom never lands.
     */
    @Test fun dragOnceADoubleTapInHasRoomPansAndStopsTheZoom() {
        viewer()
        compose.onNodeWithTag("node-2").performTouchInput {
            doubleClick(center)
            advanceEventTime(50)
            // Short of the room the zoom has by then, so the pager stays put.
            dragBy(-40f, 0f)
            up()
        }
        compose.runOnIdle {
            assertEquals(0f, position(), 0.001f)
            val scale = SharedValueStore.valueOf(Pinch)
            assertTrue("stopped at $scale", scale > 1.1f && scale < 1.95f)
            assertTrue(events().toString(), events().none { it.startsWith("slider:") })
        }
    }

    @Test fun swipeTowardsTheEdgeAZoomedPhotoIsAtPagesThePager() {
        viewer()
        // At 2x the 300dp-wide photo has 150dp to move each way. At -150 its
        // right edge is showing, so it can't go any further left.
        compose.runOnIdle {
            SharedValueStore.set(Pinch, 2f)
            SharedValueStore.set(PanX, -150f)
        }
        compose.onNodeWithTag("node-2").performTouchInput { dragBy(-120f, 0f) }
        compose.runOnIdle {
            assertEquals(-150f, SharedValueStore.valueOf(PanX), 0.01f)
            assertTrue("pager at ${position()}", position() > 0.2f)
        }
        compose.onNodeWithTag("node-2").performTouchInput { up() }
        compose.runOnIdle {
            assertEquals(1, pager.currentPage)
            assertEquals(-150f, SharedValueStore.valueOf(PanX), 0.01f)
            assertEquals(emptyList<String>(), events())
        }
    }

    @Test fun swipeAwayFromTheEdgeAZoomedPhotoIsAtPansIt() {
        viewer()
        compose.runOnIdle {
            SharedValueStore.set(Pinch, 2f)
            SharedValueStore.set(PanX, -150f)
        }
        compose.onNodeWithTag("node-2").performTouchInput { dragBy(100f, 0f) }
        compose.runOnIdle {
            assertTrue("panned to ${SharedValueStore.valueOf(PanX)}", SharedValueStore.valueOf(PanX) > -80f)
            assertEquals(0f, position(), 0.001f)
        }
        compose.onNodeWithTag("node-2").performTouchInput { up() }
        compose.runOnIdle { assertEquals(0, pager.currentPage) }
    }

    @Test fun dragDownAtTheTopEdgeOfAZoomedPhotoStaysWithThePhoto() {
        viewer()
        // At 2x the 120dp-high photo has 60dp each way, and at 60 its top
        // edge is showing: it can't go any further down. The drag to close
        // only gets drags at whole size, so the photo stretches instead.
        compose.runOnIdle {
            SharedValueStore.set(Pinch, 2f)
            SharedValueStore.set(PanY, 60f)
        }
        compose.onNodeWithTag("node-2").performTouchInput { dragBy(0f, 80f) }
        compose.runOnIdle {
            assertEquals(0f, closing, 0.01f)
            assertTrue("stretched to ${SharedValueStore.valueOf(PanY)}", SharedValueStore.valueOf(PanY) > 61f)
        }
        compose.onNodeWithTag("node-2").performTouchInput { up() }
        compose.runOnIdle {
            assertEquals(0f, closing, 0.01f)
            assertEquals(60f, SharedValueStore.valueOf(PanY), 0.01f)
        }
    }

    @Test fun zoomedPhotoDraggedPastItsEdgePullsThePagerOn() {
        viewer()
        // 50dp short of its right edge.
        compose.runOnIdle {
            SharedValueStore.set(Pinch, 2f)
            SharedValueStore.set(PanX, -100f)
        }
        compose.onNodeWithTag("node-2").performTouchInput { dragBy(-200f, 0f) }
        compose.runOnIdle {
            // At the edge, not stretched past it: the pager has the rest.
            assertEquals(-150f, SharedValueStore.valueOf(PanX), 0.01f)
            assertTrue("pager at ${position()}", position() > 0.35f && position() < 0.55f)
        }
        compose.onNodeWithTag("node-2").performTouchInput { up() }
        compose.runOnIdle {
            assertEquals(1, pager.currentPage)
            assertEquals(0f, pager.currentPageOffsetFraction, 0.001f)
            assertEquals(-150f, SharedValueStore.valueOf(PanX), 0.01f)
            assertEquals(listOf("change:$DragEnd:-150.0,0.0"), events())
        }
    }

    @Test fun slowDragPastAZoomedPhotosEdgeLetGoShortOfHalfwayStaysOnItsPage() {
        viewer()
        // From the middle, 150dp short of its right edge: most of the drag
        // pans the photo, and the pager only goes about a quarter of the
        // way. The finger has gone most of a page, which Compose's pager
        // would take as a drag past halfway.
        compose.runOnIdle {
            SharedValueStore.set(Pinch, 2f)
            SharedValueStore.set(PanX, 0f)
        }
        compose.onNodeWithTag("node-2").performTouchInput {
            dragBy(-250f, 0f)
            advanceEventTime(300)
            up()
        }
        compose.runOnIdle {
            assertEquals(0, pager.currentPage)
            assertEquals(0f, pager.currentPageOffsetFraction, 0.001f)
            assertEquals(-150f, SharedValueStore.valueOf(PanX), 0.01f)
        }
    }

    @Test fun pagerAZoomedPhotoPulledOnGoesBackBeforeThePhotoPansAgain() {
        viewer()
        compose.runOnIdle {
            SharedValueStore.set(Pinch, 2f)
            SharedValueStore.set(PanX, -100f)
        }
        compose.onNodeWithTag("node-2").performTouchInput {
            dragBy(-160f, 0f)
            repeat(8) { moveBy(Offset((160f / 8f).dp.toPx(), 0f)) }
        }
        compose.runOnIdle {
            assertEquals(0f, position(), 0.001f)
            // Back where it started, and on by the touch slop the drag took
            // to start, which moved neither.
            val x = SharedValueStore.valueOf(PanX)
            assertTrue("panned to $x", x > -100f && x < -75f)
        }
        compose.onNodeWithTag("node-2").performTouchInput { up() }
    }

    @Test fun zoomedPhotoFlickedGlidesOnToItsEdge() {
        viewer()
        // At 3x the photo has 300dp to move each way across.
        compose.runOnIdle { SharedValueStore.set(Pinch, 3f) }
        compose.onNodeWithTag("node-2").performTouchInput {
            down(center)
            // 60dp in 40ms: 1500dp/s, which would carry it some 750dp on.
            repeat(4) { moveBy(Offset((-15f).dp.toPx(), 0f), delayMillis = 10) }
            up()
        }
        compose.runOnIdle {
            assertEquals(-300f, SharedValueStore.valueOf(PanX), 0.01f)
            assertEquals(0f, position(), 0.001f)
            assertEquals(listOf("change:$DragEnd:-300.0,0.0"), events())
        }
    }

    @Test fun zoomedPhotoLetGoMovingGlidesOnAndSlowsToAStop() {
        viewer()
        compose.runOnIdle { SharedValueStore.set(Pinch, 3f) }
        var letGo = 0f
        compose.onNodeWithTag("node-2").performTouchInput {
            down(center)
            // 48dp in 128ms: 375dp/s, about another 190dp.
            repeat(8) { moveBy(Offset((-6f).dp.toPx(), 0f)) }
        }
        compose.runOnIdle { letGo = SharedValueStore.valueOf(PanX) }
        compose.onNodeWithTag("node-2").performTouchInput { up() }
        compose.runOnIdle {
            val x = SharedValueStore.valueOf(PanX)
            assertTrue("let go at $letGo, rests at $x", x < letGo - 100f && x > -300f)
            assertEquals(listOf("change:$DragEnd:$x,0.0"), events())
        }
    }

    @Test fun zoomedPhotoHeldStillBeforeLettingGoStaysWhereItIs() {
        viewer()
        compose.runOnIdle { SharedValueStore.set(Pinch, 3f) }
        var letGo = 0f
        compose.onNodeWithTag("node-2").performTouchInput {
            down(center)
            repeat(4) { moveBy(Offset((-15f).dp.toPx(), 0f), delayMillis = 10) }
        }
        compose.runOnIdle { letGo = SharedValueStore.valueOf(PanX) }
        compose.onNodeWithTag("node-2").performTouchInput {
            advanceEventTime(200)
            up()
        }
        compose.runOnIdle {
            assertEquals(letGo, SharedValueStore.valueOf(PanX), 0.01f)
            assertEquals(listOf("change:$DragEnd:$letGo,0.0"), events())
        }
    }

    /** How far the pager has moved, in pages from the first. */
    private fun position() = pager.currentPage + pager.currentPageOffsetFraction

    /** Drags [dx], [dy] dp from the middle in eight steps, and keeps the finger down. */
    private fun TouchInjectionScope.dragBy(dx: Float, dy: Float) {
        down(center)
        repeat(8) { moveBy(Offset((dx / 8f).dp.toPx(), (dy / 8f).dp.toPx())) }
    }

    /** Two fingers [from] dp apart along [along], each moved [by] dp outwards per step for five steps, still down. */
    private fun TouchInjectionScope.pinch(along: Offset, from: Float, by: Float) {
        down(0, center - along * (from / 2).dp.toPx())
        down(1, center + along * (from / 2).dp.toPx())
        repeat(5) {
            updatePointerBy(0, -along * by.dp.toPx())
            updatePointerBy(1, along * by.dp.toPx())
            move()
        }
    }

    private fun viewer() {
        compose.setContent {
            pager = rememberPagerState { 3 }
            Box(Modifier.pointerInput(Unit) { detectVerticalDragGestures { _, dy -> closing += dy.toDp().value } }) {
                // What a gesture area with a lone `pan-y-id` tells the areas inside it.
                CompositionLocalProvider(LocalGesturePans provides GesturePans(y = true)) {
                HorizontalPager(
                    state = pager,
                    modifier = Modifier.size(300.dp, 120.dp),
                    beyondViewportPageCount = 1,
                    key = { it },
                    pageNestedScrollConnection = PagerHandOff.remember(pager, Orientation.Horizontal),
                ) { page ->
                    if (page == 0) GestureAreaRenderer.Render(photo(), Modifier) else Box(Modifier.fillMaxSize())
                }
                }
            }
        }
    }

    /** This test's drag end and pinch end reports. Other tests share the bridge log. */
    private fun events() = NativeUIBridge.events.filter {
        it.startsWith("change:$DragEnd:") || it.startsWith("slider:$PinchEnd:")
    }

    /** A 300x120 photo filling its area, so it fits at whole size and has room to move past it. */
    private fun photo() = NativeUINode(
        1, "", null, null,
        GenericProps(
            mapOf(
                "bounded" to true,
                "pan-x-id" to PanX, "pan-x-initial" to 0f,
                "pan-y-id" to PanY, "pan-y-initial" to 0f,
                "pinch-id" to Pinch, "pinch-initial" to 1f, "pinch-min" to 1f, "pinch-max" to 4f,
                "double-tap-zoom" to 2f,
                "on_drag_end" to DragEnd,
                "on_pinch_end" to PinchEnd,
            ),
        ),
        0, 0, listOf(NativeUINode(2, "", null, null, GenericProps(emptyMap()), 0, 0, emptyList())),
    )

    private companion object {
        /** Their own SharedValues and callbacks, so no other test's gestures move or report them. */
        const val PanX = 4401
        const val PanY = 4402
        const val Pinch = 4403
        const val DragEnd = 4461
        const val PinchEnd = 4462
    }
}
