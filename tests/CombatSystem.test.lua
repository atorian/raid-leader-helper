local M = require('tests.mocks')
require('../lib/blizzardEvent')
local TestAddon = require('../Core')
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
        TestAddon:StopCombatTicker()
        TestAddon.inCombat = false
        TestAddon.lastCombatActivityAt = nil
        TestAddon.combatEndRequestedAt = nil
        TestAddon.currentCombat = {
            startTime = nil,
            messages = {},
            firstEnemy = nil
        }
        TestAddon.combatHistory = {}
        TestAddon.DisplayCombat = function()
        end
        TestAddon.mainFrame = {
            logText = {
                AddMessage = function()
                end,
                Clear = function()
                end
            }
        }

        wipe(TestAddon.activeEnemies)
        wipe(TestAddon.activePlayers)
        wipe(TestAddon.enemyEvents)

        TestAddon.db = {
            profile = {
                debug = false,
                combatHistory = {}
            }
        }

        M.partySize = 0
        M.raidSize = 0
        M.UnitAffectingCombat1 = true
        M.UnitAffectingCombat2 = false
        M.UnitAffectingCombat3 = false
    end)

    it("начинает бой когда игрок входит в бой", function()
        TestAddon:PLAYER_REGEN_DISABLED()

        assert.is_true(TestAddon.inCombat)
    end)

    it("начинает бой от боевого лога и отслеживает участников", function()
        M.UnitAffectingCombat1 = false

        TestAddon:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Враг1"):ToPlayer("Игрок1"):Damage(100):Build())

        assert.is_true(TestAddon.inCombat)
        assert.are.equal(1, count(TestAddon.activeEnemies))
        assert.are.equal(1, count(TestAddon.activePlayers))
        assert.are.equal("Враг1", TestAddon.currentCombat.firstEnemy)
    end)

    it("игнорирует World Invisible Trigger как название боя", function()
        M.UnitAffectingCombat1 = false

        TestAddon:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("World Invisible Trigger"):ToPlayer("Игрок1")
            :Damage(100):Build())
        TestAddon:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Ануб'арак"):ToPlayer("Игрок1")
            :Damage(100):Build())

        assert.are.equal("Ануб'арак", TestAddon.currentCombat.firstEnemy)
    end)

    it("не завершает бой сразу по PLAYER_REGEN_ENABLED", function()
        TestAddon:PLAYER_REGEN_DISABLED()
        TestAddon:PLAYER_REGEN_ENABLED()

        assert.is_true(TestAddon.inCombat)
    end)

    it("не завершает бой пока группа еще в бою", function()
        TestAddon:PLAYER_REGEN_DISABLED()
        TestAddon:OnCombatLogEvent("test message")

        M.partySize = 1
        M.UnitAffectingCombat1 = false
        M.UnitAffectingCombat2 = true
        TestAddon.lastCombatActivityAt = TestAddon:GetCombatNow() - 10
        TestAddon.combatEndRequestedAt = TestAddon:GetCombatNow() - 5

        assert.is_false(TestAddon:EvaluateCombatEnd("test"))
        assert.is_true(TestAddon.inCombat)
        assert.are.equal(0, #TestAddon.combatHistory)
    end)

    it("завершает бой после тихого периода вне боя", function()
        TestAddon:PLAYER_REGEN_DISABLED()
        TestAddon:OnCombatLogEvent("test message")

        M.UnitAffectingCombat1 = false
        TestAddon.lastCombatActivityAt = TestAddon:GetCombatNow() - 10
        TestAddon.combatEndRequestedAt = TestAddon:GetCombatNow() - 5

        assert.is_true(TestAddon:EvaluateCombatEnd("test"))
        assert.is_false(TestAddon.inCombat)
        assert.are.equal(1, #TestAddon.combatHistory)
    end)
end)
