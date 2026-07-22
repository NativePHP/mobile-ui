<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

class OutlinedTextInput extends NativeBladeComponent
{
    protected function elementType(): string
    {
        return 'outlined_text_input';
    }
}
