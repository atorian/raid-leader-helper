# Blood Queen Splash Design

## Goal

During Blood-Queen Lana'thel in Icecrown Citadel, log which player-source `Кровавый всплеск` event hit which player. The report should preserve combat-log event order and should not try to infer a single true offender, because any nearby player can be part of the spacing mistake.

## Scope

Add a separate boss module for Blood-Queen Lana'thel. Do not expand `BloodPrincesTracker` and do not create a generic ICC tracker.

The module handles only WoW 3.3.5a combat-log data.

## Event Filter

The tracker logs only events matching all of these rules:

- `event.event == "SPELL_DAMAGE"`
- `event.spellId` is one of `71483`, `71481`, or `71447`
- `sourceFlags` marks the source as a player, party member, or raid member via `RLHelper.GROUP_AFFILIATION_ANY`

The tracker ignores:

- boss-source splash events from `Кровавая королева Лана'тель`
- `71480` / `Сумеречная кровяная стрела`
- aura events, misses, periodic damage, and any unrelated spell

## Message Format

Use the event's source and destination names in combat-log order:

`HH:MM:SS |cFFFFFFFF<sourceName>|r |T<icon>:24:24:0:0|t |cFFFFFFFF<destName>|r`

Example from the provided log:

`20:54:22 |cFFFFFFFFStikers|r |T<icon>:24:24:0:0|t |cFFFFFFFFРайва|r`

The message should not label the source as "guilty" or the destination as "victim"; the event order is enough.

## Architecture

Create `modules/bosses/BloodQueenTracker.lua` following the existing boss tracker pattern:

- `local BloodQueenTracker = RLHelper:NewModule("BloodQueenTracker", "AceEvent-3.0")`
- `BloodQueenTracker.receivesCombatEvents = true`
- `BloodQueenTracker.zoneGateInstanceId = 631`
- `OnInitialize` sets `self.log` to `RLHelper:OnCombatLogEvent(...)`
- `handleEvent(event)` owns the filter and message formatting

Add the module to `RLHelper.toc` near the other ICC boss modules.

## Testing

Add focused Busted tests in `tests/BloodQueenTracker.test.lua`:

- module receives combat events only in Icecrown Citadel
- logs player-source `71483`, `71481`, and `71447` as `source -> dest`
- ignores boss-source splash events
- ignores `71480`
- ignores non-`SPELL_DAMAGE` events

No roster lookup is needed for this feature.

## Success Criteria

- `BloodQueenTracker` logs one message for each qualifying player-source splash event: `71483`, `71481`, or `71447`.
- The boss-source duplicate in the sample log is ignored.
- Existing Blood Princes behavior remains unchanged.
- Relevant tests pass.
