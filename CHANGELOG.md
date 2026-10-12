# Grimoire Changelog

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
