local assertRecord = require('tests.journal_assertions')
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

            assertRecord(log, { spellId = 70842, kind = "MANA_BARRIER_REMOVED", type = "INFO" })
        end)

        it('logs mind controlled player on dominate mind cast', function()
            DeathwhisperTracker:handleEvent({
                event = "SPELL_CAST_SUCCESS",
                spellId = 71289,
                timestamp = time(),
                sourceName = "Леди Смертный Шепот",
                destName = "Jatagun"
            })

            assertRecord(log, { targetName = "Jatagun", spellId = 71289, kind = "MIND_CONTROL", type = "INFO" })
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

            assertRecord(log, { sourceName = "Вольно", targetName = "Nudge", spellId = 33786, kind = "CYCLONE_APPLIED", type = "INFO" })
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

            assertRecord(log, { sourceName = "Movagorn", targetName = "Шафит", spellId = 33786, missType = "IMMUNE", kind = "CYCLONE_MISSED", type = "INFO" })
            assertRecord(log, { sourceName = "Вольно", targetName = "Nudge", spellId = 33786, missType = "RESIST", kind = "CYCLONE_MISSED", type = "INFO" })
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

            assertRecord(log, { targetName = "TestTarget", kind = "SPIRIT_HIT", type = "TACTIC_VIOLATION" })
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

            assertRecord(log, { targetName = "TestTarget", kind = "SPIRIT_MISSED", type = "INFO" })
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
            assertRecord(log, { targetName = "TestTarget", kind = "SPIRIT_HIT", type = "TACTIC_VIOLATION" })
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

            assertRecord(log, { text = "Духов взорвали: всего 3 Player1(2) Player2(1)", kind = "SPIRIT_SUMMARY", type = "INFO" })
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

end)
