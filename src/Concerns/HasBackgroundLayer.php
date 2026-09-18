<?php

namespace Native\Mobile\UI\Concerns;

use Native\Mobile\Edge\NativeComponent;
use Native\Mobile\UI\Builders\BackgroundLayer;

/**
 * Add a persistent background layer (content beneath every screen, mounted
 * once — a map, a video, a live canvas) to a `NativeLayout`.
 *
 * `use` this trait on a layout and override `backgroundLayer()`; return
 * null for none. Because it lives on the layout, the layer persists across
 * every screen routed under that layout — tab switches and pushes update
 * its props in place instead of recreating the native view.
 */
trait HasBackgroundLayer
{
    public function backgroundLayer(NativeComponent $screen): ?BackgroundLayer
    {
        return null;
    }
}
