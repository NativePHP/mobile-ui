<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

/**
 * Blade fallback for `<x-native-virtual-list>`. The primary entry point is
 * the `<virtual-list>` precompiler form, which the precompiler
 * lowers into an open/iterate-window/close sequence directly. This Blade
 * class exists so the component can also be invoked via Blade's normal
 * `<x-native-virtual-list>` form — but only as an empty leaf without the
 * iteration loop. Prefer `<virtual-list>`.
 */
class NativeVirtualList extends NativeBladeComponent
{
    protected bool $isSelfClosing = true;

    protected function elementType(): string
    {
        return 'virtual_list';
    }
}
