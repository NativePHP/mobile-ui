<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

class SheetPane extends NativeBladeComponent
{
    protected function elementType(): string
    {
        return 'sheet_pane';
    }
}
