<?php

namespace Native\Mobile\UI;

use Illuminate\Support\ServiceProvider;
use Illuminate\View\View;
use Native\Mobile\Edge\ChromeContributorRegistry;
use Native\Mobile\Edge\Element;
use Native\Mobile\Edge\Layouts\NativeLayout;
use Native\Mobile\Edge\NativeComponent;
use Native\Mobile\Edge\TailwindParser;
use Native\Mobile\Testing\TestableComponent;
use Native\Mobile\UI\Builders\BackgroundLayer;
use Native\Mobile\UI\Builders\Drawer;
use Native\Mobile\UI\Builders\FloatingOverlay as FloatingOverlayBuilder;
use Native\Mobile\UI\Concerns\HasBackgroundLayer;
use Native\Mobile\UI\Concerns\HasFloatingOverlay;
use Native\Mobile\UI\Concerns\InteractsWithFloatingOverlay;
use Native\Mobile\UI\Console\CopyFontsCommand;
use Native\Mobile\UI\Console\FontCommand;
use Native\Mobile\UI\Console\GenerateIconsCommand;
use Native\Mobile\UI\Elements\FloatingOverlay as FloatingOverlayElement;
use Native\Mobile\UI\Elements\NativeDrawer;
use Native\Mobile\UI\Testing\DatePickerMacros;

class NativeUIServiceProvider extends ServiceProvider
{
    public function register(): void
    {
        $this->mergeConfigFrom(
            __DIR__.'/../config/native-ui.php',
            'native-ui'
        );
    }

    public function boot(): void
    {
        // Test sugar (pickDate(), assertPickerValue(), ...) — only under a
        // test runner, and only on a core whose TestableComponent is
        // macroable. The method_exists guard keeps older cores fatal-free,
        // matching how the camera plugin gates its FakeBridge macros.
        if ($this->app->runningUnitTests()
            && class_exists(TestableComponent::class)
            && method_exists(TestableComponent::class, 'macro')) {
            DatePickerMacros::register();
        }

        $this->publishes([
            __DIR__.'/../config/native-ui.php' => config_path('native-ui.php'),
        ], 'native-ui-config');

        // Default page layout (`<x-layouts.app>`). Devs run
        // `php artisan vendor:publish --tag=native-ui-layouts` to drop the
        // scaffold into their resources/views/components/ tree and edit
        // freely. Multiple archetypes (feed/detail/etc.) can be added by
        // copying app.blade.php to neighboring files.
        $this->publishes([
            __DIR__.'/../resources/stubs/views/components/layouts/app.blade.php' => resource_path('views/components/layouts/app.blade.php'),
        ], 'native-ui-layouts');

        // Load the merged config into the runtime Theme store. Consumers can
        // override with Theme::merge([...]) from their own service provider
        // after parent::boot(). Font aliases load first (no push) so the
        // theme push from load() carries them in one payload.
        Theme::fonts(config('native-ui.fonts', []));
        Theme::load(config('native-ui.theme', []));

        // Enable `bg-theme-*` / `text-theme-*` / `border-theme-*` Tailwind
        // classes by giving the parser a way to resolve token names against
        // our Theme. Both LIGHT and DARK resolvers are registered so the
        // parser emits a `dark` companion that the collector splits into
        // `dark_bg_color` / `dark_color` / `dark_border_color` props —
        // NodeStyleModifier picks the right hex at draw time based on
        // system colorScheme.
        TailwindParser::setThemeResolver(function (string $token): ?string {
            $value = Theme::get("light.$token");

            return is_string($value) ? $value : null;
        });
        TailwindParser::setThemeDarkResolver(function (string $token): ?string {
            $value = Theme::get("dark.$token");

            return is_string($value) ? $value : null;
        });

        $this->registerLayoutDrawer();
        $this->registerFloatingOverlay();
        $this->registerBackgroundLayer();

        if ($this->app->runningInConsole()) {
            $this->commands([
                GenerateIconsCommand::class,
                CopyFontsCommand::class,
                FontCommand::class,
            ]);
        }
    }

    /**
     * Register the layout-drawer chrome contributor with core's chrome seam.
     * Core stays drawer-agnostic: it just appends whatever sentinel element a
     * contributor returns to the published tree. Here we resolve the drawer for
     * the screen (per-screen override beats the layout) and render it into a
     * `native_drawer` sentinel. The native drawer host — registered on core's
     * `NativeRootHostRegistry` from this plugin's init function — hoists it out.
     *
     * Discovery is via `method_exists`, so layouts/screens opt in by using the
     * {@see HasLayoutDrawer} / {@see InteractsWithDrawer} traits (or just by
     * declaring `drawer()` / `drawerOverride()` themselves) — core never knows.
     */
    protected function registerLayoutDrawer(): void
    {
        if (! class_exists(ChromeContributorRegistry::class)) {
            return;
        }

        ChromeContributorRegistry::register(function (NativeComponent $screen, ?NativeLayout $layout, callable $renderPartial): ?Element {
            if (self::screenHides($screen, 'hidesDrawer')) {
                return null;
            }

            $builder = null;
            if (method_exists($screen, 'drawerOverride')) {
                $builder = $screen->drawerOverride();
            }
            if ($builder === null && $layout !== null && method_exists($layout, 'drawer')) {
                $builder = $layout->drawer($screen);
            }

            if (! $builder instanceof Drawer) {
                return null;
            }

            $content = $builder->getContent();
            $contentElement = $content instanceof View ? $renderPartial($content) : $content;

            $drawer = NativeDrawer::make();
            $drawer->applyAttributes([
                'mode' => $builder->getMode(),
                'width' => $builder->getWidth(),
            ]);
            $drawer->addChild($contentElement);

            return $drawer;
        });
    }

    /**
     * Register the floating-overlay chrome contributor with core's chrome seam.
     * Same shape as {@see registerLayoutDrawer()}: resolve the overlay for the
     * screen (per-screen override beats the layout) and render it into a
     * `floating_overlay` sentinel. The native floating-overlay host — registered
     * on core's `NativeRootHostRegistry` from this plugin's init function —
     * hoists it onto a top layer over the content.
     *
     * Discovery is via `method_exists`, so layouts/screens opt in by using the
     * {@see HasFloatingOverlay} /
     * {@see InteractsWithFloatingOverlay} traits (or
     * by declaring the methods themselves) — core never knows.
     */
    /**
     * Register the background-layer chrome contributor: content rendered
     * BENEATH every screen under the layout, mounted once at the root so
     * a map/video/canvas persists across tab switches and pushes. Same
     * discovery shape as the floating overlay: layouts opt in with
     * {@see HasBackgroundLayer}, screens can
     * override via `backgroundLayerOverride()` or hide with
     * `hidesBackgroundLayer`.
     */
    protected function registerBackgroundLayer(): void
    {
        if (! class_exists(ChromeContributorRegistry::class)) {
            return;
        }

        ChromeContributorRegistry::register(function (NativeComponent $screen, ?NativeLayout $layout, callable $renderPartial): ?Element {
            if (self::screenHides($screen, 'hidesBackgroundLayer')) {
                return null;
            }

            $builder = null;
            if (method_exists($screen, 'backgroundLayerOverride')) {
                $builder = $screen->backgroundLayerOverride();
            }
            if ($builder === null && $layout !== null && method_exists($layout, 'backgroundLayer')) {
                $builder = $layout->backgroundLayer($screen);
            }

            if (! $builder instanceof BackgroundLayer) {
                return null;
            }

            $content = $builder->getContent();
            $contentElement = $content instanceof View ? $renderPartial($content) : $content;

            $sentinel = Elements\BackgroundLayer::make();
            $sentinel->addChild($contentElement);

            return $sentinel;
        });
    }

    protected function registerFloatingOverlay(): void
    {
        if (! class_exists(ChromeContributorRegistry::class)) {
            return;
        }

        ChromeContributorRegistry::register(function (NativeComponent $screen, ?NativeLayout $layout, callable $renderPartial): ?Element {
            if (self::screenHides($screen, 'hidesFloatingOverlay')) {
                return null;
            }

            $builder = null;
            if (method_exists($screen, 'floatingOverlayOverride')) {
                $builder = $screen->floatingOverlayOverride();
            }
            if ($builder === null && $layout !== null && method_exists($layout, 'floatingOverlay')) {
                $builder = $layout->floatingOverlay($screen);
            }

            if (! $builder instanceof FloatingOverlayBuilder) {
                return null;
            }

            $content = $builder->getContent();
            $contentElement = $content instanceof View ? $renderPartial($content) : $content;

            $overlay = FloatingOverlayElement::make();
            $overlay->applyAttributes([
                'alignment' => $builder->getAlignment(),
                'offset' => $builder->getOffset(),
            ]);
            $overlay->addChild($contentElement);

            return $overlay;
        });
    }

    /**
     * Read a screen's boolean opt-out flag in either spelling: the trait /
     * method form (`hidesFloatingOverlay(): bool`) or a bare property
     * (`protected bool $hidesFloatingOverlay = true;`). The bare property
     * matches core's `$hidesTabBar` / `$hidesNavBar` shorthand, so screens
     * can use the same one-liner for plugin chrome without pulling in the
     * trait. The method wins when both exist (it IS the trait's property
     * accessor in the common case).
     */
    public static function screenHides(NativeComponent $screen, string $flag): bool
    {
        if (method_exists($screen, $flag)) {
            return (bool) $screen->{$flag}();
        }

        if (property_exists($screen, $flag)) {
            $prop = new \ReflectionProperty($screen, $flag);

            return $prop->isInitialized($screen) && (bool) $prop->getValue($screen);
        }

        return false;
    }
}
