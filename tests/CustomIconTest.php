<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\Elements\Icon as CoreIcon;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\Edge\NativeTagPrecompiler;
use Native\Mobile\Icon\AndroidSymbol;
use Native\Mobile\Platform;
use Native\Mobile\UI\Elements\Button;
use Native\Mobile\UI\Elements\Chip;
use Native\Mobile\UI\Elements\Icon;
use Native\Mobile\UI\Elements\ListItem;
use Native\Mobile\UI\Elements\OutlinedTextInput;
use Native\Mobile\UI\Elements\Tab;

/**
 * App icons from `resources/icons/<name>.svg` travel as the string
 * `custom:<name>` in every icon prop, and the renderers pick the asset
 * from the prefix. These check that nothing on the PHP side lowercases,
 * maps or drops that string on its way to the wire.
 */
enum CustomIconAndroid: string implements AndroidSymbol
{
    public function variant(): string
    {
        return 'outlined';
    }

    case Notifications = 'notifications';
}

beforeEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
    ElementRegistry::register('button', Button::class);
    ElementRegistry::register('chip', Chip::class);
    ElementRegistry::register('tab', Tab::class);
    ElementRegistry::register('list_item', ListItem::class);
    ElementRegistry::register('outlined_text_input', OutlinedTextInput::class);
});

afterEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
    Platform::set(null);
});

function compileNativeTag(string $blade): array
{
    $wasActive = NativeTagPrecompiler::setActive(true);

    try {
        $php = (new NativeTagPrecompiler)($blade);
    } finally {
        NativeTagPrecompiler::setActive($wasActive);
    }

    eval('?>'.$php);

    return NativeElementCollector::collect()->toArray(new CallbackRegistry)['props'];
}

it('keeps a custom name on a Blade <native:icon>', function (string $element, ?string $platform) {
    ElementRegistry::register('icon', $element);
    Platform::set($platform);

    $props = compileNativeTag('<native:icon name="custom:git-commit-vertical" size="20" />');

    expect($props['name'])->toBe('custom:git-commit-vertical')
        ->and($props['size'])->toBe(20.0)
        ->and($props)->not->toHaveKey('material_variant');
})->with([
    'core element' => CoreIcon::class,
    'plugin element' => Icon::class,
])->with(['ios', 'android', null]);

it('keeps a custom name on the Icon builder', function (string $element) {
    $props = $element::make('custom:git-commit-vertical')->toArray(new CallbackRegistry)['props'];

    expect($props['name'])->toBe('custom:git-commit-vertical');
})->with([
    'core element' => CoreIcon::class,
    'plugin element' => Icon::class,
]);

it('keeps custom names in both button icon slots from Blade', function () {
    Platform::set('ios');

    $props = compileNativeTag(
        '<native:button label="Commit" icon="custom:git-commit-vertical" icon-trailing="custom:arrow-up" />'
    );

    expect($props['leading_icon'])->toBe('custom:git-commit-vertical')
        ->and($props['trailing_icon'])->toBe('custom:arrow-up')
        ->and($props)->not->toHaveKey('leading_icon_variant');
});

it('lets a custom button icon sit beside a Material override', function (string $platform, string $icon, ?string $variant) {
    Platform::set($platform);

    $props = Button::make('Alerts')
        ->icon('custom:bell', android: CustomIconAndroid::Notifications)
        ->toArray(new CallbackRegistry)['props'];

    expect($props['leading_icon'])->toBe($icon)
        ->and($props['leading_icon_variant'] ?? null)->toBe($variant);
})->with([
    'ios draws the custom bell' => ['ios', 'custom:bell', null],
    'android draws the material glyph' => ['android', 'notifications', 'outlined'],
]);

it('keeps custom names in every list item icon slot', function () {
    Platform::set('android');

    $props = ListItem::make('Commits')
        ->leadingIcon('custom:git-commit-vertical')
        ->trailingIconButton('custom:git-branch')
        ->trailingActions([['method' => 'revert', 'label' => 'Revert', 'icon' => 'custom:undo']])
        ->trailingBadges([['icon' => 'custom:pin']])
        ->toArray(new CallbackRegistry)['props'];

    expect($props['leading_value'])->toBe('custom:git-commit-vertical')
        ->and($props['leading_icon'])->toBe('custom:git-commit-vertical')
        ->and($props['trailing_value'])->toBe('custom:git-branch')
        ->and(json_decode($props['trailing_actions_json'], true)[0]['icon'])->toBe('custom:undo')
        ->and(json_decode($props['trailing_badges_json'], true)[0]['icon'])->toBe('custom:pin');
});

it('keeps custom names on chip, tab and text input icons', function (string $type, array $attrs, string $prop) {
    Platform::set('ios');

    NativeElementCollector::leaf($type, $attrs);
    $props = NativeElementCollector::collect()->toArray(new CallbackRegistry)['props'];

    expect($props[$prop])->toBe('custom:git-commit-vertical');
})->with([
    'chip' => ['chip', ['label' => 'Commits', 'icon' => 'custom:git-commit-vertical'], 'icon'],
    'tab' => ['tab', ['label' => 'Commits', 'icon' => 'custom:git-commit-vertical'], 'icon'],
    'text input' => ['outlined_text_input', ['leading-icon' => 'custom:git-commit-vertical'], 'leading_icon'],
]);
