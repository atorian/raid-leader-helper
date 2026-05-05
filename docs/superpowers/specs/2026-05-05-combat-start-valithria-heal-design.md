# Combat Start And Valithria First Heal Design

## Goal

Improve combat-start logging by sharing ignored enemy filtering between core combat tracking and `SpellTracker`, and add first-heal tracking for Valithria Dreamwalker.

## Current Behavior

`Core.lua` has a local `IGNORED_COMBAT_ENEMIES` table that already includes `Робот "Бей-Молоти"`. Core combat state uses this table, but `SpellTracker` has independent first-damage tracking and can still log `Первый урон` against ignored enemies.

`SpellTracker` currently logs only first damage by a player against an enemy. It does not track first healing done to Valithria.

## Design

Create a small shared helper, `lib/CombatFilters.lua`, responsible for combat-filter decisions used by both `Core.lua` and `SpellTracker.lua`.

The helper should expose:

- `CombatFilters:IsIgnoredCombatEnemy(name)` returns true for ignored combat enemy names.

The ignored enemy list should include the current core entries:

- `World Invisible Trigger`
- `Огрская пиньята`
- `Робот "Бей-Молоти"`

`Core.lua` should use this helper instead of its local table. `SpellTracker.lua` should use the same helper before logging first damage.

## Valithria First Heal

`SpellTracker` should track first healing done to `Валитрия Сноходица`.

Eligible events:

- `SPELL_HEAL`
- `SPELL_PERIODIC_HEAL`

Conditions:

- Source is a player or group member by existing `isPlayer` flag check.
- Destination name is exactly `Валитрия Сноходица`.
- `eventData.amount > 0`.
- First Valithria heal has not already been logged in the current combat tracker state.

Output format:

```text
<time> |cFFFFFFFF<sourceName>|r Первый хил по |cFFFFFFFFВалитрия Сноходица|r
```

The first-heal flag is independent from `firstDamageDone`, so a combat can log both first damage and first Valithria heal.

## Tests

Add tests that verify:

- `Core.lua` still ignores `Робот "Бей-Молоти"` through the shared helper.
- `SpellTracker` does not log first damage against `Робот "Бей-Молоти"`.
- `SpellTracker` logs first `SPELL_HEAL` with `amount > 0` to `Валитрия Сноходица`.
- `SpellTracker` logs first `SPELL_PERIODIC_HEAL` with `amount > 0` to `Валитрия Сноходица`.
- `SpellTracker` ignores zero-amount Valithria heals.
- `SpellTracker` logs Valithria first heal only once per reset.

Verification command: `busted --verbose ./tests/*.lua`.
