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
- The V2 demo should cover one Lady Deathwhisper spirit hit with a summary and one Halion mechanic death, using the real source/target shapes (`Мстительный дух` SWING_DAMAGE and `Темный шар` SPELL_DAMAGE followed by player UNIT_DIED). Match each demo entry's fields, text, and icon to what the tracker actually emits; do not add demo-only annotations. Compare the demo entries to records produced by the handlers in tests.

- V2 summaries are informational totals, not tactical errors: exclude spirit/goo/gas summaries from Errors and red backgrounds. Tracked Halion mechanic deaths and vortex hits on healers are violations; vortex misses/immunities on healers are violations too. Keep demo severity and filters consistent with real tracker output.

- Distinguish Lady Deathwhisper Cyclone (`CYCLONE_APPLIED`/`CYCLONE_MISSED`, informational) from Blood Princes knockbacks (`VORTEX_HIT`, violation; misses/immunities on healers are violations too). Do not classify by the ambiguous nickname «вихрь».
- Demo is a visual introduction for players: show exactly one example per journal event kind. Cover all spell IDs, ranks, classes and mechanic variants in automated tests, not by multiplying demo rows. Keep samples generated by normal module handlers.
- Align the top controls and GP footer to the same 2px side margins; V2 row text has no extra horizontal inset.

- V2 journal rows run oldest to newest from top to bottom. Each newly displayed event immediately scrolls to the bottom, even after manual scrolling; opening a combat or filter also shows the latest matching rows. Preserve the newest 1000 matching events when limiting rendered rows.

- A repeatable client crash during theme switching is not covered by Lua frame mocks. Avoid detaching and reusing button-owned Texture objects: change their contents in place, preserve the original texture path/blend, and leave visibility to the button state. Test repeated switches and missing template textures, and require an in-client retest before claiming the native crash is fixed. The user confirmed on 2026-09-23 that updating texture contents in place resolved the repeatable crash.

- Mechanic deaths use a skull prefix and a specific cause followed by the mechanic icon. Spell-less Lady spirit melee events need a fixed spirit icon. Demo starts in All so informational druid Cyclone control is visible even after Errors was selected.

- Release notes must compare the final version with the previous published tag and its release description. Omit fixes for regressions introduced and resolved only during unreleased development, temporary switches, reverts, test counts, and unchanged capabilities. Describe user-visible differences.

- In WoW 3.3.5a, a hardware click plus InCombatLockdown guard does not authorize direct TargetUnit calls: the client blocked this outside combat. Use SecureActionButtonTemplate with a nocombat action and secure combat hiding. Keep protected controls independent of the updating journal hierarchy; mocks must reject direct targeting, and client validation is still required. The user confirmed on 2026-09-24 that the independent secure button fixed targeting in the client.

- When adding details to demo events, update every example of that event kind, including loop-generated records. Verify the actual rendered V2 rows for all examples, with spell lookup unavailable; persist explicit effect names in dispel examples.

- Halion LIGHT_DAMAGE_WINDOW_CLOSED rows show the triggering Heroism/Bloodlust icon after the standard time/source prefix, without the technical window-closed message or target name. Apply this to live, saved, and demo records.

- `/rlh demo` must feed sample combat events into isolated module handlers; modules own their scenarios and publish normal journal entries. Never hardcode journal kinds, severity or summary text in Core. Re-running replaces the separate demo view, preserves live tracker/combat state, and cannot send chat, start pulls or reset meters. Show each journal event kind once; exhaustive ID and variant coverage belongs in tests.

- Bear taunts must include Growl (`6795`) as well as Challenging Roar (`5209`); verify spell IDs against the Isengard database and test party events through Core to the journal. `5209` is not Growl.

- Show damage amounts only for misdirection damage and pull summaries. Other journal events show the occurrence without damage, including saved history and demo rows; preserve stored amounts and mechanic occurrence counts.

- TRAMPLE_HIT records use the hit player as source. Render exactly time, player, mechanic icon, and «Не отбежал с пути босса»; no boss, repeated target or damage. Resolve older records to their target player for display and secure click targeting even when class is unknown.

- Both VORTEX_HIT and VORTEX_MISSED show «Откунул вихрем хила: <target>» after the time/source/icon prefix; omit damage and miss type, including saved history and demo. When changing wording, retain the target unless explicitly asked to remove it: the user corrected its removal from vortex rows.

- Halion mechanic deaths attribute the underlying lethal mistake, not only the final damage event. The user explicitly counts cutter hits, meteor impact, and meteor fire followed by death from the aura or another hit as mechanic deaths. Do not label intervening damage a false positive or require a mechanic killing blow; assess whether the relevant hit is retained until UNIT_DIED.

- Name Blood Queen BLOODBOLT_SPLASH «Кровавый всплеск» in the journal; do not use «Сплеш» or «Сплэш».

- GP reason settings must show the existing defaults immediately after field creation and on reopening. Empty or whitespace-only saved input must resolve to the same default used by GP buttons; preserve custom reasons. Test initial fields without manually invoking OnShow.

- Empty-looking settings are not proof of empty SavedVariables. Inspect the relevant saved keys and distinguish persisted state from the running client before claiming a root cause. A passing field-initialization test does not confirm an in-client display fix; establish whether the screenshot follows /reload. On 2026-09-26 the user confirmed the GP fields remained blank after /reload with the initialization fix; inspect live GetText/font/color before attempting another visual fix. The 2026-09-26 client returned `Каспер`, a valid font and white text while the GP field looked blank; treat this as a rendering/layout problem and require a client retest for any layout fix.

- On 2026-09-26, the user confirmed explicit text insets made GP reason text visible but 8 px on the left looked too wide. Keep a small left inset near the input border, and verify the client appearance after spacing changes.

- Sindragosa Backlash explosions above two Instability stacks are tactical errors; one or two stacks remain informational. Apply the threshold to confirmed explosions only, including demo records, and test the 2/3 boundary. Meter switching must cover both Skada NewSegment and Recount ResetFightData, as in Halion.

- For missing journal auto-wrap, check the visible V2 FontString itself: measuring taller rows does not make text wrap. Give each displayed FontString an explicit width and automatic height so WoW 3.3.5a performs its native word wrapping; avoid manual line splitting and confirm appearance in the client.

- For release requests, use the user's stated bump type and the latest published tag to compute the exact next version before any release action. The user corrected a minor bump after v0.5.1 to a patch bump: release v0.5.2, not v0.6.0.

- EP awards apply to the entire current raid and EPGP-selected standby through EPGP’s mass-award method, giving selected standby the same full amount as active players regardless of EPGP standby percentage. Do not modify EPGP settings, and restore any temporary API adaptation even when an award fails. Never reject selected standby or impose a raid-only filter. Do not snapshot rosters, track individual recipients, or add catch-up workflows for attendance: the reminder appears at local RT time, and the RL controls when to award and who is present. Raid rewards use one amount per raid regardless of size/difficulty; design for the usual single gathering per day (about four hours), without introducing session management by default.

- EP controls belong to a section in the common settings, not a separate category or a settings button in the award window. Hide reward rows when their reminder is disabled and collapse gaps. EP windows use the addon’s borderless background. Give each InputBoxTemplate edit box a unique name and explicit width: unnamed amount fields rendered with missing middle textures in the user’s client; confirm the fix in-game. Defaults are attendance 1000, ICC 7000, RS 3000 and Trial/Anubarak 2000; preserve saved custom amounts.

- When an EP default appears missing, inspect the saved amount before changing fallback logic. On 2026-09-27, ICC displayed 0 because the saved profiles explicitly contained icc = 0 while the code default was 7000. Preserve explicit zero as a valid disabled reward; distinguish it from an unset amount. Attendance defaults to 1000 EP, as explicitly requested.

- Keep EP settings inputs close to their short labels: use a 150px input-column offset, not 260px. The wider gap pushed reminder checkboxes beyond the visible settings area in the user’s client. Preserve the shortened local-RT label.

- Manual EP award buttons must always remain enabled, including after a prior award or without raid leadership. Previous awards suppress automatic reminders only; allow deliberate manual repeats and show the last result separately from the action label. Keep execution checks for a raid, positive amount and EPGP permissions; never accidentally invoke its whole-guild fallback outside a raid.

- Release archives are owned by the CI pipeline. Do not build, upload, replace or delete release archives manually; commit and push source changes and let the existing pipeline handle packaging. The user explicitly corrected manual archive updates on 2026-09-27.

- Saurfang DPS EP thresholds are per specialization, not per class (e.g. Arms/Fury and Frost/Unholy). Save the spec, DPS and applicable threshold from the winning fight; never infer a threshold from class alone.

- Lady spirit SWING_MISSED (including ABSORB/BLOCK) does not consume the tracked spirit: real logs show repeated misses followed by SWING_DAMAGE and Vengeful Blast from the same GUID. Keep tracking through all attacks until Vengeful Blast is confirmed by SPELL_DAMAGE or SPELL_MISSED. Credit the last attack target (GUID/name/class), never a splash victim; count each spirit once. Neither an absorbed nor a damaging autoattack alone confirms an explosion.

- For window-drag bug reports, treat pixel distances as approximate unless measured: the user clarified that the reported ~300px jump is not a fixed offset. Preserve native WoW StartMoving/StartSizing for this fix, as explicitly chosen; guard repeated starts and missing mouse-up without replacing coordinate handling.

- Aura Mastery has no combat-log target: show the casting paladin's selected aura, never a target placeholder. Track aura sources separately from recipients, retain selections across combat resets, and persist the aura name for saved history; use an explicit unknown label when evidence is missing.

- Before choosing a release version, check the source version and existing draft releases as well as published tags. Never downgrade the source version based only on the latest published tag. When the user identifies an existing draft, update that release and preserve its URL; let CI replace its archive.

- Opening the Saurfang DPS award window must hide the general EP award window. Closing the DPS window must not reopen the general window.

- The existing GP enable setting controls the entire GP/EP feature. When off, hide EP windows/button, stop reminders and Skada DPS collection, and preserve already saved results. Re-enable immediately without reload.

- For Codex ENOENT in WSL, inspect the exact missing executable and distinguish agent, sandbox and Windows MCP runtimes. On 2026-10-03 an isolated test confirmed Windows Codex 0.159.0-alpha.12.1 deletes an active Linux Codex tmp/arg0 directory when both share CODEX_HOME on NTFS. Restart alone did not fix recurrence; do not promise it will. Diagnose shared-home cleanup before recommending environment switches. Windows-format attachment/MCP paths are a separate issue.

- When editing global Codex instructions for Windows from WSL, use /mnt/c/Users/atori/.codex/AGENTS.md and identify it to the user as C:\Users\atori\.codex\AGENTS.md. Verify through Windows when needed; do not confuse it with the separate Linux ~/.codex/AGENTS.md.

- Boss DPS settings extend the existing per-specialization Saurfang thresholds. When adding configurable bosses, preserve spec-specific values, existing Saurfang settings/results, and avoid assuming one shared DPS threshold per boss. The user chose per-spec thresholds on 2026-10-06.

- Keep the DPS boss dropdown compact (220px) and place Add/Remove immediately beside it (x=247). The 275px dropdown pushed the action buttons beyond the visible settings area in the user’s 2026-10-06 screenshot; verify the whole row in the client, not only the nominal content width.

- For Putricide EP rewards, do not assume the existing spec DPS threshold and the per-ooze damage threshold are cumulative requirements. The user corrected this: there is one DPS award with a choice of threshold, boss DPS or total damage to oozes. The RL explicitly selects the condition in settings; do not use AND/OR eligibility or create a second award.

- For Putricide EP thresholds, «слизни» includes both Volatile Ooze (37697) and Gas Cloud (37562). Count each spawn GUID, but compare combined damage to all oozes against spawn count × configured damage per spawn. Reduce the player’s total threshold by 100000 for each Gas Cloud targeting (SPELL_AURA_APPLIED of Gaseous Bloat), clamped at zero; ticks, refreshes and stack changes do not add reductions. Show combined damage and the reduced personal threshold. The user corrected the per-ooze minimum on 2026-10-10: four spawns and one gas targeting require 300000 at the default setting.

- Anchored InterfaceOptions category panels can report zero viewport width during addon initialization. Measure scrollFrame:GetWidth() again on settings OnShow; use the documented 375px viewport only until the anchored width becomes positive. Test creation at width 0 followed by opening/resizing. On 2026-10-10 the user screenshot showed only the DPS selector’s left border after an initialization-time width calculation.
