# Faction Champions Yell Automark Design

## Goal

In Trial of the Crusader / Trial of the Grand Crusader, start Faction Champions automarking automatically when Tirion Fordring's Russian encounter announcement appears. Remove the temporary manual `/rlh tocmarks` fallback now that the real trigger text is known.

The addon targets WoW 3.3.5a only.

## Existing Behavior

`modules/bosses/TrialCrusaderTracker.lua` already listens to `CHAT_MSG_MONSTER_YELL` and `CHAT_MSG_RAID_BOSS_EMOTE`. AceEvent passes the event name before the message arguments, so handlers must read `(eventName, message, sender)`. Both events are logged for debug, but only `CHAT_MSG_MONSTER_YELL` should start `StartFactionChampionAutomark()` when its message contains one configured fragment from `FACTION_CHAMPION_START_FRAGMENTS`.

The automark scan itself already runs for 180 seconds and checks only `target` and `mouseover`.

`Core.lua` currently exposes `/rlh tocmarks`, which manually calls the same automark start path through `TriggerTrialCrusaderAutomark()`.

## Trigger Text

Use the full phrase from `toc.png` as the single configured start fragment:

```text
В следующем бою вы встретитесь с могучими рыцарями Серебряного Авангарда! Лишь победив их, вы заслужите достойную награду.
```

Keep the existing plain substring match. This is strict enough to avoid unrelated starts while still working if the server message includes sender prefixes or other chat metadata outside the actual `message` argument.

## Command Removal

Remove the manual Trial of the Crusader automark command from user-facing slash handling:

- remove `/rlh tocmarks` from help output;
- remove the `tocmarks` branch from `HandleSlashCommand`;
- remove `TriggerTrialCrusaderAutomark()` if nothing else uses it.

This leaves automatic boss-message activation as the supported path.

## Testing

Update focused tests only:

- `TrialCrusaderTracker` starts automark when `CHAT_MSG_MONSTER_YELL` contains the exact Russian phrase;
- `Core` no longer has a `/rlh tocmarks` manual command test;
- existing automark scan behavior remains covered by current tests.

Run the Lua test suite after implementation.
