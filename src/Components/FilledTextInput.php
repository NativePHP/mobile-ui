<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

class FilledTextInput extends NativeBladeComponent
{
    protected function elementType(): string
    {
        return 'filled_text_input';
    }
}