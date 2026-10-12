# Grimoire
Lists your character's abilities, talents and runes, with what each one does, for the Grimfall server (WotLK 3.3.5a client, Ascension core).

## Use
- `/grim` opens the window. Tabs: **Abilities**, **Talents**, **Runes**, **Discovery**.
- Copy everything: click the text, press Ctrl+A, then Ctrl+C.
- The data is also saved per character in `WTF\Account\<account>\<realm>\<character>\SavedVariables\Grimoire.lua`.

## Runes
Grimfall's rune window is custom, so Grimoire captures runes from their tooltips:
1. Press **Capture** on the Runes tab (or type `/grim capture`).
2. Open the rune window and hover every rune.
3. Press **Stop capture**. The runes stay saved.

`/grim runes clear` forgets all captured runes.

## Commands
| Command | What it does |
|---|---|
| `/grim` | Open or close the window |
| `/grim abilities` / `talents` / `runes` / `discovery` | Open that tab |
| `/grim capture` | Turn rune capture on or off |
| `/grim runes clear` | Forget all captured runes |
| `/grim scan` | List rune/talent-related functions the client exposes |
| `/grim mouse` | Describe the window under the cursor |
