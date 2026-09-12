<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

/**
 * Blade fallback for `<x-native-reel>`. The primary entry point is the
 * `<reel>` precompiler form: self-closing with `item` lowers to the
 * windowed open/iterate/close sequence, paired wraps inline pages.
 */
class Reel extends NativeBladeComponent
{
    protected function elementType(): string
    {
        return 'reel';
    }
}
