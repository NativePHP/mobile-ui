<?php

use Native\Mobile\JumpBridge;
use Nativephp\NativeUi\Theme;

/**
 * Font aliases: `config('native-ui.fonts')` maps semantic names to bundled
 * font tokens. The map rides the Theme.Set payload as `fonts` (where the
 * native resolvers consult it before file lookup), and the special `default`
 * alias becomes the app-wide default font by overriding the `font-family`
 * token in the same payload.
 */
beforeEach(function () {
    JumpBridge::instance()->mute();
    Theme::reset();
});

afterEach(function () {
    Theme::reset();
});

it('carries the alias map in the theme payload', function () {
    Theme::fonts(['accent' => 'accent']);
    Theme::load(['font-family' => 'System']);

    expect(Theme::all()['fonts'])->toBe(['accent' => 'accent']);
});

it('promotes the default alias to the font-family token', function () {
    Theme::fonts([
        'default' => 'Inter-Regular',
        'accent' => 'accent',
    ]);
    Theme::load(['font-family' => 'System']);

    expect(Theme::all()['font-family'])->toBe('Inter-Regular');
});

it('leaves font-family alone when no default alias exists', function () {
    Theme::fonts(['accent' => 'accent']);
    Theme::load(['font-family' => 'Lobster-Regular']);

    expect(Theme::all()['font-family'])->toBe('Lobster-Regular');
});

it('omits the fonts key entirely when no aliases are configured', function () {
    Theme::load(['font-family' => 'System']);

    expect(Theme::all())->not->toHaveKey('fonts');
});

it('clears aliases on reset', function () {
    Theme::fonts(['accent' => 'X']);
    Theme::reset();
    Theme::load(['font-family' => 'System']);

    expect(Theme::all())->not->toHaveKey('fonts');
});
