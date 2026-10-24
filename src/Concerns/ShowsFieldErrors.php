<?php

namespace Native\Mobile\UI\Concerns;

use Native\Mobile\Edge\FieldErrors;

/**
 * Error state for form controls that have an `error` flag and a
 * `supporting` helper-text slot.
 *
 * An authored `error` attribute always wins. Otherwise, when the screen
 * validates with `ValidatesInput`, the first message for the field the
 * control binds (`error-for`, then `native:model`) turns the error state
 * on and replaces the supporting text.
 */
trait ShowsFieldErrors
{
    /** @param  array<string, mixed>  $attrs */
    protected function applyErrorAttributes(array $attrs): void
    {
        if (! empty($attrs['error']) || ! empty($attrs['isError']) || ! empty($attrs['is-error'])) {
            $this->error();

            return;
        }

        // FieldErrors ships with a later nativephp/mobile than this
        // package's minimum; without it there are no bound errors.
        if (! class_exists(FieldErrors::class)) {
            return;
        }

        $message = FieldErrors::for($attrs);

        if ($message !== null) {
            $this->error();
            $this->supporting($message);
        }
    }
}
