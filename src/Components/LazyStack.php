<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

class LazyStack extends NativeBladeComponent
{
    protected function elementType(): string
    {
        return 'lazy_stack';
    }
}
