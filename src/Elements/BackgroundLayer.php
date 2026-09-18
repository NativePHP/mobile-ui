<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * Sentinel element produced by the background-layer chrome contributor.
 * Core appends it to the published tree; the native host — registered on
 * core's `NativeRootHostRegistry` — pulls it out and renders it BENEATH
 * the screen content at a stable structural position, so whatever lives
 * in the layer (a map, a video, a canvas) mounts once and persists
 * across tab switches and pushes instead of re-initializing per screen.
 *
 * Content-agnostic: its single child is an arbitrary rendered
 * Blade/element tree.
 */
class BackgroundLayer extends Element
{
    protected string $type = 'background_layer';

    protected array $props = [];

    public static function make(): static
    {
        return new static;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        return $this->props;
    }
}
