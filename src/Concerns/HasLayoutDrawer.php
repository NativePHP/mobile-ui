<?php

namespace Native\Mobile\UI\Concerns;

use Native\Mobile\Edge\NativeComponent;
use Native\Mobile\UI\Builders\Drawer;

/**
 * Add a content-agnostic side drawer (X-style side nav) to a `NativeLayout`.
 *
 * `use` this trait on a layout and override `drawer()`:
 *
 *   class AppLayout extends NativeLayout
 *   {
 *       use HasLayoutDrawer;
 *
 *       public function drawer(NativeComponent $screen): ?Drawer
 *       {
 *           return Drawer::make(view('native.side_bar'))->reveal();
 *       }
 *   }
 *
 * The native-ui chrome contributor (registered with core's
 * `ChromeContributorRegistry`) discovers `drawer()` and hoists it into a global
 * drawer host. A screen can override per-screen or suppress it with
 * {@see InteractsWithDrawer}.
 */
trait HasLayoutDrawer
{
    /**
     * Return the side drawer for screens routed under this layout, or null for
     * none. Declared once here so it isn't duplicated across every screen.
     */
    public function drawer(NativeComponent $screen): ?Drawer
    {
        return null;
    }
}
