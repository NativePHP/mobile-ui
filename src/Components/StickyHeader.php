<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

class StickyHeader extends NativeBladeComponent
{
    protected function elementType(): string
    {
        return 'sticky_header';
    }
}
