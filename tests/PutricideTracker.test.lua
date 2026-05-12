require('tests.mocks')
require('../lib/blizzardEvent')

local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local spy = require("luassert.spy")
local Builder = require("../utils/CombatEventBuilder")

local ok, PutricideTracker = pcall(require, "../modules/bosses/PutricideTracker")
if not ok then
    PutricideTracker = {
        handleEvent = function()
        end
    }
end

local function dispatch(module, ...)
    module:handleEvent(blizzardEvent(select(2, ...)))
end

describe('PutricideTracker', function()
    local log
    local originalCurrentCombat

    before_each(function()
        originalCurrentCombat = RLHelper.currentCombat
        RLHelper.currentCombat = { firstEnemy = "Профессор Мерзоцид" }
        log = spy.new(function()
        end)
        PutricideTracker.log = log
    end)

    after_each(function()
        RLHelper.currentCombat = originalCurrentCombat
    end)

    it('receives combat events only in Icecrown Citadel', function()
        assert.is_true(PutricideTracker.receivesCombatEvents)
        assert.are.equal(631, PutricideTracker.zoneGateInstanceId)
    end)

    it('logs normal 10-player Malleable Goo aura applications', function()
        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид"):ToPlayer("Темшамя")
            :ApplyAura(70853, "Вязкая гадость", "DEBUFF"):Build())

        assert.spy(log).was_called_with(
            "SOME DATE |cFFFFFFFFТемшамя|r |TInterface\\Icons\\INV_Misc_Herb_EvergreenMoss:24:24:0:0|t Вязкая гадость")
    end)

    it('logs heroic 10-player Malleable Goo aura applications', function()
        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид"):ToPlayer("Глорихол")
            :ApplyAura(72873, "Вязкая гадость", "DEBUFF"):Build())

        assert.spy(log).was_called_with(
            "SOME DATE |cFFFFFFFFГлорихол|r |TInterface\\Icons\\INV_Misc_Herb_EvergreenMoss:24:24:0:0|t Вязкая гадость")
    end)

    it('logs observed 25-player Malleable Goo aura applications', function()
        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид"):ToPlayer("Vafli")
            :ApplyAura(72550, "Вязкая гадость", "DEBUFF"):Build())

        assert.spy(log).was_called_with(
            "SOME DATE |cFFFFFFFFVafli|r |TInterface\\Icons\\INV_Misc_Herb_EvergreenMoss:24:24:0:0|t Вязкая гадость")
    end)

    it('ignores the no-target Malleable Goo cast trigger', function()
        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид")
            :CastSuccess(72295, "Вязкая гадость"):Build())

        assert.spy(log).was_not_called()
    end)

    it('ignores Malleable Goo ids not observed from Professor Putricide', function()
        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид"):ToPlayer("Фанатик")
            :ApplyAura(72549, "Вязкая гадость", "DEBUFF"):Build())

        assert.spy(log).was_not_called()
    end)

    it('ignores Malleable Goo outside Professor Putricide combat', function()
        RLHelper.currentCombat = { firstEnemy = "Король-лич" }

        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид"):ToPlayer("Темшамя")
            :ApplyAura(70853, "Вязкая гадость", "DEBUFF"):Build())

        assert.spy(log).was_not_called()
    end)
end)
