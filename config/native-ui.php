<?php

/**
 * Native UI — Theme Tokens
 *
 * Published via `php artisan vendor:publish --tag=native-ui-config`.
 * Edit to customize your app's visual identity in one place.
 *
 * For dynamic per-tenant theming, use Native\Mobile\UI\Theme::merge([...])
 * from a service provider. Runtime merges deep-merge on top of these values.
 *
 * Decision log: /docs/NATIVE-UI-REWRITE-PLAN.md (D — theme layer)
 */

return [

    /*
    |---------------------------------------------------------------------------
    | Theme
    |---------------------------------------------------------------------------
    |
    | 17 color tokens, 4 radii, 4 font sizes, font family.
    |
    | "on-X" means "color of content placed ON a surface of color X"
    |   — i.e., text/icons on that background.
    |
    | Color tokens accept:
    |   - CSS hex: '#B91C1C', '#F00', or with alpha '#8B5CF680' (#RRGGBBAA)
    |   - Tailwind palette names: 'red-300', 'orange-800'
    |   - Opacity modifiers on either: 'red-300/20', '#8B5CF6/50'
    |
    | Dark mode is auto-derived from `light` when `dark` is not set. To opt
    | into explicit dark tokens, fill out the `dark` block.
    |
    | The default pairs meet WCAG AA (4.5:1) — if you customize, keep each
    | `on-*` color at 4.5:1 contrast against its background token.
    |
    */

    'theme' => [

        'light' => [
            // Primary brand color — used for filled buttons, active states, key accents.
            'primary'       => '#0F766E',
            'on-primary'    => '#FFFFFF',

            // Secondary / muted action color.
            'secondary'     => '#475569',
            'on-secondary'  => '#FFFFFF',

            // Surface = cards, sheets, dialogs. Background = page root.
            'surface'       => '#FFFFFF',
            'on-surface'    => '#0F172A',
            'background'    => '#F8FAFC',
            'on-background' => '#0F172A',

            // Surface variant = filled text fields, muted tonal surfaces.
            // on-surface-variant = muted label/hint text on those surfaces.
            'surface-variant'    => '#F1F5F9',
            'on-surface-variant' => '#475569',

            // Outline = neutral borders (text fields, dividers, cards).
            'outline'       => '#CBD5E1',

            // Destructive actions — maps to `variant="destructive"` on components.
            'destructive'    => '#B91C1C',
            'on-destructive' => '#FFFFFF',

            // Tertiary accent — for highlights, badges, emphasis not covered by primary.
            'accent'        => '#C2410C',
            'on-accent'     => '#FFFFFF',
        ],

        'dark' => [
            // Leave empty or partial to auto-derive from `light` (luminance inversion).
            // Specify any token here to override the derived value.
            'primary'       => '#14B8A6',
            'on-primary'    => '#FFFFFF',

            'secondary'     => '#94A3B8',
            'on-secondary'  => '#0F172A',

            'surface'       => '#1E293B',
            'on-surface'    => '#F8FAFC',
            'background'    => '#0F172A',
            'on-background' => '#F8FAFC',

            'surface-variant'    => '#334155',
            'on-surface-variant' => '#94A3B8',

            'outline'       => '#475569',

            'destructive'    => '#F87171',
            'on-destructive' => '#0F172A',

            'accent'        => '#FDBA74',
            'on-accent'     => '#0F172A',
        ],

        // Corner radii (points / dp).
        'radius-sm'   => 4,
        'radius-md'   => 8,
        'radius-lg'   => 16,
        'radius-full' => 9999,

        // Font size scale (points / sp).
        'font-sm' => 14,
        'font-md' => 16,
        'font-lg' => 20,
        'font-xl' => 24,

        // 'System' resolves to the platform default (San Francisco on iOS, Roboto on Android).
        // Set a bundled font token to apply it app-wide — a file from your app's
        // resources/fonts/ minus the extension (e.g. 'Inter-Regular'). Download one
        // with `php artisan native:font Inter`. Per-element `font` attributes and
        // font-serif / font-mono classes still win over this default.
        'font-family' => 'System',
    ],

];