<?php

use Native\Mobile\Concerns\HasPlatformIcon;
use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Layouts\Builders\NavAction;
use Native\Mobile\Icon\AndroidSymbol;
use Native\Mobile\Icon\IosSymbol;
use Native\Mobile\Platform;

/**
 * Test fixtures defined inline so the trait tests don't depend on
 * `App\Icons\*` (which only exists after a developer has run
 * `php artisan native-ui:generate-icons`) or any other concrete catalog.
 * They implement the same marker interfaces that real generated enums
 * use, so the trait's `instanceof IosSymbol` / `instanceof AndroidSymbol`
 * checks behave identically.
 */
enum Ios: string implements IosSymbol
{
    case BellSlash = 'bell.slash';
    case SquareAndArrowUp = 'square.and.arrow.up';
    case Trash = 'trash';
}

enum Android: string implements AndroidSymbol
{
    public function variant(): string
    {
        return 'filled';
    }
    case Delete = 'delete';
    case NotificationsOff = 'notifications_off';
}

enum AndroidOutlined: string implements AndroidSymbol
{
    public function variant(): string
    {
        return 'outlined';
    }
    case Home = 'home';
    case NotificationsOff = 'notifications_off';
}

/**
 * A bare consumer of the trait so we can exercise resolution behavior
 * without coupling tests to a specific builder (NavAction etc.) — those
 * have their own additional state we don't care about here.
 */
class IconBag
{
    use HasPlatformIcon;
}

afterEach(function () {
    // Reset platform between tests so cross-pollination can't hide bugs.
    Platform::set(null);
});

it('resolves a shared name on both platforms', function () {
    $bag = (new IconBag)->icon('save');

    Platform::set('ios');
    expect($bag->resolvedIcon())->toBe('save');
    expect($bag->resolvedMaterialVariant())->toBeNull();

    Platform::set('android');
    expect($bag->resolvedIcon())->toBe('save');
    expect($bag->resolvedMaterialVariant())->toBeNull();
});

it('picks the iOS override on iOS and the Android override on Android', function () {
    $bag = (new IconBag)->icon(
        ios: Ios::BellSlash,
        android: Android::NotificationsOff,
    );

    Platform::set('ios');
    expect($bag->resolvedIcon())->toBe('bell.slash');

    Platform::set('android');
    expect($bag->resolvedIcon())->toBe('notifications_off');
    expect($bag->resolvedMaterialVariant())->toBe('filled');
});

it('falls back to the shared name when only one platform override is set', function () {
    $bag = (new IconBag)->icon('share', ios: Ios::SquareAndArrowUp);

    Platform::set('ios');
    expect($bag->resolvedIcon())->toBe('square.and.arrow.up');

    Platform::set('android');
    expect($bag->resolvedIcon())->toBe('share');
});

it('emits material_variant=outlined for AndroidOutlined overrides', function () {
    $bag = (new IconBag)->icon(android: AndroidOutlined::Home);

    Platform::set('android');
    expect($bag->resolvedIcon())->toBe('home');
    expect($bag->resolvedMaterialVariant())->toBe('outlined');

    Platform::set('ios');
    expect($bag->resolvedMaterialVariant())->toBeNull();
});

it('accepts raw strings as platform overrides for new symbols not yet in the enum', function () {
    $bag = (new IconBag)->icon(
        ios: 'newly.released.symbol',
        android: 'newly_released_symbol',
    );

    Platform::set('ios');
    expect($bag->resolvedIcon())->toBe('newly.released.symbol');
    expect($bag->resolvedMaterialVariant())->toBeNull();

    Platform::set('android');
    expect($bag->resolvedIcon())->toBe('newly_released_symbol');
    expect($bag->resolvedMaterialVariant())->toBeNull();
});

it('returns null when no slot is set', function () {
    $bag = new IconBag;

    Platform::set('ios');
    expect($bag->resolvedIcon())->toBeNull();
    expect($bag->resolvedMaterialVariant())->toBeNull();

    Platform::set('android');
    expect($bag->resolvedIcon())->toBeNull();
    expect($bag->resolvedMaterialVariant())->toBeNull();
});

it('falls back to the shared name when platform is unknown (test / web preview)', function () {
    Platform::set(null);
    $bag = (new IconBag)->icon('save', ios: Ios::BellSlash);

    // No platform → no override applies → shared name is the safe default.
    expect($bag->resolvedIcon())->toBe('save');
    expect($bag->resolvedMaterialVariant())->toBeNull();
});

it('overrides earlier values when icon() is called multiple times', function () {
    $bag = (new IconBag)
        ->icon('save')
        ->icon(ios: Ios::Trash)
        ->icon('delete', android: Android::Delete);

    Platform::set('ios');
    expect($bag->resolvedIcon())->toBe('trash');

    Platform::set('android');
    expect($bag->resolvedIcon())->toBe('delete');
});

// ── NavAction integration ──────────────────────────────

it('NavAction emits the iOS-resolved icon and no material_variant on iOS', function () {
    Platform::set('ios');

    $element = NavAction::make('mute')
        ->icon(ios: Ios::BellSlash, android: Android::NotificationsOff)
        ->toElement();

    $props = $element->getResolvedProps(new CallbackRegistry);
    expect($props['icon'] ?? null)->toBe('bell.slash');
    expect($props['material_variant'] ?? null)->toBeNull();
});

it('NavAction emits the Android-resolved icon and material_variant on Android', function () {
    Platform::set('android');

    $element = NavAction::make('mute')
        ->icon(ios: Ios::BellSlash, android: AndroidOutlined::NotificationsOff)
        ->toElement();

    $props = $element->getResolvedProps(new CallbackRegistry);
    expect($props['icon'] ?? null)->toBe('notifications_off');
    expect($props['material_variant'] ?? null)->toBe('outlined');
});

it('NavAction with a shared name only emits no material_variant', function () {
    Platform::set('android');

    $element = NavAction::make('save')
        ->icon('save')
        ->toElement();

    $props = $element->getResolvedProps(new CallbackRegistry);
    expect($props['icon'] ?? null)->toBe('save');
    expect($props['material_variant'] ?? null)->toBeNull();
});
