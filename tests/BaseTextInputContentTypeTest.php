<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\UI\Elements\BareTextInput;
use Native\Mobile\UI\Elements\FilledTextInput;
use Native\Mobile\UI\Elements\OutlinedTextInput;

// ── content-type (NativePHP/mobile-air#422) ──────────────────────────────────

function contentTypeProps(string $inputClass, array $attrs): array
{
    $input = new $inputClass;
    $input->applyAttributes($attrs);

    return $input->getResolvedProps(new CallbackRegistry);
}

it('omits content_type entirely when the author did not set one', function (string $inputClass) {
    // Absent means "declare nothing" on both platforms — neither resolver may
    // see an empty string as a choice, and a secure field must not have one
    // inferred for it.
    $props = contentTypeProps($inputClass, ['keyboard' => 'email', 'secure' => true]);

    expect($props)->not->toHaveKey('content_type');
})->with([
    'outlined' => OutlinedTextInput::class,
    'filled' => FilledTextInput::class,
    'bare' => BareTextInput::class,
]);

it('resolves content-type from every attribute spelling', function (string $inputClass, string $attribute) {
    expect(contentTypeProps($inputClass, [$attribute => 'username'])['content_type'])->toBe('username');
})->with([
    'outlined' => OutlinedTextInput::class,
    'filled' => FilledTextInput::class,
    'bare' => BareTextInput::class,
])->with([
    'content-type',
    'contentType',
    'autocomplete',
]);

it('passes each supported type through unchanged', function (string $type) {
    expect(contentTypeProps(OutlinedTextInput::class, ['content-type' => $type])['content_type'])->toBe($type);
})->with(['username', 'email', 'password', 'new-password', 'one-time-code']);

it('normalizes case and spelling to the kebab-case form the natives match on', function (string $given, string $expected) {
    expect(OutlinedTextInput::make()->contentType($given)->getResolvedProps(new CallbackRegistry)['content_type'])
        ->toBe($expected);
})->with([
    ['newPassword', 'new-password'],
    ['new_password', 'new-password'],
    ['NEW-PASSWORD', 'new-password'],
    ['oneTimeCode', 'one-time-code'],
    ['  Username ', 'username'],
]);

it('accepts the HTML aliases for the same types', function (string $given, string $expected) {
    expect(contentTypeProps(OutlinedTextInput::class, ['autocomplete' => $given])['content_type'])->toBe($expected);
})->with([
    ['current-password', 'password'],
    ['email-address', 'email'],
]);

it('ignores an empty attribute rather than declaring it', function () {
    // `content-type="{{ $type }}"` renders an empty string when $type is null.
    expect(contentTypeProps(OutlinedTextInput::class, ['content-type' => '']))->not->toHaveKey('content_type')
        ->and(contentTypeProps(OutlinedTextInput::class, ['content-type' => '  ']))->not->toHaveKey('content_type');
});

it('passes an unknown type through for the natives to ignore', function () {
    // Same policy as `keyboard` / `autocapitalize`: the element does not
    // gatekeep the vocabulary, both native resolvers fall back to nothing.
    expect(contentTypeProps(OutlinedTextInput::class, ['content-type' => 'street-address'])['content_type'])
        ->toBe('street-address');
});

it('sits alongside keyboard and secure without disturbing them', function () {
    $props = OutlinedTextInput::make()
        ->keyboard('email')
        ->contentType('username')
        ->getResolvedProps(new CallbackRegistry);

    expect($props['keyboard'])->toBe('email')
        ->and($props['content_type'])->toBe('username');

    $secure = OutlinedTextInput::make()
        ->secure()
        ->contentType('password')
        ->getResolvedProps(new CallbackRegistry);

    expect($secure['secure'])->toBeTrue()
        ->and($secure['content_type'])->toBe('password');
});
