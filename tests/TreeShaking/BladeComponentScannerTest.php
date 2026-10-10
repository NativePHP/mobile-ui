<?php

use Native\Mobile\UI\TreeShaking\BladeComponentScanner;

it('detects namespace syntax components', function () {
    $scanner = new BladeComponentScanner();
    $blade = <<<'BLADE'
<native:button label="Save" />
<native:outlined-text-input label="Email" />
<native:column class="gap-4">
    <native:text>Hello</native:text>
</native:column>
BLADE;

    $result = $scanner->scan([tempFile($blade)]);

    expect($result['uncertain'])->toBeFalse()
        ->and($result['components'])->toContain('button')
        ->and($result['components'])->toContain('outlined_text_input')
        ->and($result['components'])->toContain('column')
        ->and($result['components'])->toContain('text');
});

it('detects x-component syntax', function () {
    $scanner = new BladeComponentScanner();
    $blade = '<x-native::button label="Click" />';

    $result = $scanner->scan([tempFile($blade)]);

    expect($result['uncertain'])->toBeFalse()
        ->and($result['components'])->toContain('button');
});

it('detects @component directive', function () {
    $scanner = new BladeComponentScanner();
    $blade = "@component('native:button', ['label' => 'Submit'])";

    $result = $scanner->scan([tempFile($blade)]);

    expect($result['uncertain'])->toBeFalse()
        ->and($result['components'])->toContain('button');
});

it('normalizes kebab-case to snake_case', function () {
    $scanner = new BladeComponentScanner();
    $blade = '<native:outlined-text-input /><native:bottom-sheet />';

    $result = $scanner->scan([tempFile($blade)]);

    expect($result['components'])->toContain('outlined_text_input')
        ->and($result['components'])->toContain('bottom_sheet');
});

it('marks uncertainty for dynamic component names', function () {
    $scanner = new BladeComponentScanner();
    $blade = '<native:{{ $componentType }} />';

    $result = $scanner->scan([tempFile($blade)]);

    expect($result['uncertain'])->toBeTrue();
});

it('marks uncertainty for x-dynamic-component', function () {
    $scanner = new BladeComponentScanner();
    $blade = '<x-dynamic-component :component="$type" />';

    $result = $scanner->scan([tempFile($blade)]);

    expect($result['uncertain'])->toBeTrue();
});

it('marks uncertainty for variable in @component', function () {
    $scanner = new BladeComponentScanner();
    $blade = '@component($componentName)';

    $result = $scanner->scan([tempFile($blade)]);

    expect($result['uncertain'])->toBeTrue();
});

it('handles multiple files', function () {
    $scanner = new BladeComponentScanner();

    $file1 = tempFile('<native:button />');
    $file2 = tempFile('<native:text />');
    $file3 = tempFile('<native:column />');

    $result = $scanner->scan([$file1, $file2, $file3]);

    expect($result['components'])->toHaveCount(3)
        ->and($result['components'])->toContain('button')
        ->and($result['components'])->toContain('text')
        ->and($result['components'])->toContain('column');
});

it('returns unique components', function () {
    $scanner = new BladeComponentScanner();
    $blade = <<<'BLADE'
<native:button label="Save" />
<native:button label="Cancel" />
<native:button label="Delete" />
BLADE;

    $result = $scanner->scan([tempFile($blade)]);

    expect($result['components'])->toHaveCount(1)
        ->and($result['components'])->toContain('button');
});

// Helper function to create temporary file
function tempFile(string $content): string
{
    $file = tempnam(sys_get_temp_dir(), 'blade_test_');
    file_put_contents($file, $content);
    register_shutdown_function(fn () => @unlink($file));

    return $file;
}
