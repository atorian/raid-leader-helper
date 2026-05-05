# Combat Start And Valithria First Heal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Share ignored combat enemy filtering between core combat tracking and `SpellTracker`, and log the first positive heal on Valithria Dreamwalker.

**Architecture:** Add `lib/CombatFilters.lua` as a tiny shared global/require-able helper and load it before `Core.lua` in `RLHelper.toc`. Keep `SpellTracker` state local, adding a second resettable first-event flag for Valithria healing that is independent from first damage.

**Tech Stack:** Lua 5.1, busted, luassert, WoW 3.3.5a combat-log events `SPELL_HEAL` and `SPELL_PERIODIC_HEAL`.

---

### Task 1: Shared Combat Enemy Filter

**Files:**
- Create: `lib/CombatFilters.lua`
- Modify: `RLHelper.toc`
- Modify: `Core.lua`
- Modify: `tests/CombatSystem.test.lua`
- Create: `tests/CombatFilters.test.lua`

- [ ] **Step 1: Add failing helper test**

Create `tests/CombatFilters.test.lua`:

```lua
local CombatFilters = require('../lib/CombatFilters')

describe('CombatFilters', function()
    it('identifies ignored combat enemies', function()
        assert.is_true(CombatFilters:IsIgnoredCombatEnemy('World Invisible Trigger'))
        assert.is_true(CombatFilters:IsIgnoredCombatEnemy('Огрская пиньята'))
        assert.is_true(CombatFilters:IsIgnoredCombatEnemy('Робот "Бей-Молоти"'))
        assert.is_false(CombatFilters:IsIgnoredCombatEnemy('Ануб\'арак'))
    end)
end)
```

- [ ] **Step 2: Run helper test to verify failure**

Run: `busted --verbose ./tests/CombatFilters.test.lua`

Expected before implementation: module `../lib/CombatFilters` is not found.

- [ ] **Step 3: Implement helper and load order**

Create `lib/CombatFilters.lua`:

```lua
local CombatFilters = {}

local IGNORED_COMBAT_ENEMIES = {
    ["World Invisible Trigger"] = true,
    ["Огрская пиньята"] = true,
    ["Робот \"Бей-Молоти\""] = true
}

function CombatFilters:IsIgnoredCombatEnemy(name)
    return IGNORED_COMBAT_ENEMIES[name] == true
end

_G.RLHelperCombatFilters = CombatFilters

return CombatFilters
```

In `RLHelper.toc`, add `lib\CombatFilters.lua` after `lib\RingBuffer.lua` and before `Core.lua`.

- [ ] **Step 4: Update Core to use helper**

In `Core.lua`, remove the local `IGNORED_COMBAT_ENEMIES` table. Add:

```lua
local CombatFilters = RLHelperCombatFilters
```

Update `shouldIgnoreCombatEnemy`:

```lua
local function shouldIgnoreCombatEnemy(name)
    return CombatFilters and CombatFilters:IsIgnoredCombatEnemy(name) or false
end
```

In `tests/CombatSystem.test.lua`, require the helper before requiring `Core`:

```lua
require('../lib/CombatFilters')
```

- [ ] **Step 5: Run core/filter tests**

Run: `busted --verbose ./tests/CombatFilters.test.lua ./tests/CombatSystem.test.lua`

Expected after implementation: tests pass with no failures.

### Task 2: SpellTracker Ignore Filter And Valithria First Heal

**Files:**
- Modify: `modules/SpellTracker.lua`
- Modify: `tests/SpellTracker.test.lua`
- Modify: `utils/CombatEventBuilder.lua`

- [ ] **Step 1: Add failing SpellTracker tests**

In `tests/SpellTracker.test.lua`, require the helper before requiring `SpellTracker`:

```lua
require('../lib/CombatFilters')
```

Add tests after `logs first damage to enemy`:

```lua
        it('does not log first damage to ignored combat enemy', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("TestPlayer"):ToEnemy('Робот "Бей-Молоти"')
                :SpellDamage(12345, "Test Spell", 100):Build())

            assert.spy(log).was_not_called()
        end)

        it('logs first direct heal to Valithria', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("Всёпадаем"):ToEnemy("Валитрия Сноходица")
                :SpellHeal(54968, "Символ Света небес", 6038):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r Первый хил по |cFFFFFFFF%s|r",
                date("%H:%M:%S", GetTime()), "Всёпадаем", "Валитрия Сноходица"))
        end)

        it('logs first periodic heal to Valithria', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("Bultuzor"):ToEnemy("Валитрия Сноходица")
                :PeriodicHeal(61301, "Быстрина", 1674):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r Первый хил по |cFFFFFFFF%s|r",
                date("%H:%M:%S", GetTime()), "Bultuzor", "Валитрия Сноходица"))
        end)

        it('ignores zero amount Valithria heals', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("Всёпадаем"):ToEnemy("Валитрия Сноходица")
                :SpellHeal(54968, "Символ Света небес", 0):Build())

            assert.spy(log).was_not_called()
        end)

        it('logs Valithria first heal only once per reset', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("Всёпадаем"):ToEnemy("Валитрия Сноходица")
                :SpellHeal(54968, "Символ Света небес", 6038):Build())
            dispatch(SpellTracker, Builder:New():FromPlayer("Bultuzor"):ToEnemy("Валитрия Сноходица")
                :SpellHeal(61301, "Быстрина", 5205):Build())

            assert.spy(log).was_called(1)
        end)
```

- [ ] **Step 2: Run SpellTracker tests to verify failure**

Run: `busted --verbose ./tests/SpellTracker.test.lua`

Expected before implementation: failure because heal builder methods or Valithria first-heal logging are missing.

- [ ] **Step 3: Add heal event builder support**

In `utils/CombatEventBuilder.lua`, add:

```lua
function CombatEventBuilder:SpellHeal(spellId, spellName, amount)
    self.event = "SPELL_HEAL"
    self.spell.id = spellId
    self.spell.name = spellName
    self.amount = amount
    return self
end

function CombatEventBuilder:PeriodicHeal(spellId, spellName, amount)
    self.event = "SPELL_PERIODIC_HEAL"
    self.spell.id = spellId
    self.spell.name = spellName
    self.amount = amount
    return self
end
```

In `Build`, return the same heal shape parsed by `blizzardEvent`:

```lua
    elseif self.event == "SPELL_HEAL" or self.event == "SPELL_PERIODIC_HEAL" then
        return "COMBAT_LOG_EVENT_UNFILTERED", self.timestamp, self.event, self.source.guid, self.source.name,
            self.source.flags, self.target.guid, self.target.name, self.target.flags, self.spell.id, self.spell.name,
            self.spell.school, self.amount, 0, 0, nil
```

- [ ] **Step 4: Implement SpellTracker behavior**

In `modules/SpellTracker.lua`:

```lua
local CombatFilters = RLHelperCombatFilters
local firstValithriaHealDone = false
local VALITHRIA_DREAMWALKER = "Валитрия Сноходица"
```

Reset `firstValithriaHealDone` in `OnEnable` and `reset`.

Add:

```lua
local function formatFirstHeal(ts, source, dest)
    return string.format("%s |cFFFFFFFF%s|r Первый хил по |cFFFFFFFF%s|r", date("%H:%M:%S", ts), source,
        dest)
end
```

Skip ignored first-damage targets:

```lua
            if not CombatFilters or not CombatFilters:IsIgnoredCombatEnemy(eventData.destName) then
                firstDamageDone = true
                self.log(formatFirstHit(eventData.timestamp, eventData.sourceName, eventData.destName))
            end
```

Add Valithria heal logging near first-damage tracking:

```lua
    if not firstValithriaHealDone and (eventData.event == "SPELL_HEAL" or eventData.event == "SPELL_PERIODIC_HEAL") then
        if isPlayer(eventData.sourceFlags) and eventData.destName == VALITHRIA_DREAMWALKER and (eventData.amount or 0) > 0 then
            firstValithriaHealDone = true
            self.log(formatFirstHeal(eventData.timestamp, eventData.sourceName, eventData.destName))
        end
    end
```

- [ ] **Step 5: Run SpellTracker tests**

Run: `busted --verbose ./tests/SpellTracker.test.lua`

Expected after implementation: tests pass with no failures.

### Task 3: Full Verification

**Files:**
- No further edits expected.

- [ ] **Step 1: Run full suite**

Run: `busted --verbose ./tests/*.lua`

Expected: all tests pass with no failures or errors.
