# Faction Champions Automark Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a 180-second target/mouseover automark mode for Faction Champions in Trial of the Crusader, sharing state with the existing combat-log marker.

**Architecture:** Extend `TrialCrusaderTracker` instead of adding a new module. The tracker keeps one shared champion state, adds explicit-unit marking for target/mouseover, owns its timer and boss-message handlers, while `Core.lua` only adds a small slash-command bridge.

**Tech Stack:** Lua 5.1-style WoW 3.3.5a addon code, AceAddon/AceEvent module pattern, `UnitGUID`, `SetRaidTarget`, `C_Timer.NewTicker`, Busted tests with local mocks.

---

## File Structure

- Modify `modules/bosses/TrialCrusaderTracker.lua`
  - Add automark constants, target/mouseover scan logic, ticker lifecycle, boss yell/emote debug logging, and partial trigger matching.
  - Keep existing combat-log champion detection and Icehowl trample logging in the same module.
- Modify `Core.lua`
  - Add `/rlh tocmarks` help text and route the command to `TrialCrusaderTracker:StartFactionChampionAutomark()`.
- Modify `tests/TrialCrusaderTracker.test.lua`
  - Add focused tests for target/mouseover scan behavior, shared state, timeout, completion shutdown, and boss-message debug/autostart.
- Modify `tests/Core.test.lua`
  - Add one slash-command routing test for `/rlh tocmarks`.
- Leave `tests/mocks.lua` unchanged; existing `UnitGUID`, `UnitExists`, `C_Timer.NewTicker`, and `GetTime` mocks are enough for this plan.

## Preconditions

- Run `git status --short` before editing.
- Existing untracked `.codex`, `AGENTS.md`, and `docs/superpowers/plans/` may be present. Do not add them except for this plan file when committing the plan, and do not revert unrelated changes.
- The feature implementation should be committed in small commits after each task that passes tests.

### Task 1: Add Failing Tests for Target/Mouseover Scanning

**Files:**
- Modify: `tests/TrialCrusaderTracker.test.lua`

- [ ] **Step 1: Add automark test helpers**

In `tests/TrialCrusaderTracker.test.lua`, inside `describe('TrialCrusaderTracker', function()`, after `unrelatedDamage()`, add:

```lua
    local function collectMarks()
        local calls = {}
        _G.SetRaidTarget = function(unitId, marker)
            table.insert(calls, { unitId = unitId, marker = marker })
        end
        return calls
    end
```

- [ ] **Step 2: Add target and mouseover tests**

Before the existing `it('stops champion marking after all configured marks are done', function()` test, add:

```lua
    it('marks a target faction champion during automark scan', function()
        local mocks = require('tests.mocks')
        local hunterGuid = championGuid(34467)
        local calls = collectMarks()

        mocks:SetUnitGUID("target", hunterGuid)

        TrialCrusaderTracker:StartFactionChampionAutomark()

        assert.are.same({
            {
                unitId = "target",
                marker = 8
            }
        }, calls)
        assert.are.equal(hunterGuid, TrialCrusaderTracker.championGuidsByRole.HUNTER)
    end)

    it('marks a mouseover faction champion during automark scan', function()
        local mocks = require('tests.mocks')
        local warriorGuid = championGuid(34455)
        local calls = collectMarks()

        mocks:SetUnitGUID("mouseover", warriorGuid)

        TrialCrusaderTracker:StartFactionChampionAutomark()

        assert.are.same({
            {
                unitId = "mouseover",
                marker = 2
            }
        }, calls)
        assert.are.equal(warriorGuid, TrialCrusaderTracker.championGuidsByRole.WARRIOR)
    end)
```

- [ ] **Step 3: Add ignore test for non-scanned units**

After the target/mouseover tests, add:

```lua
    it('does not scan boss focus or raid units during automark scan', function()
        local mocks = require('tests.mocks')
        local calls = collectMarks()

        mocks:SetUnitGUID("boss1", championGuid(34467))
        mocks:SetUnitGUID("focus", championGuid(34455))
        mocks:SetUnitGUID("raid1target", championGuid(34447))

        TrialCrusaderTracker:StartFactionChampionAutomark()

        assert.are.same({}, calls)
        assert.are.same({}, TrialCrusaderTracker.championGuidsByRole)
    end)
```

- [ ] **Step 4: Run tests and verify expected failure**

Run:

```bash
busted --verbose tests/TrialCrusaderTracker.test.lua
```

Expected: FAIL with a message like `attempt to call method 'StartFactionChampionAutomark'`.

### Task 2: Implement Minimal Target/Mouseover Scan

**Files:**
- Modify: `modules/bosses/TrialCrusaderTracker.lua`

- [ ] **Step 1: Add automark constants**

Near the existing `ICEHOWL_TRAMPLE` constant, add:

```lua
local FACTION_CHAMPION_AUTOMARK_SECONDS = 180
local FACTION_CHAMPION_AUTOMARK_INTERVAL = 0.2
local FACTION_CHAMPION_AUTOMARK_UNITS = { "target", "mouseover" }
```

- [ ] **Step 2: Add explicit-unit fixed marker helper**

Replace the current `markFixedChampion` function:

```lua
function TrialCrusaderTracker:markFixedChampion(role)
    local marker = FIXED_MARKS[role]
    if not marker or self.markedRoles[role] then
        return false
    end

    local unitId = unitIdFromGuid(self.championGuidsByRole[role])
    if unitId and markUnit(unitId, marker) then
        self.markedRoles[role] = true
        return true
    end

    return false
end
```

with:

```lua
function TrialCrusaderTracker:markFixedChampionUnit(role, unitId)
    local marker = FIXED_MARKS[role]
    if not marker or self.markedRoles[role] or not unitId then
        return false
    end

    if markUnit(unitId, marker) then
        self.markedRoles[role] = true
        return true
    end

    return false
end

function TrialCrusaderTracker:markFixedChampion(role)
    return self:markFixedChampionUnit(role, unitIdFromGuid(self.championGuidsByRole[role]))
end
```

- [ ] **Step 3: Add time and scan functions**

After `markDiamondChampion()`, add:

```lua
local function getNow()
    if type(GetTime) == "function" then
        return GetTime()
    end

    return time()
end

function TrialCrusaderTracker:markFactionChampionUnit(unitId)
    if type(UnitGUID) ~= "function" then
        return false
    end

    local guid = UnitGUID(unitId)
    local role = championRoleFromGuid(guid)
    if not role then
        return false
    end

    self:rememberFactionChampion(guid)
    local fixedMarked = self:markFixedChampionUnit(role, unitId)
    local diamondMarked = self:markDiamondChampion()

    return fixedMarked or diamondMarked
end

function TrialCrusaderTracker:ScanFactionChampionAutomark()
    if not self.factionChampionAutomarkActiveUntil then
        return false
    end

    if self:AreChampionMarksDone() or getNow() > self.factionChampionAutomarkActiveUntil then
        self:StopFactionChampionAutomark()
        return false
    end

    local marked = false
    for _, unitId in ipairs(FACTION_CHAMPION_AUTOMARK_UNITS) do
        if self:markFactionChampionUnit(unitId) then
            marked = true
        end
    end

    if self:AreChampionMarksDone() then
        self:StopFactionChampionAutomark()
    end

    return marked
end
```

- [ ] **Step 4: Add start and stop functions**

After `ScanFactionChampionAutomark()`, add:

```lua
function TrialCrusaderTracker:StopFactionChampionAutomark()
    if self.factionChampionAutomarkTicker and type(self.factionChampionAutomarkTicker.Cancel) == "function" then
        self.factionChampionAutomarkTicker:Cancel()
    end

    self.factionChampionAutomarkTicker = nil
    self.factionChampionAutomarkActiveUntil = nil
end

function TrialCrusaderTracker:StartFactionChampionAutomark()
    if self:AreChampionMarksDone() then
        return false
    end

    self.factionChampionAutomarkActiveUntil = getNow() + FACTION_CHAMPION_AUTOMARK_SECONDS

    if not self.factionChampionAutomarkTicker then
        local timerApi = C_Timer
        if timerApi and type(timerApi.NewTicker) == "function" then
            self.factionChampionAutomarkTicker = timerApi.NewTicker(FACTION_CHAMPION_AUTOMARK_INTERVAL, function()
                self:ScanFactionChampionAutomark()
            end)
        end
    end

    self:ScanFactionChampionAutomark()
    return true
end
```

- [ ] **Step 5: Stop ticker during reset**

At the start of `TrialCrusaderTracker:reset()`, add:

```lua
    self:StopFactionChampionAutomark()
```

The resulting function should start like:

```lua
function TrialCrusaderTracker:reset()
    self:StopFactionChampionAutomark()
    self.championGuidsByRole = {}
    self.seenChampionGuids = {}
```

- [ ] **Step 6: Run tests and verify pass**

Run:

```bash
busted --verbose tests/TrialCrusaderTracker.test.lua
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add modules/bosses/TrialCrusaderTracker.lua tests/TrialCrusaderTracker.test.lua
git commit -m "feat: scan target and mouseover champions"
```

### Task 3: Add Failing Tests for Shared State and Diamond Priority

**Files:**
- Modify: `tests/TrialCrusaderTracker.test.lua`

- [ ] **Step 1: Add shared-state retry test**

After the non-scanned-units test, add:

```lua
    it('marks a champion discovered by combat log once it becomes target', function()
        local mocks = require('tests.mocks')
        local hunterGuid = championGuid(34467)

        TrialCrusaderTracker:handleEvent(damageFromChampion(34467))
        assert.are.equal(hunterGuid, TrialCrusaderTracker.championGuidsByRole.HUNTER)
        assert.is_nil(TrialCrusaderTracker.markedRoles.HUNTER)

        local calls = collectMarks()
        mocks:SetUnitGUID("target", hunterGuid)

        TrialCrusaderTracker:StartFactionChampionAutomark()

        assert.are.same({
            {
                unitId = "target",
                marker = 8
            }
        }, calls)
        assert.is_true(TrialCrusaderTracker.markedRoles.HUNTER)
    end)
```

- [ ] **Step 2: Add no-duplicate test**

After the shared-state retry test, add:

```lua
    it('does not duplicate a fixed mark already assigned through combat log', function()
        local mocks = require('tests.mocks')
        local hunterGuid = championGuid(34467)
        local calls = collectMarks()

        mocks:SetUnitGUID("boss1", hunterGuid)
        TrialCrusaderTracker:handleEvent(damageFromChampion(34467))

        mocks:SetUnitGUID("target", hunterGuid)
        TrialCrusaderTracker:StartFactionChampionAutomark()

        assert.are.same({
            {
                unitId = "boss1",
                marker = 8
            }
        }, calls)
    end)
```

- [ ] **Step 3: Add diamond priority test through target/mouseover**

After the no-duplicate test, add:

```lua
    it('marks diamond by priority when champions are discovered through target and mouseover', function()
        local mocks = require('tests.mocks')
        local druidGuid = championGuid(34451)
        local shamanGuid = championGuid(34463)
        local calls = collectMarks()

        mocks:SetUnitGUID("target", druidGuid)
        TrialCrusaderTracker:StartFactionChampionAutomark()

        mocks:SetUnitGUID("target", nil)
        mocks:SetUnitGUID("mouseover", shamanGuid)
        TrialCrusaderTracker:ScanFactionChampionAutomark()

        assert.are.same({
            {
                unitId = "target",
                marker = 3
            },
            {
                unitId = "mouseover",
                marker = 3
            }
        }, calls)
        assert.are.equal("ENHANCEMENT_SHAMAN", TrialCrusaderTracker.diamondRole)
    end)
```

- [ ] **Step 4: Run tests and verify pass**

Run:

```bash
busted --verbose tests/TrialCrusaderTracker.test.lua
```

Expected: PASS. The Task 2 implementation already calls `markFixedChampionUnit(role, unitId)` after `rememberFactionChampion(guid)`, so a champion first seen in combat log can still be marked later through `target`.

- [ ] **Step 5: Commit**

```bash
git add modules/bosses/TrialCrusaderTracker.lua tests/TrialCrusaderTracker.test.lua
git commit -m "test: cover shared champion automark state"
```

### Task 4: Add Failing Tests for Automark Lifecycle

**Files:**
- Modify: `tests/TrialCrusaderTracker.test.lua`

- [ ] **Step 1: Add active-window test**

After the diamond priority test, add:

```lua
    it('starts automark for 180 seconds', function()
        TrialCrusaderTracker:StartFactionChampionAutomark()

        assert.are.equal(GetTime() + 180, TrialCrusaderTracker.factionChampionAutomarkActiveUntil)
        assert.is_not_nil(TrialCrusaderTracker.factionChampionAutomarkTicker)
    end)
```

- [ ] **Step 2: Add completion shutdown test**

After the active-window test, add:

```lua
    it('stops automark when all configured marks are done', function()
        local mocks = require('tests.mocks')
        local guids = {
            hunter = championGuid(34467),
            warrior = championGuid(34455),
            priest = championGuid(34447),
            warlock = championGuid(34450),
            deathKnight = championGuid(34458),
            shaman = championGuid(34463)
        }

        mocks:SetUnitGUID("target", guids.hunter)
        TrialCrusaderTracker:StartFactionChampionAutomark()
        mocks:SetUnitGUID("target", guids.warrior)
        TrialCrusaderTracker:ScanFactionChampionAutomark()
        mocks:SetUnitGUID("target", guids.priest)
        TrialCrusaderTracker:ScanFactionChampionAutomark()
        mocks:SetUnitGUID("target", guids.warlock)
        TrialCrusaderTracker:ScanFactionChampionAutomark()
        mocks:SetUnitGUID("target", guids.deathKnight)
        TrialCrusaderTracker:ScanFactionChampionAutomark()
        mocks:SetUnitGUID("target", guids.shaman)
        TrialCrusaderTracker:ScanFactionChampionAutomark()

        assert.is_true(TrialCrusaderTracker:AreChampionMarksDone())
        assert.is_nil(TrialCrusaderTracker.factionChampionAutomarkTicker)
        assert.is_nil(TrialCrusaderTracker.factionChampionAutomarkActiveUntil)
    end)
```

- [ ] **Step 3: Add timeout shutdown test**

After the completion shutdown test, add:

```lua
    it('stops automark after the active window expires', function()
        local originalGetTime = _G.GetTime
        local now = 100
        _G.GetTime = function()
            return now
        end

        TrialCrusaderTracker:StartFactionChampionAutomark()
        assert.are.equal(280, TrialCrusaderTracker.factionChampionAutomarkActiveUntil)

        now = 281
        TrialCrusaderTracker:ScanFactionChampionAutomark()

        assert.is_nil(TrialCrusaderTracker.factionChampionAutomarkTicker)
        assert.is_nil(TrialCrusaderTracker.factionChampionAutomarkActiveUntil)

        _G.GetTime = originalGetTime
    end)
```

- [ ] **Step 4: Harden the timeout test cleanup**

In `before_each`, add:

```lua
        originalGetTime = _G.GetTime
```

and define the local near the other originals:

```lua
    local originalGetTime
```

In `after_each`, add:

```lua
        _G.GetTime = originalGetTime
```

Then remove the local `originalGetTime` save/restore lines from the timeout test so cleanup always runs even if an assertion fails. The timeout test should start with:

```lua
        local now = 100
        _G.GetTime = function()
            return now
        end
```

- [ ] **Step 5: Run tests and verify pass**

Run:

```bash
busted --verbose tests/TrialCrusaderTracker.test.lua
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add modules/bosses/TrialCrusaderTracker.lua tests/TrialCrusaderTracker.test.lua
git commit -m "feat: stop champion automark automatically"
```

### Task 5: Add Boss Yell/Emote Debug Logging and Autostart

**Files:**
- Modify: `modules/bosses/TrialCrusaderTracker.lua`
- Modify: `tests/TrialCrusaderTracker.test.lua`

- [ ] **Step 1: Add failing boss-message tests**

In `tests/TrialCrusaderTracker.test.lua`, define debug locals near `log`:

```lua
    local debugLog
    local originalDebug
```

In `before_each`, after `TrialCrusaderTracker.log = log`, add:

```lua
        originalDebug = TrialCrusaderTracker.debug
        debugLog = spy.new(function()
        end)
        TrialCrusaderTracker.debug = debugLog
        TrialCrusaderTracker.factionChampionStartFragments = {}
```

In `after_each`, before clearing unit GUIDs, add:

```lua
        TrialCrusaderTracker.debug = originalDebug
        TrialCrusaderTracker.factionChampionStartFragments = {}
```

After the lifecycle tests, add:

```lua
    it('logs Trial of the Crusader boss yell and emote messages for debug collection', function()
        TrialCrusaderTracker:CHAT_MSG_MONSTER_YELL("Champions, attack!", "Tirion Fordring")
        TrialCrusaderTracker:CHAT_MSG_RAID_BOSS_EMOTE("The next battle begins.", "Argent Coliseum")

        assert.spy(debugLog).was_called_with(
            "TrialCrusaderTracker CHAT_MSG_MONSTER_YELL sender='Tirion Fordring' text='Champions, attack!'")
        assert.spy(debugLog).was_called_with(
            "TrialCrusaderTracker CHAT_MSG_RAID_BOSS_EMOTE sender='Argent Coliseum' text='The next battle begins.'")
    end)

    it('starts automark when a boss message contains a configured trigger fragment', function()
        TrialCrusaderTracker.factionChampionStartFragments = { "Champions" }

        local started = TrialCrusaderTracker:CHAT_MSG_MONSTER_YELL("Champions, attack!", "Tirion Fordring")

        assert.is_true(started)
        assert.are.equal(GetTime() + 180, TrialCrusaderTracker.factionChampionAutomarkActiveUntil)
    end)
```

- [ ] **Step 2: Run tests and verify expected failure**

Run:

```bash
busted --verbose tests/TrialCrusaderTracker.test.lua
```

Expected: FAIL because `CHAT_MSG_MONSTER_YELL` and `CHAT_MSG_RAID_BOSS_EMOTE` are not implemented.

- [ ] **Step 3: Add trigger fragments and debug helper**

In `modules/bosses/TrialCrusaderTracker.lua`, after `CHAMPION_ROLE_BY_NPC_ID`, add:

```lua
local FACTION_CHAMPION_START_FRAGMENTS = {}

TrialCrusaderTracker.factionChampionStartFragments = FACTION_CHAMPION_START_FRAGMENTS
```

After `formatIcehowlTrample`, add:

```lua
local function formatBossMessageDebug(eventName, message, sender)
    return string.format("TrialCrusaderTracker %s sender='%s' text='%s'", eventName, tostring(sender or ""),
        tostring(message or ""))
end
```

- [ ] **Step 4: Register boss-message events**

In `OnInitialize`, after `self:RegisterMessage("RLHelper_CombatEnded", "reset")`, add:

```lua
    self:RegisterEvent("CHAT_MSG_MONSTER_YELL")
    self:RegisterEvent("CHAT_MSG_RAID_BOSS_EMOTE")
```

- [ ] **Step 5: Add boss-message handlers**

Before `handleEvent(event)`, add:

```lua
function TrialCrusaderTracker:debug(message)
    RLHelper:Debug(message)
end

function TrialCrusaderTracker:shouldStartFactionChampionAutomark(message)
    if type(message) ~= "string" then
        return false
    end

    for _, fragment in ipairs(self.factionChampionStartFragments or FACTION_CHAMPION_START_FRAGMENTS) do
        if fragment ~= "" and message:find(fragment, 1, true) then
            return true
        end
    end

    return false
end

function TrialCrusaderTracker:handleBossMessage(eventName, message, sender)
    self:debug(formatBossMessageDebug(eventName, message, sender))

    if self:shouldStartFactionChampionAutomark(message) then
        return self:StartFactionChampionAutomark()
    end

    return false
end

function TrialCrusaderTracker:CHAT_MSG_MONSTER_YELL(message, sender)
    return self:handleBossMessage("CHAT_MSG_MONSTER_YELL", message, sender)
end

function TrialCrusaderTracker:CHAT_MSG_RAID_BOSS_EMOTE(message, sender)
    return self:handleBossMessage("CHAT_MSG_RAID_BOSS_EMOTE", message, sender)
end
```

- [ ] **Step 6: Run tests and verify pass**

Run:

```bash
busted --verbose tests/TrialCrusaderTracker.test.lua
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add modules/bosses/TrialCrusaderTracker.lua tests/TrialCrusaderTracker.test.lua
git commit -m "feat: start champion automark from boss messages"
```

### Task 6: Add Slash Command Routing

**Files:**
- Modify: `Core.lua`
- Modify: `tests/Core.test.lua`

- [ ] **Step 1: Add failing slash command test**

In `tests/Core.test.lua`, after the `describe("RLHelper damage meter reset command", function()` block, add:

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

- [ ] **Step 2: Run the focused test and verify expected failure**

Run:

```bash
busted --verbose tests/Core.test.lua
```

Expected: FAIL because `HandleSlashCommand("tocmarks")` does nothing.

- [ ] **Step 3: Add Core bridge method**

In `Core.lua`, after `TriggerDamageMeterReset()`, add:

```lua
function RLHelper:TriggerTrialCrusaderAutomark()
    local trialCrusaderTracker = self:FindModuleByName("TrialCrusaderTracker")
    if not trialCrusaderTracker or type(trialCrusaderTracker.StartFactionChampionAutomark) ~= "function" then
        self:Debug("TrialCrusaderTracker недоступен")
        return false
    end

    local ok = trialCrusaderTracker:StartFactionChampionAutomark()
    if ok then
        self:Debug("Faction Champions automark запущен")
    end
    return ok
end
```

- [ ] **Step 4: Add slash help and command branch**

In `HandleSlashCommand`, in the help branch after:

```lua
        print("/rlh meters - вручную сбросить сегменты урона")
```

add:

```lua
        print("/rlh tocmarks - включить метки Faction Champions на 180 секунд")
```

Then after the existing meters branch:

```lua
    elseif input == "meters" then
        self:TriggerDamageMeterReset()
```

add:

```lua
    elseif input == "tocmarks" then
        self:TriggerTrialCrusaderAutomark()
```

- [ ] **Step 5: Run the focused Core tests**

Run:

```bash
busted --verbose tests/Core.test.lua
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Core.lua tests/Core.test.lua
git commit -m "feat: add tocmarks slash command"
```

### Task 7: Full Verification

**Files:**
- No code edits expected.

- [ ] **Step 1: Run focused Trial Crusader tests**

Run:

```bash
busted --verbose tests/TrialCrusaderTracker.test.lua
```

Expected: PASS.

- [ ] **Step 2: Run focused Core tests**

Run:

```bash
busted --verbose tests/Core.test.lua
```

Expected: PASS.

- [ ] **Step 3: Run full test suite**

Run:

```bash
make test
```

Expected: PASS for all tests in `./tests/*.lua`.

- [ ] **Step 4: Inspect final diff**

Run:

```bash
git diff --stat HEAD
git status --short
```

Expected: no unstaged implementation changes. Untracked `.codex`, `AGENTS.md`, or unrelated plan files may remain if they existed before.

- [ ] **Step 5: Commit verification corrections**

If verification required a correction, commit only the touched feature files:

```bash
git add Core.lua modules/bosses/TrialCrusaderTracker.lua tests/Core.test.lua tests/TrialCrusaderTracker.test.lua
git commit -m "test: verify faction champion automark"
```

Expected when no correction was required: `git diff --stat HEAD` printed no tracked implementation changes, so skip this commit step.
