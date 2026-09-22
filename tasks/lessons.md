# Lessons

- When changing journal V2, keep V1 behavior unchanged unless explicitly requested. Rogue pull display in V2 uses the existing spell whitelist and one row per hit, with the damaged target's name; do not extend that change to V1's grouped report.

- Journal V2 must preserve V1 presentation and visible spell filters unless a change is requested. First-damage/heal entries use the V1 wording with the common source/icon prefix. Hunter misdirection totals include all damage, but visible rows use the existing tracked-spell list and exclusions from `master`; verify both live and saved views.
- Journal V2 pull-damage rows use one format for hunters and rogues: time, source name, damage-spell icon, target, and amount; verify both live and saved views.
- All Journal V2 rows use the same prefix order: time, source name when available, spell icon when available, then the message; omit absent fields without leaving empty placeholders.
- Misdirection summary rows use the message `Напул окончен <amount>` after the source and pull icon; do not include the pull target in the summary row.
- Classify Distracting Shot (`20736`) with the current taunt rules: a known non-tank taunting a known boss during combat is a violation; casts on ordinary mobs are informational. Tank assignments include both MAINTANK and MAINASSIST.
- For Distracting Shot, record only `SPELL_CAST_SUCCESS`; ignore the resulting aura event to avoid duplicate journal rows.
- First-damage rows always use `Interface\\Icons\\Ability_SteelMelee`, independent of the combat-log spell icon.
- TAUNT rows omit the textual `Провокация`; the spell icon identifies the taunt and only the target remains after it.
+ V2 player names use the standard WoW 3.3.5a class colors from the class token persisted when the event is created; unknown classes remain white.
+ Prefer `sourceClass`/`destClass` from the event, then resolve and persist a missing class at event creation; never resolve class while rendering saved history.
- Render `TACTIC_VIOLATION` message text in red without adding a violation label, while keeping the time white and the source name in its class color; embedded message colors or resets must not override the event color.

- When an update adds addon files or changes the TOC, tell the user to fully restart WoW 3.3.5a before testing; `/reload` is only sufficient for switching journal versions after those files are loaded. For `mainFrame == nil` during OnEnable, inspect the earlier OnInitialize error first: an unloaded Journal dependency can prevent frame creation.

- In bug reports, preserve the user's uncertainty and specific observed result. For Lady's spirit explosions, record that only one of two explosions appeared in the addon; simultaneous timing is suspected, not confirmed.

- When release packaging omits a file or directory, first add its copy command to the existing Makefile. Do not replace the build process or add scripts, validation infrastructure, or CI changes unless explicitly requested. The user rejected that expansion for issue #2.
- AceEvent handlers receive the event name before its payload. Tests must pass that argument too; calling a boss yell handler with only the message can hide a handler that never works in-game.
- For Halion's first-cutter entry countdown on Isengard, anchor to the phase-two transition using DBM-RS's initial schedule. The cutter yell triggered the countdown about 15 seconds late in the user's raid; do not assume Warmane-specific yell timing applies here. Verify elapsed start/end times in tests and distinguish DBM estimates from in-game confirmation.
- Keep journal filters to All, Errors, and Misdirection, as chosen by the user. Include tracked Halion mechanic deaths in Errors. Do not propose separate Deaths or Abilities filters without a new use case: ordinary abilities remain in All and flagged violations also appear in Errors.

- Resolve ambiguous spell nicknames by the explicit SpellID before applying error rules. Righteous Defense (`31789`) on an assigned tank during combat is a violation when cast by another known non-tank; another assigned tank is allowed to use it for a tank swap. Hand of Protection (`10278`) on an assigned tank during combat is a violation regardless of the caster’s tank assignment. Check both source and target roles; do not infer safety from the target alone.
