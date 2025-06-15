require('tests.mocks')
local SpiritTracker = require("../modules/SpiritTracker")
local spy = require("luassert.spy")

describe('SpiritTracker', function()
    local originalSendChatMessage
    local sendChatMessageSpy

    setup(function()
        originalSendChatMessage = _G.SendChatMessage
        sendChatMessageSpy = spy.new(function()
        end)
        _G.SendChatMessage = sendChatMessageSpy
    end)

    teardown(function()
        _G.SendChatMessage = originalSendChatMessage
    end)

    before_each(function()
        sendChatMessageSpy:clear()
        SpiritTracker:reset()
    end)

    describe('handleEvent', function()
        local log

        before_each(function()
            log = spy.new(function()
            end)
            SpiritTracker.log = log
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

            SpiritTracker:handleEvent(summonEvent)
            SpiritTracker:handleEvent(swingEvent)

            assert.spy(log).was_called_with(
                "SOME DATE |cFFFFFFFFTestTarget|r взорвал духа |TInterface\\Icons\\spell_shadow_deathsembrace:24:24:0:0|t")
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

            SpiritTracker:handleEvent(summonEvent)
            SpiritTracker:handleEvent(missEvent)

            assert.spy(log).was_called_with("SOME DATE Дух автоатачил |cFFFFFFFFTestTarget|r")
        end)

    end)

    describe("reset", function()
        it("should send raid message with spirit explosion report", function()
            SpiritTracker.report = {
                ["Player1"] = 2,
                ["Player2"] = 1
            }

            SpiritTracker:reset()

            assert.spy(sendChatMessageSpy).was
                .called_with("Духов взорвали:  Player1(2) Player2(1)", "RAID")
        end)

        it("should not send message when report is empty", function()
            SpiritTracker.report = {}

            SpiritTracker:reset()

            assert.spy(sendChatMessageSpy).was_not.called()
        end)
    end)
end)
