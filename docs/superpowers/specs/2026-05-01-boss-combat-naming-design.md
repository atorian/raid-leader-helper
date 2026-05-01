# Boss Combat Naming Design

## Goal

When a boss participates in a combat, the combat entry should use the boss name. If `Оставлять бои только с боссами` is enabled, non-boss combats should still be visible as the current combat while active, but should not be saved to long-term combat history.

## Current Behavior

RLHelper stores the visible combat name in `currentCombat.firstEnemy`. That field is set once from the first non-ignored enemy that affects the group. Boss participation is tracked separately with `currentCombat.isBoss`, but boss detection does not update `firstEnemy`. As a result, if a non-boss enemy is seen before the boss, the saved combat can be marked as a boss combat while still being named after the non-boss enemy.

The `bossOnlyHistory` option already filters saved history through `ShouldSaveCombatToHistory()`. Non-boss combats are not written to `combatHistory` or `profile.combatHistory` when the option is enabled.

## Desired Behavior

- `currentCombat.firstEnemy` remains the display name for a combat.
- The first non-ignored enemy can still set a temporary combat name.
- When `MarkBossCombat()` detects a boss through `boss1`-`boss5`, it should set `currentCombat.isBoss = true` and replace `currentCombat.firstEnemy` with that boss name.
- The boss name should be taken from the matching combat-log participant: `sourceName` if the source is the boss, or `destName` if the destination is the boss.
- Ignored names should not become combat names.
- If `bossOnlyHistory` is enabled, active non-boss combats still display through the existing current-combat flow, but are not saved after combat ends.
- Boss combats are saved with the boss name even if the combat started with a non-boss enemy.

## Implementation Shape

Keep the existing data model and use `firstEnemy` as the combat display name. Do not add a separate `bossName` field. Update boss detection so it returns or applies the detected boss name at the same time it marks the combat as boss-related.

The smallest implementation is to make `MarkBossCombat(event)` assign `self.currentCombat.firstEnemy` when `isKnownBossUnit()` matches the source or destination. The method should continue returning `true` only when it newly marks a boss combat. If `currentCombat.isBoss` is already true, no further rename is needed.

## Testing

Add focused Busted tests in `tests/CombatSystem.test.lua`:

- a combat that starts with a non-boss enemy and later sees `boss1` is renamed to the boss;
- with `bossOnlyHistory = true`, a non-boss combat with messages is not saved to long-term history after combat ends;
- with `bossOnlyHistory = true`, a combat that starts with a non-boss enemy and later sees `boss1` is saved with the boss name.

Run the full Busted suite after implementation.
