<?php

namespace Nativephp\NativeUi\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

class Webview extends NativeBladeComponent
{
    protected bool $isSelfClosing = true;

    protected function elementType(): string
    {
        return 'webview';
    }
}
