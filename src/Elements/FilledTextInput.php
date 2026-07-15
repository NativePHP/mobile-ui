<?php

namespace Native\Mobile\UI\Elements;

/**
 * Filled text input — renders as Material3 `TextField` (filled) on Android
 * and a fill-background SwiftUI `TextField` on iOS. Higher-emphasis alternative
 * to `OutlinedTextInput`.
 *
 * All API shape is defined in `BaseTextInput`.
 */
class FilledTextInput extends BaseTextInput
{
    protected string $type = 'filled_text_input';
}
