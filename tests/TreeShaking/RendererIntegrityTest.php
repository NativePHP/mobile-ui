<?php

use Native\Mobile\UI\TreeShaking\RendererDependencyResolver;
use Native\Mobile\UI\TreeShaking\RendererMapper;

function treeShakingManifest(): array
{
    return json_decode(file_get_contents(dirname(__DIR__, 2).'/nativephp.json'), true);
}

function rendererClassIndex(string $platform): array
{
    $ext = $platform === 'ios' ? 'swift' : 'kt';
    $dir = dirname(__DIR__, 2)."/resources/{$platform}";
    $index = [];

    foreach (glob("{$dir}/*.{$ext}") ?: [] as $path) {
        $content = (string) file_get_contents($path);
        if (preg_match_all(
            '/\b(?:struct|enum|class|protocol|extension|object|fun)\s+([A-Z][a-zA-Z]+Renderer)\b/',
            $content,
            $matches
        )) {
            foreach ($matches[1] as $className) {
                $index[$className] ??= basename($path);
            }
        }
    }

    return $index;
}

it('verifies all iOS renderer references are defined in a source file', function () {
    $iosPath = dirname(__DIR__, 2).'/resources/ios';
    $index = rendererClassIndex('ios');
    $resolver = new RendererDependencyResolver($iosPath, 'ios');
    $undeclaredRefs = [];

    foreach (glob("{$iosPath}/*.swift") ?: [] as $file) {
        $filename = basename($file);
        foreach ($resolver->getDependencies($filename) as $dep) {
            $className = pathinfo($dep, PATHINFO_FILENAME);
            if (! isset($index[$className]) && ! is_file("{$iosPath}/{$dep}")) {
                $undeclaredRefs[] = "{$filename} references {$dep}";
            }
        }
    }

    expect($undeclaredRefs)->toBeEmpty(
        'Found undeclared renderer references: '.implode(', ', $undeclaredRefs)
    );
});

it('verifies all Android renderer references are defined in a source file', function () {
    $androidPath = dirname(__DIR__, 2).'/resources/android';
    $index = rendererClassIndex('android');
    $resolver = new RendererDependencyResolver($androidPath, 'android');
    $undeclaredRefs = [];

    foreach (glob("{$androidPath}/*.kt") ?: [] as $file) {
        $filename = basename($file);
        foreach ($resolver->getDependencies($filename) as $dep) {
            $className = pathinfo($dep, PATHINFO_FILENAME);
            if (! isset($index[$className]) && ! is_file("{$androidPath}/{$dep}")) {
                $undeclaredRefs[] = "{$filename} references {$dep}";
            }
        }
    }

    expect($undeclaredRefs)->toBeEmpty(
        'Found undeclared renderer references: '.implode(', ', $undeclaredRefs)
    );
});

it('verifies all manifest components resolve to an existing renderer file', function () {
    $mapper = new RendererMapper(dirname(__DIR__, 2).'/nativephp.json');
    $missingFiles = [];

    foreach (treeShakingManifest()['components'] ?? [] as $component) {
        $type = $component['type'];
        foreach (['ios', 'android'] as $platform) {
            $files = $mapper->getFilesToCopy([$type], $platform);
            $ext = $platform === 'ios' ? 'swift' : 'kt';
            $dir = dirname(__DIR__, 2)."/resources/{$platform}";
            $existing = array_filter($files, fn ($file) => is_file("{$dir}/{$file}"));

            expect($existing)->not->toBeEmpty("No existing {$platform} files for component {$type}");

            foreach ($existing as $file) {
                if (! str_ends_with($file, ".{$ext}")) {
                    $missingFiles[] = "{$platform}: {$type} -> {$file}";
                }
            }
        }
    }

    expect($missingFiles)->toBeEmpty(
        'Manifest resolved to unexpected renderer files: '.implode(', ', $missingFiles)
    );
});

it('fails when a renderer references another renderer that is not defined anywhere', function () {
    $dir = sys_get_temp_dir().'/integrity_break_'.uniqid();
    mkdir($dir, 0755, true);
    file_put_contents("{$dir}/NativeUIRadioGroupRenderer.swift", <<<'SWIFT'
struct NativeUIRadioGroupRenderer: View {
    var body: some View {
        NativeUIRadioRenderer(node: child)
    }
}
SWIFT);

    $resolver = new RendererDependencyResolver($dir, 'ios');
    $deps = $resolver->getDependencies('NativeUIRadioGroupRenderer.swift');

    expect($deps)->toContain('NativeUIRadioRenderer.swift');

    $defined = [];
    foreach (glob("{$dir}/*.swift") ?: [] as $path) {
        $content = (string) file_get_contents($path);
        if (preg_match_all('/\b(?:struct|enum|class)\s+(NativeUI[A-Z][a-zA-Z]+Renderer)\b/', $content, $matches)) {
            foreach ($matches[1] as $className) {
                $defined[$className] = true;
            }
        }
    }

    $undeclared = [];
    foreach ($deps as $dep) {
        $className = pathinfo($dep, PATHINFO_FILENAME);
        if (! isset($defined[$className])) {
            $undeclared[] = "NativeUIRadioGroupRenderer.swift references {$dep}";
        }
    }

    expect($undeclared)->not->toBeEmpty();

    foreach (glob("{$dir}/*") ?: [] as $file) {
        @unlink($file);
    }
    @rmdir($dir);
});
