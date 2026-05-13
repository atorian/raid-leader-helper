# Putricide Choking Gas Tracking Design

## Goal

Track players affected by `Удушливый газ` / Choking Gas during Professor Putricide combat, log each application with an icon when it happens, and add a combat-end summary.

## Scope

- WoW 3.3.5a only.
- Track only during Professor Putricide combat.
- Use `SPELL_AURA_APPLIED`, which is an observed valid combat-log subevent for this addon.
- Use Choking Gas spell ids confirmed on `https://wotlk.ezhead.org/`: 71278 Normal 10, 72460 Normal 25, 72619 Heroic 10, 72620 Heroic 25.
- Use icon `ability_creature_cursed_01`, confirmed on the same ezhead spell pages.

## Design

Extend `modules/bosses/PutricideTracker.lua`, because it already owns Professor Putricide combat tracking and has the existing immediate-log plus combat-summary pattern for `Вязкая гадость`.

The tracker will keep a separate `chokingGasReport` table keyed by destination player name. When it receives `SPELL_AURA_APPLIED` for a tracked Choking Gas spell id during Professor Putricide combat and `destName` is present, it will:

- Increment that player's count in `chokingGasReport`.
- Log an immediate message naming the affected player with the Choking Gas icon and mechanic name.

On `RLHelper_CombatEnding`, it will append a summary if at least one player was affected. The summary will sort players by count descending, then name ascending, matching the existing `Вязкая гадость` summary behavior.

On `RLHelper_CombatEnded`, it will clear both Putricide report tables.

## Tests

Update `tests/PutricideTracker.test.lua` to cover:

- Immediate log for `SPELL_AURA_APPLIED` spell id 71278 with icon.
- Heroic 10 spell id 72619 is tracked.
- Summary sorted by count descending, then name ascending.
- No summary when no Choking Gas applications were tracked.
- Reset clears the Choking Gas report.
- Events outside Professor Putricide combat are ignored.
