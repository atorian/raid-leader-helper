# Lessons

- When changing journal V2, keep V1 behavior unchanged unless explicitly requested. Rogue pull display in V2 uses the existing spell whitelist and one row per hit, with the damaged target's name; do not extend that change to V1's grouped report.

- Journal V2 must preserve V1 presentation and visible spell filters unless a change is requested. First-damage/heal entries use the V1 wording without a spell icon. Hunter misdirection totals include all damage, but visible rows use the existing tracked-spell list and exclusions from `master`; verify both live and saved views.
- Render `TACTIC_VIOLATION` messages in red throughout; embedded name colors or resets must not override the event color.

- When an update adds addon files or changes the TOC, tell the user to fully restart WoW 3.3.5a before testing; `/reload` is only sufficient for switching journal versions after those files are loaded. For `mainFrame == nil` during OnEnable, inspect the earlier OnInitialize error first: an unloaded Journal dependency can prevent frame creation.

- In bug reports, preserve the user's uncertainty and specific observed result. For Lady's spirit explosions, record that only one of two explosions appeared in the addon; simultaneous timing is suspected, not confirmed.

- When release packaging omits a file or directory, first add its copy command to the existing Makefile. Do not replace the build process or add scripts, validation infrastructure, or CI changes unless explicitly requested. The user rejected that expansion for issue #2.
- AceEvent handlers receive the event name before its payload. Tests must pass that argument too; calling a boss yell handler with only the message can hide a handler that never works in-game.
- For Halion's first-cutter entry countdown on Isengard, anchor to the phase-two transition using DBM-RS's initial schedule. The cutter yell triggered the countdown about 15 seconds late in the user's raid; do not assume Warmane-specific yell timing applies here. Verify elapsed start/end times in tests and distinguish DBM estimates from in-game confirmation.
