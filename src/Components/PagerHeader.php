<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

class PagerHeader extends NativeBladeComponent
{
    protected bool $isSelfClosing = false;

    protected function elementType(): string
    {
        return 'pager_header';
    }
}
