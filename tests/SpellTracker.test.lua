require('tests.mocks')
require("../lib/blizzardEvent")
local SpellTracker = require("../modules/SpellTracker")
local Builder = require("../utils/CombatEventBuilder")
local mocks = require('tests.mocks')

local function dispatch(module, ...)
    module:handleEvent(blizzardEvent(select(2, ...)))
end

describe('SpellTracker', function()
    describe('COMBAT_LOG_EVENT_UNFILTERED', function()
        local log

        before_each(function()
            log = spy.new(function()
            end)
            SpellTracker.log = log
            SpellTracker:reset()
            mocks:ClearUnitGUIDs()
        end)

        it('logs first damage to enemy', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("TestPlayer"):ToEnemy("TestTarget")
                :SpellDamage(12345, "Test Spell", 100):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r Первый урон по |cFFFFFFFF%s|r",
                date("%H:%M:%S", GetTime()), "TestPlayer", "TestTarget"))
        end)

        it('logs taunt spell cast', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("TestWarrior"):ToEnemy("TestTarget")
                :ApplyAura(355, "Taunt"):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "TestWarrior", "Interface\\Icons\\spell_nature_reincarnation", "TestTarget"))
        end)

        it('logs death grip spell cast', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("TestDK"):ToEnemy("TestTarget"):ApplyAura(
                49560, "Death Grip"):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "TestDK", "Interface\\Icons\\Spell_DeathKnight_Strangulate", "TestTarget"))
        end)

        it('logs Корона', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("TestPaladin"):ToEnemy("TestTarget")
                :ApplyAura(10278, "Seal of Protection"):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "TestPaladin", "Interface\\Icons\\Spell_Holy_SealOfProtection",
                "TestTarget"))
        end)

        it('logs Divine Intervention on spell cast success', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("TestPaladin"):ToPlayer("TargetPlayer")
                :CastSuccess(19752, "Божественное вмешательство"):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "TestPaladin", "Interface\\Icons\\Spell_Nature_TimeStop",
                "TargetPlayer"))
        end)

        it('ignores non-tracked spells', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("TestCaster"):ToEnemy("TestTarget")
                :ApplyAura(12345, "Random Spell"):Build())

            assert.spy(log).was_not_called()
        end)

        it('does not log hand of reckoning on aura applied alone', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("TestPaladin"):ToEnemy("TestTarget")
                :ApplyAura(62124, "Hand of Reckoning"):Build())

            assert.spy(log).was_not_called()
        end)

        it('logs hand of reckoning once when target changes to paladin', function()
            local eventName, timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags,
                spellId, spellName, spellSchool, auraType =
                Builder:New():FromPlayer("TestPaladin"):ToEnemy("TestTarget"):ApplyAura(62124, "Hand of Reckoning")
                    :Build()

            dispatch(SpellTracker, eventName, timestamp, event, sourceGUID, sourceName, sourceFlags,
                destGUID, destName, destFlags, spellId, spellName, spellSchool, auraType)
            mocks:SetUnitGUID("target", destGUID)
            mocks:SetUnitGUID("targettarget", sourceGUID)
            SpellTracker:UNIT_TARGET("UNIT_TARGET", "target")

            assert.spy(log).was_called(1)
            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "TestPaladin", "Interface\\Icons\\Spell_Holy_UnyieldingFaith",
                "TestTarget"))
        end)

        it('logs druid battle resurrection on spell resurrect', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("TestDruid"):ToPlayer("DeadPlayer")
                :Resurrect(48477, "Rebirth"):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "TestDruid", "Interface\\Icons\\spell_nature_reincarnation",
                "DeadPlayer"))
        end)

        it('clears pending hand of reckoning on the next paladin spell', function()
            local eventName, timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags,
                spellId, spellName, spellSchool, auraType =
                Builder:New():FromPlayer("TestPaladin"):ToEnemy("TestTarget"):ApplyAura(62124, "Hand of Reckoning")
                    :Build()

            dispatch(SpellTracker, eventName, timestamp, event, sourceGUID, sourceName, sourceFlags,
                destGUID, destName, destFlags, spellId, spellName, spellSchool, auraType)

            dispatch(SpellTracker, Builder:New():FromPlayer("TestPaladin"):ToEnemy("AnotherTarget")
                :ApplyAura(12345, "Random Spell"):Build())

            mocks:SetUnitGUID("target", destGUID)
            mocks:SetUnitGUID("targettarget", sourceGUID)
            SpellTracker:UNIT_TARGET("UNIT_TARGET", "target")

            assert.spy(log).was_not_called()
        end)
    end)
end)
