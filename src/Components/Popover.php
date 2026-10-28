<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

class Popover extends NativeBladeComponent
{
    protected function elementType(): string
    {
        return 'popover';
    }
}
