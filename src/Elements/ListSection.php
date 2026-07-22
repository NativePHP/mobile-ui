<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * A grouped section inside a {@see NativeList}. Renders as a SwiftUI
 * `Section` (iOS) / a sticky-header + grouped block inside `LazyColumn`
 * (Android). Place `ListItem` children inside; the parent list renderer
 * consumes the section inline — a section on its own renders nothing.
 *
 *   NativeList::make(
 *       ListSection::make('Fruits', ListItem::make('Apple'))->footer('1 item'),
 *       ListSection::make('Vegetables', ListItem::make('Carrot')),
 *   );
 */
class ListSection extends Element
{
    protected string $type = 'list_section';

    protected array $sectionProps = [];

    public static function make(string $header = '', Element ...$children): static
    {
        $el = new static;
        if ($header !== '') {
            $el->sectionProps['header'] = $header;
        }
        $el->children = $children;

        return $el;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['header'])) {
            $this->header($attrs['header']);
        }
        if (isset($attrs['footer'])) {
            $this->footer($attrs['footer']);
        }

        $this->applyA11yAttributes($attrs);
    }

    public function header(string $text): static
    {
        $this->sectionProps['header'] = $text;

        return $this;
    }

    public function footer(string $text): static
    {
        $this->sectionProps['footer'] = $text;

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        return $this->sectionProps;
    }
}
