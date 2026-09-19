<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\UI\Elements\ListItem;
use Orchestra\Testbench\TestCase;

/**
 * `leadingAvatar` / `leadingImage` follow the same `src` rules as
 * `<native:image>`: a relative path means an asset in `public/`. On device the
 * native renderer resolves it; under Jump `public/` only exists on the dev
 * machine, so core's ImageSource rewrites it to a URL the phone can fetch.
 *
 * The only file in this suite that needs a booted app — the Jump branch calls
 * `asset()`, which needs a URL generator.
 */
uses(TestCase::class);

afterEach(function () {
    putenv('JUMP_BRIDGE_PORT');
});

function leadingValue(ListItem $item): string
{
    return $item->toArray(new CallbackRegistry)['props']['leading_value'];
}

it('leaves relative avatar and image paths for the renderer on device', function () {
    putenv('JUMP_BRIDGE_PORT');

    expect(leadingValue(ListItem::make()->leadingAvatar('img/ada.png')))->toBe('img/ada.png')
        ->and(leadingValue(ListItem::make()->leadingImage('img/cover.png')))->toBe('img/cover.png');
});

it('rewrites relative avatar and image paths to fetchable URLs under Jump', function () {
    putenv('JUMP_BRIDGE_PORT=3002');

    expect(leadingValue(ListItem::make()->leadingAvatar('img/ada.png')))->toBe(asset('img/ada.png'))
        ->and(leadingValue(ListItem::make()->leadingImage('img/cover.png')))->toBe(asset('img/cover.png'));
});

it('leaves device paths and remote URLs alone under Jump', function () {
    putenv('JUMP_BRIDGE_PORT=3002');

    $captured = '/var/mobile/Containers/Data/Application/x/tmp/photo.jpg';

    expect(leadingValue(ListItem::make()->leadingAvatar($captured)))->toBe($captured)
        ->and(leadingValue(ListItem::make()->leadingImage('https://example.com/cover.png')))
        ->toBe('https://example.com/cover.png');
});
