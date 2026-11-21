<?php

namespace Native\Mobile\UI;

use Native\Mobile\Edge\Elements\TopBarAction;

/**
 * Extras for a row of a `:menu`, `:context-menu` or `:trailing-menu`, which
 * core's `NavAction` doesn't have a method for yet.
 *
 *     MenuItem::subtitle(
 *         NavAction::make('me')->label('Simon')->icon('person')->toElement(),
 *         '@simon-hamp',
 *     )
 *
 * An app can check `class_exists(MenuItem::class)` to tell whether the
 * installed mobile-ui draws subtitles, and put everything in the label if not.
 */
final class MenuItem
{
    /**
     * A second, smaller line under the row's label, such as an account's
     * handle under its name. Screen readers read it after the label. An
     * empty or null subtitle leaves the row as it was.
     */
    public static function subtitle(TopBarAction $item, ?string $subtitle): TopBarAction
    {
        if ($subtitle !== null && $subtitle !== '') {
            $item->setProp('subtitle', $subtitle);
        }

        return $item;
    }
}
