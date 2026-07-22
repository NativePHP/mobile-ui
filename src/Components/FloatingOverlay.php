<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;
use Native\Mobile\UI\Concerns\HasFloatingOverlay;

/**
 * Blade component for the `floating_overlay` sentinel. The floating overlay is
 * normally emitted by the chrome contributor (see
 * {@see HasFloatingOverlay}), so this tag is rarely
 * written by hand — it exists to satisfy the manifest's element/blade pairing
 * and so the native no-op renderer (`EmptyRenderer`) is registered for the
 * marker (the host consumes it before it would render in place).
 */
class FloatingOverlay extends NativeBladeComponent
{
    protected function elementType(): string
    {
        return 'floating_overlay';
    }
}
