<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\Elements\Text;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\Edge\NativeTagPrecompiler;
use Native\Mobile\UI\Elements\Popover;

/**
 * `<native:popover>` floats its children in a bubble beside the spot it's
 * laid over while `visible` is true, and tells PHP on `on_dismiss` when the
 * person closes it, which both renderers fire.
 */
beforeEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
    ElementRegistry::register('popover', Popover::class);
    ElementRegistry::register('text', Text::class);
});

afterEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
});

function popoverTree(string $blade, array $vars = []): array
{
    $wasActive = NativeTagPrecompiler::setActive(true);

    try {
        $php = (new NativeTagPrecompiler)($blade);
    } finally {
        NativeTagPrecompiler::setActive($wasActive);
    }

    (function (array $vars) use ($php) {
        extract($vars);
        eval('?>'.$php);
    })($vars);

    $registry = new CallbackRegistry;

    return ['tree' => NativeElementCollector::collect()->toArray($registry), 'registry' => $registry];
}

it('wires visible, placement, its content and the dismiss handler from a Blade tag', function () {
    ['tree' => $tree, 'registry' => $registry] = popoverTree(
        '<native:popover :visible="$open" placement="bottom" @dismiss="closeReactions({{ $id }})"><native:text>😂</native:text></native:popover>',
        ['open' => true, 'id' => 7],
    );

    expect($tree['type'])->toBe('popover')
        ->and($tree['props']['visible'])->toBeTrue()
        ->and($tree['props']['placement'])->toBe('bottom')
        ->and($registry->resolve($tree['props']['on_dismiss']))->toBe(['method' => 'closeReactions', 'args' => [7]])
        ->and($tree['children'])->toHaveCount(1)
        ->and($tree['children'][0]['type'])->toBe('text');
});

it('leaves the side to the renderers when no placement is given', function () {
    ['tree' => $tree] = popoverTree('<native:popover :visible="$open"><native:text>hi</native:text></native:popover>', ['open' => false]);

    expect($tree['props']['visible'])->toBeFalse()
        ->and($tree['props'])->not->toHaveKey('placement');
});

it('refuses a side it cannot open on', function () {
    Popover::make()->placement('left');
})->throws(InvalidArgumentException::class);
