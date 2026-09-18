<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

/**
 * Blade component for the `background_layer` sentinel — exists to satisfy
 * the manifest's element/blade pairing; the layer is normally emitted by
 * the chrome contributor (see HasBackgroundLayer), not written by hand.
 */
class BackgroundLayer extends NativeBladeComponent
{
    protected function elementType(): string
    {
        return 'background_layer';
    }
}
