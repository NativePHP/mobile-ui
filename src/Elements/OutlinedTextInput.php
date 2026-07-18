<?php

namespace Native\Mobile\UI\Elements;

/**
 * Outlined text input — renders as Material3 `OutlinedTextField` on Android
 * and a bordered SwiftUI `TextField` on iOS. Default/most-common text input
 * style.
 *
 * All API shape is defined in `BaseTextInput`.
 */
class OutlinedTextInput extends BaseTextInput
{
    protected string $type = 'outlined_text_input';
}
