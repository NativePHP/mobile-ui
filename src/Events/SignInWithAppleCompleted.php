<?php

namespace Native\Mobile\UI\Events;

use Illuminate\Foundation\Events\Dispatchable;
use SensitiveParameter;

/**
 * Sent by `<native:sign-in-with-apple-button>` when Apple signs someone in.
 *
 * Apple only sends `email`, `givenName` and `familyName` the first time
 * someone signs in to your app, and only for the scopes you asked for. After
 * that you get the user id and the identity token, so store what you need.
 */
class SignInWithAppleCompleted
{
    use Dispatchable;

    public function __construct(
        public string $userId,
        #[SensitiveParameter] public ?string $identityToken = null,
        #[SensitiveParameter] public ?string $authorizationCode = null,
        public ?string $email = null,
        public ?string $givenName = null,
        public ?string $familyName = null,
        /** The raw nonce the button was given. Apple's token carries its SHA-256 hex. */
        #[SensitiveParameter] public ?string $nonce = null,
        public ?string $state = null,
        /** likely_real, unknown or unsupported. */
        public string $realUserStatus = 'unsupported',
    ) {}
}
