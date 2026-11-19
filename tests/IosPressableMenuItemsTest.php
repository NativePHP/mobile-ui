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

it('gives a menu pressable its accessibility label and hint on iOS', function () {
    $source = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUISimpleRenderers.swift');
    $start = strpos($source, 'struct NativeUIPressableRenderer');
    $pressable = substr($source, $start, strpos($source, 'private struct PressableMenuAccessibility') - $start);
    $modifier = substr($source, strpos($source, 'private struct PressableMenuAccessibility'), strpos($source, 'private func pressableMenuItem') - strpos($source, 'private struct PressableMenuAccessibility'));

    expect($pressable)
        ->toContain('.modifier(PressableMenuAccessibility(')
        ->toContain('label: node.props.getString("a11y_label")')
        ->toContain('hint: node.props.getString("a11y_hint")')
        ->and($modifier)
        ->toContain('case (true, true):')
        ->toContain('content.accessibilityLabel(Text(label))')
        ->toContain('content.accessibilityHint(Text(hint))');
});
