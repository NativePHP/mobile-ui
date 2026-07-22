<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * Sentinel element produced by the native-ui layout-drawer chrome contributor
 * (registered with core's `ChromeContributorRegistry`). Core appends it to the
 * published tree; the native `NativeDrawerHost` / `NativeLayoutDrawerHost` —
 * registered on core's `NativeRootHostRegistry` from this plugin's init
 * function — pulls it out and renders the actual drawer.
 *
 * Content-agnostic: its single child is an arbitrary rendered Blade/element
 * tree, so developers can put any UI inside the drawer.
 *
 * Props:
 *  - `mode`  — `modal` (slides over content with a scrim, default) or
 *              `reveal` (main content slides aside to expose the drawer behind).
 *  - `width` — drawer width in points/dp; null = platform default.
 */
class NativeDrawer extends Element
{
    protected string $type = 'native_drawer';

    protected array $props = ['mode' => 'modal'];

    public static function make(): static
    {
        return new static;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['mode'])) {
            $this->props['mode'] = $attrs['mode'] === 'reveal' ? 'reveal' : 'modal';
        }
        if (isset($attrs['width']) && $attrs['width'] !== null) {
            $this->props['width'] = (int) $attrs['width'];
        }

        $this->applyA11yAttributes($attrs);
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        return $this->props;
    }
}
