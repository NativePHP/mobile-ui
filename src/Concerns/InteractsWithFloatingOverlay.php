<?php

namespace Native\Mobile\UI\Concerns;

use Native\Mobile\UI\Builders\FloatingOverlay;

/**
 * Per-screen control over the layout's floating overlay. `use` this trait on a
 * `NativeComponent` screen to override or suppress the overlay its layout
 * declares via {@see HasFloatingOverlay}.
 *
 *   class CheckoutScreen extends NativeComponent
 *   {
 *       use InteractsWithFloatingOverlay;
 *
 *       // Hide the app-wide pill on this screen:
 *       protected bool $hidesFloatingOverlay = true;
 *   }
 *
 * Or replace it just for this screen:
 *
 *   public function floatingOverlayOverride(): ?FloatingOverlay
 *   {
 *       return FloatingOverlay::make(view('native.checkout_hint'));
 *   }
 *
 * Mirrors how {@see InteractsWithDrawer} overrides the layout drawer. The
 * native-ui chrome contributor checks these (via `method_exists`) before
 * falling back to the layout. A bare `protected bool $hidesFloatingOverlay
 * = true;` property WITHOUT this trait also works — the contributor falls
 * back to reading the property directly, matching core's `$hidesTabBar` /
 * `$hidesNavBar` shorthand.
 */
trait InteractsWithFloatingOverlay
{
    /**
     * Suppress the layout's floating overlay on this screen. Default `false`
     * → the layout's `floatingOverlay()` (if any) shows.
     */
    protected bool $hidesFloatingOverlay = false;

    /**
     * Override to provide a per-screen overlay that wins over the layout's
     * `floatingOverlay()`. Returning null falls back to the layout.
     */
    public function floatingOverlayOverride(): ?FloatingOverlay
    {
        return null;
    }

    /** Whether this screen suppresses its layout's floating overlay. */
    public function hidesFloatingOverlay(): bool
    {
        return $this->hidesFloatingOverlay;
    }
}
