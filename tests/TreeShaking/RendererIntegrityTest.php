<?php

use Native\Mobile\UI\TreeShaking\RendererDependencyResolver;

it('verifies all iOS renderer references are declared in manifest or shared files', function () {
    $manifestPath = dirname(__DIR__, 2).'/nativephp.json';
    $manifest = json_decode(file_get_contents($manifestPath), true);

    // Build list of all valid iOS renderer names
    $validRenderers = [];

    // From manifest
    foreach ($manifest['components'] ?? [] as $component) {
        if (isset($component['ios_renderer'])) {
            $validRenderers[] = $component['ios_renderer'].'.swift';
        }
    }

    // Shared files (always included)
    $sharedFiles = [
        'NativeUITheme.swift',
        'NativeUIFontResolver.swift',
        'NativeUIDrawerHost.swift',
        'NativeUIFloatingOverlayHost.swift',
        'NativeUIBackgroundLayerHost.swift',
        'NativeUITransitionFunctions.swift',
        'NativeUIFillWidthHelper.swift',
        'NativeUINavRenderers.swift',
        'NativeUITextInputCore.swift',
        'NativeUIButtonPreviews.swift',
    ];

    $validRenderers = array_merge($validRenderers, $sharedFiles);

    // Scan all iOS renderer files
    $iosPath = dirname(__DIR__, 2).'/resources/ios';
    $resolver = new RendererDependencyResolver($iosPath, 'ios');

    $allFiles = glob("{$iosPath}/*.swift");
    $undeclaredRefs = [];

    foreach ($allFiles as $file) {
        $filename = basename($file);
        $deps = $resolver->getDependencies($filename);

        foreach ($deps as $dep) {
            if (! in_array($dep, $validRenderers, true)) {
                $undeclaredRefs[] = "{$filename} references {$dep}";
            }
        }
    }

    expect($undeclaredRefs)->toBeEmpty(
        'Found undeclared renderer references: '.implode(', ', $undeclaredRefs)
    );
});

it('verifies all Android renderer references are declared in manifest or shared files', function () {
    $manifestPath = dirname(__DIR__, 2).'/nativephp.json';
    $manifest = json_decode(file_get_contents($manifestPath), true);

    // Build list of all valid Android renderer names
    $validRenderers = [];

    // From manifest
    foreach ($manifest['components'] ?? [] as $component) {
        if (isset($component['android_renderer'])) {
            $parts = explode('.', $component['android_renderer']);
            $className = end($parts);
            $validRenderers[] = $className.'.kt';
        }
    }

    // Shared files (always included)
    $sharedFiles = [
        'NativeUITheme.kt',
        'NativeUIFontResolver.kt',
        'NativeUIChromeInit.kt',
        'NativeLayoutDrawerHost.kt',
        'NativeFloatingOverlayHost.kt',
        'NativeUIBackgroundLayerHost.kt',
        'NativeUITransitionFunctions.kt',
        'TextInputShared.kt',
        'NativeUIImageSource.kt',
        'ContainerRenderers.kt',
        'SimpleRenderers.kt',
        'ImageRenderer.kt',
        'ButtonPreviews.kt',
    ];

    $validRenderers = array_merge($validRenderers, $sharedFiles);

    // Scan all Android renderer files
    $androidPath = dirname(__DIR__, 2).'/resources/android';
    $resolver = new RendererDependencyResolver($androidPath, 'android');

    $allFiles = glob("{$androidPath}/*.kt");
    $undeclaredRefs = [];

    foreach ($allFiles as $file) {
        $filename = basename($file);
        $deps = $resolver->getDependencies($filename);

        foreach ($deps as $dep) {
            if (! in_array($dep, $validRenderers, true)) {
                $undeclaredRefs[] = "{$filename} references {$dep}";
            }
        }
    }

    expect($undeclaredRefs)->toBeEmpty(
        'Found undeclared renderer references: '.implode(', ', $undeclaredRefs)
    );
});

it('verifies all manifest components have corresponding renderer files', function () {
    $manifestPath = dirname(__DIR__, 2).'/nativephp.json';
    $manifest = json_decode(file_get_contents($manifestPath), true);

    $missingFiles = [];

    foreach ($manifest['components'] ?? [] as $component) {
        // Check iOS
        if (isset($component['ios_renderer'])) {
            $file = dirname(__DIR__, 2)."/resources/ios/{$component['ios_renderer']}.swift";
            if (! file_exists($file)) {
                $missingFiles[] = "iOS: {$component['type']} -> {$component['ios_renderer']}.swift";
            }
        }

        // Check Android
        if (isset($component['android_renderer'])) {
            $parts = explode('.', $component['android_renderer']);
            $className = end($parts);
            $file = dirname(__DIR__, 2)."/resources/android/{$className}.kt";
            if (! file_exists($file)) {
                $missingFiles[] = "Android: {$component['type']} -> {$className}.kt";
            }
        }
    }

    expect($missingFiles)->toBeEmpty(
        'Manifest references missing renderer files: '.implode(', ', $missingFiles)
    );
});
