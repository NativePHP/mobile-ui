<?php

use Illuminate\Support\MessageBag;
use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\FieldErrors;
use Native\Mobile\Edge\NativeElementCollector;
use Native\Mobile\UI\Elements\Checkbox;
use Native\Mobile\UI\Elements\DatePicker;
use Native\Mobile\UI\Elements\OutlinedTextInput;
use Native\Mobile\UI\Elements\RadioGroup;
use Native\Mobile\UI\Elements\Select;

beforeEach(function () {
    if (! class_exists(FieldErrors::class)) {
        $this->markTestSkipped('Needs a nativephp/mobile release with FieldErrors.');
    }

    NativeElementCollector::reset();
    ElementRegistry::register('outlined_text_input', OutlinedTextInput::class);
    ElementRegistry::register('checkbox', Checkbox::class);
    ElementRegistry::register('select', Select::class);
    ElementRegistry::register('date_picker', DatePicker::class);
    ElementRegistry::register('radio_group', RadioGroup::class);
});

afterEach(function () {
    NativeElementCollector::reset();
    ElementRegistry::reset();
});

/** Props of one control hydrated from Blade-style attrs while $bag is the screen's error bag. */
function propsWithErrors(string $type, array $attrs, ?MessageBag $bag): array
{
    $render = function () use ($type, $attrs) {
        NativeElementCollector::reset();
        NativeElementCollector::leaf($type, $attrs);

        return NativeElementCollector::collect()->toArray(new CallbackRegistry)['props'] ?? [];
    };

    return $bag === null ? $render() : FieldErrors::using($bag, $render);
}

/** What `native:model="email"` precompiles to. */
function boundTo(string $field): array
{
    return ['_change' => "__syncProperty('{$field}')", 'sync-mode' => 'live'];
}

it('shows the bound field’s first message on every form control', function (string $type) {
    $bag = new MessageBag([
        'email' => ['The email field is required.', 'Second message.'],
        'name' => ['Wrong field.'],
    ]);

    $props = propsWithErrors($type, [...boundTo('email'), 'supporting' => 'Helper'], $bag);

    expect($props['is_error'] ?? null)->toBeTrue()
        ->and($props['supporting'] ?? null)->toBe('The email field is required.');
})->with(['outlined_text_input', 'checkbox', 'select', 'date_picker', 'radio_group']);

it('binds by error-for when there is no native:model', function () {
    $props = propsWithErrors('outlined_text_input', ['error-for' => 'email'], new MessageBag(['email' => 'Bad.']));

    expect($props['is_error'] ?? null)->toBeTrue()
        ->and($props['supporting'] ?? null)->toBe('Bad.');
});

it('leaves a control alone when its field has no message', function () {
    $props = propsWithErrors('outlined_text_input', [...boundTo('name'), 'supporting' => 'Helper'], new MessageBag(['email' => 'Bad.']));

    expect($props)->not->toHaveKey('is_error')
        ->and($props['supporting'] ?? null)->toBe('Helper');
});

it('lets an authored error win over a bound message', function () {
    $props = propsWithErrors('checkbox', [...boundTo('email'), 'error' => true, 'supporting' => 'Authored'], new MessageBag(['email' => 'Bad.']));

    expect($props['is_error'] ?? null)->toBeTrue()
        ->and($props['supporting'] ?? null)->toBe('Authored');
});

it('shows nothing outside a validating screen', function () {
    $props = propsWithErrors('outlined_text_input', [...boundTo('email'), 'supporting' => 'Helper'], null);

    expect($props)->not->toHaveKey('is_error')
        ->and($props['supporting'] ?? null)->toBe('Helper');
});
