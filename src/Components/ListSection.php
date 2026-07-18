<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

class ListSection extends NativeBladeComponent
{
    protected function elementType(): string
    {
        return 'list_section';
    }
}
