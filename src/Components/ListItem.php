<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

class ListItem extends NativeBladeComponent
{
    protected bool $isSelfClosing = true;

    protected function elementType(): string
    {
        return 'list_item';
    }
}
