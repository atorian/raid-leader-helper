# Igor Pet Death Messages Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add separate Igor emotes for group-affiliated pet and guardian deaths while preserving player death emotes.

**Architecture:** Keep Igor death handling centralized in `MaybeSendIgorDeathMessage`. Classify `UNIT_DIED` targets as `player` or `pet` based on group affiliation plus combat-log type flags, select the matching phrase list, and use the existing shared cooldown for both classes.

**Tech Stack:** Lua addon code for WoW 3.3.5a, Busted tests, Makefile test target.

---

## File Structure

- Modify `Core.lua`: add pet/guardian type flags, pet phrase list, target classifier, and phrase-list formatting.
- Modify `tests/Core.test.lua`: add pet, guardian, shared-cooldown, and ignored plain non-player coverage.
- Add `docs/superpowers/specs/2026-05-02-igor-pet-death-messages-design.md`: written design for this behavior.

### Task 1: Add Failing Pet Death Tests

**Files:**
- Modify: `tests/Core.test.lua`

- [ ] **Step 1: Add tests inside `describe("RLHelper Igor death emote", function()`**

```lua
    it("sends a pet emote when a group pet dies", function()
        local messages = {}
        _G.SendChatMessage = function(message, channel)
            table.insert(messages, { message = message, channel = channel })
        end
        RLHelper.GetCombatNow = function()
            return 100
        end

        local sent = RLHelper:MaybeSendIgorDeathMessage({
            event = "UNIT_DIED",
            destName = "Волк",
            destFlags = 0x1012
        })

        assert.is_true(sent)
        assert.are.same({ { message = "Игорь скорбит по питомцу Волк.", channel = "EMOTE" } }, messages)
    end)

    it("sends a pet emote when a group guardian dies", function()
        local messages = {}
        _G.SendChatMessage = function(message, channel)
            table.insert(messages, { message = message, channel = channel })
        end
        RLHelper.GetCombatNow = function()
            return 100
        end

        local sent = RLHelper:MaybeSendIgorDeathMessage({
            event = "UNIT_DIED",
            destName = "Прислужник",
            destFlags = 0x2014
        })

        assert.is_true(sent)
        assert.are.same({ { message = "Игорь скорбит по питомцу Прислужник.", channel = "EMOTE" } }, messages)
    end)

    it("shares cooldown between player and pet death emotes", function()
        local messages = {}
        _G.SendChatMessage = function(message, channel)
            table.insert(messages, { message = message, channel = channel })
        end
        local now = 100
        RLHelper.GetCombatNow = function()
            return now
        end

        assert.is_true(RLHelper:MaybeSendIgorDeathMessage({
            event = "UNIT_DIED",
            destName = "Игрок",
            destFlags = 0x514
        }))
        now = 109
        assert.is_false(RLHelper:MaybeSendIgorDeathMessage({
            event = "UNIT_DIED",
            destName = "Волк",
            destFlags = 0x1014
        }))
        now = 111
        assert.is_true(RLHelper:MaybeSendIgorDeathMessage({
            event = "UNIT_DIED",
            destName = "Волк",
            destFlags = 0x1014
        }))

        assert.are.equal(2, #messages)
    end)
```

- [ ] **Step 2: Run focused Core tests and verify RED**

Run: `busted --verbose ./tests/Core.test.lua`

Expected: pet and guardian tests fail because current code ignores non-player deaths.

### Task 2: Implement Pet Death Classification And Messages

**Files:**
- Modify: `Core.lua`
- Test: `tests/Core.test.lua`

- [ ] **Step 1: Add constants and pet phrases**

Add near existing combat-log type constant:

```lua
local COMBATLOG_OBJECT_TYPE_PET_FLAG = COMBATLOG_OBJECT_TYPE_PET or 0x00001000
local COMBATLOG_OBJECT_TYPE_GUARDIAN_FLAG = COMBATLOG_OBJECT_TYPE_GUARDIAN or 0x00002000
```

Add after `IGOR_DEATH_PHRASES`:

```lua
local IGOR_PET_DEATH_PHRASES = {
    "Игорь скорбит по питомцу %s.",
    "Игорь считает, что %s заслуживал большего.",
    "Игорь делает пометку: %s погиб за чужие ошибки.",
    "Игорь говорит: минус лапа в рейде.",
    "Игорь подозревает, что %s просто хотел домой.",
    "Игорь смотрит на тело %s и молчит.",
    "Игорь напоминает: питомцев тоже надо лечить.",
    "Игорь записал смерть %s в отчет о халатности.",
    "Игорь говорит: зверя жалко.",
    "Игорь считает, что %s был лучшим из нас."
}
```

- [ ] **Step 2: Add type helpers and classifier**

Add near `isPlayerType`:

```lua
local function isPetOrGuardianType(flags)
    local value = flags or 0
    return bit.band(value, COMBATLOG_OBJECT_TYPE_PET_FLAG) > 0 or
        bit.band(value, COMBATLOG_OBJECT_TYPE_GUARDIAN_FLAG) > 0
end
```

Replace `IsGroupMemberDeath` with:

```lua
function RLHelper:GetGroupDeathMessagePhrases(event)
    if not event or event.event ~= "UNIT_DIED" then
        return nil
    end

    local destFlags = event.destFlags or 0
    local groupFlags = bit.bor and bit.bor(self.GROUP_AFFILIATION_PARTY, self.GROUP_AFFILIATION_RAID) or
        (self.GROUP_AFFILIATION_PARTY + self.GROUP_AFFILIATION_RAID)
    if bit.band(destFlags, groupFlags) <= 0 then
        return nil
    end

    if isPlayerType(destFlags) then
        return IGOR_DEATH_PHRASES
    end

    if isPetOrGuardianType(destFlags) then
        return IGOR_PET_DEATH_PHRASES
    end

    return nil
end

function RLHelper:IsGroupMemberDeath(event)
    return self:GetGroupDeathMessagePhrases(event) ~= nil
end
```

- [ ] **Step 3: Make formatting accept a phrase list**

Change `FormatIgorDeathMessage` to:

```lua
function RLHelper:FormatIgorDeathMessage(playerName, phrases)
    local phraseList = phrases or IGOR_DEATH_PHRASES
    local phrase = phraseList[math.random(#phraseList)]
    if phrase:find("%%s") then
        return string.format(phrase, playerName or "кто-то")
    end

    return phrase
end
```

Change `MaybeSendIgorDeathMessage` to retrieve `phrases` once and pass it to formatting.

- [ ] **Step 4: Run focused Core tests and verify GREEN**

Run: `busted --verbose ./tests/Core.test.lua`

Expected: all Core tests pass.

### Task 3: Full Verification

**Files:**
- Verify all modified files.

- [ ] **Step 1: Run full test suite**

Run: `make test`

Expected: all tests pass.

- [ ] **Step 2: Review diff**

Run: `git diff -- Core.lua tests/Core.test.lua docs/superpowers/specs/2026-05-02-igor-player-death-filter-design.md docs/superpowers/plans/2026-05-02-igor-player-death-filter.md docs/superpowers/specs/2026-05-02-igor-pet-death-messages-design.md docs/superpowers/plans/2026-05-02-igor-pet-death-messages.md`

Expected: diff contains only Igor player/pet death filtering, messages, tests, and spec/plan files.

Do not commit unless the user explicitly asks for a commit.
