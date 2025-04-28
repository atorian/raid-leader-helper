require('tests.mocks')
local SpiritTracker = require("../modules/SpiritTracker")

describe('SpiritTracker', function()
    
    describe('handleEvent', function()
        local log

        before_each(function()
            SpiritTracker:reset()
            log = spy.new(function() end)
        end)

        it('logs explode on SWING_DAMAGE', function()
            local summonEvent = {
                event = "SPELL_SUMMON",
                spellId = 71426,
                timestamp = time(),
                sourceName = "Summoner",
                destName = "TestTarget",
                sourceGUID = "Summoner-123",
                destGUID = "Spirit-123"
            }

            local swingEvent = {
                event = "SWING_DAMAGE",
                timestamp = time(),
                sourceGUID = "Spirit-123",
                sourceName = "Spirit",
                destName = "TestTarget"
            }
            
            SpiritTracker:handleEvent(summonEvent, log)
            SpiritTracker:handleEvent(swingEvent, log)
             
            assert.spy(log).was_called_with("TestTarget", "SOME DATE |cFFFFFFFFTestTarget|r взорвал духа")
        end)

        it('logs explode on SWING_DAMAGE', function()
            local summonEvent = {
                event = "SPELL_SUMMON",
                spellId = 71426,
                timestamp = time(),
                sourceName = "Summoner",
                destName = "TestTarget",
                sourceGUID = "Summoner-123",
                destGUID = "Spirit-123"
            }

            local missEvent = {
                event = "SWING_MISSED",
                timestamp = time(),
                sourceGUID = "Spirit-123",
                sourceName = "Spirit",
                destName = "TestTarget"
            }
            
            SpiritTracker:handleEvent(summonEvent, log)
            SpiritTracker:handleEvent(missEvent, log)
             
            assert.spy(log).was_called_with("TestTarget", "SOME DATE Дух автоатачил |cFFFFFFFFTestTarget|r")
        end)

    end)
end)