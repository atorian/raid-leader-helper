local M = require('tests.mocks')
require('../lib/blizzardEvent')
local RLHelper = require('../Core')
local Builder = require('../utils/CombatEventBuilder')

local function count(tbl)
    local total = 0
    for _ in pairs(tbl) do
        total = total + 1
    end
    return total
end

describe("Боевая система", function()
    before_each(function()
        RLHelper:StopCombatTicker()
        RLHelper.inCombat = false
        RLHelper.lastCombatActivityAt = nil
        RLHelper.combatEndRequestedAt = nil
        RLHelper.currentCombat = {
            startTime = nil,
            messages = {},
            firstEnemy = nil,
            isBoss = false
        }
        RLHelper.combatHistory = {}
        RLHelper.DisplayCombat = function()
        end
        RLHelper.mainFrame = {
            logText = {
                AddMessage = function()
                end,
                Clear = function()
                end
            }
        }

        wipe(RLHelper.activeEnemies)
        wipe(RLHelper.activePlayers)
        wipe(RLHelper.enemyEvents)

        RLHelper.db = {
            profile = {
                debug = false,
                combatHistory = {},
                bossOnlyHistory = false
            }
        }

        M:ClearUnitGUIDs()
        M.partySize = 0
        M.raidSize = 0
        M.UnitAffectingCombat1 = true
        M.UnitAffectingCombat2 = false
        M.UnitAffectingCombat3 = false
    end)

    it("начинает бой когда игрок входит в бой", function()
        RLHelper:PLAYER_REGEN_DISABLED()

        assert.is_true(RLHelper.inCombat)
    end)

    it("начинает бой от боевого лога и отслеживает участников", function()
        M.UnitAffectingCombat1 = false

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Враг1"):ToPlayer("Игрок1"):Damage(100):Build())

        assert.is_true(RLHelper.inCombat)
        assert.are.equal(1, count(RLHelper.activeEnemies))
        assert.are.equal(1, count(RLHelper.activePlayers))
        assert.are.equal("Враг1", RLHelper.currentCombat.firstEnemy)
    end)

    it("переименовывает бой в имя босса если босс появился после обычного врага", function()
        M.UnitAffectingCombat1 = false

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Адд"):ToPlayer("Игрок1"):Damage(100):Build())

        local bossEvent = { Builder:New():FromEnemy("Босс"):ToPlayer("Игрок1"):Damage(100):Build() }
        M:SetUnitGUID("boss1", "0xF130000000000001")
        M:SetUnitName("boss1", "Босс")

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(unpack(bossEvent))

        assert.is_true(RLHelper.currentCombat.isBoss)
        assert.are.equal("Босс", RLHelper.currentCombat.firstEnemy)
    end)

    it("проверяет только boss1 при определении босса", function()
        M.UnitAffectingCombat1 = false

        local bossEvent = { Builder:New():FromEnemy("Босс2"):ToPlayer("Игрок1"):Damage(100):Build() }
        M:SetUnitGUID("boss2", bossEvent[4])
        M:SetUnitName("boss2", "Босс2")

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(unpack(bossEvent))

        assert.is_false(RLHelper.currentCombat.isBoss)
    end)

    it("игнорирует World Invisible Trigger как название боя", function()
        M.UnitAffectingCombat1 = false

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("World Invisible Trigger"):ToPlayer("Игрок1")
            :Damage(100):Build())
        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Ануб'арак"):ToPlayer("Игрок1")
            :Damage(100):Build())

        assert.are.equal("Ануб'арак", RLHelper.currentCombat.firstEnemy)
    end)

    it("не завершает бой сразу по PLAYER_REGEN_ENABLED", function()
        RLHelper:PLAYER_REGEN_DISABLED()
        RLHelper:PLAYER_REGEN_ENABLED()

        assert.is_true(RLHelper.inCombat)
    end)

    it("не завершает бой пока группа еще в бою", function()
        RLHelper:PLAYER_REGEN_DISABLED()
        RLHelper:OnCombatLogEvent("test message")

        M.partySize = 1
        M.UnitAffectingCombat1 = false
        M.UnitAffectingCombat2 = true
        RLHelper.lastCombatActivityAt = RLHelper:GetCombatNow() - 10
        RLHelper.combatEndRequestedAt = RLHelper:GetCombatNow() - 5

        assert.is_false(RLHelper:EvaluateCombatEnd("test"))
        assert.is_true(RLHelper.inCombat)
        assert.are.equal(0, #RLHelper.combatHistory)
    end)

    it("завершает бой после тихого периода вне боя", function()
        RLHelper:PLAYER_REGEN_DISABLED()
        RLHelper:OnCombatLogEvent("test message")

        M.UnitAffectingCombat1 = false
        RLHelper.lastCombatActivityAt = RLHelper:GetCombatNow() - 10
        RLHelper.combatEndRequestedAt = RLHelper:GetCombatNow() - 5

        assert.is_true(RLHelper:EvaluateCombatEnd("test"))
        assert.is_false(RLHelper.inCombat)
        assert.are.equal(1, #RLHelper.combatHistory)
    end)

    it("не сохраняет обычный бой когда включена история только боссов", function()
        RLHelper.db.profile.bossOnlyHistory = true
        RLHelper:PLAYER_REGEN_DISABLED()
        RLHelper:OnCombatLogEvent("test message")

        M.UnitAffectingCombat1 = false
        RLHelper.lastCombatActivityAt = RLHelper:GetCombatNow() - 10
        RLHelper.combatEndRequestedAt = RLHelper:GetCombatNow() - 5

        assert.is_true(RLHelper:EvaluateCombatEnd("test"))
        assert.are.equal(0, #RLHelper.combatHistory)
        assert.are.equal(0, #RLHelper.db.profile.combatHistory)
    end)

    it("сохраняет боссовый бой когда включена история только боссов", function()
        RLHelper.db.profile.bossOnlyHistory = true
        M.UnitAffectingCombat1 = false

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Адд"):ToPlayer("Игрок1"):Damage(100):Build())
        local bossEvent = { Builder:New():FromEnemy("Адд2"):ToPlayer("Игрок1"):Damage(100):Build() }
        M:SetUnitGUID("boss1", "0xF130000000000001")
        M:SetUnitName("boss1", "Босс")

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
        assert.are.equal("Босс", RLHelper.combatHistory[1].firstEnemy)
        assert.are.equal("Босс", RLHelper.db.profile.combatHistory[1].firstEnemy)
    end)
end)
