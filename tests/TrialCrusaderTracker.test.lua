require('tests.mocks')
require("../lib/blizzardEvent")
local TrialCrusaderTracker = require("../modules/bosses/TrialCrusaderTracker")
local Builder = require("../utils/CombatEventBuilder")

local function dispatch(module, ...)
    module:handleEvent(blizzardEvent(select(2, ...)))
end

describe('TrialCrusaderTracker', function()
    local log
    local debugLog
    local originalDebug
    local originalSetRaidTarget
    local originalGetRealNumRaidMembers
    local originalGetTime

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
        originalGetTime = _G.GetTime
        log = spy.new(function()
        end)
        TrialCrusaderTracker.log = log
        originalDebug = TrialCrusaderTracker.debug
        debugLog = spy.new(function()
        end)
        TrialCrusaderTracker.debug = debugLog
        TrialCrusaderTracker.factionChampionStartFragments = nil
        TrialCrusaderTracker:reset()
    end)

    after_each(function()
        _G.SetRaidTarget = originalSetRaidTarget
        _G.GetRealNumRaidMembers = originalGetRealNumRaidMembers
        _G.GetTime = originalGetTime
        TrialCrusaderTracker.debug = originalDebug
        TrialCrusaderTracker.factionChampionStartFragments = nil
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
        local warriorGuid = championGuid(34453)
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
        TrialCrusaderTracker:handleEvent(damageFromChampion(34453))
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

    it('marks rogue faction champions with cross', function()
        local mocks = require('tests.mocks')
        local rogueGuid = championGuid(34454)
        local calls = {}

        mocks:SetUnitGUID("boss1", rogueGuid)
        _G.SetRaidTarget = function(unitId, marker)
            table.insert(calls, { unitId = unitId, marker = marker })
        end

        TrialCrusaderTracker:handleEvent(damageFromChampion(34454))

        assert.are.same({
            {
                unitId = "boss1",
                marker = 7
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
        local warriorGuid = championGuid(34453)
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
        mocks:SetUnitGUID("focus", championGuid(34453))
        mocks:SetUnitGUID("raid1target", championGuid(34447))

        TrialCrusaderTracker:StartFactionChampionAutomark()

        assert.are.same({}, calls)
        assert.are.same({}, TrialCrusaderTracker.championGuidsByRole)
    end)

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

    it('starts automark for 180 seconds', function()
        TrialCrusaderTracker:StartFactionChampionAutomark()

        assert.are.equal(GetTime() + 180, TrialCrusaderTracker.factionChampionAutomarkActiveUntil)
        assert.is_not_nil(TrialCrusaderTracker.factionChampionAutomarkTicker)
    end)

    it('stops automark when all configured marks are done', function()
        local mocks = require('tests.mocks')
        collectMarks()
        local guids = {
            hunter = championGuid(34467),
            warrior = championGuid(34453),
            priest = championGuid(34447),
            warlock = championGuid(34450),
            deathKnight = championGuid(34458),
            rogue = championGuid(34454),
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
        mocks:SetUnitGUID("target", guids.rogue)
        TrialCrusaderTracker:ScanFactionChampionAutomark()
        mocks:SetUnitGUID("target", guids.shaman)
        TrialCrusaderTracker:ScanFactionChampionAutomark()

        assert.is_true(TrialCrusaderTracker:AreChampionMarksDone())
        assert.is_nil(TrialCrusaderTracker.factionChampionAutomarkTicker)
        assert.is_nil(TrialCrusaderTracker.factionChampionAutomarkActiveUntil)
    end)

    it('stops automark after the active window expires', function()
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
    end)

    it('logs Trial of the Crusader boss yell and emote messages for debug collection', function()
        TrialCrusaderTracker:CHAT_MSG_MONSTER_YELL("CHAT_MSG_MONSTER_YELL", "Champions, attack!", "Tirion Fordring")
        TrialCrusaderTracker:CHAT_MSG_RAID_BOSS_EMOTE("CHAT_MSG_RAID_BOSS_EMOTE", "The next battle begins.",
            "Argent Coliseum")

        assert.spy(debugLog).was_called_with(
            "TrialCrusaderTracker CHAT_MSG_MONSTER_YELL sender='Tirion Fordring' text='Champions, attack!'")
        assert.spy(debugLog).was_called_with(
            "TrialCrusaderTracker CHAT_MSG_RAID_BOSS_EMOTE sender='Argent Coliseum' text='The next battle begins.'")
    end)

    it('starts automark when Tirion announces Faction Champions', function()
        local started = TrialCrusaderTracker:CHAT_MSG_MONSTER_YELL(
            "CHAT_MSG_MONSTER_YELL",
            "В следующем бою вы встретитесь с могучими рыцарями Серебряного Авангарда! Лишь победив их, вы заслужите достойную награду.",
            "Тирион Фордринг")

        assert.is_true(started)
        assert.are.equal(GetTime() + 180, TrialCrusaderTracker.factionChampionAutomarkActiveUntil)
    end)

    it('does not start automark from a raid boss emote with the Faction Champions phrase', function()
        local started = TrialCrusaderTracker:CHAT_MSG_RAID_BOSS_EMOTE(
            "CHAT_MSG_RAID_BOSS_EMOTE",
            "В следующем бою вы встретитесь с могучими рыцарями Серебряного Авангарда! Лишь победив их, вы заслужите достойную награду.",
            "Тирион Фордринг")

        assert.is_false(started)
        assert.is_nil(TrialCrusaderTracker.factionChampionAutomarkActiveUntil)
    end)

    it('stops champion marking after all configured marks are done', function()
        local mocks = require('tests.mocks')
        local guids = {
            hunter = championGuid(34467),
            warrior = championGuid(34453),
            priest = championGuid(34447),
            warlock = championGuid(34450),
            deathKnight = championGuid(34458),
            rogue = championGuid(34454),
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
        mocks:SetUnitGUID("mouseover", guids.rogue)
        mocks:SetUnitGUID("target", guids.paladin)

        _G.SetRaidTarget = function()
            setRaidTargetCalls = setRaidTargetCalls + 1
        end

        TrialCrusaderTracker:handleEvent(damageFromChampion(34467))
        TrialCrusaderTracker:handleEvent(damageFromChampion(34453))
        TrialCrusaderTracker:handleEvent(damageFromChampion(34447))
        TrialCrusaderTracker:handleEvent(damageFromChampion(34450))
        TrialCrusaderTracker:handleEvent(damageFromChampion(34458))
        TrialCrusaderTracker:handleEvent(damageFromChampion(34454))
        TrialCrusaderTracker:handleEvent(damageFromChampion(34463))

        assert.is_true(TrialCrusaderTracker:AreChampionMarksDone())
        local callsAfterComplete = setRaidTargetCalls

        TrialCrusaderTracker:handleEvent(damageFromChampion(34445))

        assert.are.equal(callsAfterComplete, setRaidTargetCalls)
        assert.is_nil(TrialCrusaderTracker.championGuidsByRole.RETRIBUTION_PALADIN)
    end)
end)
