# SpellTracker Dispel Tracking Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Log successful player dispels in `SpellTracker` using the real WotLK combat-log subevent `SPELL_DISPEL`.

**Architecture:** Extend the combat-log parser to populate `extraSpellId`, `extraSpellName`, `extraSpellSchool`, and `auraType` for `SPELL_DISPEL`. Add a `SpellTracker` whitelist of dispel spell IDs mapped to icon paths, then log whitelisted `SPELL_DISPEL` events with the existing `formatSpellCast` output.

**Tech Stack:** Lua 5.1, busted, luassert, WoW 3.3.5a combat log data from addon-folder `.txt` logs.

---

### Task 1: Parse Real SPELL_DISPEL Events

**Files:**
- Modify: `utils/CombatEventBuilder.lua`
- Modify: `tests/CombatEventBuilder.test.lua`
- Modify: `lib/blizzardEvent.lua`

- [ ] **Step 1: Add a failing parser/builder test**

Add this test before the final `end` in `tests/CombatEventBuilder.test.lua`:

```lua
    it("parses successful dispel combat log events", function()
        local eventData = blizzardEvent(select(2, Builder:New():FromPlayer("Диспеллер"):ToPlayer("Цель")
            :Dispel(988, "Рассеивание заклинаний", 74562, "Пылающий огонь", 4, "BUFF"):Build()))

        assert.equals("SPELL_DISPEL", eventData.event)
        assert.equals(988, eventData.spellId)
        assert.equals("Рассеивание заклинаний", eventData.spellName)
        assert.equals(74562, eventData.extraSpellId)
        assert.equals("Пылающий огонь", eventData.extraSpellName)
        assert.equals(4, eventData.extraSpellSchool)
        assert.equals("BUFF", eventData.auraType)
    end)
```

- [ ] **Step 2: Run parser/builder tests to verify failure**

Run: `busted --verbose ./tests/CombatEventBuilder.test.lua`

Expected before implementation: failure because `CombatEventBuilder:Dispel` does not exist.

- [ ] **Step 3: Add minimal builder support**

In `utils/CombatEventBuilder.lua`, add this method after `SpellMissed`:

```lua
function CombatEventBuilder:Dispel(spellId, spellName, extraSpellId, extraSpellName, extraSpellSchool, auraType)
    self.event = "SPELL_DISPEL"
    self.spell.id = spellId
    self.spell.name = spellName
    self.extraSpell = {
        id = extraSpellId,
        name = extraSpellName,
        school = extraSpellSchool
    }
    self.type = auraType or "BUFF"
    return self
end
```

In `Build`, include `SPELL_DISPEL` with the same shape as observed logs:

```lua
    elseif self.event == "SPELL_DISPEL" then
        return "COMBAT_LOG_EVENT_UNFILTERED", self.timestamp, self.event, self.source.guid, self.source.name,
            self.source.flags, self.target.guid, self.target.name, self.target.flags, self.spell.id, self.spell.name,
            self.spell.school, self.extraSpell.id, self.extraSpell.name, self.extraSpell.school, self.type
```

- [ ] **Step 4: Parse SPELL_DISPEL in blizzardEvent**

In `lib/blizzardEvent.lua`, replace the parser-only dispel branches with real `SPELL_DISPEL` parsing:

```lua
        elseif event == "SPELL_DISPEL" then
            args.extraSpellId, args.extraSpellName, args.extraSpellSchool, args.auraType = select(4, ...)
```

- [ ] **Step 5: Run parser/builder tests to verify pass**

Run: `busted --verbose ./tests/CombatEventBuilder.test.lua`

Expected after implementation: parser/builder tests pass with no failures.

### Task 2: Log Whitelisted Dispels In SpellTracker

**Files:**
- Modify: `modules/SpellTracker.lua`
- Modify: `tests/SpellTracker.test.lua`

- [ ] **Step 1: Add failing SpellTracker dispel tests**

Add these tests after the `ignores non-tracked spells` test in `tests/SpellTracker.test.lua`:

```lua
        it('logs successful Dispel Magic dispel', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("Вольнож"):ToPlayer("Valgallaa")
                :Dispel(988, "Рассеивание заклинаний", 74792, "Пожирание души", 32, "BUFF"):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "Вольнож", "Interface\\Icons\\Spell_Holy_DispelMagic",
                "Valgallaa"))
        end)

        it('logs successful Remove Curse dispel', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("Волыно"):ToPlayer("Биполярник")
                :Dispel(2782, "Снятие проклятия", 74795, "Метка пожирания", 32, "BUFF"):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "Волыно", "Interface\\Icons\\Spell_Nature_RemoveCurse",
                "Биполярник"))
        end)

        it('ignores non-whitelisted dispels', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("Охотник"):ToEnemy("Леди Смертный Шепот")
                :Dispel(19801, "Усмиряющий выстрел", 33206, "Подавление боли", 2, "BUFF"):Build())

            assert.spy(log).was_not_called()
        end)
```

- [ ] **Step 2: Run SpellTracker tests to verify failure**

Run: `busted --verbose ./tests/SpellTracker.test.lua`

Expected before implementation: whitelisted dispel tests fail because `SpellTracker` does not log `SPELL_DISPEL`.

- [ ] **Step 3: Add dispel whitelist and handling**

In `modules/SpellTracker.lua`, add this table after `TRACKED_CAST_SUCCESS_SPELLS`:

```lua
local TRACKED_DISPEL_SPELLS = {
    [475] = "Interface\\Icons\\Spell_Nature_RemoveCurse", -- Mage: Remove Curse
    [526] = "Interface\\Icons\\Spell_Nature_NullifyPoison", -- Shaman: Cure Toxins
    [527] = "Interface\\Icons\\Spell_Holy_DispelMagic", -- Priest: Dispel Magic
    [528] = "Interface\\Icons\\Spell_Holy_NullifyDisease", -- Priest: Cure Disease
    [552] = "Interface\\Icons\\Spell_Nature_NullifyDisease", -- Priest: Abolish Disease
    [988] = "Interface\\Icons\\Spell_Holy_DispelMagic", -- Priest: Dispel Magic
    [1152] = "Interface\\Icons\\Spell_Holy_Purify", -- Paladin: Purify
    [2782] = "Interface\\Icons\\Spell_Nature_RemoveCurse", -- Druid: Remove Curse
    [4987] = "Interface\\Icons\\Spell_Holy_Renew", -- Paladin: Cleanse
    [10872] = "Interface\\Icons\\Spell_Nature_NullifyDisease", -- Priest: Abolish Disease Effect
    [32375] = "Interface\\Icons\\Spell_Arcane_MassDispel", -- Priest: Mass Dispel
    [32592] = "Interface\\Icons\\Spell_Arcane_MassDispel", -- Priest: Mass Dispel triggered
    [51886] = "Interface\\Icons\\Ability_Shaman_CleanseSpirit" -- Shaman: Cleanse Spirit
}
```

In `handleEvent`, add this branch before the `SPELL_RESURRECT` branch:

```lua
    if eventData.event == "SPELL_DISPEL" and TRACKED_DISPEL_SPELLS[eventData.spellId] then
        self.log(formatSpellCast(eventData.timestamp, eventData.sourceName, TRACKED_DISPEL_SPELLS[eventData.spellId],
            eventData.destName))
        return
    end
```

- [ ] **Step 4: Run SpellTracker tests to verify pass**

Run: `busted --verbose ./tests/SpellTracker.test.lua`

Expected after implementation: SpellTracker tests pass with no failures.

### Task 3: Verify Full Suite

**Files:**
- No further edits expected.

- [ ] **Step 1: Run full suite**

Run: `busted --verbose ./tests/*.lua`

Expected: all tests pass with no failures or errors.
