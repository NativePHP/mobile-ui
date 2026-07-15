<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

class BottomSheet extends NativeBladeComponent
{
    protected function elementType(): string
    {
        return 'bottom_sheet';
    }
}
