# Grimoire Changelog

## v1.2.2 - 2026-10-12
- The report text is now editable: delete or change anything before copying. Switching tabs or pressing Refresh redraws the full report.
- Clicking anywhere in the text area puts the cursor in it.

## v1.2.1 - 2026-10-12
- Talents tab lists only talents you have ranks in; trees with no points are hidden (tick "Show unlearned talents" to see everything).
- Each tree is labelled with its class (e.g. "Death Knight - Frost", "Paladin - Protection") and trees are sorted by class.
- Total talent points spent shown at the top. The empty "Captured from the Classless window" section is gone (the talent API reads all classes on Grimfall).

## v1.2.0 - 2026-10-12
- Minimap button: left-click opens/closes Grimoire, right-click toggles capture (icon turns red while capturing), drag to move.
- Options page under Esc > Interface > AddOns > Grimoire: show minimap button, show unlearned talents, capture on/off, plus Open, API probe and clear buttons.
- New commands: `/grim minimap`, `/grim options`.

## v1.1.0 - 2026-10-12
- Classless support: Capture now also records talents hovered in the Classless trees (any class), shown on the Talents tab with their rank.
- Rune capture limited to "Rune of ..." tooltips; other tooltips are ignored.
- `/grim probe` tests Grimfall's read-only Classless and Mystic Enchant (rune) functions and saves the results, to wire up automatic reading next.

## v1.0.0 - 2026-10-12
- First release: Abilities (spellbook, highest rank, with tooltip text), Talents (learned or all) and Runes (captured from tooltips) in a copyable window, saved per character.
- Discovery tools (`/grim scan`, `/grim mouse`) to find Grimfall's rune API for a later version.
