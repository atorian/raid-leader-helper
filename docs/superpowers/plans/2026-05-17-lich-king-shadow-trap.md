# Lich King Shadow Trap Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Track the first player damaged by each Lich King Shadow Trap explosion in Icecrown Citadel and log it with the Shadow Trap icon.

**Architecture:** Add a focused `LichKingTracker` boss module gated to Icecrown Citadel by `zoneGateInstanceId = 631`. The module listens for `SPELL_DAMAGE` spell id `73529`, logs only the first player seen per combat-log timestamp, clears timestamp state on combat reset, and emits a representative demo message on `RLHelper_Demo`.

**Tech Stack:** Lua 5.1, AceAddon/AceEvent module pattern, WoW 3.3.5a combat-log events, busted, luassert.

---

## File Structure

- Create `modules/bosses/LichKingTracker.lua`: owns ICC Shadow Trap combat-log handling, formatting, timestamp de-duplication, and reset behavior.
- Create `tests/LichKingTracker.test.lua`: unit tests for Shadow Trap logging, same-timestamp suppression, non-player and non-damage ignores, reset behavior, and demo output.
- Modify `RLHelper.toc`: load `modules\bosses\LichKingTracker.lua` with the other boss modules.

### Task 1: Add Lich King Shadow Trap Tests

**Files:**
- Create: `tests/LichKingTracker.test.lua`

- [ ] **Step 1: Create the failing test file**

Create `tests/LichKingTracker.test.lua` with this content:

```lua
require('tests.mocks')
require('../lib/blizzardEvent')

local spy = require('luassert.spy')
local Builder = require('../utils/CombatEventBuilder')
local LichKingTracker = require('../modules/bosses/LichKingTracker')

local function dispatch(module, ...)
    module:handleEvent(blizzardEvent(select(2, ...)))
end

describe('LichKingTracker', function()
    local log

    before_each(function()
        log = spy.new(function()
        end)
        LichKingTracker.log = log
        LichKingTracker:reset()
    end)

    it('receives combat events only in Icecrown Citadel', function()
        assert.is_true(LichKingTracker.receivesCombatEvents)
        assert.are.equal(631, LichKingTracker.zoneGateInstanceId)
    end)

    it('logs the first player damaged by Shadow Trap with icon', function()
        dispatch(LichKingTracker, Builder:New(100):FromEnemy('Темная ловушка'):ToPlayer('Jatagun')
            :SpellDamage(73529, 'Теневая ловушка', 13594):Build())

        assert.spy(log).was_called(1)
        assert.spy(log).was_called_with(
            'SOME DATE |cFFFFFFFFJatagun|r |TInterface\\Icons\\spell_shadow_gathershadows:24:24:0:0|t взорвал ловушку')
    end)

    it('ignores later Shadow Trap damage at the same timestamp', function()
        dispatch(LichKingTracker, Builder:New(100):FromEnemy('Темная ловушка'):ToPlayer('Jatagun')
            :SpellDamage(73529, 'Теневая ловушка', 13594):Build())
        dispatch(LichKingTracker, Builder:New(100):FromEnemy('Темная ловушка'):ToPlayer('Ragnboe')
            :SpellDamage(73529, 'Теневая ловушка', 17211):Build())

        assert.spy(log).was_called(1)
        assert.spy(log).was_called_with(
            'SOME DATE |cFFFFFFFFJatagun|r |TInterface\\Icons\\spell_shadow_gathershadows:24:24:0:0|t взорвал ловушку')
    end)

    it('logs another Shadow Trap explosion at a different timestamp', function()
        dispatch(LichKingTracker, Builder:New(100):FromEnemy('Темная ловушка'):ToPlayer('Jatagun')
            :SpellDamage(73529, 'Теневая ловушка', 13594):Build())
        dispatch(LichKingTracker, Builder:New(101):FromEnemy('Темная ловушка'):ToPlayer('Ragnboe')
            :SpellDamage(73529, 'Теневая ловушка', 17211):Build())

        assert.spy(log).was_called(2)
        assert.spy(log).was_called_with(
            'SOME DATE |cFFFFFFFFJatagun|r |TInterface\\Icons\\spell_shadow_gathershadows:24:24:0:0|t взорвал ловушку')
        assert.spy(log).was_called_with(
            'SOME DATE |cFFFFFFFFRagnboe|r |TInterface\\Icons\\spell_shadow_gathershadows:24:24:0:0|t взорвал ловушку')
    end)

    it('ignores Shadow Trap damage to non-players', function()
        dispatch(LichKingTracker, Builder:New(100):FromEnemy('Темная ловушка'):ToEnemy('Вурдалак')
            :SpellDamage(73529, 'Теневая ловушка', 13594):Build())

        assert.spy(log).was_not_called()
    end)

    it('ignores non-damage Shadow Trap events', function()
        dispatch(LichKingTracker, Builder:New(100):FromEnemy('Темная ловушка'):ToPlayer('Jatagun')
            :ApplyAura(73529, 'Теневая ловушка', 'DEBUFF'):Build())

        assert.spy(log).was_not_called()
    end)

    it('resets same-timestamp suppression on reset', function()
        dispatch(LichKingTracker, Builder:New(100):FromEnemy('Темная ловушка'):ToPlayer('Jatagun')
            :SpellDamage(73529, 'Теневая ловушка', 13594):Build())

        LichKingTracker:reset()

        dispatch(LichKingTracker, Builder:New(100):FromEnemy('Темная ловушка'):ToPlayer('Ragnboe')
            :SpellDamage(73529, 'Теневая ловушка', 17211):Build())

        assert.spy(log).was_called(2)
        assert.spy(log).was_called_with(
            'SOME DATE |cFFFFFFFFRagnboe|r |TInterface\\Icons\\spell_shadow_gathershadows:24:24:0:0|t взорвал ловушку')
    end)

    it('logs representative Shadow Trap message in demo', function()
        LichKingTracker:demo()

        assert.spy(log).was_called_with(
            'SOME DATE |cFFFFFFFFDemoPlayer|r |TInterface\\Icons\\spell_shadow_gathershadows:24:24:0:0|t взорвал ловушку')
    end)
end)
```

- [ ] **Step 2: Run the focused test to verify it fails**

Run: `busted --verbose ./tests/LichKingTracker.test.lua`

Expected before implementation: the test file errors because `../modules/bosses/LichKingTracker` does not exist.

### Task 2: Implement LichKingTracker

**Files:**
- Create: `modules/bosses/LichKingTracker.lua`

- [ ] **Step 1: Create the tracker module**

Create `modules/bosses/LichKingTracker.lua` with this content:

```lua
local RLHelper = LibStub('AceAddon-3.0'):GetAddon('RLHelper')
local LichKingTracker = RLHelper:NewModule('LichKingTracker', 'AceEvent-3.0')
LichKingTracker.receivesCombatEvents = true
LichKingTracker.zoneGateInstanceId = 631 -- Icecrown Citadel

local SHADOW_TRAP_DAMAGE = 73529
local SHADOW_TRAP_ICON = 'Interface\\Icons\\spell_shadow_gathershadows'
local PLAYER_FLAGS = 0x7

function LichKingTracker:OnInitialize()
    self.log = function(...)
        RLHelper:OnCombatLogEvent(...)
    end
end

function LichKingTracker:OnEnable()
    self:RegisterMessage('RLHelper_CombatEnded', 'reset')
    self:RegisterMessage('RLHelper_Demo', 'demo')
end

function LichKingTracker:reset()
    self.lastShadowTrapTimestamp = nil
end

local function isPlayer(flags)
    return bit.band(flags or 0, PLAYER_FLAGS) > 0
end

local function formatShadowTrap(ts, playerName)
    return string.format('%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t взорвал ловушку', date('%H:%M:%S', ts),
        playerName, SHADOW_TRAP_ICON)
end

function LichKingTracker:handleEvent(event)
    if event.event ~= 'SPELL_DAMAGE' or event.spellId ~= SHADOW_TRAP_DAMAGE or not event.destName or
        not isPlayer(event.destFlags) then
        return
    end

    if self.lastShadowTrapTimestamp == event.timestamp then
        return
    end

    self.lastShadowTrapTimestamp = event.timestamp
    self.log(formatShadowTrap(event.timestamp, event.destName))
end

function LichKingTracker:demo()
    self.log(formatShadowTrap(time(), 'DemoPlayer'))
end

return LichKingTracker
```

- [ ] **Step 2: Run the focused test to verify it passes**

Run: `busted --verbose ./tests/LichKingTracker.test.lua`

Expected after implementation: all `LichKingTracker` tests pass.

### Task 3: Load the Module from TOC

**Files:**
- Modify: `RLHelper.toc`

- [ ] **Step 1: Add the module to the addon load order**

In `RLHelper.toc`, add the Lich King tracker after other Icecrown boss trackers and before `HalionTracker`:

```toc
modules\bosses\DeathwhisperTracker.lua
modules\bosses\BloodPrincesTracker.lua
modules\bosses\BloodQueenTracker.lua
modules\bosses\PutricideTracker.lua
modules\bosses\TrialCrusaderTracker.lua
modules\bosses\LichKingTracker.lua
modules\bosses\HalionTracker.lua
```

- [ ] **Step 2: Run the focused test again**

Run: `busted --verbose ./tests/LichKingTracker.test.lua`

Expected: all `LichKingTracker` tests still pass.

### Task 4: Verify Full Suite

**Files:**
- No further edits expected.

- [ ] **Step 1: Run all tests**

Run: `busted --verbose ./tests/*.lua`

Expected: all tests pass with no failures or errors.

- [ ] **Step 2: Inspect changed files**

Run: `git diff -- modules/bosses/LichKingTracker.lua tests/LichKingTracker.test.lua RLHelper.toc docs/superpowers/specs/2026-05-17-lich-king-shadow-trap-design.md docs/superpowers/plans/2026-05-17-lich-king-shadow-trap.md`

Expected: diff contains only the new tracker, its tests, TOC load entry, and the approved spec/plan docs.
