require('tests.mocks')
local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local DeathwhisperTracker = require("../modules/bosses/DeathwhisperTracker")
local spy = require("luassert.spy")

describe('DeathwhisperTracker', function()
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
        DeathwhisperTracker.currentSpirits = {}
        DeathwhisperTracker.report = {}
    end)

    describe('handleEvent', function()
        local log
        local originalCurrentCombat

        before_each(function()
            originalCurrentCombat = RLHelper.currentCombat
            log = spy.new(function()
            end)
            DeathwhisperTracker.log = log
        end)

        after_each(function()
            RLHelper.currentCombat = originalCurrentCombat
        end)

        it('logs shield broken on mana barrier removed', function()
            DeathwhisperTracker:handleEvent({
                event = "SPELL_AURA_REMOVED",
                spellId = 70842,
                timestamp = time()
            })

            assert.spy(log).was_called_with("SOME DATE Леди: Щит разбит")
        end)

        it('logs mind controlled player on dominate mind cast', function()
            DeathwhisperTracker:handleEvent({
                event = "SPELL_CAST_SUCCESS",
                spellId = 71289,
                timestamp = time(),
                sourceName = "Леди Смертный Шепот",
                destName = "Jatagun"
            })

            assert.spy(log).was_called_with("SOME DATE |cFFFFFFFFJatagun|r получил контроль разума")
        end)

        it('logs successful cyclone during Lady Deathwhisper combat', function()
            RLHelper.currentCombat = { firstEnemy = "Леди Смертный Шепот" }

            DeathwhisperTracker:handleEvent({
                event = "SPELL_AURA_APPLIED",
                spellId = 33786,
                timestamp = time(),
                sourceName = "Вольно",
                destName = "Nudge"
            })

            assert.spy(log).was_called_with(
                "SOME DATE |cFFFFFFFFВольно|r |TInterface\\Icons\\Spell_Nature_EarthBind:24:24:0:0|t |cFFFFFFFFNudge|r")
        end)

        it('logs failed cyclone attempts during Lady Deathwhisper combat', function()
            RLHelper.currentCombat = { firstEnemy = "Леди Смертный Шепот" }

            DeathwhisperTracker:handleEvent({
                event = "SPELL_MISSED",
                spellId = 33786,
                timestamp = time(),
                sourceName = "Movagorn",
                destName = "Шафит",
                missType = "IMMUNE"
            })
            DeathwhisperTracker:handleEvent({
                event = "DAMAGE_SHIELD_MISSED",
                spellId = 33786,
                timestamp = time(),
                sourceName = "Вольно",
                destName = "Nudge",
                missType = "RESIST"
            })

            assert.spy(log).was_called_with(
                "SOME DATE |cFFFFFFFFMovagorn|r |TInterface\\Icons\\Spell_Nature_EarthBind:24:24:0:0|t |cFFFFFFFFШафит|r: IMMUNE")
            assert.spy(log).was_called_with(
                "SOME DATE |cFFFFFFFFВольно|r |TInterface\\Icons\\Spell_Nature_EarthBind:24:24:0:0|t |cFFFFFFFFNudge|r: RESIST")
        end)

        it('does not log cyclone outside Lady Deathwhisper combat', function()
            RLHelper.currentCombat = { firstEnemy = "Король-лич" }

            DeathwhisperTracker:handleEvent({
                event = "SPELL_AURA_APPLIED",
                spellId = 33786,
                timestamp = time(),
                sourceName = "Вольно",
                destName = "Nudge"
            })

            assert.spy(log).was_not_called()
        end)

        it('tracks spirit summon without logging it', function()
            DeathwhisperTracker:handleEvent({
                event = "SPELL_SUMMON",
                spellId = 71426,
                timestamp = time(),
                sourceName = "Леди Смертный Шепот",
                destName = "Мстительный дух",
                sourceGUID = "Summoner-123",
                destGUID = "Spirit-123"
            })

            assert.are.same({
                name = "Мстительный дух",
                summonTime = time()
            }, DeathwhisperTracker.currentSpirits["Spirit-123"])
            assert.spy(log).was_not_called()
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

            DeathwhisperTracker:handleEvent(summonEvent)
            DeathwhisperTracker:handleEvent(swingEvent)

            assert.spy(log).was_called_with(
                "SOME DATE |cFFFFFFFFTestTarget|r |TInterface\\Icons\\spell_shadow_deathsembrace:24:24:0:0|t взорвал духа")
        end)

        it('logs miss on SWING_MISSED', function()
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

            DeathwhisperTracker:handleEvent(summonEvent)
            DeathwhisperTracker:handleEvent(missEvent)

            assert.spy(log).was_called_with("SOME DATE Дух автоатачил |cFFFFFFFFTestTarget|r")
        end)

        it('does not double log when swing damage is followed by vengeful blast', function()
            local summonEvent = {
                event = "SPELL_SUMMON",
                spellId = 71426,
                timestamp = time(),
                sourceGUID = "Summoner-123",
                destGUID = "Spirit-123"
            }

            local swingEvent = {
                event = "SWING_DAMAGE",
                timestamp = time(),
                sourceGUID = "Spirit-123",
                destName = "TestTarget"
            }

            local blastEvent = {
                event = "SPELL_DAMAGE",
                timestamp = time(),
                sourceGUID = "Spirit-123",
                destName = "TestTarget",
                spellId = 72010
            }

            DeathwhisperTracker:handleEvent(summonEvent)
            DeathwhisperTracker:handleEvent(swingEvent)
            DeathwhisperTracker:handleEvent(blastEvent)

            assert.spy(log).was_called(1)
            assert.spy(log).was_called_with(
                "SOME DATE |cFFFFFFFFTestTarget|r |TInterface\\Icons\\spell_shadow_deathsembrace:24:24:0:0|t взорвал духа")
        end)

        it('does not add misses to spirit explosion report', function()
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

            DeathwhisperTracker:handleEvent(summonEvent)
            DeathwhisperTracker:handleEvent(missEvent)

            assert.is_nil(DeathwhisperTracker.report["TestTarget"])
        end)

    end)

    describe("summarizeCombat", function()
        it("logs total and per-player spirit explosion summary", function()
            local log = spy.new(function()
            end)
            DeathwhisperTracker.log = log
            DeathwhisperTracker.report = {
                ["Player1"] = 2,
                ["Player2"] = 1
            }

            DeathwhisperTracker:summarizeCombat()

            assert.spy(log).was.called_with("SOME DATE Духов взорвали: всего 3 Player1(2) Player2(1)")
        end)

        it("does not log summary when there were no spirit explosions", function()
            local log = spy.new(function()
            end)
            DeathwhisperTracker.log = log

            DeathwhisperTracker:summarizeCombat()

            assert.spy(log).was_not.called()
        end)
    end)

    describe("reset", function()
        it("should send raid message with spirit explosion report", function()
            DeathwhisperTracker.report = {
                ["Player1"] = 2,
                ["Player2"] = 1
            }

            DeathwhisperTracker:reset()

            assert.spy(sendChatMessageSpy).was
                .called_with("Духов взорвали: всего 3 Player1(2) Player2(1)", "RAID")
        end)

        it("should not send message when report is empty", function()
            DeathwhisperTracker.report = {}

            DeathwhisperTracker:reset()

            assert.spy(sendChatMessageSpy).was_not.called()
        end)
    end)

    describe("demo", function()
        it("logs all visible Deathwhisper mechanics", function()
            local log = spy.new(function()
            end)
            DeathwhisperTracker.log = log

            DeathwhisperTracker:demo()

            assert.spy(log).was_called_with("SOME DATE Леди: Щит разбит")
            assert.spy(log).was_called_with("SOME DATE |cFFFFFFFFDemoPlayer|r получил контроль разума")
            assert.spy(log).was_called_with(
                "SOME DATE |cFFFFFFFFDemoDruid|r |TInterface\\Icons\\Spell_Nature_EarthBind:24:24:0:0|t |cFFFFFFFFDemoTarget|r")
            assert.spy(log).was_called_with(
                "SOME DATE |cFFFFFFFFDemoDruid|r |TInterface\\Icons\\Spell_Nature_EarthBind:24:24:0:0|t |cFFFFFFFFImmuneTarget|r: IMMUNE")
            assert.spy(log).was_called_with(
                "SOME DATE |cFFFFFFFFPlayer|r |TInterface\\Icons\\spell_shadow_deathsembrace:24:24:0:0|t взорвал духа")
            assert.spy(log).was_called_with("SOME DATE Дух автоатачил |cFFFFFFFFLucky|r")
            assert.spy(log).was_called_with("SOME DATE Духов взорвали: всего 2 Player(2)")
        end)
    end)
end)
