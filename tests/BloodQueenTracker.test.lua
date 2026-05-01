require('tests.mocks')
require("../lib/blizzardEvent")
local spy = require("luassert.spy")
local BloodQueenTracker = require("../modules/bosses/BloodQueenTracker")
local Builder = require("../utils/CombatEventBuilder")

local function dispatch(module, ...)
    module:handleEvent(blizzardEvent(select(2, ...)))
end

describe('BloodQueenTracker', function()
    local log

    before_each(function()
        log = spy.new(function()
        end)
        BloodQueenTracker.log = log
    end)

    it('receives combat events only in Icecrown Citadel', function()
        assert.is_true(BloodQueenTracker.receivesCombatEvents)
        assert.are.equal(631, BloodQueenTracker.zoneGateInstanceId)
    end)

    it('logs player-source Bloodbolt Splash in combat-log order', function()
        dispatch(BloodQueenTracker, Builder:New():FromPlayer("Stikers"):ToPlayer("Райва")
            :SpellDamage(71483, "Кровавый всплеск", 6141):Build())

        assert.spy(log).was_called_with(
            "SOME DATE |cFFFFFFFFStikers|r |TInterface\\Icons\\Spell_Shadow_BloodBoil:24:24:0:0|t |cFFFFFFFFРайва|r")
    end)

    it('logs all Bloodbolt Splash difficulty spell ids', function()
        local spellIds = { 71483, 71481, 71447 }

        for _, spellId in ipairs(spellIds) do
            log:clear()

            dispatch(BloodQueenTracker, Builder:New():FromPlayer("Источник"):ToPlayer("Цель")
                :SpellDamage(spellId, "Кровавый всплеск", 5000):Build())

            assert.spy(log).was_called()
        end
    end)

    it('ignores boss-source Bloodbolt Splash duplicates', function()
        dispatch(BloodQueenTracker, Builder:New():FromEnemy("Кровавая королева Лана'тель"):ToPlayer("Райва")
            :SpellDamage(71483, "Кровавый всплеск", 9648):Build())

        assert.spy(log).was_not_called()
    end)

    it('ignores Twilight Bloodbolt', function()
        dispatch(BloodQueenTracker, Builder:New():FromEnemy("Кровавая королева Лана'тель"):ToPlayer("Stikers")
            :SpellDamage(71480, "Сумеречная кровяная стрела", 14818):Build())

        assert.spy(log).was_not_called()
    end)

    it('ignores non-damage splash events', function()
        dispatch(BloodQueenTracker, Builder:New():FromPlayer("Stikers"):ToPlayer("Райва")
            :SpellMissed(71483, "Кровавый всплеск", "MISS"):Build())

        assert.spy(log).was_not_called()
    end)
end)
