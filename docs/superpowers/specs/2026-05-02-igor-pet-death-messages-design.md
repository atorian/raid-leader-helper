# Igor Pet Death Messages Design

## Goal

Extend Igor death emotes so group-affiliated pets and guardians get their own pet-themed messages instead of being ignored or using player death messages.

The addon targets WoW 3.3.5a only.

## Existing Behavior

`RLHelper:MaybeSendIgorDeathMessage(event)` handles Igor death emotes for `UNIT_DIED` combat-log events.

The current player-death filter requires party or raid affiliation and the combat-log `TYPE_PLAYER` flag. This keeps totems, pets, guardians, and objects out of the player message path.

Igor uses one cooldown timestamp, `lastIgorDeathMessageAt`, to prevent death-emote spam.

## Pet And Guardian Behavior

Add a second Igor message path for `UNIT_DIED` events where the destination is both group-affiliated and a pet or guardian type.

Accepted pet targets:

- `destFlags` contains party or raid affiliation;
- `destFlags` contains `COMBATLOG_OBJECT_TYPE_PET` or `COMBATLOG_OBJECT_TYPE_GUARDIAN`;
- event name is exactly `UNIT_DIED`.

Player deaths keep using `IGOR_DEATH_PHRASES`. Pet and guardian deaths use a separate `IGOR_PET_DEATH_PHRASES` list.

Player and pet/guardian messages share the existing 10-second Igor cooldown. If Igor comments on a player death, a pet death inside that cooldown is suppressed, and vice versa.

## Pet Message Phrases

Use these 10 phrases:

```lua
local IGOR_PET_DEATH_PHRASES = {
    "Игорь скорбит по питомцу %s.",
    "Игорь считает, что %s заслуживал большего.",
    "Игорь делает пометку: %s погиб за чужие ошибки.",
    "Игорь говорит: минус лапа в рейде.",
    "Игорь подозревает, что %s просто хотел домой.",
    "Игорь смотрит на тело %s и молчит.",
    "Игорь напоминает: питомцев тоже надо лечить.",
    "Игорь записал смерть %s в отчет о халатности.",
    "Игорь говорит: зверя жалко.",
    "Игорь считает, что %s был лучшим из нас."
}
```

Use the same formatting behavior as player messages: if a phrase has `%s`, substitute `destName`; otherwise send it unchanged.

## Implementation Shape

Keep the sending path centralized in `MaybeSendIgorDeathMessage`.

Add small helpers near the existing Igor death filter:

- `isPetOrGuardianType(flags)`;
- a classifier that returns which phrase list applies for a group-affiliated death.

Do not add new options, UI, slash commands, or separate cooldown settings.

## Testing

Update `tests/Core.test.lua` around the Igor death emote tests:

- pet death with party/raid affiliation and `TYPE_PET` sends a pet phrase;
- guardian death with party/raid affiliation and `TYPE_GUARDIAN` sends a pet phrase;
- pet/guardian deaths use the same cooldown as player deaths;
- existing player-death tests keep passing;
- existing group-affiliated non-player test should still prove plain non-player units without pet/guardian type are ignored.

Run `busted --verbose ./tests/Core.test.lua` and `make test` after implementation.
