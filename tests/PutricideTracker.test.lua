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

local function summarizeCombat(module)
    assert.is_function(module.summarizeCombat)
    module:summarizeCombat()
end

local function reset(module)
    assert.is_function(module.reset)
    module:reset()
end

describe('PutricideTracker', function()
    local log
    local originalCurrentCombat

    before_each(function()
        originalCurrentCombat = RLHelper.currentCombat
        RLHelper.currentCombat = { firstEnemy = "Профессор Мерзоцид" }
        PutricideTracker.malleableGooReport = {}
        PutricideTracker.chokingGasReport = {}
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

    for _, spellId in ipairs({ 70853, 72297, 72458, 72548, 72549, 72550, 72873, 72874 }) do
        it('logs Malleable Goo aura applications for spell ' .. spellId, function()
            dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид"):ToPlayer("Темшамя")
                :ApplyAura(spellId, "Вязкая гадость", "DEBUFF"):Build())

            assert.spy(log).was_called_with(
                "SOME DATE |cFFFFFFFFТемшамя|r |TInterface\\Icons\\INV_Misc_Herb_EvergreenMoss:24:24:0:0|t Вязкая гадость")
        end)
    end

    it('logs Malleable Goo during Festergut combat', function()
        RLHelper.currentCombat = { firstEnemy = "Тухлопуз" }

        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид"):ToPlayer("Темшамя")
            :ApplyAura(72297, "Вязкая гадость", "DEBUFF"):Build())

        assert.spy(log).was_called_with(
            "SOME DATE |cFFFFFFFFТемшамя|r |TInterface\\Icons\\INV_Misc_Herb_EvergreenMoss:24:24:0:0|t Вязкая гадость")
    end)

    it('ignores the no-target Malleable Goo cast trigger', function()
        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид")
            :CastSuccess(72295, "Вязкая гадость"):Build())

        assert.spy(log).was_not_called()
    end)

    it('ignores Malleable Goo ids not observed from Professor Putricide', function()
        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид"):ToPlayer("Фанатик")
            :ApplyAura(72551, "Вязкая гадость", "DEBUFF"):Build())

        assert.spy(log).was_not_called()
    end)

    it('logs Malleable Goo by spell id without checking current combat enemy', function()
        RLHelper.currentCombat = { firstEnemy = "Король-лич" }

        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид"):ToPlayer("Темшамя")
            :ApplyAura(72297, "Вязкая гадость", "DEBUFF"):Build())

        assert.spy(log).was_called_with(
            "SOME DATE |cFFFFFFFFТемшамя|r |TInterface\\Icons\\INV_Misc_Herb_EvergreenMoss:24:24:0:0|t Вязкая гадость")
    end)

    it('logs combat-end Malleable Goo summary sorted by count then name', function()
        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид"):ToPlayer("Player2")
            :ApplyAura(72550, "Вязкая гадость", "DEBUFF"):Build())
        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид"):ToPlayer("Player1")
            :ApplyAura(72550, "Вязкая гадость", "DEBUFF"):Build())
        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид"):ToPlayer("Player2")
            :ApplyAura(72550, "Вязкая гадость", "DEBUFF"):Build())

        log:clear()
        summarizeCombat(PutricideTracker)

        assert.spy(log).was_called_with("SOME DATE Вязкая гадость: всего 3 Player2(2) Player1(1)")
    end)

    it('counts Malleable Goo summary during Festergut combat', function()
        RLHelper.currentCombat = { firstEnemy = "Тухлопуз" }

        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид"):ToPlayer("Темшамя")
            :ApplyAura(72297, "Вязкая гадость", "DEBUFF"):Build())

        log:clear()
        summarizeCombat(PutricideTracker)

        assert.spy(log).was_called_with("SOME DATE Вязкая гадость: всего 1 Темшамя(1)")
    end)

    it('does not log Malleable Goo summary when report is empty', function()
        summarizeCombat(PutricideTracker)

        assert.spy(log).was_not_called()
    end)

    it('clears Malleable Goo report on reset', function()
        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид"):ToPlayer("Player1")
            :ApplyAura(72550, "Вязкая гадость", "DEBUFF"):Build())

        reset(PutricideTracker)
        log:clear()
        summarizeCombat(PutricideTracker)

        assert.spy(log).was_not_called()
    end)

    it('logs Choking Gas aura applications', function()
        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид"):ToPlayer("Темшамя")
            :ApplyAura(71278, "Удушливый газ", "DEBUFF"):Build())

        assert.spy(log).was_called_with(
            "SOME DATE |cFFFFFFFFТемшамя|r |TInterface\\Icons\\Ability_Creature_Cursed_01:24:24:0:0|t Удушливый газ")
    end)

    it('logs heroic 10-player Choking Gas aura applications', function()
        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид"):ToPlayer("Глорихол")
            :ApplyAura(72619, "Удушливый газ", "DEBUFF"):Build())

        assert.spy(log).was_called_with(
            "SOME DATE |cFFFFFFFFГлорихол|r |TInterface\\Icons\\Ability_Creature_Cursed_01:24:24:0:0|t Удушливый газ")
    end)

    it('logs Choking Gas by spell id without checking current combat enemy', function()
        RLHelper.currentCombat = { firstEnemy = "Король-лич" }

        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид"):ToPlayer("Темшамя")
            :ApplyAura(71278, "Удушливый газ", "DEBUFF"):Build())

        assert.spy(log).was_called_with(
            "SOME DATE |cFFFFFFFFТемшамя|r |TInterface\\Icons\\Ability_Creature_Cursed_01:24:24:0:0|t Удушливый газ")
    end)

    it('logs Choking Gas during Festergut combat', function()
        RLHelper.currentCombat = { firstEnemy = "Тухлопуз" }

        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид"):ToPlayer("Темшамя")
            :ApplyAura(71278, "Удушливый газ", "DEBUFF"):Build())

        assert.spy(log).was_called_with(
            "SOME DATE |cFFFFFFFFТемшамя|r |TInterface\\Icons\\Ability_Creature_Cursed_01:24:24:0:0|t Удушливый газ")
    end)

    it('logs combat-end Choking Gas summary sorted by count then name', function()
        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид"):ToPlayer("Player2")
            :ApplyAura(71278, "Удушливый газ", "DEBUFF"):Build())
        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид"):ToPlayer("Player1")
            :ApplyAura(71278, "Удушливый газ", "DEBUFF"):Build())
        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид"):ToPlayer("Player2")
            :ApplyAura(71278, "Удушливый газ", "DEBUFF"):Build())

        log:clear()
        summarizeCombat(PutricideTracker)

        assert.spy(log).was_called_with("SOME DATE Удушливый газ: всего 3 Player2(2) Player1(1)")
    end)

    it('does not log Choking Gas summary when report is empty', function()
        summarizeCombat(PutricideTracker)

        assert.spy(log).was_not_called()
    end)

    it('clears Choking Gas report on reset', function()
        dispatch(PutricideTracker, Builder:New():FromEnemy("Профессор Мерзоцид"):ToPlayer("Player1")
            :ApplyAura(71278, "Удушливый газ", "DEBUFF"):Build())

        reset(PutricideTracker)
        log:clear()
        summarizeCombat(PutricideTracker)

        assert.spy(log).was_not_called()
    end)

    it('demo logs Putricide visible mechanics and summaries', function()
        assert.is_function(PutricideTracker.demo)

        PutricideTracker:demo()

        assert.spy(log).was_called_with(
            "SOME DATE |cFFFFFFFFDemoPlayer|r |TInterface\\Icons\\INV_Misc_Herb_EvergreenMoss:24:24:0:0|t Вязкая гадость")
        assert.spy(log).was_called_with(
            "SOME DATE |cFFFFFFFFDemoPlayer|r |TInterface\\Icons\\Ability_Creature_Cursed_01:24:24:0:0|t Удушливый газ")
        assert.spy(log).was_called_with("SOME DATE Вязкая гадость: всего 1 DemoPlayer(1)")
        assert.spy(log).was_called_with("SOME DATE Удушливый газ: всего 1 DemoPlayer(1)")
    end)
end)
