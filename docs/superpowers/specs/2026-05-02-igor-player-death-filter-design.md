# Igor Player Death Filter Design

## Goal

Make Igor react only to actual player deaths. Group-owned non-player units such as totems, pets, guardians, and objects must not trigger Igor death emotes.

The addon targets WoW 3.3.5a only.

## Existing Behavior

`RLHelper:MaybeSendIgorDeathMessage(event)` calls `RLHelper:IsGroupMemberDeath(event)` before sending an emote.

`IsGroupMemberDeath` currently accepts `UNIT_DIED` events when `destFlags` has party or raid affiliation. That can include group-affiliated non-player units.

`Core.lua` already has an `isPlayer(flags)` helper, but that helper checks group affiliation, not the combat-log player type flag. The Igor filter needs a separate `TYPE_PLAYER` check.

## Filter Rule

`IsGroupMemberDeath` should return true only when all of these are true:

- `event.event == "UNIT_DIED"`;
- `destFlags` contains party or raid affiliation;
- `destFlags` contains `TYPE_PLAYER`, checked with `COMBATLOG_OBJECT_TYPE_PLAYER` when available and `0x00000400` as the WoW 3.3.5a fallback.

This keeps Igor active for both party members and raid members while ignoring totems and other non-player entities.

## Testing

Update `tests/Core.test.lua` around the Igor death emote tests:

- keep the existing positive test for a raid member death with `destFlags = 0x514`;
- add a positive test for a party member player death with `destFlags = 0x512`;
- add a negative test for a group-affiliated non-player death, for example `destFlags = 0x114`, proving no emote is sent.

Run `busted --verbose ./tests/Core.test.lua` and `make test` after implementation.
