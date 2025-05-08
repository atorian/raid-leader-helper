require('tests.mocks')
local SpellTracker = require("../modules/SpellTracker")

describe('SpellTracker', function()
    describe('handleEvent', function()
        local log

        before_each(function()
            log = spy.new(function() end)
        end)

        it('logs taunt spell cast', function()
            local spellEvent = {
                event = "SPELL_AURA_APPLIED",
                spellId = 355,  -- Warrior Taunt
                spellName = "Taunt",
                timestamp = time(),
                sourceName = "TestWarrior",
                destName = "TestTarget"
            }
            
            SpellTracker:handleEvent(spellEvent, log)
             
            assert.spy(log).was_called_with("TestWarrior", string.format(
                "%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", spellEvent.timestamp),
                spellEvent.sourceName,
                GetSpellTexture(spellEvent.spellName),
                spellEvent.destName
            ))
        end)

        it('logs death grip spell cast', function()
            local spellEvent = {
                event = "SPELL_AURA_APPLIED",
                spellId = 49560,  -- Death Knight Death Grip
                spellName = "Death Grip",
                timestamp = time(),
                sourceName = "TestDK",
                destName = "TestTarget"
            }
            
            SpellTracker:handleEvent(spellEvent, log)
             
            assert.spy(log).was_called_with("TestDK", string.format(
                "%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", spellEvent.timestamp),
                spellEvent.sourceName,
                GetSpellTexture(spellEvent.spellName),
                spellEvent.destName
            ))
        end)

        it('logs hand of protection cast', function()
            local spellEvent = {
                event = "SPELL_AURA_APPLIED",
                spellId = 10278,  -- Hand of Protection
                spellName = "Hand of Protection",
                timestamp = time(),
                sourceName = "TestPaladin",
                destName = "TestTarget"
            }
            
            SpellTracker:handleEvent(spellEvent, log)
             
            assert.spy(log).was_called_with("TestPaladin", string.format(
                "%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", spellEvent.timestamp),
                spellEvent.sourceName,
                GetSpellTexture(spellEvent.spellName),
                spellEvent.destName
            ))
        end)

        it('ignores non-tracked spells', function()
            local spellEvent = {
                event = "SPELL_AURA_APPLIED",
                spellId = 12345,  -- Some random spell
                spellName = "Random Spell",
                timestamp = time(),
                sourceName = "TestCaster",
                destName = "TestTarget"
            }
            
            SpellTracker:handleEvent(spellEvent, log)
             
            assert.spy(log).was_not_called()
        end)

        it('ignores non-SPELL_AURA_APPLIED events', function()
            local spellEvent = {
                event = "ANY_OTHER_EVENT",
                spellId = 355,  -- Warrior Taunt
                spellName = "Taunt",
                timestamp = time(),
                sourceName = "TestWarrior",
                destName = "TestTarget"
            }
            
            SpellTracker:handleEvent(spellEvent, log)
             
            assert.spy(log).was_not_called()
        end)
    end)
end)