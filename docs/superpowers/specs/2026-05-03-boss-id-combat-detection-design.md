# Boss ID Combat Detection Design

## Goal

Fix boss combat detection for `bossOnlyHistory` by removing the `boss1` dependency and marking boss fights from known boss NPC IDs seen in combat-log events.

## Problem

`Core.lua` currently uses `UnitName("boss1")` in `MarkBossCombat(event)`. In many real boss encounters on WoW 3.3.5a, `boss1` is absent or unreliable, so boss fights are not marked as boss fights and are dropped when `bossOnlyHistory` is enabled.

This loses combat history data.

## Scope

In scope:
- Use static boss NPC ID lists exposed by existing boss modules.
- Detect boss fights from combat-log `sourceGUID` and `destGUID` creature IDs.
- Use encounter names for saved combat names.
- Cover only currently existing boss modules:
  - `TrialCrusaderTracker`
  - `DeathwhisperTracker`
  - `BloodPrincesTracker`
  - `BloodQueenTracker`
  - `HalionTracker`

Out of scope:
- Full WotLK raid boss database.
- Spell-triggered boss detection.
- Halion burst/reset or damage-meter reset behavior.
- Any `boss1` fallback for boss history detection.

## Module Contract

Each in-scope boss module will expose a `bossIds` table:

```lua
Tracker.bossIds = {
    [37955] = "Кровавая королева Лана'тель"
}
```

The key is the NPC ID extracted from a combat-log GUID. The value is the canonical encounter name used for `currentCombat.firstEnemy`.

For multi-NPC encounters, multiple NPC IDs map to the same encounter name:

```lua
BloodPrincesTracker.bossIds = {
    [37970] = "Кровавый совет",
    [37972] = "Кровавый совет",
    [37973] = "Кровавый совет"
}
```

## Core Detection Flow

`RLHelper:MarkBossCombat(event)` should:

1. Return `false` if there is no active `currentCombat`, if it is already marked as boss, or if the event does not affect the group.
2. Extract NPC IDs from `event.sourceGUID` and `event.destGUID` using the existing `RLHelper.GetCreatureId` helper.
3. Iterate loaded modules with `IterateModules()`.
4. Check only modules that pass `ShouldDispatchCombatEventToModule(module)` so instance gates are respected.
5. If `module.bossIds[npcId]` exists for either source or destination, set:
   - `currentCombat.isBoss = true`
   - `currentCombat.firstEnemy = module.bossIds[npcId]`
6. Return `true` when a boss match is found, otherwise `false`.

`UnitExists("boss1")` and `UnitName("boss1")` must not participate in boss history detection.

## Encounter Names

Use encounter names, not first-seen NPC names, for stable history entries.

Examples:
- Faction Champions NPC IDs -> `Чемпионы фракций`
- Blood Princes NPC IDs -> `Кровавый совет`
- Blood-Queen Lana'thel NPC ID -> `Кровавая королева Лана'тель`
- Lady Deathwhisper NPC ID -> `Леди Смертный Шепот`
- Halion NPC ID -> `Халион`

Exact NPC ID lists should be limited to the existing module scope and verified in tests for representative IDs.

## Tests

Add focused tests in `tests/CombatSystem.test.lua`:

- A known boss NPC ID marks combat as boss without any `boss1` unit.
- `bossOnlyHistory` saves a combat marked by known boss NPC ID.
- A populated `boss1` no longer marks combat as boss when the combat-log NPC ID is not known.
- A multi-NPC encounter maps a known participant NPC ID to the encounter name.

Existing module tests should continue to pass unchanged, because this feature only consumes module metadata and does not change module event handling.

## Risks

- Incorrect NPC IDs would still cause missed boss history entries. Keep the first implementation scoped to existing modules and add tests for the IDs that matter to those modules.
- `ShouldDispatchCombatEventToModule(module)` depends on current zone context. Tests should set or avoid zone gates explicitly so failures are deterministic.
- If a boss module is not loaded, its `bossIds` will not be available. This matches the current addon architecture where modules are loaded by TOC.

## Success Criteria

- Boss fights from existing modules are saved by `bossOnlyHistory` even when `boss1` is absent.
- `boss1` presence alone does not mark combat as boss.
- Combat history names use stable encounter names.
- Full Busted suite passes.
