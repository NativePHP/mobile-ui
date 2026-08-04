<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * SheetPane — an inline, permanently-visible bottom pane that drags
 * FLUIDLY with the finger and spring-snaps to detents on release, all
 * native-side (no PHP round-trips while tracking). Unlike BottomSheet
 * (a presented UISheetPresentationController) it renders inside the
 * screen's own layer, so floating chrome — the Liquid Glass tab bar,
 * FABs — stays above it. The Maps/Flighty "always-on pane" pattern.
 *
 * Dragging the pane's non-scrolling area (header/grabber) moves the
 * pane; drags inside a child scroll-view scroll the content — SwiftUI
 * responder precedence resolves that per-touch.
 *
 *   <native:sheet-pane detents="200,560,780" :detent="$detent"
 *       corner-radius="44" inset-x="8" inset-bottom="8"
 *       @change="setDetent">
 *       ...content...
 *   </native:sheet-pane>
 *
 * `@change` fires when a drag settles, with the resolved detent (px) as
 * the value — store it and re-publish the same number so re-renders
 * don't move the pane.
 */
class SheetPane extends Element
{
    protected string $type = 'sheet_pane';

    /** @var array<string, mixed> */
    protected array $paneProps = [];

    protected ?string $changeCallback = null;

    public static function make(): static
    {
        return new static;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['detents'])) {
            $this->detents($attrs['detents']);
        }
        if (isset($attrs['detent'])) {
            $this->detent((float) $attrs['detent']);
        }
        foreach (['corner-radius', 'cornerRadius'] as $key) {
            if (isset($attrs[$key])) {
                $this->cornerRadius((float) $attrs[$key]);
            }
        }
        foreach (['inset-x', 'insetX'] as $key) {
            if (isset($attrs[$key])) {
                $this->insetX((float) $attrs[$key]);
            }
        }
        foreach (['inset-bottom', 'insetBottom'] as $key) {
            if (isset($attrs[$key])) {
                $this->insetBottom((float) $attrs[$key]);
            }
        }

        $this->applyA11yAttributes($attrs);
    }

    /** Comma-separated resting heights in points, ascending: "200,560,780". */
    public function detents(string $detents): static
    {
        $this->paneProps['detents'] = $detents;

        return $this;
    }

    /** Current resting height (px). Bind to the value @change reported. */
    public function detent(float $height): static
    {
        $this->paneProps['detent'] = $height;

        return $this;
    }

    /** Match the device's display curvature: screen radius minus inset. */
    public function cornerRadius(float $radius): static
    {
        $this->paneProps['corner_radius'] = $radius;

        return $this;
    }

    public function insetX(float $points): static
    {
        $this->paneProps['inset_x'] = $points;

        return $this;
    }

    public function insetBottom(float $points): static
    {
        $this->paneProps['inset_bottom'] = $points;

        return $this;
    }

    public function onChange(string $method): static
    {
        $this->changeCallback = $method;

        return $this;
    }

    protected function defaults(): array
    {
        return [
            'detents' => '200,560,780',
            'corner_radius' => 44.0,
            'inset_x' => 8.0,
            'inset_bottom' => 8.0,
        ];
    }

    /** The pane paints its own chrome — no generic style wrapper. */
    public function getStyle(): array
    {
        return [];
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        $props = $this->paneProps;

        if ($this->changeCallback !== null) {
            $props['on_change'] = $registry->register($this->changeCallback);
        }

        return $props;
    }
}
