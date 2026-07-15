<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

/**
 * Blade component for the `native_drawer` sentinel. The layout drawer is
 * normally emitted by the chrome contributor (see
 * {@see \Native\Mobile\UI\Concerns\HasLayoutDrawer}), so this tag is rarely
 * written by hand — it exists to satisfy the manifest's element/blade pairing
 * and so the native no-op renderer (`EmptyRenderer`) is registered for the
 * marker.
 */
class NativeDrawer extends NativeBladeComponent
{
    protected function elementType(): string
    {
        return 'native_drawer';
    }
}
