# Igor Module Extraction Design

## Goal

Move Igor death-emote handling out of `Core.lua` into a dedicated module while preserving current behavior.

## Existing Behavior

`Core.lua` currently owns Igor phrase lists, death classification, message formatting, cooldown state, and direct handling from `COMBAT_LOG_EVENT_UNFILTERED`.

Igor behavior is enabled by `db.profile.igor`. Player deaths use player phrases, group pet/guardian deaths use pet phrases, and both share one 10-second cooldown.

## Design

Create `modules/IgorDeathTracker.lua` as an Ace module with `receivesCombatEvents = true` and no zone gate.

The module owns:

- Igor player and pet phrase lists;
- combat-log type flag fallbacks;
- death classification;
- message formatting;
- `lastDeathMessageAt` cooldown state;
- `handleEvent(event)` entrypoint.

`Core.lua` keeps the Igor option UI and `db.profile.igor`, but no longer calls Igor directly. Igor receives combat events through the existing `DispatchCombatEvent` path.

Add `modules\IgorDeathTracker.lua` to `RLHelper.toc` after `Core.lua` and before other modules.

## Testing

Move the Igor death-emote tests from `tests/Core.test.lua` to `tests/IgorDeathTracker.test.lua` and adapt calls from `RLHelper:MaybeSendIgorDeathMessage(event)` to `IgorDeathTracker:handleEvent(event)`.

Keep existing coverage for:

- raid player deaths;
- party player deaths;
- 10-second cooldown;
- non-group deaths;
- typed deaths outside the group;
- group-affiliated non-player deaths;
- group pet deaths;
- group guardian deaths;
- shared cooldown between player and pet deaths.

Run `busted --verbose ./tests/IgorDeathTracker.test.lua`, `busted --verbose ./tests/Core.test.lua`, and `make test`.
