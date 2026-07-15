<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * Sentinel element produced by the native-ui floating-overlay chrome
 * contributor (registered with core's `ChromeContributorRegistry`). Core
 * appends it to the published tree; the native `NativeFloatingOverlayHost` —
 * registered on core's `NativeRootHostRegistry` from this plugin's init
 * function — pulls it out and floats it on a top layer over the content
 * instead of rendering it in place.
 *
 * Content-agnostic: its single child is an arbitrary rendered Blade/element
 * tree, so developers can float any UI (a pill, a banner, a mini-player).
 *
 * Props:
 *  - `alignment` — `bottom` (above the tab bar, default) or `top`
 *                  (below the nav bar).
 *  - `offset`    — points/dp between the overlay and the aligned edge on top
 *                  of the safe-area inset; null = platform default that clears
 *                  a standard bottom tab bar.
 */
class FloatingOverlay extends Element
{
    protected string $type = 'floating_overlay';

    protected array $props = ['alignment' => 'bottom'];

    public static function make(): static
    {
        return new static;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['alignment'])) {
            $this->props['alignment'] = $attrs['alignment'] === 'top' ? 'top' : 'bottom';
        }
        if (isset($attrs['offset']) && $attrs['offset'] !== null) {
            $this->props['offset'] = (int) $attrs['offset'];
        }

        $this->applyA11yAttributes($attrs);
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        return $this->props;
    }
}
