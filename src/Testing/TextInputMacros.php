<?php

namespace Native\Mobile\UI\Testing;

use Native\Mobile\Testing\TestableComponent;
use Native\Mobile\UI\Caret;
use PHPUnit\Framework\Assert;

/**
 * Text input test vocabulary, registered as TestableComponent macros:
 *
 *     Native::test(Composer::class)
 *         ->moveCaretTo('body', new Caret(y: 48, height: 24, line: 2));
 *
 * fires the field's `@caretChange` as a device would after the caret moved,
 * with the payload the renderers send.
 *
 * Registered by NativeUIServiceProvider under a test runner, on a core whose
 * TestableComponent is macroable.
 */
class TextInputMacros
{
    public static function register(): void
    {
        /**
         * Report the caret of the input `$target` (its ref, or the method or
         * model its callbacks name) as drawn at `$caret`. Fails when the
         * input registered no `@caretChange` in the last render.
         */
        TestableComponent::macro('moveCaretTo', function (string $target, Caret $caret) {
            /** @var TestableComponent $this */
            $this->startInteraction();

            $node = $this->nodeFor($target);
            $callbackId = $node['props']['on_caret_change'] ?? null;

            Assert::assertIsInt(
                $callbackId,
                "No @caretChange callback registered for [{$target}] in the last render."
            );

            return $this->dispatchUiEvent([
                'type' => TestableComponent::EVENT_TEXT_CHANGE,
                'callback_id' => $callbackId,
                'text' => $caret->toPayload(),
            ]);
        });
    }
}
