<?php

use Illuminate\Config\Repository;
use Illuminate\Container\Container;
use Native\Mobile\JumpBridge;
use Native\Mobile\UI\Theme;

beforeEach(function () {
    // Keep Theme::pushToNative() off the wire: plain Pest has no Laravel
    // app, so Theme's runningUnitTests guard can't trip, and an un-muted
    // JumpBridge would open a TCP connection to a live Jump session.
    JumpBridge::instance()->mute();
    Theme::reset();
});

afterEach(function () {
    Theme::reset();
});

describe('Theme color token normalization', function () {
    it('resolves tailwind palette names', function () {
        Theme::load(['light' => ['primary' => 'red-300', 'accent' => 'orange-800']]);

        expect(Theme::get('light.primary'))->toBe('#FCA5A5');
        expect(Theme::get('light.accent'))->toBe('#9A3412');
    });

    it('resolves opacity modifiers on names and hex', function () {
        Theme::load(['light' => [
            'primary' => 'red-300/20',
            'accent' => '#8B5CF6/50',
        ]]);

        expect(Theme::get('light.primary'))->toBe('#33FCA5A5');
        expect(Theme::get('light.accent'))->toBe('#808B5CF6');
    });

    it('converts CSS alpha hex (#RRGGBBAA) to wire ARGB order', function () {
        Theme::load(['light' => ['primary' => '#8B5CF680']]);

        expect(Theme::get('light.primary'))->toBe('#808B5CF6');
    });

    it('passes plain hex and unrecognized strings through untouched', function () {
        Theme::load(['light' => [
            'primary' => '#B91C1C',
            'accent' => 'not-a-color',
        ]]);

        expect(Theme::get('light.primary'))->toBe('#B91C1C');
        expect(Theme::get('light.accent'))->toBe('not-a-color');
    });

    it('normalizes tokens supplied via merge()', function () {
        Theme::load(['light' => ['primary' => '#B91C1C']]);
        Theme::merge(['light' => ['accent' => 'orange-800/50']]);

        expect(Theme::get('light.primary'))->toBe('#B91C1C');
        expect(Theme::get('light.accent'))->toBe('#809A3412');
    });

    it('normalizes explicit dark tokens', function () {
        Theme::load([
            'light' => ['primary' => 'red-300'],
            'dark' => ['primary' => 'red-800'],
        ]);

        expect(Theme::get('dark.primary'))->toBe('#991B1B');
    });

    it('auto-derives dark tokens from normalized palette names', function () {
        Theme::load(['light' => ['primary' => 'red-300']]);

        $dark = Theme::get('dark.primary');

        expect($dark)->toMatch('/^#[0-9A-F]{6}$/');
        expect($dark)->not->toBe('#FCA5A5');
    });

    it('preserves the alpha byte when auto-deriving dark tokens', function () {
        Theme::load(['light' => ['primary' => '#8B5CF680']]);

        // Wire format is #AARRGGBB — derived dark keeps the authored alpha.
        expect(Theme::get('dark.primary'))->toMatch('/^#80[0-9A-F]{6}$/');
    });
});

describe('Theme config write-back', function () {
    // Core's theme() helper reads config('native-ui.theme.…') directly, so
    // load()/merge() must mirror the normalized tokens back into the config
    // repository — otherwise chrome setters like ->color(theme('primary'))
    // receive raw authored strings ('red-500') the native side can't parse.
    it('mirrors normalized tokens into the config repository on load', function () {
        Container::getInstance()->instance('config', new Repository);

        try {
            Theme::load([
                'light' => ['primary' => 'red-300'],
                'dark' => ['primary' => 'red-800'],
            ]);

            expect(config('native-ui.theme.light.primary'))->toBe('#FCA5A5');
            expect(config('native-ui.theme.dark.primary'))->toBe('#991B1B');
        } finally {
            Container::setInstance(null);
        }
    });

    it('mirrors the auto-derived dark block, so theme() works in dark mode without one', function () {
        Container::getInstance()->instance('config', new Repository);

        try {
            Theme::load(['light' => ['primary' => 'red-300']]);

            expect(config('native-ui.theme.dark.primary'))->toMatch('/^#[0-9A-F]{6}$/');
        } finally {
            Container::setInstance(null);
        }
    });

    it('mirrors merge() overrides into the config repository', function () {
        Container::getInstance()->instance('config', new Repository);

        try {
            Theme::load(['light' => ['primary' => 'red-300']]);
            Theme::merge(['light' => ['primary' => 'orange-800']]);

            expect(config('native-ui.theme.light.primary'))->toBe('#9A3412');
        } finally {
            Container::setInstance(null);
        }
    });

    it('no-ops without a bound config repository', function () {
        Container::setInstance(null);

        Theme::load(['light' => ['primary' => 'red-300']]);

        expect(Theme::get('light.primary'))->toBe('#FCA5A5');
    });
});
