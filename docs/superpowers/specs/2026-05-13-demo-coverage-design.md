# Demo Coverage Design

## Goal

Make `/rlh demo` show representative persistent battle-log messages for every visible log feature currently implemented by combat trackers.

## Scope

- Cover visible combat-log messages only.
- Do not demo side effects such as Faction Champions automark or Igor death `EMOTE` chat output.
- Keep the existing `RLHelper_Demo` message flow.
- Make surgical changes inside existing tracker modules.

## Design

Add missing `RLHelper_Demo` registrations and `demo()` methods to modules that emit visible log lines but currently have no demo output:

- `PutricideTracker`: Malleable Goo hit, Choking Gas hit, and both summaries.
- `BloodPrincesTracker`: group-five healer vortex hit.
- `BloodQueenTracker`: Bloodbolt Splash hit.
- `TrialCrusaderTracker`: Icehowl trample.

Extend existing demo methods where visible log features are missing:

- `SpellTracker`: first Valithria heal, tracked spell categories not currently shown, druid battle resurrection, Holy Wrath, and a successful dispel.
- `DeathwhisperTracker`: mind control, successful cyclone, missed cyclone, and existing spirit logs.

No new demo framework is needed. Each module will keep formatting through its existing local formatter functions so demo output stays aligned with real tracking output.

## Tests

Add or extend tests for affected modules by calling `module:demo()` with a spy `log` function and asserting representative demo lines are emitted.
