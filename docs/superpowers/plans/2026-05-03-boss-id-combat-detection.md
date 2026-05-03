# Boss ID Combat Detection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Mark boss combats from known boss NPC IDs in combat-log GUIDs so `bossOnlyHistory` does not drop boss fights when `boss1` is absent.

**Architecture:** Existing boss modules expose static `bossIds` metadata. `Core.lua` extracts creature IDs from `sourceGUID` and `destGUID`, checks zone-eligible modules, and marks the current combat with the mapped encounter name. `boss1` is removed from boss history detection entirely.

**Tech Stack:** Lua 5.1-style WoW 3.3.5a addon code, AceAddon module pattern, existing `LibCompat-1.0` creature ID helper, Busted tests.

---

## File Structure

- Modify `Core.lua`
  - Remove `getBoss1Name()`.
  - Add local helpers for extracting NPC IDs and looking up `module.bossIds`.
  - Update `RLHelper:MarkBossCombat(event)` to use combat-log GUIDs and module metadata.
- Modify `modules/bosses/TrialCrusaderTracker.lua`
  - Add `TrialCrusaderTracker.bossIds` for existing Trial of the Crusader encounter scope.
- Modify `modules/bosses/DeathwhisperTracker.lua`
  - Add `DeathwhisperTracker.bossIds`.
- Modify `modules/bosses/BloodPrincesTracker.lua`
  - Add `BloodPrincesTracker.bossIds`.
- Modify `modules/bosses/BloodQueenTracker.lua`
  - Add `BloodQueenTracker.bossIds`.
- Modify `modules/bosses/HalionTracker.lua`
  - Add `HalionTracker.bossIds` only. Do not change burst/reset or damage-meter behavior.
- Modify `tests/CombatSystem.test.lua`
  - Replace `boss1`-based boss naming tests with NPC-ID-based tests.

## Task 1: Add Failing Combat-System Tests

**Files:**
- Modify: `tests/CombatSystem.test.lua`

- [ ] **Step 1: Add helper functions near the top of `tests/CombatSystem.test.lua`**

Add these helpers after the existing `count(tbl)` function:

```lua
local function npcGuid(npcId, spawnId)
    return string.format("0xF13000%04X%06X", npcId, spawnId or npcId)
end

local function setBossModules(modules)
    RLHelper.IterateModules = function()
        return ipairs(modules)
    end
end
```

- [ ] **Step 2: Preserve and restore module iteration in the test fixture**

Inside `describe("Боевая система", function()`, add this local before `before_each`:

```lua
    local originalIterateModules
```

At the start of `before_each`, before any state mutation, add:

```lua
        originalIterateModules = RLHelper.IterateModules
```

After the existing `before_each` block, add this `after_each` block:

```lua
    after_each(function()
        RLHelper.IterateModules = originalIterateModules
    end)
```

- [ ] **Step 3: Replace the old boss rename test body**

Replace the full test named `"переименовывает бой в имя босса если босс появился после обычного врага"` with:

```lua
    it("переименовывает бой в имя босса по известному npc id без boss1", function()
        M.UnitAffectingCombat1 = false
        RLHelper.currentInstanceId = 631
        setBossModules({
            {
                name = "BloodQueenTracker",
                receivesCombatEvents = true,
                zoneGateInstanceId = 631,
                bossIds = {
                    [37955] = "Кровавая королева Лана'тель"
                }
            }
        })

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Адд"):ToPlayer("Игрок1"):Damage(100):Build())

        local bossEvent = { Builder:New():FromEnemy("Кровавая королева Лана'тель"):ToPlayer("Игрок1"):Damage(100):Build() }
        bossEvent[4] = npcGuid(37955)

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(unpack(bossEvent))

        assert.is_true(RLHelper.currentCombat.isBoss)
        assert.are.equal("Кровавая королева Лана'тель", RLHelper.currentCombat.firstEnemy)
    end)
```

- [ ] **Step 4: Replace the old `boss1` detection test**

Replace the full test named `"проверяет только boss1 при определении босса"` with:

```lua
    it("не использует boss1 для определения боссового боя", function()
        M.UnitAffectingCombat1 = false
        RLHelper.currentInstanceId = 631
        M:SetUnitGUID("boss1", npcGuid(37955))
        M:SetUnitName("boss1", "Кровавая королева Лана'тель")
        setBossModules({
            {
                name = "BloodQueenTracker",
                receivesCombatEvents = true,
                zoneGateInstanceId = 631,
                bossIds = {
                    [37955] = "Кровавая королева Лана'тель"
                }
            }
        })

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Адд"):ToPlayer("Игрок1"):Damage(100):Build())

        assert.is_false(RLHelper.currentCombat.isBoss)
        assert.are.equal("Адд", RLHelper.currentCombat.firstEnemy)
    end)
```

- [ ] **Step 5: Replace the boss-only history save test body**

Replace the body of the test named `"сохраняет боссовый бой когда включена история только боссов"` with:

```lua
        RLHelper.db.profile.bossOnlyHistory = true
        M.UnitAffectingCombat1 = false
        RLHelper.currentInstanceId = 631
        setBossModules({
            {
                name = "BloodPrincesTracker",
                receivesCombatEvents = true,
                zoneGateInstanceId = 631,
                bossIds = {
                    [37970] = "Кровавый совет",
                    [37972] = "Кровавый совет",
                    [37973] = "Кровавый совет"
                }
            }
        })

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Адд"):ToPlayer("Игрок1"):Damage(100):Build())
        local bossEvent = { Builder:New():FromEnemy("Принц Валанар"):ToPlayer("Игрок1"):Damage(100):Build() }
        bossEvent[4] = npcGuid(37970)

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(unpack(bossEvent))
        RLHelper:OnCombatLogEvent("test message")

        for guid in pairs(RLHelper.activeEnemies) do
            RLHelper.activeEnemies[guid] = RLHelper:GetCombatNow() - 10
        end
        RLHelper.lastCombatActivityAt = RLHelper:GetCombatNow() - 10
        RLHelper.combatEndRequestedAt = RLHelper:GetCombatNow() - 5

        assert.is_true(RLHelper:EvaluateCombatEnd("test"))
        assert.are.equal(1, #RLHelper.combatHistory)
        assert.is_true(RLHelper.combatHistory[1].isBoss)
        assert.are.equal("Кровавый совет", RLHelper.combatHistory[1].firstEnemy)
        assert.are.equal("Кровавый совет", RLHelper.db.profile.combatHistory[1].firstEnemy)
```

- [ ] **Step 6: Add a destination-GUID boss detection test**

Add this test after the new boss rename test:

```lua
    it("определяет босса по destGUID если босс является целью события", function()
        M.UnitAffectingCombat1 = false
        RLHelper.currentInstanceId = 724
        setBossModules({
            {
                name = "HalionTracker",
                receivesCombatEvents = true,
                zoneGateInstanceId = 724,
                bossIds = {
                    [39863] = "Халион"
                }
            }
        })

        local bossEvent = { Builder:New():FromPlayer("Игрок1"):ToEnemy("Халион"):SpellDamage(12345, "Удар", 100):Build() }
        bossEvent[7] = npcGuid(39863)

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(unpack(bossEvent))

        assert.is_true(RLHelper.currentCombat.isBoss)
        assert.are.equal("Халион", RLHelper.currentCombat.firstEnemy)
    end)
```

- [ ] **Step 7: Run focused tests and verify RED**

Run:

```bash
busted --verbose tests/CombatSystem.test.lua
```

Expected before implementation: at least one failure because `MarkBossCombat(event)` still depends on `boss1` and does not read `module.bossIds`.

## Task 2: Add Boss ID Metadata to Existing Boss Modules

**Files:**
- Modify: `modules/bosses/TrialCrusaderTracker.lua`
- Modify: `modules/bosses/DeathwhisperTracker.lua`
- Modify: `modules/bosses/BloodPrincesTracker.lua`
- Modify: `modules/bosses/BloodQueenTracker.lua`
- Modify: `modules/bosses/HalionTracker.lua`

- [ ] **Step 1: Add Trial of the Crusader boss IDs**

In `modules/bosses/TrialCrusaderTracker.lua`, after `TrialCrusaderTracker.zoneGateInstanceId = 649`, add:

```lua
TrialCrusaderTracker.bossIds = {
    [34796] = "Чудовища Нордскола", -- Gormok the Impaler
    [35144] = "Чудовища Нордскола", -- Acidmaw
    [34799] = "Чудовища Нордскола", -- Dreadscale
    [34797] = "Чудовища Нордскола", -- Icehowl
    [34780] = "Лорд Джараксус",
    [34467] = "Чемпионы фракций",
    [34448] = "Чемпионы фракций",
    [34475] = "Чемпионы фракций",
    [34455] = "Чемпионы фракций",
    [34466] = "Чемпионы фракций",
    [34447] = "Чемпионы фракций",
    [34473] = "Чемпионы фракций",
    [34441] = "Чемпионы фракций",
    [34474] = "Чемпионы фракций",
    [34450] = "Чемпионы фракций",
    [34461] = "Чемпионы фракций",
    [34458] = "Чемпионы фракций",
    [34463] = "Чемпионы фракций",
    [34444] = "Чемпионы фракций",
    [34471] = "Чемпионы фракций",
    [34445] = "Чемпионы фракций",
    [34460] = "Чемпионы фракций",
    [34451] = "Чемпионы фракций",
    [34497] = "Валь'киры-близнецы", -- Fjola Lightbane
    [34496] = "Валь'киры-близнецы", -- Eydis Darkbane
    [34564] = "Ануб'арак"
}
```

- [ ] **Step 2: Add Lady Deathwhisper boss ID**

In `modules/bosses/DeathwhisperTracker.lua`, after `local DeathwhisperTracker = RLHelper:NewModule("DeathwhisperTracker", "AceEvent-3.0")`, add:

```lua
DeathwhisperTracker.bossIds = {
    [36855] = "Леди Смертный Шепот"
}
```

- [ ] **Step 3: Add Blood Princes boss IDs**

In `modules/bosses/BloodPrincesTracker.lua`, after `BloodPrincesTracker.zoneGateInstanceId = 631 -- Icecrown Citadel`, add:

```lua
BloodPrincesTracker.bossIds = {
    [37970] = "Кровавый совет", -- Prince Valanar
    [37972] = "Кровавый совет", -- Prince Keleseth
    [37973] = "Кровавый совет" -- Prince Taldaram
}
```

- [ ] **Step 4: Add Blood-Queen boss ID**

In `modules/bosses/BloodQueenTracker.lua`, after `BloodQueenTracker.zoneGateInstanceId = 631 -- Icecrown Citadel`, add:

```lua
BloodQueenTracker.bossIds = {
    [37955] = "Кровавая королева Лана'тель"
}
```

- [ ] **Step 5: Add Halion boss IDs**

In `modules/bosses/HalionTracker.lua`, after `HalionTracker.zoneGateInstanceId = 724 -- The Ruby Sanctum`, add:

```lua
HalionTracker.bossIds = {
    [39863] = "Халион",
    [40142] = "Халион"
}
```

- [ ] **Step 6: Run existing module tests**

Run:

```bash
busted --verbose tests/TrialCrusaderTracker.test.lua tests/DeathwhisperTracker.test.lua tests/BloodPrincesTracker.test.lua tests/BloodQueenTracker.test.lua tests/HalionTracker.test.lua
```

Expected: all listed module tests pass, because adding metadata must not change module event handling.

## Task 3: Implement Boss ID Detection in Core

**Files:**
- Modify: `Core.lua`

- [ ] **Step 1: Remove `getBoss1Name()`**

Delete this local function from `Core.lua`:

```lua
local function getBoss1Name()
    if type(UnitExists) == "function" and not UnitExists("boss1") then
        return nil
    end

    if type(UnitName) == "function" then
        return UnitName("boss1")
    end

    return nil
end
```

- [ ] **Step 2: Add Core helpers for boss ID lookup**

In `Core.lua`, where `getBoss1Name()` was removed, add:

```lua
local function creatureIdFromGuid(guid)
    if type(RLHelper.GetCreatureId) == "function" then
        return RLHelper.GetCreatureId(guid)
    end

    return type(guid) == "string" and tonumber(guid:sub(9, 12), 16) or nil
end

local function bossNameFromModule(module, npcId)
    if type(module) ~= "table" or type(module.bossIds) ~= "table" or type(npcId) ~= "number" then
        return nil
    end

    return module.bossIds[npcId]
end
```

- [ ] **Step 3: Add `RLHelper:GetKnownBossNameFromCombatEvent(event)`**

In `Core.lua`, add this function immediately before `function RLHelper:MarkBossCombat(event)`:

```lua
function RLHelper:GetKnownBossNameFromCombatEvent(event)
    if type(self.IterateModules) ~= "function" then
        return nil
    end

    local sourceNpcId = creatureIdFromGuid(event.sourceGUID)
    local destNpcId = creatureIdFromGuid(event.destGUID)

    for _, module in self:IterateModules() do
        if self:ShouldDispatchCombatEventToModule(module) then
            local bossName = bossNameFromModule(module, sourceNpcId) or bossNameFromModule(module, destNpcId)
            if bossName then
                return bossName
            end
        end
    end

    return nil
end
```

- [ ] **Step 4: Replace `RLHelper:MarkBossCombat(event)`**

Replace the full existing `RLHelper:MarkBossCombat(event)` function with:

```lua
function RLHelper:MarkBossCombat(event)
    if not self.currentCombat or self.currentCombat.isBoss or not affectingGroup(event) then
        return false
    end

    local bossName = self:GetKnownBossNameFromCombatEvent(event)
    if not bossName then
        return false
    end

    self.currentCombat.isBoss = true
    self.currentCombat.firstEnemy = bossName
    return true
end
```

- [ ] **Step 5: Run focused combat system tests and verify GREEN**

Run:

```bash
busted --verbose tests/CombatSystem.test.lua
```

Expected: all combat system tests pass.

## Task 4: Full Verification and Commit

**Files:**
- Verify all modified files.

- [ ] **Step 1: Run full test suite**

Run:

```bash
make test
```

Expected: all tests pass.

- [ ] **Step 2: Inspect scoped diff**

Run:

```bash
git diff -- Core.lua tests/CombatSystem.test.lua modules/bosses/TrialCrusaderTracker.lua modules/bosses/DeathwhisperTracker.lua modules/bosses/BloodPrincesTracker.lua modules/bosses/BloodQueenTracker.lua modules/bosses/HalionTracker.lua docs/superpowers/specs/2026-05-03-boss-id-combat-detection-design.md docs/superpowers/plans/2026-05-03-boss-id-combat-detection.md
```

Expected: diff only contains boss-ID metadata, Core boss detection, tests, and the spec/plan.

- [ ] **Step 3: Check worktree status**

Run:

```bash
git status --short
```

Expected: unrelated local changes such as `features.md`, `readme.md`, older untracked docs, and tool folders may still exist. Do not add them.

- [ ] **Step 4: Commit only scoped files if the user explicitly asks for a commit**

Run only after explicit commit approval:

```bash
git add -- Core.lua tests/CombatSystem.test.lua modules/bosses/TrialCrusaderTracker.lua modules/bosses/DeathwhisperTracker.lua modules/bosses/BloodPrincesTracker.lua modules/bosses/BloodQueenTracker.lua modules/bosses/HalionTracker.lua docs/superpowers/specs/2026-05-03-boss-id-combat-detection-design.md docs/superpowers/plans/2026-05-03-boss-id-combat-detection.md
git commit -m "fix: detect boss combats by npc id"
```

Expected: one commit containing only the scoped boss-ID combat detection changes.

## Self-Review

- Spec coverage: The plan removes `boss1`, adds module `bossIds`, detects from combat-log source/dest GUIDs, uses encounter names, and avoids Halion burst/reset changes.
- Placeholder scan: No TBD/TODO/fill-in steps remain.
- Type consistency: The plan consistently uses `bossIds`, `GetKnownBossNameFromCombatEvent(event)`, `MarkBossCombat(event)`, `currentCombat.isBoss`, and `currentCombat.firstEnemy`.
- Scope: The plan only touches existing boss modules plus Core combat detection and combat-system tests.
