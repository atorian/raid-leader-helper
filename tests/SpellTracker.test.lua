require('tests.mocks')
require("../lib/blizzardEvent")
local SpellTracker = require("../modules/SpellTracker")
local Builder = require("../utils/CombatEventBuilder")

describe('SpellTracker', function()
    describe('COMBAT_LOG_EVENT_UNFILTERED', function()
        local log

        before_each(function()
            log = spy.new(function()
            end)
            SpellTracker.log = log
            SpellTracker:reset()
        end)

        it('logs first damage to enemy', function()
            SpellTracker:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromPlayer("TestPlayer"):ToEnemy("TestTarget")
                :SpellDamage(12345, "Test Spell", 100):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r Первый урон по |cFFFFFFFF%s|r",
                date("%H:%M:%S", GetTime()), "TestPlayer", "TestTarget"))
        end)

        it('logs taunt spell cast', function()
            SpellTracker:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromPlayer("TestWarrior"):ToEnemy("TestTarget")
                :ApplyAura(355, "Taunt"):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "TestWarrior", "Interface\\Icons\\spell_nature_reincarnation", "TestTarget"))
        end)

        it('logs death grip spell cast', function()
            SpellTracker:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromPlayer("TestDK"):ToEnemy("TestTarget"):ApplyAura(
                49560, "Death Grip"):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "TestDK", "Interface\\Icons\\Spell_DeathKnight_Strangulate", "TestTarget"))
        end)

        it('logs Корона', function()
            SpellTracker:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromPlayer("TestPaladin"):ToEnemy("TestTarget")
                :ApplyAura(10278, "Seal of Protection"):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "TestPaladin", "Interface\\Icons\\Spell_Holy_SealOfProtection",
                "TestTarget"))
        end)

        it('ignores non-tracked spells', function()
            SpellTracker:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromPlayer("TestCaster"):ToEnemy("TestTarget")
                :ApplyAura(12345, "Random Spell"):Build())

            assert.spy(log).was_not_called()
        end)
    end)
end)
