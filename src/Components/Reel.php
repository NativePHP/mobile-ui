<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

/**
 * Blade fallback for `<x-native-reel>`. The primary entry point is the
 * paired `<native:reel>` tag, whose children are the pages — for a feed,
 * the window slice the app's own loop renders (see Elements\Reel).
 */
class Reel extends NativeBladeComponent
{
    protected function elementType(): string
    {
        return 'reel';
    }
}
