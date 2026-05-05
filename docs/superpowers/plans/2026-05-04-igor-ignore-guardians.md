# Igor Ignore Guardian Deaths Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop Igor from reacting to totem and guardian deaths while preserving reactions to group players and real group pets.

**Architecture:** Keep the existing Igor death filtering flow. Narrow the pet path from `PET or GUARDIAN` to `PET` only, and update the guardian test to assert ignored behavior.

**Tech Stack:** Lua 5.1, busted, luassert, WoW 3.3.5a combat log flags.

---

### Task 1: Pet-Only Igor Death Filtering

**Files:**
- Modify: `tests/IgorDeathTracker.test.lua:171-188`
- Modify: `modules/IgorDeathTracker.lua:8-55`

- [ ] **Step 1: Write the failing test**

Replace the guardian test in `tests/IgorDeathTracker.test.lua` with:

```lua
    it("ignores a group guardian death", function()
        local sentCount = 0
        _G.SendChatMessage = function()
            sentCount = sentCount + 1
        end
        RLHelper.GetCombatNow = function()
            return 100
        end

        local sent = IgorDeathTracker:handleEvent({
            event = "UNIT_DIED",
            destName = "Тотем",
            destFlags = 0x2014
        })

        assert.is_false(sent)
        assert.are.equal(0, sentCount)
    end)
```

- [ ] **Step 2: Run test to verify it fails**

Run: `busted --verbose ./tests/IgorDeathTracker.test.lua`

Expected before implementation: one failure for `ignores a group guardian death` because guardian deaths still trigger pet emotes.

- [ ] **Step 3: Write minimal implementation**

In `modules/IgorDeathTracker.lua`, remove the guardian flag constant and make the helper pet-only:

```lua
local COMBATLOG_OBJECT_TYPE_PET_FLAG = COMBATLOG_OBJECT_TYPE_PET or 0x00001000

local function isPetType(flags)
    return bit.band(flags or 0, COMBATLOG_OBJECT_TYPE_PET_FLAG) > 0
end
```

Update phrase selection to use the pet-only helper:

```lua
    if isPetType(destFlags) then
        return IGOR_PET_DEATH_PHRASES
    end
```

- [ ] **Step 4: Run targeted test to verify it passes**

Run: `busted --verbose ./tests/IgorDeathTracker.test.lua`

Expected after implementation: IgorDeathTracker tests pass with no failures.

- [ ] **Step 5: Run full suite**

Run: `busted --verbose ./tests/*.lua`

Expected: all tests pass with no failures or errors.
