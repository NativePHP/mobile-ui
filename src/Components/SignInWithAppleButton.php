<?php

namespace Native\Mobile\UI\Components;

use Native\Mobile\Edge\Components\Native\NativeBladeComponent;

/**
 * Not self-closing: children are an optional Android-only fallback, since
 * Apple has no button there. iOS always draws Apple's button and ignores them.
 */
class SignInWithAppleButton extends NativeBladeComponent
{
    protected function elementType(): string
    {
        return 'sign_in_with_apple_button';
    }
}
