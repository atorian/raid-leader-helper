require('tests.mocks')
require("../lib/blizzardEvent")
local TrialCrusaderTracker = require("../modules/bosses/TrialCrusaderTracker")
local Builder = require("../utils/CombatEventBuilder")

local function dispatch(module, ...)
    module:handleEvent(blizzardEvent(select(2, ...)))
end

describe('TrialCrusaderTracker', function()
    local log
    local originalSetRaidTarget
    local originalGetRealNumRaidMembers

    local function championGuid(npcId, spawnId)
        return string.format("0xF13000%04X%06X", npcId, spawnId or npcId)
    end

    local function damageFromChampion(npcId)
        return {
            event = "SPELL_DAMAGE",
            sourceGUID = championGuid(npcId),
            destGUID = "0x0000000000000001"
        }
    end

    local function unrelatedDamage()
        return {
            event = "SPELL_DAMAGE",
            sourceGUID = championGuid(34780),
            destGUID = "0x0000000000000001"
        }
    end

    local function collectMarks()
        local calls = {}
        _G.SetRaidTarget = function(unitId, marker)
            table.insert(calls, { unitId = unitId, marker = marker })
        end
        return calls
    end

    before_each(function()
        originalSetRaidTarget = _G.SetRaidTarget
        originalGetRealNumRaidMembers = _G.GetRealNumRaidMembers
        log = spy.new(function()
        end)
        TrialCrusaderTracker.log = log
        TrialCrusaderTracker:reset()
    end)

    after_each(function()
        _G.SetRaidTarget = originalSetRaidTarget
        _G.GetRealNumRaidMembers = originalGetRealNumRaidMembers
        require('tests.mocks'):ClearUnitGUIDs()
    end)

    it('receives combat events only in Trial of the Crusader', function()
        assert.is_true(TrialCrusaderTracker.receivesCombatEvents)
        assert.are.equal(649, TrialCrusaderTracker.zoneGateInstanceId)
    end)

    it('logs players trampled by Icehowl', function()
        dispatch(TrialCrusaderTracker, Builder:New():FromEnemy("Ледяной Рев"):ToPlayer("Игрок1")
            :SpellDamage(66734, "Trample", 50000):Build())

        assert.spy(log).was_called_with(
            "SOME DATE |cFFFFFFFFИгрок1|r |TInterface\\Icons\\Ability_Druid_DemoralizingRoar:24:24:0:0|t размазало об стену")
    end)

    it('ignores unrelated damage events', function()
        dispatch(TrialCrusaderTracker, Builder:New():FromEnemy("Ледяной Рев"):ToPlayer("Игрок1")
            :SpellDamage(66330, "Whirl", 8000):Build())

        assert.spy(log).was_not_called()
    end)

    it('marks faction champions once they appear in combat log', function()
        local mocks = require('tests.mocks')
        local hunterGuid = championGuid(34467)
        local warriorGuid = championGuid(34455)
        local priestGuid = championGuid(34447)
        local warlockGuid = championGuid(34450)
        local deathKnightGuid = championGuid(34458)
        local marks = {}

        mocks:SetUnitGUID("boss1", hunterGuid)
        mocks:SetUnitGUID("boss2", warriorGuid)
        mocks:SetUnitGUID("boss3", priestGuid)
        mocks:SetUnitGUID("boss4", warlockGuid)
        mocks:SetUnitGUID("boss5", deathKnightGuid)

        _G.SetRaidTarget = function(unitId, marker)
            marks[unitId] = marker
        end

        TrialCrusaderTracker:handleEvent(damageFromChampion(34467))
        TrialCrusaderTracker:handleEvent(damageFromChampion(34455))
        TrialCrusaderTracker:handleEvent(damageFromChampion(34447))
        TrialCrusaderTracker:handleEvent(damageFromChampion(34450))
        TrialCrusaderTracker:handleEvent(damageFromChampion(34458))

        assert.are.equal(8, marks.boss1)
        assert.are.equal(2, marks.boss2)
        assert.are.equal(1, marks.boss3)
        assert.are.equal(5, marks.boss4)
        assert.are.equal(4, marks.boss5)
    end)

    it('marks fixed champions immediately without waiting for the full champion set', function()
        local mocks = require('tests.mocks')
        local hunterGuid = championGuid(34467)
        local calls = {}

        mocks:SetUnitGUID("boss1", hunterGuid)
        _G.SetRaidTarget = function(unitId, marker)
            table.insert(calls, { unitId = unitId, marker = marker })
        end

        TrialCrusaderTracker:handleEvent(damageFromChampion(34467))

        assert.are.same({
            {
                unitId = "boss1",
                marker = 8
            }
        }, calls)
    end)

    it('upgrades diamond when a higher priority champion appears later', function()
        local mocks = require('tests.mocks')
        local shamanGuid = championGuid(34463)
        local paladinGuid = championGuid(34445)
        local druidGuid = championGuid(34451)
        local calls = {}

        mocks:SetUnitGUID("boss1", druidGuid)
        mocks:SetUnitGUID("boss2", paladinGuid)
        mocks:SetUnitGUID("boss3", shamanGuid)

        _G.SetRaidTarget = function(unitId, marker)
            table.insert(calls, { unitId = unitId, marker = marker })
        end

        TrialCrusaderTracker:handleEvent(damageFromChampion(34451))
        TrialCrusaderTracker:handleEvent(damageFromChampion(34445))
        TrialCrusaderTracker:handleEvent(damageFromChampion(34463))

        assert.are.same({
            {
                unitId = "boss1",
                marker = 3
            },
            {
                unitId = "boss2",
                marker = 3
            },
            {
                unitId = "boss3",
                marker = 3
            }
        }, calls)
        assert.are.equal("ENHANCEMENT_SHAMAN", TrialCrusaderTracker.diamondRole)
    end)

    it('does not mark a fixed champion twice in the same combat', function()
        local mocks = require('tests.mocks')
        local hunterGuid = championGuid(34467)
        mocks:SetUnitGUID("boss1", hunterGuid)
        local setRaidTargetCalls = 0
        _G.SetRaidTarget = function()
            setRaidTargetCalls = setRaidTargetCalls + 1
        end

        TrialCrusaderTracker:handleEvent(damageFromChampion(34467))
        TrialCrusaderTracker:handleEvent(damageFromChampion(34467))

        assert.are.equal(1, setRaidTargetCalls)
    end)

    it('skips champion marking for unrelated combat log events', function()
        local setRaidTargetCalls = 0
        _G.SetRaidTarget = function()
            setRaidTargetCalls = setRaidTargetCalls + 1
        end

        TrialCrusaderTracker:handleEvent(unrelatedDamage())

        assert.are.equal(0, setRaidTargetCalls)
        assert.are.same({}, TrialCrusaderTracker.championGuidsByRole)
        assert.are.same({}, TrialCrusaderTracker.seenChampionGuids)
    end)

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

    it('stops champion marking after all configured marks are done', function()
        local mocks = require('tests.mocks')
        local guids = {
            hunter = championGuid(34467),
            warrior = championGuid(34455),
            priest = championGuid(34447),
            warlock = championGuid(34450),
            deathKnight = championGuid(34458),
            shaman = championGuid(34463),
            paladin = championGuid(34445)
        }
        local setRaidTargetCalls = 0

        mocks:SetUnitGUID("boss1", guids.hunter)
        mocks:SetUnitGUID("boss2", guids.warrior)
        mocks:SetUnitGUID("boss3", guids.priest)
        mocks:SetUnitGUID("boss4", guids.warlock)
        mocks:SetUnitGUID("boss5", guids.deathKnight)
        mocks:SetUnitGUID("focus", guids.shaman)
        mocks:SetUnitGUID("target", guids.paladin)

        _G.SetRaidTarget = function()
            setRaidTargetCalls = setRaidTargetCalls + 1
        end

        TrialCrusaderTracker:handleEvent(damageFromChampion(34467))
        TrialCrusaderTracker:handleEvent(damageFromChampion(34455))
        TrialCrusaderTracker:handleEvent(damageFromChampion(34447))
        TrialCrusaderTracker:handleEvent(damageFromChampion(34450))
        TrialCrusaderTracker:handleEvent(damageFromChampion(34458))
        TrialCrusaderTracker:handleEvent(damageFromChampion(34463))

        assert.is_true(TrialCrusaderTracker:AreChampionMarksDone())
        local callsAfterComplete = setRaidTargetCalls

        TrialCrusaderTracker:handleEvent(damageFromChampion(34445))

        assert.are.equal(callsAfterComplete, setRaidTargetCalls)
        assert.is_nil(TrialCrusaderTracker.championGuidsByRole.RETRIBUTION_PALADIN)
    end)
end)
