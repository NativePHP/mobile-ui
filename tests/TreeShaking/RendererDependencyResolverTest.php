<?php

use Native\Mobile\UI\TreeShaking\RendererDependencyResolver;

it('detects iOS renderer dependencies from Swift source', function () {
    $swiftSource = <<<'SWIFT'
import SwiftUI

struct NativeUIButtonGroupRenderer: View {
    var body: some View {
        HStack {
            NativeUIButtonRenderer(node: buttonNode1)
            NativeUIButtonRenderer(node: buttonNode2)
        }
    }
}
SWIFT;

    $sourcePath = createTempRendererDir('ios', [
        'NativeUIButtonGroupRenderer.swift' => $swiftSource,
    ]);

    $resolver = new RendererDependencyResolver($sourcePath, 'ios');
    $deps = $resolver->getDependencies('NativeUIButtonGroupRenderer.swift');

    expect($deps)->toContain('NativeUIButtonRenderer.swift');
});

it('detects Android renderer dependencies from Kotlin source', function () {
    $kotlinSource = <<<'KOTLIN'
package com.nativephp.plugins.native_ui.ui

@Composable
fun ButtonGroupRenderer(node: NativeUINode) {
    Row {
        ButtonRenderer(node1)
        ButtonRenderer(node2)
    }
}
KOTLIN;

    $sourcePath = createTempRendererDir('android', [
        'ButtonGroupRenderer.kt' => $kotlinSource,
    ]);

    $resolver = new RendererDependencyResolver($sourcePath, 'android');
    $deps = $resolver->getDependencies('ButtonGroupRenderer.kt');

    expect($deps)->toContain('ButtonRenderer.kt');
});

it('detects EmptyRenderer usage in iOS', function () {
    $swiftSource = <<<'SWIFT'
struct NativeUIListItemRenderer: View {
    var body: some View {
        if let trailing = trailingNode {
            NativeUIEmptyRenderer(node: trailing)
        }
    }
}
SWIFT;

    $sourcePath = createTempRendererDir('ios', [
        'NativeUIListItemRenderer.swift' => $swiftSource,
    ]);

    $resolver = new RendererDependencyResolver($sourcePath, 'ios');
    $deps = $resolver->getDependencies('NativeUIListItemRenderer.swift');

    expect($deps)->toContain('NativeUIEmptyRenderer.swift');
});

it('detects Android import statements', function () {
    $kotlinSource = <<<'KOTLIN'
package com.nativephp.plugins.native_ui.ui

import com.nativephp.plugins.native_ui.ui.EmptyRenderer
import com.nativephp.plugins.native_ui.ui.IconRenderer

@Composable
fun ListItemRenderer(node: NativeUINode) {
    EmptyRenderer()
    IconRenderer()
}
KOTLIN;

    $sourcePath = createTempRendererDir('android', [
        'ListItemRenderer.kt' => $kotlinSource,
    ]);

    $resolver = new RendererDependencyResolver($sourcePath, 'android');
    $deps = $resolver->getDependencies('ListItemRenderer.kt');

    expect($deps)->toContain('EmptyRenderer.kt')
        ->and($deps)->toContain('IconRenderer.kt');
});

it('does not include self in dependencies', function () {
    $swiftSource = <<<'SWIFT'
struct NativeUIButtonRenderer: View {
    var body: some View {
        Button {
            // NativeUIButtonRenderer should not depend on itself
        }
    }
}
SWIFT;

    $sourcePath = createTempRendererDir('ios', [
        'NativeUIButtonRenderer.swift' => $swiftSource,
    ]);

    $resolver = new RendererDependencyResolver($sourcePath, 'ios');
    $deps = $resolver->getDependencies('NativeUIButtonRenderer.swift');

    expect($deps)->not->toContain('NativeUIButtonRenderer.swift');
});

it('returns empty array for files with no dependencies', function () {
    $swiftSource = <<<'SWIFT'
import SwiftUI

struct NativeUITextRenderer: View {
    var body: some View {
        Text(node.props.text)
    }
}
SWIFT;

    $sourcePath = createTempRendererDir('ios', [
        'NativeUITextRenderer.swift' => $swiftSource,
    ]);

    $resolver = new RendererDependencyResolver($sourcePath, 'ios');
    $deps = $resolver->getDependencies('NativeUITextRenderer.swift');

    expect($deps)->toBeEmpty();
});

it('caches results for repeated calls', function () {
    $swiftSource = 'struct NativeUIButtonRenderer: View {}';

    $sourcePath = createTempRendererDir('ios', [
        'NativeUIButtonRenderer.swift' => $swiftSource,
    ]);

    $resolver = new RendererDependencyResolver($sourcePath, 'ios');

    $deps1 = $resolver->getDependencies('NativeUIButtonRenderer.swift');
    $deps2 = $resolver->getDependencies('NativeUIButtonRenderer.swift');

    expect($deps1)->toBe($deps2);
});

it('returns unique dependencies', function () {
    $swiftSource = <<<'SWIFT'
struct NativeUIButtonGroupRenderer: View {
    NativeUIButtonRenderer(node1)
    NativeUIButtonRenderer(node2)
    NativeUIButtonRenderer(node3)
}
SWIFT;

    $sourcePath = createTempRendererDir('ios', [
        'NativeUIButtonGroupRenderer.swift' => $swiftSource,
    ]);

    $resolver = new RendererDependencyResolver($sourcePath, 'ios');
    $deps = $resolver->getDependencies('NativeUIButtonGroupRenderer.swift');

    $buttonCount = count(array_filter($deps, fn ($d) => $d === 'NativeUIButtonRenderer.swift'));

    expect($buttonCount)->toBe(1);
});

// Helper to create temporary renderer directory
function createTempRendererDir(string $platform, array $files): string
{
    $dir = sys_get_temp_dir().'/renderer_test_'.uniqid();
    mkdir($dir, 0755, true);

    foreach ($files as $filename => $content) {
        file_put_contents("{$dir}/{$filename}", $content);
    }

    register_shutdown_function(function () use ($dir) {
        $files = glob("{$dir}/*");
        foreach ($files as $file) {
            @unlink($file);
        }
        @rmdir($dir);
    });

    return $dir;
}
