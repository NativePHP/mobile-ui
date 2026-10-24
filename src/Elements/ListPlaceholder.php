<?php

namespace Native\Mobile\UI\Elements;

use Native\Mobile\Edge\CallbackRegistry;
use Native\Mobile\Edge\Element;

/**
 * An empty row of a {@see NativeList}, drawn at the height the list last
 * measured for the row it stands in for, so a long list can send only the
 * rows near the screen and nothing on screen moves.
 *
 * Give it the row's key: a node's id comes from its key and its parent's, so
 * the placeholder takes the row's place in the list rather than replacing it.
 *
 *   $row = $nearScreen ? CommitRow::make($commit) : ListPlaceholder::make();
 *   $row->key('commit-'.$commit->id);
 *
 * Lists measure their rows while they report their visible range (see
 * {@see NativeList::onVisibleRange()}). A row the list hasn't drawn yet takes
 * the estimated height, or the list's typical row height without one.
 */
class ListPlaceholder extends Element
{
    protected string $type = 'list_placeholder';

    protected array $placeholderProps = [];

    public static function make(): static
    {
        return new static;
    }

    public function applyAttributes(array $attrs): void
    {
        if (isset($attrs['estimated-height']) || isset($attrs['estimatedHeight'])) {
            $this->estimatedHeight((float) ($attrs['estimated-height'] ?? $attrs['estimatedHeight']));
        }
    }

    /**
     * The height in points for a row the list hasn't measured.
     */
    public function estimatedHeight(float $points): static
    {
        $this->placeholderProps['estimated_height'] = max(0.0, $points);

        return $this;
    }

    protected function resolveProps(CallbackRegistry $registry): array
    {
        return $this->placeholderProps;
    }
}
