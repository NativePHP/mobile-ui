<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

class AccordionContent extends NativeBladeComponent
{
    protected bool $isSelfClosing = false;

    protected function elementType(): string
    {
        return 'accordion_content';
    }
}
