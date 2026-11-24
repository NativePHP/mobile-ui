<?php

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\ComponentMethodInvoker;
use Native\Mobile\Edge\ElementRegistry;
use Native\Mobile\Edge\NativeComponent;
use Native\Mobile\Edge\NativeTagPrecompiler;
use Native\Mobile\UI\Caret;
use Native\Mobile\UI\Elements\BareTextInput;
use Native\Mobile\UI\Elements\FilledTextInput;
use Native\Mobile\UI\Elements\OutlinedTextInput;
use Orchestra\Testbench\TestCase;

uses(TestCase::class);

function caretProps(string $inputClass, array $attrs): array
{
    $input = new $inputClass;
    $input->applyAttributes($attrs);

    return $input->getResolvedProps(new CallbackRegistry);
}

class CaretTestComponent extends NativeComponent
{
    public array $carets = [];

    public function caretMoved(string $field, Caret $caret): void
    {
        $this->carets[] = [$field, $caret];
    }

    public function rawCaret(string $payload): void
    {
        $this->carets[] = $payload;
    }
}

it('declares @caretChange to the precompiler', function () {
    ElementRegistry::register('bare_text_input', BareTextInput::class);

    expect(BareTextInput::elementEvents())->toBe(['caretChange'])
        ->and(NativeTagPrecompiler::customElementEvents())->toContain('caretChange');
});

it('serializes @caretChange as a plain callback', function (string $inputClass) {
    $props = caretProps($inputClass, ['multiline' => true, '_caretChange' => "caretMoved('body')"]);

    expect($props['on_caret_change'])->toBeInt()->not->toBe(0);
})->with([
    'outlined' => OutlinedTextInput::class,
    'filled' => FilledTextInput::class,
    'bare' => BareTextInput::class,
]);

it('is absent unless asked for', function () {
    expect(caretProps(BareTextInput::class, ['multiline' => true]))->not->toHaveKey('on_caret_change');
});

it('never reports the caret of a secure field', function () {
    expect(caretProps(BareTextInput::class, ['secure' => true, '_caretChange' => 'caretMoved']))
        ->not->toHaveKey('on_caret_change');
});

it('is settable fluently', function () {
    $props = BareTextInput::make()->multiline()->onCaretChange('caretMoved')->getResolvedProps(new CallbackRegistry);

    expect($props)->toHaveKey('on_caret_change');
});

it('decodes the payload the renderers send', function () {
    $caret = Caret::fromPayload('12.50,48.00,2.00,24.00,2,350.00,240.00');

    expect($caret->x)->toBe(12.5)
        ->and($caret->y)->toBe(48.0)
        ->and($caret->width)->toBe(2.0)
        ->and($caret->height)->toBe(24.0)
        ->and($caret->line)->toBe(2)
        ->and($caret->fieldWidth)->toBe(350.0)
        ->and($caret->fieldHeight)->toBe(240.0)
        ->and($caret->bottom())->toBe(72.0)
        ->and($caret->visible())->toBeTrue();
});

it('reads a short or malformed payload as zeros', function () {
    $caret = Caret::fromPayload('4,oops');

    expect($caret->x)->toBe(4.0)
        ->and($caret->y)->toBe(0.0)
        ->and($caret->line)->toBe(0);
});

it('knows when the field has scrolled the caret out of view', function () {
    expect((new Caret(y: -30, height: 24, fieldHeight: 200))->visible())->toBeFalse()
        ->and((new Caret(y: 210, height: 24, fieldHeight: 200))->visible())->toBeFalse()
        ->and((new Caret(y: 190, height: 24, fieldHeight: 200))->visible())->toBeTrue();
});

it('round-trips through its payload', function () {
    $caret = new Caret(x: 3.25, y: 72, width: 2, height: 24, line: 3, fieldWidth: 351.5, fieldHeight: 300);

    expect(Caret::fromPayload($caret->toPayload()))->toEqual($caret)
        ->and($caret->toPayload())->toBe('3.25,72,2,24,3,351.5,300');
});

it('hands a handler typed Caret the decoded caret, after its literal arguments', function () {
    $component = new CaretTestComponent;

    ComponentMethodInvoker::invoke($component, 'caretMoved', ['body', '0,48,2,24,2,350,240']);

    [$field, $caret] = $component->carets[0];

    expect($field)->toBe('body')
        ->and($caret)->toBeInstanceOf(Caret::class)
        ->and($caret->y)->toBe(48.0)
        ->and($caret->line)->toBe(2);
});

it('hands a handler typed string the raw payload', function () {
    $component = new CaretTestComponent;

    ComponentMethodInvoker::invoke($component, 'rawCaret', ['0,48,2,24,2,350,240']);

    expect($component->carets)->toBe(['0,48,2,24,2,350,240']);
});

it('measures the iOS caret from the text view, less its scrolling', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUITextInputCore.swift');

    expect($source)
        ->toContain('let caretEnabled  = onCaretCb != 0 && multiline && !secure')
        ->toContain('let rect = tv.caretRect(for: range.end)')
        ->toContain('Self.format(rect.minY - tv.contentOffset.y)')
        ->toContain('tv.observe(\.contentOffset')
        ->toContain('guard callbackId != 0, let tv = textView, tv.isFirstResponder');
});

it('measures the Android caret from the text layout, less the field\'s scrolling', function () {
    $shared = file_get_contents(dirname(__DIR__).'/resources/android/TextInputShared.kt');
    $bare = file_get_contents(dirname(__DIR__).'/resources/android/BareTextInputRenderer.kt');

    expect($shared)
        ->toContain('val active: Boolean get() = props.onCaretChangeCb != 0 && props.multiline && !props.secure')
        ->toContain('result.getCursorRect(end)')
        ->toContain('format((cursor.top - offset) / d)')
        ->toContain('offset = (offset - consumed.y).coerceIn(0f, maxOffset())')
        ->and($bare)
        ->toContain('onTextLayout = { result -> caretReporter.onLayout(result, value) }')
        ->toContain('.nestedScroll(caretReporter.scrollConnection)');
});
