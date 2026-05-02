# Igor Player Death Filter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Igor death emotes trigger only for actual party or raid player deaths, not group-owned totems or other non-player units.

**Architecture:** Keep Igor filtering centralized in `RLHelper:IsGroupMemberDeath(event)`. Add a small local combat-log type check for `TYPE_PLAYER` and require it alongside the existing party/raid affiliation check.

**Tech Stack:** Lua addon code for WoW 3.3.5a, Busted tests, Makefile test target.

---

## File Structure

- Modify `Core.lua`: add a local `TYPE_PLAYER` flag constant/check and require it in `RLHelper:IsGroupMemberDeath`.
- Modify `tests/Core.test.lua`: add Igor tests for party player deaths and group-affiliated non-player deaths.
- Modify `docs/superpowers/specs/2026-05-02-igor-player-death-filter-design.md`: keep the spec aligned with the discovered helper behavior.

### Task 1: Add Failing Igor Filter Tests

**Files:**
- Modify: `tests/Core.test.lua`

- [ ] **Step 1: Add party-player and non-player death tests**

Add these tests inside `describe("RLHelper Igor death emote", function()`:

```lua
    it("sends a random emote when a party player dies", function()
        local messages = {}
        _G.SendChatMessage = function(message, channel)
            table.insert(messages, { message = message, channel = channel })
        end
        RLHelper.GetCombatNow = function()
            return 100
        end

        local sent = RLHelper:MaybeSendIgorDeathMessage({
            event = "UNIT_DIED",
            destName = "Игрок",
            destFlags = 0x512
        })

        assert.is_true(sent)
        assert.are.same({ { message = "Игорь осуждает смерть Игрок.", channel = "EMOTE" } }, messages)
    end)

    it("ignores group-affiliated non-player deaths", function()
        local sentCount = 0
        _G.SendChatMessage = function()
            sentCount = sentCount + 1
        end

        local sent = RLHelper:MaybeSendIgorDeathMessage({
            event = "UNIT_DIED",
            destName = "Тотем",
            destFlags = 0x114
        })

        assert.is_false(sent)
        assert.are.equal(0, sentCount)
    end)
```

- [ ] **Step 2: Run focused Core tests and verify RED**

Run: `busted --verbose ./tests/Core.test.lua`

Expected: the non-player death test fails because current filtering only checks party/raid affiliation.

### Task 2: Require TYPE_PLAYER for Igor Deaths

**Files:**
- Modify: `Core.lua`
- Test: `tests/Core.test.lua`

- [ ] **Step 1: Add the player type check**

Add near the other local constants:

```lua
local COMBATLOG_OBJECT_TYPE_PLAYER_FLAG = COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400
```

Add near the local helper functions:

```lua
local function isPlayerType(flags)
    return bit.band(flags or 0, COMBATLOG_OBJECT_TYPE_PLAYER_FLAG) > 0
end
```

Change `RLHelper:IsGroupMemberDeath(event)` to:

```lua
function RLHelper:IsGroupMemberDeath(event)
    if not event or event.event ~= "UNIT_DIED" then
        return false
    end

    local destFlags = event.destFlags or 0
    local groupFlags = bit.bor and bit.bor(self.GROUP_AFFILIATION_PARTY, self.GROUP_AFFILIATION_RAID) or
        (self.GROUP_AFFILIATION_PARTY + self.GROUP_AFFILIATION_RAID)
    return bit.band(destFlags, groupFlags) > 0 and isPlayerType(destFlags)
end
```

- [ ] **Step 2: Run focused Core tests and verify GREEN**

Run: `busted --verbose ./tests/Core.test.lua`

Expected: all Core tests pass.

### Task 3: Full Verification

**Files:**
- Verify all modified files.

- [ ] **Step 1: Run full test suite**

Run: `make test`

Expected: all tests pass.

- [ ] **Step 2: Check diff**

Run: `git diff -- Core.lua tests/Core.test.lua docs/superpowers/specs/2026-05-02-igor-player-death-filter-design.md docs/superpowers/plans/2026-05-02-igor-player-death-filter.md`

Expected: diff contains only the Igor player-death filter, tests, and spec/plan files.

Do not commit unless the user explicitly asks for a commit.
