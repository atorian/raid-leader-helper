require('tests.mocks')
require("../lib/blizzardEvent")
local TrialCrusaderTracker = require("../modules/bosses/TrialCrusaderTracker")
local Builder = require("../utils/CombatEventBuilder")

local function dispatch(module, ...)
    module:handleEvent(blizzardEvent(select(2, ...)))
end

describe('TrialCrusaderTracker', function()
    local log

    before_each(function()
        log = spy.new(function()
        end)
        TrialCrusaderTracker.log = log
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
end)
