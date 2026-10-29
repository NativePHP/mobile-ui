<?php

it('lays out a pressable without its menu items on iOS', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUISimpleRenderers.swift');
    $start = strpos($source, 'struct NativeUIPressableRenderer');
    $pressable = substr($source, $start, strpos($source, 'private func pressableMenuItem') - $start);

    expect($pressable)
        ->toContain('let content = node.children.filter { $0.type != "top_bar_action" }')
        ->not->toContain('NativeUIColumnRenderer(node: node)')
        ->and(substr_count($pressable, 'NativeUIColumnRenderer(node: node, children: content)'))->toBe(3);
});

it('lays out only the children it is given on iOS', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIColumnRenderer.swift');

    expect($source)
        ->toContain('let children = self.children ?? node.children')
        ->toContain('childNodes: children')
        ->toContain('ForEach(children) { child in');
});
