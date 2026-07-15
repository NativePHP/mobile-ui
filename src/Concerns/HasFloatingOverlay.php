<?php

namespace Native\Mobile\UI\Concerns;

use Native\Mobile\Edge\NativeComponent;
use Native\Mobile\UI\Builders\FloatingOverlay;

/**
 * Add a content-agnostic floating overlay (a pill/banner that hovers above the
 * content and the tab bar) to a `NativeLayout`.
 *
 * `use` this trait on a layout and override `floatingOverlay()`:
 *
 *   class AppLayout extends NativeLayout
 *   {
 *       use HasFloatingOverlay;
 *
 *       public function floatingOverlay(NativeComponent $screen): ?FloatingOverlay
 *       {
 *           return FloatingOverlay::make(view('native.now_playing'))->offset(88);
 *       }
 *   }
 *
 * Because it lives on the layout, the overlay floats over *every* screen routed
 * under that layout — it persists across tabs and pushes rather than living on
 * one screen. The native-ui chrome contributor (registered with core's
 * `ChromeContributorRegistry`) discovers `floatingOverlay()` and hoists it onto
 * a global top layer. A screen can override per-screen or suppress it with
 * {@see InteractsWithFloatingOverlay}.
 *
 * Note: the method is re-evaluated on every publish from the current `$screen`,
 * so an app-wide overlay whose contents depend on state (e.g. "N servers
 * nearby") should read that state from a shared store rather than from the
 * active screen's own properties.
 */
trait HasFloatingOverlay
{
    /**
     * Return the floating overlay for screens routed under this layout, or null
     * for none. Declared once here so it isn't duplicated across every screen.
     */
    public function floatingOverlay(NativeComponent $screen): ?FloatingOverlay
    {
        return null;
    }
}
