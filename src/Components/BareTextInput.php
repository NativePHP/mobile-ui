<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

class BareTextInput extends NativeBladeComponent
{
    protected function elementType(): string
    {
        return 'bare_text_input';
    }
}
