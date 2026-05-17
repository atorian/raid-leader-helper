---
name: rlhelper-release
description: Use when releasing RLHelper, running /release, bumping RLHelper.toc Version, creating git tags, pushing tags, or preparing Russian release notes.
---

# RLHelper Release

Use the bundled script for release mechanics. Do not infer versions, choose fallback ranges, or run release git commands manually.

## Workflow

1. Prepare release data:

```bash
python3 .opencode/skills/rlhelper-release/scripts/release.py prepare
```

If the script exits non-zero, stop and ask the user how to proceed. Do not invent a workaround.

2. Draft the Russian release message from the commits and file summary printed by the script:

```markdown
## Что нового
- <new features>

## Что исправлено
- <bug fixes>
```

Use concrete changes only. If a section has no items, write `- Нет.`.

3. Present the proposed `next_tag` and the Russian release message to the user. Ask for approval before changing files, committing, tagging, or pushing.

4. After approval, run:

```bash
python3 .opencode/skills/rlhelper-release/scripts/release.py apply --tag <next_tag>
```

5. Report the script output and the final Russian release message.

## Rules

- The script is the source of truth for the next version tag.
- The agent only prepares the release message and passes the approved tag to the script.
- No fallbacks. If branch, worktree, tag history, version state, or remote state is unclear, ask the user.
- Do not create or edit GitHub releases. GitHub automation handles draft release creation after the tag push.
- Do not force-push, amend, hard-reset, or use destructive git commands.
