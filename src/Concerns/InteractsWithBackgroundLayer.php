<?php

namespace Native\Mobile\UI\Concerns;

use Native\Mobile\UI\Builders\BackgroundLayer;

/**
 * Per-screen control over the layout's background layer. `use` this trait on
 * a `NativeComponent` screen to override or suppress the layer its layout
 * declares via {@see HasBackgroundLayer}.
 *
 *   class SettingsScreen extends NativeComponent
 *   {
 *       use InteractsWithBackgroundLayer;
 *
 *       // Hide the app-wide map on this screen:
 *       protected bool $hidesBackgroundLayer = true;
 *   }
 *
 * Or replace it just for this screen:
 *
 *   public function backgroundLayerOverride(): ?BackgroundLayer
 *   {
 *       return BackgroundLayer::make(view('native.settings_backdrop'));
 *   }
 *
 * Mirrors {@see InteractsWithFloatingOverlay}. The native-ui chrome
 * contributor checks these (via `method_exists`) before falling back to the
 * layout. A bare `protected bool $hidesBackgroundLayer = true;` property
 * WITHOUT this trait also works — the contributor falls back to reading the
 * property directly, matching core's `$hidesTabBar` / `$hidesNavBar`
 * shorthand.
 */
trait InteractsWithBackgroundLayer
{
    /**
     * Suppress the layout's background layer on this screen. Default `false`
     * → the layout's `backgroundLayer()` (if any) shows.
     */
    protected bool $hidesBackgroundLayer = false;

    /**
     * Override to provide a per-screen layer that wins over the layout's
     * `backgroundLayer()`. Returning null falls back to the layout.
     */
    public function backgroundLayerOverride(): ?BackgroundLayer
    {
        return null;
    }

    /** Whether this screen suppresses its layout's background layer. */
    public function hidesBackgroundLayer(): bool
    {
        return $this->hidesBackgroundLayer;
    }
}
