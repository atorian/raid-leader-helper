# Character Combat History Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Store RLHelper combat history separately for each character and keep at most 30 saved combats per character.

**Architecture:** Keep profile-scoped addon settings in `db.profile`, but move combat history to AceDB's character namespace `db.char.combatHistory`. Runtime UI continues to use `RLHelper.combatHistory`, which is loaded from and persisted to the current character's history list.

**Tech Stack:** Lua 5.1, WoW 3.3.5a addon APIs, AceDB-3.0, Busted tests.

---

## File Structure

- Modify `Core.lua`: add `defaults.char.combatHistory`, change initialization, save, and clear paths from `db.profile.combatHistory` to `db.char.combatHistory`; change history cap from 50 to 30.
- Modify `tests/CombatSystem.test.lua`: set up `db.char` in test fixtures and add behavior tests for per-character persistence and the 30-combat cap.

## Task 1: Character-Scoped Persistence

**Files:**
- Modify: `tests/CombatSystem.test.lua`
- Modify: `Core.lua`

- [ ] **Step 1: Write failing tests for character history storage**

In `tests/CombatSystem.test.lua`, update the `before_each` fixture in `describe("Боевая система", function()` so `RLHelper.db` includes both `profile` and `char`:

```lua
RLHelper.db = {
    profile = {
        debug = false,
        combatHistory = {},
        bossOnlyHistory = false
    },
    char = {
        combatHistory = {}
    }
}
```

Then add this test near the existing save-history tests:

```lua
it("сохраняет историю боев в хранилище текущего персонажа", function()
    RLHelper:PLAYER_REGEN_DISABLED()
    RLHelper:OnCombatLogEvent("test message")

    M.UnitAffectingCombat1 = false
    RLHelper.lastCombatActivityAt = RLHelper:GetCombatNow() - 10
    RLHelper.combatEndRequestedAt = RLHelper:GetCombatNow() - 5

    assert.is_true(RLHelper:EvaluateCombatEnd("test"))
    assert.are.equal(1, #RLHelper.combatHistory)
    assert.are.equal(1, #RLHelper.db.char.combatHistory)
    assert.are.equal("test message", RLHelper.db.char.combatHistory[1].messages[1])
    assert.are.equal(0, #RLHelper.db.profile.combatHistory)
end)
```

- [ ] **Step 2: Run the targeted test and verify RED**

Run:

```bash
busted --verbose ./tests/CombatSystem.test.lua
```

Expected: the new test fails because `SaveCombatToProfile` still writes to `RLHelper.db.profile.combatHistory`, leaving `RLHelper.db.char.combatHistory` empty.

- [ ] **Step 3: Implement minimal character storage**

In `Core.lua`, add character defaults next to the existing `profile` defaults:

```lua
local defaults = {
    profile = {
        enabled = true,
        debug = false,
        pullCancelMessage = "ГАЛЯ, ОТМЕНА!",
        displayOnlyInGroup = false,
        bossOnlyHistory = false,
        igor = false,
        halionBurstPull = false,
        halionBurstReset = true,
        halionPhaseTwoEntryTimer = false,
        minimap = {
            hide = false
        },
        savedPosition = nil
    },
    char = {
        combatHistory = {}
    }
}
```

Then update initialization to load from `db.char.combatHistory` instead of `db.profile.combatHistory`:

```lua
-- Load combat history from character DB
local combatHistory = self.db.char and self.db.char.combatHistory or {}
for _, combat in ipairs(combatHistory) do
    table.insert(self.combatHistory, {
        startTime = combat.startTime,
        endTime = combat.endTime,
        messages = combat.messages,
        firstEnemy = combat.firstEnemy,
        isBoss = combat.isBoss
    })
end
```

Replace `SaveCombatToProfile` with character persistence while keeping the public function name to minimize call-site churn:

```lua
function RLHelper:SaveCombatToProfile(combat, profile)
    table.insert(self.combatHistory, 1, combat)

    while #self.combatHistory > 30 do
        table.remove(self.combatHistory)
    end

    local charDb = self.db.char
    charDb.combatHistory = {}
    for _, savedCombat in ipairs(self.combatHistory) do
        table.insert(charDb.combatHistory, savedCombat)
    end
end
```

The unused `profile` parameter remains for now because `FinishCombat` already passes `self.db.profile`, and removing it is unnecessary for this behavior change.

- [ ] **Step 4: Run the targeted test and verify GREEN**

Run:

```bash
busted --verbose ./tests/CombatSystem.test.lua
```

Expected: `CombatSystem.test.lua` passes.

## Task 2: Limit and Clear Character History

**Files:**
- Modify: `tests/CombatSystem.test.lua`
- Modify: `Core.lua`

- [ ] **Step 1: Write failing tests for the 30-combat cap and clearing character history**

In `tests/CombatSystem.test.lua`, add these tests near the save-history tests:

```lua
it("ограничивает историю текущего персонажа тридцатью боями", function()
    for i = 1, 31 do
        RLHelper:SaveCombatToProfile({
            startTime = i,
            endTime = i + 1,
            messages = { "combat " .. i },
            firstEnemy = "Enemy " .. i,
            isBoss = false
        }, RLHelper.db.profile)
    end

    assert.are.equal(30, #RLHelper.combatHistory)
    assert.are.equal(30, #RLHelper.db.char.combatHistory)
    assert.are.equal("Enemy 31", RLHelper.combatHistory[1].firstEnemy)
    assert.are.equal("Enemy 2", RLHelper.combatHistory[30].firstEnemy)
end)

it("очищает историю только текущего персонажа", function()
    RLHelper.combatHistory = {
        {
            startTime = 1,
            endTime = 2,
            messages = { "combat" },
            firstEnemy = "Enemy",
            isBoss = false
        }
    }
    RLHelper.db.char.combatHistory = RLHelper.combatHistory
    RLHelper.db.profile.combatHistory = {
        {
            startTime = 10,
            endTime = 11,
            messages = { "old shared combat" },
            firstEnemy = "Old Enemy",
            isBoss = false
        }
    }

    RLHelper:ClearCombatHistory()

    assert.are.equal(0, #RLHelper.combatHistory)
    assert.are.equal(0, #RLHelper.db.char.combatHistory)
    assert.are.equal(1, #RLHelper.db.profile.combatHistory)
end)
```

- [ ] **Step 2: Run targeted tests and verify RED**

Run:

```bash
busted --verbose ./tests/CombatSystem.test.lua
```

Expected before implementation: the clear-history test fails because `ClearCombatHistory` still clears `db.profile.combatHistory`.

- [ ] **Step 3: Update clear history to character storage**

In `Core.lua`, change `ClearCombatHistory` to clear `db.char.combatHistory`:

```lua
function RLHelper:ClearCombatHistory()
    self.combatHistory = {}
    self.db.char.combatHistory = {}
    self:Print("История боев очищена")
end
```

- [ ] **Step 4: Run targeted tests and verify GREEN**

Run:

```bash
busted --verbose ./tests/CombatSystem.test.lua
```

Expected: all `CombatSystem.test.lua` tests pass.

## Task 3: Full Verification and Commit

**Files:**
- Verify: `Core.lua`
- Verify: `tests/CombatSystem.test.lua`
- Verify: `docs/superpowers/specs/2026-05-17-character-combat-history-design.md`
- Verify: `docs/superpowers/plans/2026-05-17-character-combat-history.md`

- [ ] **Step 1: Run the full test suite**

Run:

```bash
make test
```

Expected: all tests pass with `0 failures / 0 errors`.

- [ ] **Step 2: Review the diff**

Run:

```bash
git diff -- Core.lua tests/CombatSystem.test.lua docs/superpowers/specs/2026-05-17-character-combat-history-design.md docs/superpowers/plans/2026-05-17-character-combat-history.md
```

Expected: diff only contains character-scoped combat history storage, limit change to 30, tests, and planning docs.

- [ ] **Step 3: Commit after user approval**

Only commit if the user explicitly asks to commit. Use:

```bash
git add Core.lua tests/CombatSystem.test.lua docs/superpowers/specs/2026-05-17-character-combat-history-design.md docs/superpowers/plans/2026-05-17-character-combat-history.md
git commit -m "fix: store combat history per character"
```

Expected: commit succeeds and `git status --short` shows a clean worktree.

## Self-Review

- Spec coverage: the plan moves history to `db.char.combatHistory`, starts without migrating old shared history, trims to 30 combats, updates clear behavior, and adds tests for all specified requirements.
- Placeholder scan: no TBD/TODO placeholders remain.
- Type consistency: all tasks use existing Lua tables and the existing `RLHelper:SaveCombatToProfile(combat, profile)` call shape to avoid unrelated call-site changes.
