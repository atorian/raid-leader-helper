# Faction Champions Yell Automark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Start Trial of the Crusader Faction Champions automarking from the captured Russian Tirion Fordring yell and remove the manual `/rlh tocmarks` command.

**Architecture:** Reuse the existing `TrialCrusaderTracker` boss-message activation path by populating `FACTION_CHAMPION_START_FRAGMENTS` with the exact phrase. Handle AceEvent callbacks as `(eventName, message, sender)`, and start automark only from `CHAT_MSG_MONSTER_YELL`; raid boss emotes remain debug-only. Remove only the slash-command wrapper from `Core.lua`; the automark implementation remains in the tracker.

**Tech Stack:** Lua addon code for WoW 3.3.5a, AceAddon/AceEvent, Busted tests, Makefile test target.

---

## File Structure

- Modify `modules/bosses/TrialCrusaderTracker.lua`: set the known Faction Champions start phrase in `FACTION_CHAMPION_START_FRAGMENTS`, fix AceEvent handler argument order, and restrict automark startup to `CHAT_MSG_MONSTER_YELL`.
- Modify `Core.lua`: remove `TriggerTrialCrusaderAutomark()`, remove `/rlh tocmarks` help text, and remove the `tocmarks` slash branch.
- Modify `tests/TrialCrusaderTracker.test.lua`: add a focused test for the exact Russian yell.
- Modify `tests/Core.test.lua`: remove the obsolete manual command test block.

### Task 1: Add Failing Yell Trigger Test

**Files:**
- Modify: `tests/TrialCrusaderTracker.test.lua`

- [ ] **Step 1: Replace the configurable-fragment test with the real phrase test**

Change the test near the existing boss-message tests to:

```lua
    it('starts automark when Tirion announces Faction Champions', function()
        local started = TrialCrusaderTracker:CHAT_MSG_MONSTER_YELL(
            "В следующем бою вы встретитесь с могучими рыцарями Серебряного Авангарда! Лишь победив их, вы заслужите достойную награду.",
            "Тирион Фордринг")

        assert.is_true(started)
        assert.are.equal(GetTime() + 180, TrialCrusaderTracker.factionChampionAutomarkActiveUntil)
    end)
```

- [ ] **Step 2: Run the focused test and verify it fails**

Run: `busted --verbose ./tests/TrialCrusaderTracker.test.lua`

Expected: the new test fails because `FACTION_CHAMPION_START_FRAGMENTS` is still empty by default.

### Task 2: Configure the Real Boss Yell Trigger

**Files:**
- Modify: `modules/bosses/TrialCrusaderTracker.lua`
- Test: `tests/TrialCrusaderTracker.test.lua`

- [ ] **Step 1: Add the exact trigger phrase**

Change:

```lua
local FACTION_CHAMPION_START_FRAGMENTS = {}
```

to:

```lua
local FACTION_CHAMPION_START_FRAGMENTS = {
    "В следующем бою вы встретитесь с могучими рыцарями Серебряного Авангарда! Лишь победив их, вы заслужите достойную награду."
}
```

- [ ] **Step 2: Run the focused tracker test and verify it passes**

Run: `busted --verbose ./tests/TrialCrusaderTracker.test.lua`

Expected: all `TrialCrusaderTracker` tests pass.

### Task 3: Remove Manual Slash Command

**Files:**
- Modify: `Core.lua`
- Modify: `tests/Core.test.lua`

- [ ] **Step 1: Remove the obsolete Core command test**

Delete this whole describe block from `tests/Core.test.lua`:

```lua
describe("RLHelper Trial Crusader automark command", function()
    local originalFindModuleByName

    before_each(function()
        originalFindModuleByName = RLHelper.FindModuleByName
    end)

    after_each(function()
        RLHelper.FindModuleByName = originalFindModuleByName
    end)

    it("handles the slash tocmarks command", function()
        local startCalls = 0
        RLHelper.FindModuleByName = function(_, moduleName)
            assert.are.equal("TrialCrusaderTracker", moduleName)
            return {
                StartFactionChampionAutomark = function()
                    startCalls = startCalls + 1
                    return true
                end
            }
        end

        RLHelper:HandleSlashCommand("tocmarks")

        assert.are.equal(1, startCalls)
    end)
end)
```

- [ ] **Step 2: Remove the manual trigger function and slash branch**

Delete `RLHelper:TriggerTrialCrusaderAutomark()` from `Core.lua`.

Delete this help line:

```lua
        print("/rlh tocmarks - включить метки Faction Champions на 180 секунд")
```

Delete this branch:

```lua
    elseif input == "tocmarks" then
        self:TriggerTrialCrusaderAutomark()
```

- [ ] **Step 3: Run focused Core tests**

Run: `busted --verbose ./tests/Core.test.lua`

Expected: all `Core` tests pass.

### Task 4: Full Verification

**Files:**
- Verify all modified files.

- [ ] **Step 1: Run the full Lua test suite**

Run: `make test`

Expected: Busted reports all tests passing.

- [ ] **Step 2: Check the final diff**

Run: `git diff -- Core.lua modules/bosses/TrialCrusaderTracker.lua tests/Core.test.lua tests/TrialCrusaderTracker.test.lua docs/superpowers/specs/2026-05-02-faction-champions-yell-automark-design.md docs/superpowers/plans/2026-05-02-faction-champions-yell-automark.md`

Expected: diff contains only the trigger phrase, manual command removal, test updates, and planning/spec documents.

Do not commit unless the user explicitly asks for a commit.
