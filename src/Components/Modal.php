<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

class Modal extends NativeBladeComponent
{
    protected function elementType(): string
    {
        return 'modal';
    }
}
