# Group membership by GUID

## When to apply

When filtering combat events or identifying participants in RLHelper for WoW 3.3.5a.

## Rule

Recognize party/raid members and their pets by a GUID roster populated from unit tokens, with combat-log affiliation flags as a fallback. Refresh the roster on login, group changes and pet changes. Keep it separate from per-combat state. Use the same membership check in the dispatcher, combat tracking and mechanic modules.

## Reason

When the observer is mind-controlled, their raid members can appear as hostile outsiders (`0x548`) and controlled players can appear as pets (`0x1248`/`0x1218`). Their GUIDs remain unchanged. WoWCombatLog3.txt contains a spirit summon at 20:34:32.185 and a hit on Storm at 20:34:36.022 during the observer's control that demonstrate this. The user chose Skada's GUID-roster approach.

## Checklist

- Preserve events from known group GUIDs when flags change.
- Do not classify known group members as combat enemies.
- Keep genuinely outside players filtered out.
- Remove departed members and replaced pets when rebuilding the roster.
- Do not clear group membership at the end of a fight.
- Verify mechanics through the complete dispatcher in both journal versions.
