<?php

use Native\Mobile\UI\TreeShaking\PhpElementScanner;

it('detects Element class use statements', function () {
    $scanner = new PhpElementScanner();
    $php = <<<'PHP'
<?php
use Native\Mobile\UI\Elements\Button;
use Native\Mobile\UI\Elements\OutlinedTextInput;
use Native\Mobile\Edge\Elements\Column;

class MyComponent {
    public function render() {
        return Button::make('Save');
    }
}
PHP;

    $result = $scanner->scan([tempPhpFile($php)]);

    expect($result['uncertain'])->toBeFalse()
        ->and($result['components'])->toContain('button')
        ->and($result['components'])->toContain('outlined_text_input')
        ->and($result['components'])->toContain('column');
});

it('detects fully-qualified Element class calls', function () {
    $scanner = new PhpElementScanner();
    $php = <<<'PHP'
<?php
class MyComponent {
    public function render() {
        return Native\Mobile\UI\Elements\Button::make('Click')
            ->onPress('handleClick');
    }
}
PHP;

    $result = $scanner->scan([tempPhpFile($php)]);

    expect($result['uncertain'])->toBeFalse()
        ->and($result['components'])->toContain('button');
});

it('detects NativeElementCollector leaf calls', function () {
    $scanner = new PhpElementScanner();
    $php = <<<'PHP'
<?php
use Native\Mobile\Edge\NativeElementCollector;

NativeElementCollector::leaf('button', ['label' => 'Save']);
NativeElementCollector::open('column', ['fill' => true]);
NativeElementCollector::leaf('text', ['text' => 'Hello']);
NativeElementCollector::close();
PHP;

    $result = $scanner->scan([tempPhpFile($php)]);

    expect($result['uncertain'])->toBeFalse()
        ->and($result['components'])->toContain('button')
        ->and($result['components'])->toContain('column')
        ->and($result['components'])->toContain('text');
});

it('converts PascalCase to snake_case', function () {
    $scanner = new PhpElementScanner();
    $php = <<<'PHP'
<?php
use Native\Mobile\UI\Elements\OutlinedTextInput;
use Native\Mobile\UI\Elements\BottomSheet;
use Native\Mobile\UI\Elements\NativeList;

OutlinedTextInput::make();
BottomSheet::make();
NativeList::make();
PHP;

    $result = $scanner->scan([tempPhpFile($php)]);

    expect($result['components'])->toContain('outlined_text_input')
        ->and($result['components'])->toContain('bottom_sheet')
        ->and($result['components'])->toContain('native_list');
});

it('marks uncertainty for variable element types in collector', function () {
    $scanner = new PhpElementScanner();
    $php = <<<'PHP'
<?php
use Native\Mobile\Edge\NativeElementCollector;

$type = 'button';
NativeElementCollector::leaf($type, ['label' => 'Save']);
PHP;

    $result = $scanner->scan([tempPhpFile($php)]);

    expect($result['uncertain'])->toBeTrue();
});

it('marks uncertainty for dynamic instantiation', function () {
    $scanner = new PhpElementScanner();
    $php = <<<'PHP'
<?php
$className = 'Native\Mobile\UI\Elements\Button';
$element = new $className();
PHP;

    $result = $scanner->scan([tempPhpFile($php)]);

    expect($result['uncertain'])->toBeTrue();
});

it('marks uncertainty for app()->make() with variables', function () {
    $scanner = new PhpElementScanner();
    $php = <<<'PHP'
<?php
$element = app()->make($elementClass);
PHP;

    $result = $scanner->scan([tempPhpFile($php)]);

    expect($result['uncertain'])->toBeTrue();
});

it('handles multiple PHP files', function () {
    $scanner = new PhpElementScanner();

    $file1 = tempPhpFile('<?php use Native\Mobile\UI\Elements\Button;');
    $file2 = tempPhpFile('<?php use Native\Mobile\UI\Elements\Text;');
    $file3 = tempPhpFile('<?php NativeElementCollector::leaf("column", []);');

    $result = $scanner->scan([$file1, $file2, $file3]);

    expect($result['components'])->toHaveCount(3)
        ->and($result['components'])->toContain('button')
        ->and($result['components'])->toContain('text')
        ->and($result['components'])->toContain('column');
});

it('returns unique components', function () {
    $scanner = new PhpElementScanner();
    $php = <<<'PHP'
<?php
use Native\Mobile\UI\Elements\Button;
Button::make('Save');
Button::make('Cancel');
Button::make('Delete');
PHP;

    $result = $scanner->scan([tempPhpFile($php)]);

    expect($result['components'])->toHaveCount(1)
        ->and($result['components'])->toContain('button');
});

// Helper function
function tempPhpFile(string $content): string
{
    $file = tempnam(sys_get_temp_dir(), 'php_test_');
    file_put_contents($file, $content);
    register_shutdown_function(fn () => @unlink($file));

    return $file;
}
