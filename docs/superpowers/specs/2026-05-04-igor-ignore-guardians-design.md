# Igor Ignore Guardian Deaths Design

## Goal

Stop Igor death emotes from triggering on totems and other guardian deaths. Igor should react only to deaths of group players and real group pets.

## Current Behavior

`IgorDeathTracker:GetGroupDeathMessagePhrases` first checks that the death belongs to party or raid affiliation. It then returns player phrases for `PLAYER` flags and pet phrases for either `PET` or `GUARDIAN` flags.

Because totems can appear as group-affiliated guardians, they can currently trigger pet death emotes.

## Desired Behavior

Igor reacts to:

- Group player deaths with player death phrases.
- Group pet deaths with pet death phrases.

Igor ignores:

- Totems.
- Guardians.
- Non-party/non-raid deaths.
- Group-affiliated non-player, non-pet units.

## Approach

Use the existing combat log type flags, but remove `COMBATLOG_OBJECT_TYPE_GUARDIAN` from the accepted pet path. Rename the helper from guardian-inclusive wording to pet-only wording so the code matches the behavior.

No name-based filtering is needed. This keeps the change simple and avoids localization-dependent checks.

## Tests

Update `tests/IgorDeathTracker.test.lua` so that:

- Existing player and pet death tests continue to pass.
- The current guardian death test becomes an ignored guardian/totem death test.
- Cooldown sharing still covers player and pet deaths.

The full suite should pass with `busted --verbose ./tests/*.lua`.
