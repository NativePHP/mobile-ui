<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

class TabRow extends NativeBladeComponent
{
    protected function elementType(): string
    {
        return 'tab_row';
    }
}
