# Lessons

- When release packaging omits a file or directory, first add its copy command to the existing Makefile. Do not replace the build process or add scripts, validation infrastructure, or CI changes unless explicitly requested. The user rejected that expansion for issue #2.
- AceEvent handlers receive the event name before its payload. Tests must pass that argument too; calling a boss yell handler with only the message can hide a handler that never works in-game.
- For Halion's first-cutter entry countdown on Isengard, anchor to the phase-two transition using DBM-RS's initial schedule. The cutter yell triggered the countdown about 15 seconds late in the user's raid; do not assume Warmane-specific yell timing applies here. Verify elapsed start/end times in tests and distinguish DBM estimates from in-game confirmation.
