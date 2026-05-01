# Faction Champions Automark Design

## Goal

In Trial of the Crusader / Trial of the Grand Crusader, add a temporary target/mouseover automark mode for the Faction Champions encounter. The mode helps the raid leader mark champions before or alongside the existing combat-log-based marking.

The addon is for WoW 3.3.5a only. Other WoW versions are out of scope.

## Existing Behavior

`modules/bosses/TrialCrusaderTracker.lua` already tracks Faction Champions from combat log events. It maps known champion NPC IDs to roles, assigns fixed raid target icons for selected roles, picks diamond from a priority list, tracks which roles are already marked, and stops once all configured champion marks are done.

The new automark mode should reuse that state and marking logic instead of duplicating champion tables or creating a separate module.

## Automark Mode

Add target/mouseover automark mode to `TrialCrusaderTracker`.

When active, the mode runs for up to 180 seconds. It checks only these unit IDs:

- `target`
- `mouseover`

It must not scan `boss1`, `focus`, raid units, nameplates, or any broader unit list.

For each checked unit, the tracker should:

1. Read `UnitGUID(unitId)`.
2. Extract the NPC ID through the existing GUID parsing path.
3. Confirm the NPC ID is one of the known Faction Champions.
4. Reuse the existing champion role and raid marker mapping.
5. Call `SetRaidTarget(unitId, marker)` through the same marking path used by combat-log discovery.
6. Update the shared champion mark state.

Combat-log marking and target/mouseover automark are active at the same time. They share `championGuidsByRole`, `seenChampionGuids`, `markedRoles`, `diamondRole`, and `allChampionMarksDone`. If one path discovers a champion first, the other path must not duplicate the fixed mark.

The mode stops automatically when `AreChampionMarksDone()` returns true. It also stops after 180 seconds if some marks were not completed.

`reset()` can remain a technical state cleanup used by existing addon lifecycle events, but user-visible correctness must not depend on manually resetting this mode.

## Activation

Add a slash command:

```text
/rlh tocmarks
```

The command enables the same 180-second automark mode. It is used for testing and as a manual fallback before the exact server boss yell/emote trigger text is known.

Also listen for these boss message events:

- `CHAT_MSG_MONSTER_YELL`
- `CHAT_MSG_RAID_BOSS_EMOTE`

Inside Trial of the Crusader, log every message from these events through `RLHelper:Debug(...)` with the event name, sender when available, and message text. This is required so the exact Faction Champions encounter-start string can be collected on the server.

Autostart should use partial string matching against a small list of known trigger fragments. Because the exact fragments are not known yet, the initial list may be empty. Once collected, fragments can be added without changing the automark scan logic.

## Error Handling

Keep handling minimal:

- if `UnitGUID` is unavailable or returns no useful GUID, skip that unit;
- if the GUID is not a known champion NPC ID, skip it;
- if `SetRaidTarget` is unavailable, the existing marker helper should return false and no state should be marked complete for that unit;
- if the mode is already active and activation is requested again, extend or refresh the active window to another 180 seconds.

No additional recovery, configuration, or UI is required.

## Testing

Extend `tests/TrialCrusaderTracker.test.lua` and mocks only as needed.

Focused tests:

- `/rlh tocmarks` or the equivalent module entrypoint enables a 180-second mode;
- scanning `target` marks a known champion with the correct fixed raid target icon;
- scanning `mouseover` marks a known champion with the correct fixed raid target icon;
- scanning ignores `boss1`, `focus`, raid units, and unrelated unit IDs;
- combat-log discovery and target/mouseover discovery share state and do not duplicate fixed marks;
- diamond marking still follows the existing priority rule when champions are discovered through target/mouseover;
- the mode stops when `AreChampionMarksDone()` becomes true;
- the mode stops after the 180-second timeout;
- `CHAT_MSG_MONSTER_YELL` and `CHAT_MSG_RAID_BOSS_EMOTE` are written to debug in Trial of the Crusader;
- a boss yell/emote containing a configured trigger fragment starts the mode.

Run the existing Lua test suite after implementation.
