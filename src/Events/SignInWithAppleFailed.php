<?php

namespace Native\Mobile\UI\Events;

use Illuminate\Foundation\Events\Dispatchable;

/**
 * Sent by `<native:sign-in-with-apple-button>` when the Apple ID request ends
 * without signing anyone in, including when the person closes Apple's sheet.
 */
class SignInWithAppleFailed
{
    use Dispatchable;

    /** The person closed Apple's sheet. */
    public const Canceled = 'canceled';

    /**
     * Apple's catch-all (error 1000). On a phone it usually means it isn't
     * signed in to an Apple Account, or the app lacks the Sign in with Apple
     * entitlement. Simulator builds always get it.
     */
    public const Unknown = 'unknown';

    public function __construct(
        /** canceled, failed, invalid_response, not_handled, not_interactive or unknown. */
        public string $code,
        public string $message = '',
        public ?string $state = null,
    ) {}
}
