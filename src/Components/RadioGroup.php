<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

class RadioGroup extends NativeBladeComponent
{
    protected function elementType(): string
    {
        return 'radio_group';
    }
}
