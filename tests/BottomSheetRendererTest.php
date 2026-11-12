<?php

test('leaves the iOS grabber to the system, so only a resizable sheet shows one', function () {
    $renderer = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIBottomSheetRenderer.swift');

    expect($renderer)
        ->toBeString()
        ->toMatch('/\.presentationDragIndicator\(\.automatic\)/')
        ->not->toContain('.presentationDragIndicator(.visible)');
});

test('keeps the Android bottom sheet composed until hiding it has slid it away', function () {
    $rendererPath = dirname(__DIR__).'/resources/android/BottomSheetRenderer.kt';

    expect($rendererPath)->toBeFile();

    $renderer = file_get_contents($rendererPath);

    expect($renderer)
        ->toBeString()
        ->not->toMatch('/if \(!visible\) return/')
        ->toMatch('/LaunchedEffect\(visible\) \{.*?sheetState\.hide\(\)\s*shown = false/s')
        ->toMatch('/if \(!shown\) return/');
});

test('wraps an Android fit sheet around its content, opened in full', function () {
    $renderer = file_get_contents(dirname(__DIR__).'/resources/android/BottomSheetRenderer.kt');

    expect($renderer)
        ->toBeString()
        ->toMatch('/val skipPartial = fits \|\| !hasPartialDetent\(detentsStr\)/')
        ->toMatch('/Column\(modifier = if \(fits\) sheetModifier else sheetModifier\.fillMaxHeight\(\)\)/')
        ->toMatch('/private fun hasDetent\(str: String, detent: String\): Boolean/');
});

test('sizes an iOS fit sheet to the height its content measures', function () {
    $renderer = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIBottomSheetRenderer.swift');

    expect($renderer)
        ->toBeString()
        ->toMatch('/case "fit":\s*detents\.insert\(fitDetent\)/')
        ->toMatch('/height\.map \{ \.height\(\$0\) \}/')
        ->toMatch('/\.fixedSize\(horizontal: false, vertical: fits\)\s*'
            .'\.onGeometryChange\(for: CGFloat\.self\) \{ \$0\.size\.height \} action: \{ height in\s*'
            .'contentHeight = height\s*'
            .'if fits, height > 0 \{ fitHeight = height \+ barHeight \}/s');
});

test('puts a titled iOS sheet in a navigation stack with its title inline', function () {
    $renderer = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIBottomSheetRenderer.swift');

    expect($renderer)
        ->toBeString()
        ->toMatch('/let title = node\.props\.getString\("title"\)/')
        ->toMatch('/\.background\(theme\.surface\)\s*\.modifier\(SheetTitleBar\(\s*title: title,/s')
        ->toMatch('/if title\.isEmpty \{\s*content\s*\} else \{\s*NavigationStack \{\s*content/s')
        ->toMatch('/\.navigationTitle\(title\)\s*\.navigationBarTitleDisplayMode\(\.inline\)/s');
});

test('closes a titled iOS sheet with the system close button, as the user\'s dismissal', function () {
    $renderer = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIBottomSheetRenderer.swift');

    expect($renderer)
        ->toBeString()
        ->toMatch('/closable: !permanent,/')
        ->toMatch('/close: \{ isPresented = false \},/')
        ->toMatch('/if closable \{\s*ToolbarItem\(placement: \.cancellationAction\) \{ closeButton \}/s')
        ->toMatch('/if #available\(iOS 26\.0, \*\) \{\s*Button\(role: \.close, action: close\)\s*'
            .'\.modifier\(A11yLabelModifier\(label: closeLabel\)\)/s')
        ->toMatch('/Image\(systemName: "xmark\.circle\.fill"\)/');
});

test('makes a titled iOS fit sheet as tall as its content and its bar', function () {
    $renderer = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIBottomSheetRenderer.swift');

    expect($renderer)
        ->toBeString()
        ->toMatch('/@State private var barHeight: CGFloat = 0/')
        ->toMatch('/measured: \{ height in\s*barHeight = height\s*'
            .'if fits, contentHeight > 0 \{ fitHeight = contentHeight \+ height \}/s')
        ->toMatch('/\.onGeometryChange\(for: CGFloat\.self\) \{ \$0\.safeAreaInsets\.top \} action: \{ measured\(\$0\) \}/');
});

test('shows a titled Android sheet\'s title as heading text above its content', function () {
    $renderer = file_get_contents(dirname(__DIR__).'/resources/android/BottomSheetRenderer.kt');

    expect($renderer)
        ->toBeString()
        ->toMatch('/val title = p\.getString\("title"\)/')
        ->toMatch('/if \(title\.isNotEmpty\(\)\) \{\s*SheetHeading\(title = title, color = theme\.onSurface\)\s*\}\s*'
            .'node\.children\.forEach \{ RenderNode\(it\) \}/s')
        ->toMatch('/private fun SheetHeading\(title: String, color: Color\) \{.*?'
            .'style = MaterialTheme\.typography\.titleLarge/s');
});

test('keeps an iOS fit sheet on its fit detent when the content height changes', function () {
    $renderer = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIBottomSheetRenderer.swift');

    expect($renderer)
        ->toBeString()
        ->toMatch('/\.presentationDetents\(detents, selection: selection\)/')
        ->toMatch('/\.onChange\(of: fitHeight\) \{ old, _ in\s*'
            .'if selectedDetent == Self\.fitDetent\(for: old\) \{ selectedDetent = fitDetent \}/s');
});

test('reports only the user\'s dismissals of an iOS sheet to PHP', function () {
    $renderer = file_get_contents(dirname(__DIR__).'/resources/ios/NativeUIBottomSheetRenderer.swift');

    expect($renderer)
        ->toBeString()
        ->toMatch('/@State private var closedByPhp: Bool = false/')
        ->toMatch('/private func present\(_ visible: Bool\) \{.*?if !visible && isPresented \{ closedByPhp = true \}\s*isPresented = visible/s')
        ->toMatch('/\.sheet\(isPresented: \$isPresented, onDismiss: \{\s*(?:\/\/[^\n]*\n\s*)*if closedByPhp \{\s*closedByPhp = false\s*return\s*\}\s*if onDismissCb != 0 \{/')
        ->toMatch('/\.onAppear \{\s*NativeUIKeyboardAccessoryState\.shared\.sheetDepth \+= 1\s*(?:\/\/[^\n]*\n\s*)*closedByPhp = false\s*\}/');
});
