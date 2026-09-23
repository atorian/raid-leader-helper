# Lessons

- The structured journal is the only supported journal. Do not restore version commands, switches, string-history rendering, or per-module demos. On initialization, remove obsolete history and version settings across saved characters/profiles while preserving structured history and unrelated settings.

- Preserve journal presentation and visible spell filters unless a change is requested. First-damage/heal entries use the common source/icon prefix. Hunter misdirection totals include all damage, but visible rows use the existing tracked-spell list and exclusions from `master`; verify both live and saved views.
- Journal V2 pull-damage rows use one format for hunters and rogues: time, source name, damage-spell icon, target, and amount; verify both live and saved views.
- All Journal V2 rows use the same prefix order: time, source name when available, spell icon when available, then the message; omit absent fields without leaving empty placeholders.
- Misdirection summary rows use the message `Напул окончен <amount>` after the source and pull icon; do not include the pull target in the summary row.
- Classify Distracting Shot (`20736`) with the current taunt rules: a known non-tank taunting a known boss during combat is a violation; casts on ordinary mobs are informational. Tank assignments include both MAINTANK and MAINASSIST.
- For Distracting Shot, record only `SPELL_CAST_SUCCESS`; ignore the resulting aura event to avoid duplicate journal rows.
- First-damage rows always use `Interface\\Icons\\Ability_SteelMelee`, independent of the combat-log spell icon.
- TAUNT rows omit the textual `Провокация`; the spell icon identifies the taunt and only the target remains after it.
+ V2 player names use the standard WoW 3.3.5a class colors from the class token persisted when the event is created; unknown classes remain white.
+ Prefer `sourceClass`/`destClass` from the event, then resolve and persist a missing class at event creation; never resolve class while rendering saved history.
- In plain formatted text, render `TACTIC_VIOLATION` messages red with white time and class-colored player. In the V2 All view, highlight every entry that appears in Errors (including mechanic deaths and vortex hits, but excluding summaries) with a dark red row background; in Errors-only, omit that background and render violation messages white, preserving class-colored player names. Keep the message legible and do not add a violation label.

- When an update adds addon files or changes the TOC, tell the user to fully restart WoW 3.3.5a before testing; `/reload` is sufficient for updates to already loaded addon files. For `mainFrame == nil` during OnEnable, inspect the earlier OnInitialize error first: an unloaded Journal dependency can prevent frame creation.

- In bug reports, preserve the user's uncertainty and specific observed result. For Lady's spirit explosions, record that only one of two explosions appeared in the addon; simultaneous timing is suspected, not confirmed.

- When release packaging omits a file or directory, first add its copy command to the existing Makefile. Do not replace the build process or add scripts, validation infrastructure, or CI changes unless explicitly requested. The user rejected that expansion for issue #2.
- AceEvent handlers receive the event name before its payload. Tests must pass that argument too; calling a boss yell handler with only the message can hide a handler that never works in-game.
- For Halion's first-cutter entry countdown on Isengard, anchor to the phase-two transition using DBM-RS's initial schedule. The cutter yell triggered the countdown about 15 seconds late in the user's raid; do not assume Warmane-specific yell timing applies here. Verify elapsed start/end times in tests and distinguish DBM estimates from in-game confirmation.
- Keep journal filters to All, Errors, and Misdirection, as chosen by the user. Include tracked Halion mechanic deaths in Errors. Do not propose separate Deaths or Abilities filters without a new use case: ordinary abilities remain in All and flagged violations also appear in Errors.

- Resolve ambiguous spell nicknames by the explicit SpellID before applying error rules. Righteous Defense (`31789`) on an assigned tank during combat is a violation when cast by another known non-tank; another assigned tank is allowed to use it for a tank swap. Hand of Protection (`10278`) on an assigned tank during combat is a violation regardless of the caster’s tank assignment. Check both source and target roles; do not infer safety from the target alone.

- The minimalist theme must retain the existing window background and its transparency. The user explicitly prefers the current background; limit theme changes to controls, text, spacing, and selected-filter styling.

- Theme startup must not rely on a newly added TOC entry being loaded by an already running client. Initialize the theme with Core, share it through the addon, and test startup/resizing without preloading a separate theme file in mocks.

- Do not display an addon-name heading in the RLHelper window or reserve a header row for it. Removing a heading must reclaim its space in every theme.

- Theme application must be idempotent: never hide an already assigned button texture when reapplying the same theme. Test first display and repeated application before any clicks. Minimize and anchor (A) controls must keep empty backgrounds in every theme and button state.

- `/rlh demo` for V2 must use fixed fictional players but mirror real tracker event shapes: a harmful spell may have the boss or no source and the player as target, while a combat summary has no invented source. Show the relevant player in class color when available, keep the demo independent of the current character, and make all three filters explorable from any selected combat.
- A journal overlay that receives mouse input must forward window dragging from both filled rows and empty scroll space. Verify scrolling and tooltips still work.
- Do not use unsupported Unicode glyphs or fabricated target suffixes in WoW 3.3.5a journal messages. Compare demo examples against tracker output and targeted real combat-log samples before presenting them.
- V2 uses 20px icons after the user requested a small increase from 18px; keep a compact 21px minimum row, a 1px measured-height allowance, and allow wrapping.
- The V2 demo should include two Lady Deathwhisper spirit hits with a summary and two Halion blade deaths, using the real source/target shapes (`Мстительный дух` SWING_DAMAGE and `Темный шар` SPELL_DAMAGE followed by player UNIT_DIED). Match each demo entry's fields, text, and icon to what the tracker actually emits; do not add demo-only annotations. Compare the demo entries to records produced by the handlers in tests.

- V2 summaries are informational totals, not tactical errors: exclude spirit/goo/gas summaries from Errors and red backgrounds. Tracked Halion mechanic deaths and vortex hits on healers are violations; vortex misses remain informational. Keep demo severity and filters consistent with real tracker output.

- Distinguish Lady Deathwhisper Cyclone (`CYCLONE_APPLIED`/`CYCLONE_MISSED`, informational) from Blood Princes knockbacks (`VORTEX_HIT`, violation; misses informational). Do not classify by the ambiguous nickname «вихрь».
- V2 demo must cover every journal kind and every tracked SpellTracker ability, including dispels and resurrects, plus hunter and rogue pulls; keep its records consistent with live tracker shapes.
- Align the top controls and GP footer to the same 2px side margins; V2 row text has no extra horizontal inset.

- V2 journal rows run oldest to newest from top to bottom. Each newly displayed event immediately scrolls to the bottom, even after manual scrolling; opening a combat or filter also shows the latest matching rows. Preserve the newest 1000 matching events when limiting rendered rows.
