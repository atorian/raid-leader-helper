# Character Combat History Design

## Context

RLHelper currently stores combat history in `db.profile.combatHistory`. The addon creates AceDB with `AceDB:New("RLHelperDB", defaults, true)`, and AceDB maps `true` to the shared `Default` profile. As a result, characters using the default profile can see and append to the same combat history list.

The desired behavior is separate combat history per character, with no more than 30 saved combats for each character.

## Decision

Store combat history in AceDB's character namespace: `db.char.combatHistory`.

Profile-level settings remain in `db.profile`. Only combat history moves to `db.char`, because combat logs are character-specific data while options such as display settings can remain profile-scoped.

The AceDB defaults define `char.combatHistory = {}` so each character has an explicit empty history list by default.

Existing shared `db.profile.combatHistory` is not migrated. After the change, each character starts with an empty character-specific history unless `db.char.combatHistory` already exists.

## Data Flow

On initialization, RLHelper loads `self.combatHistory` from `self.db.char.combatHistory`.

When combat ends and should be saved, RLHelper inserts the combat at the front of `self.combatHistory`, trims the list to 30 items, and writes the trimmed list back to `self.db.char.combatHistory`.

The dropdown, current display, and `ShowCombatByIndex` continue to read from `self.combatHistory`. Clearing history resets both `self.combatHistory` and `self.db.char.combatHistory` for the current character only.

## Compatibility

The old shared `db.profile.combatHistory` remains untouched but is no longer read or updated. This avoids accidentally assigning old mixed-character data to the wrong character.

## Testing

Add or update tests to verify:

- saved combats are written to `db.char.combatHistory`, not `db.profile.combatHistory`;
- history is limited to 30 combats per character;
- initialization loads from `db.char.combatHistory`;
- clearing history clears only character history.
