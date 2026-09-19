<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

/**
 * Blade fallback for `<x-native-pager>`. The primary entry point is the
 * paired `<native:pager>` tag, whose children are the pages — for a feed,
 * the window slice the app's own loop renders (see Elements\Pager).
 */
class Pager extends NativeBladeComponent
{
    protected function elementType(): string
    {
        return 'pager';
    }
}
