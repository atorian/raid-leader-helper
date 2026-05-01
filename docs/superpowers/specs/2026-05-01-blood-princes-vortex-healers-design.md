# Blood Princes Vortex Healers Design

## Goal

In Icecrown Citadel on Blood Prince Council, add a combat-log message when a player damages a healer from raid group 5 with `Могучий вихрь`.

## Combat Log Rule

Track `SPELL_DAMAGE` events with spellId `72817` and spell name `Могучий вихрь`. In these events, `sourceName` is the player who damaged someone with the vortex, and `destName` is the damaged player.

Only log when the destination player is a healer assigned to raid group 5. A group-5 healer is identified from raid roster data as:

- `subgroup == 5`;
- class is one of `PRIEST`, `PALADIN`, `SHAMAN`, or `DRUID`.

Other group-5 classes, including warlocks, are ignored. Players outside group 5 are ignored even if their class can heal. The source player is not filtered; if the source is also a healer, still log the event when the destination matches the healer rule.

`SPELL_MISSED` for spellId `72817` is not logged because the requested behavior is damage only.

## Implementation Shape

Create a new boss module `modules/bosses/BloodPrincesTracker.lua`. It should follow the existing boss tracker pattern:

- create an Ace module from `RLHelper:NewModule`;
- set `receivesCombatEvents = true`;
- set `zoneGateInstanceId = 631` for Icecrown Citadel;
- initialize `self.log` to call `RLHelper:OnCombatLogEvent(...)`;
- expose `handleEvent(event)` for `Core.lua` dispatch.

The module should use `GetRaidRosterInfo(i)` to resolve whether `event.destName` is in subgroup 5 and has an allowed healer class. In WoW 3.3.5a, the class token is returned by raid roster info and should be compared against the English class tokens.

Add the module to `RLHelper.toc` after the other ICC boss tracker entries.

## Message Format

Log one message per qualifying damage event:

```text
<HH:MM:SS> <sourceName> <vortex icon> <destName>
```

Use WoW color/icon formatting consistent with the rest of the addon:

```lua
string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t |cFFFFFFFF%s|r", date("%H:%M:%S", ts), sourceName, icon, destName)
```

The icon can be a locally chosen spell icon for the vortex; it should be a normal WoW texture path string.

## Testing

Add `tests/BloodPrincesTracker.test.lua` with focused Busted tests:

- module receives combat events only in ICC by checking `receivesCombatEvents` and `zoneGateInstanceId`;
- logs when `SPELL_DAMAGE` spellId `72817` damages a group-5 `PRIEST`, `PALADIN`, `SHAMAN`, or `DRUID`;
- ignores a group-5 `WARLOCK`;
- ignores an allowed healer class outside group 5;
- ignores `SPELL_MISSED` spellId `72817`;
- does not filter the source player, including when source is also a group-5 healer.

Extend test mocks only as needed to provide `GetRaidRosterInfo(i)`.

Run the full Busted suite after implementation.
