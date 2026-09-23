local assertRecord = require('tests.journal_assertions')
require('tests.mocks')
require('../Core')
require("../lib/blizzardEvent")
local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local HalionTracker = require("../modules/bosses/HalionTracker")
local Builder = require("../utils/CombatEventBuilder")

local function dispatch(module, ...)
    module:handleEvent(blizzardEvent(select(2, ...)))
end

local function npcGuid(npcId, spawnId)
    return string.format("0xF13000%04X%06X", npcId, spawnId or npcId)
end

local function dispatchWithGuids(module, event, sourceGUID, destGUID)
    event[4] = sourceGUID or event[4]
    event[7] = destGUID or event[7]
    dispatch(module, unpack(event))
end

describe('HalionTracker', function()
    local log
    local originalDetails
    local originalSkada
    local originalRecount
    local originalDebug
    local originalIsHalionBurstPullEnabled
    local originalIsHalionBurstResetEnabled
    local originalIsHalionPhaseTwoEntryTimerEnabled
    local originalStartPullCountdown
    local originalStartDBMPullCommand

    before_each(function()
        HalionTracker:reset()
        log = spy.new(function()
        end)
        HalionTracker.log = log
        originalDetails = _G._detalhes
        originalSkada = _G.Skada
        originalRecount = _G.Recount
        originalDebug = RLHelper.Debug
        originalIsHalionBurstPullEnabled = RLHelper.IsHalionBurstPullEnabled
        originalIsHalionBurstResetEnabled = RLHelper.IsHalionBurstResetEnabled
        originalIsHalionPhaseTwoEntryTimerEnabled = RLHelper.IsHalionPhaseTwoEntryTimerEnabled
        originalStartPullCountdown = RLHelper.StartPullCountdown
        originalStartDBMPullCommand = RLHelper.StartDBMPullCommand
        _G._detalhes = nil
        _G.Skada = nil
        _G.Recount = nil
    end)

    after_each(function()
        _G._detalhes = originalDetails
        _G.Skada = originalSkada
        _G.Recount = originalRecount
        RLHelper.Debug = originalDebug
        RLHelper.IsHalionBurstPullEnabled = originalIsHalionBurstPullEnabled
        RLHelper.IsHalionBurstResetEnabled = originalIsHalionBurstResetEnabled
        RLHelper.IsHalionPhaseTwoEntryTimerEnabled = originalIsHalionPhaseTwoEntryTimerEnabled
        RLHelper.StartPullCountdown = originalStartPullCountdown
        RLHelper.StartDBMPullCommand = originalStartDBMPullCommand
    end)

    it('logs player death with last damage from meteor', function()

        dispatch(HalionTracker, Builder:New():FromEnemy("Босс"):ToPlayer("Игрок1")
            :SpellDamage(75879, "Метеорит", 1000):Build())

        dispatch(HalionTracker, Builder:New():ToPlayer("Игрок1"):Death():Build())

        assertRecord(log, { targetName = "Игрок1", spellId = 75879, kind = "MECHANIC_DEATH", type = "TACTIC_VIOLATION" })
    end)

    it('logs player death with last damage from blades', function()
        dispatch(HalionTracker, Builder:New():FromEnemy("Босс"):ToPlayer("Игрок1")
            :SpellDamage(77844, "Лезвия", 1000):Build())

        dispatch(HalionTracker, Builder:New():ToPlayer("Игрок1"):Death():Build())

        assertRecord(log, { targetName = "Игрок1", spellId = 77844, kind = "MECHANIC_DEATH", type = "TACTIC_VIOLATION" })
    end)

    it('checks up to the last 10 damage events on player death', function()
        dispatch(HalionTracker, Builder:New():FromEnemy("Босс"):ToPlayer("Игрок1")
            :SpellDamage(75879, "Метеорит", 1000):Build())

        for i = 1, 9 do
            dispatch(HalionTracker, Builder:New():FromEnemy("Босс"):ToPlayer("Игрок1")
                :SpellDamage(12345 + i, "Обычный урон", 1000):Build())
        end

        dispatch(HalionTracker, Builder:New():ToPlayer("Игрок1"):Death():Build())

        assertRecord(log, { targetName = "Игрок1", spellId = 75879, kind = "MECHANIC_DEATH", type = "TACTIC_VIOLATION" })
    end)

    it('drops damage events older than the last 10', function()
        dispatch(HalionTracker, Builder:New():FromEnemy("Босс"):ToPlayer("Игрок1")
            :SpellDamage(75879, "Метеорит", 1000):Build())

        for i = 1, 10 do
            dispatch(HalionTracker, Builder:New():FromEnemy("Босс"):ToPlayer("Игрок1")
                :SpellDamage(12345 + i, "Обычный урон", 1000):Build())
        end

        dispatch(HalionTracker, Builder:New():ToPlayer("Игрок1"):Death():Build())

        assert.spy(log).was_not_called()
    end)

    it('ignores non-player death', function()
        dispatch(HalionTracker, Builder:New():ToEnemy("Моб"):Death():Build())

        assert.spy(log).was_not_called()
    end)

    it('logs first damage from Shadow Trap only once', function()
        dispatch(HalionTracker, Builder:New():FromEnemy("Босс"):ToPlayer("Игрок1")
            :SpellDamage(75483, "Пелена Тени", 1000):Build())

        dispatch(HalionTracker, Builder:New():FromEnemy("Босс"):ToPlayer("Игрок2")
            :SpellDamage(75483, "Пелена Тени", 1000):Build())

        assert.spy(log).was_called(1)
        assertRecord(log, { targetName = "Игрок1", spellId = 75483, kind = "FIRST_TWILIGHT_ENTRY", type = "INFO" })
    end)

    it('logs first Shadow Trap SPELL_MISSED', function()
        dispatch(HalionTracker, Builder:New():FromEnemy("Босс"):ToPlayer("Игрок1")
            :SpellMissed(75483, "Пелена Тени", "MISS"):Build())

        dispatch(HalionTracker, Builder:New():FromEnemy("Босс"):ToPlayer("Игрок2")
            :SpellMissed(75483, "Пелена Тени", "MISS"):Build())

        assert.spy(log).was_called(1)
        assertRecord(log, { targetName = "Игрок1", spellId = 75483, kind = "FIRST_TWILIGHT_ENTRY", type = "INFO" })
    end)

    it('logs first Shadow Trap DAMAGE_SHIELD_MISSED', function()
        dispatch(HalionTracker, Builder:New():FromEnemy("Босс"):ToPlayer("Игрок1")
            :DamageShieldMissed(75483, "Пелена Тени", "MISS"):Build())

        dispatch(HalionTracker, Builder:New():FromEnemy("Босс"):ToPlayer("Игрок2")
            :DamageShieldMissed(75483, "Пелена Тени", "MISS"):Build())

        assert.spy(log).was_called(1)
        assertRecord(log, { targetName = "Игрок1", spellId = 75483, kind = "FIRST_TWILIGHT_ENTRY", type = "INFO" })
    end)

    it('resets damage meters on first heroism aura applied', function()
        local detailsLeaveCalls = 0
        local detailsEnterCalls = 0
        local skadaNewSegmentCalls = 0
        local recountResetFightCalls = 0

        _G._detalhes = {
            in_combat = true,
            SairDoCombate = function()
                detailsLeaveCalls = detailsLeaveCalls + 1
            end,
            EntrarEmCombate = function()
                detailsEnterCalls = detailsEnterCalls + 1
            end
        }
        _G.Skada = {
            current = {},
            NewSegment = function()
                skadaNewSegmentCalls = skadaNewSegmentCalls + 1
            end
        }
        _G.Recount = {
            ResetFightData = function()
                recountResetFightCalls = recountResetFightCalls + 1
            end
        }

        dispatch(HalionTracker, Builder:New():FromPlayer("Шаман"):ToPlayer("Игрок1")
            :ApplyAura(32182, "Heroism"):Build())

        assert.are.equal(1, detailsLeaveCalls)
        assert.are.equal(1, detailsEnterCalls)
        assert.are.equal(1, skadaNewSegmentCalls)
        assert.are.equal(1, recountResetFightCalls)
    end)

    it('does not reset damage meters when Halion burst reset option is disabled', function()
        local detailsEnterCalls = 0
        RLHelper.IsHalionBurstResetEnabled = function()
            return false
        end
        _G._detalhes = {
            in_combat = true,
            SairDoCombate = function()
            end,
            EntrarEmCombate = function()
                detailsEnterCalls = detailsEnterCalls + 1
            end
        }

        dispatch(HalionTracker, Builder:New():FromPlayer("Шаман"):ToPlayer("Игрок1")
            :ApplyAura(32182, "Heroism"):Build())

        assert.are.equal(0, detailsEnterCalls)
    end)

    it('keeps Halion logging active when Halion burst option is disabled', function()
        RLHelper.IsHalionBurstPullEnabled = function()
            return false
        end
        RLHelper.IsHalionBurstResetEnabled = function()
            return false
        end

        dispatch(HalionTracker, Builder:New():FromEnemy("Халион"):ToPlayer("Игрок1")
            :ApplyAura(75483, "Пелена Тени"):Build())
        dispatch(HalionTracker, Builder:New():FromEnemy("Халион"):ToPlayer("Игрок1")
            :SpellDamage(75879, "Метеорит", 1000):Build())
        dispatch(HalionTracker, Builder:New():ToPlayer("Игрок1"):Death():Build())

        assertRecord(log, { targetName = "Игрок1", spellId = 75483, kind = "FIRST_TWILIGHT_ENTRY", type = "INFO" })
        assertRecord(log, { targetName = "Игрок1", spellId = 75879, kind = "MECHANIC_DEATH", type = "TACTIC_VIOLATION" })
    end)

    it('resets damage meters only once per fight', function()
        local detailsLeaveCalls = 0
        local detailsEnterCalls = 0
        _G._detalhes = {
            in_combat = true,
            SairDoCombate = function()
                detailsLeaveCalls = detailsLeaveCalls + 1
            end,
            EntrarEmCombate = function()
                detailsEnterCalls = detailsEnterCalls + 1
            end
        }

        dispatch(HalionTracker, Builder:New():FromPlayer("Шаман"):ToPlayer("Игрок1")
            :ApplyAura(32182, "Heroism"):Build())
        dispatch(HalionTracker, Builder:New():FromPlayer("Шаман"):ToPlayer("Игрок2")
            :ApplyAura(32182, "Heroism"):Build())

        assert.are.equal(1, detailsLeaveCalls)
        assert.are.equal(1, detailsEnterCalls)
    end)

    it('starts a new Details segment even when Details is not already in combat', function()
        local detailsLeaveCalls = 0
        local detailsEnterCalls = 0
        local currentCombat = nil
        _G._detalhes = {
            in_combat = false,
            SairDoCombate = function()
                detailsLeaveCalls = detailsLeaveCalls + 1
            end,
            EntrarEmCombate = function()
                detailsEnterCalls = detailsEnterCalls + 1
                currentCombat = {}
            end,
            GetCurrentCombat = function()
                return currentCombat
            end
        }

        local ok = HalionTracker:resetDamageMeters()

        assert.is_true(ok)
        assert.are.equal(0, detailsLeaveCalls)
        assert.are.equal(1, detailsEnterCalls)
        assert.are.equal("Halion Burst", currentCombat.enemy)
        assert.are.equal("Halion Burst", currentCombat.is_boss.encounter)
    end)

    it('names Details split segments using the current boss name', function()
        local endedCombat
        local currentCombat = {
            is_boss = {
                name = "Halion",
                encounter = "Halion"
            },
            enemy = "Halion"
        }
        _G._detalhes = {
            in_combat = true,
            SairDoCombate = function()
                endedCombat = currentCombat
            end,
            EntrarEmCombate = function()
                currentCombat = {}
            end,
            GetCurrentCombat = function()
                return currentCombat
            end
        }

        local ok = HalionTracker:resetDamageMeters()

        assert.is_true(ok)
        assert.are.equal("Halion", endedCombat.enemy)
        assert.are.equal("Halion", endedCombat.is_boss.encounter)
        assert.are.equal("Halion Burst", currentCombat.enemy)
        assert.are.equal("Halion Burst", currentCombat.is_boss.encounter)
    end)

    it('starts a new Skada segment by starting combat when there is no current segment', function()
        local startCombatCalls = 0
        _G.Skada = {
            current = nil,
            NewSegment = function()
                error("NewSegment should not be used without current segment")
            end,
            StartCombat = function()
                startCombatCalls = startCombatCalls + 1
            end
        }

        local ok = HalionTracker:resetDamageMeters()

        assert.is_true(ok)
        assert.are.equal(1, startCombatCalls)
    end)

    it('marks Skada split segments as boss segments so boss-only history keeps both parts', function()
        local endedSegment
        _G.Skada = {
            current = {},
            NewSegment = function(self)
                endedSegment = self.current
                self.current = {}
            end
        }

        local ok = HalionTracker:resetDamageMeters()

        assert.is_true(ok)
        assert.are.equal("Halion", endedSegment.mobname)
        assert.is_true(endedSegment.gotboss)
        assert.are.equal("Halion Burst", _G.Skada.current.mobname)
        assert.is_true(_G.Skada.current.gotboss)
    end)

    it('uses the remembered enemy name for split segment names', function()
        local endedSegment
        _G.Skada = {
            current = {},
            NewSegment = function(self)
                endedSegment = self.current
                self.current = {}
            end
        }

        dispatch(HalionTracker, Builder:New():FromEnemy("Халион"):ToPlayer("Игрок1")
            :SpellDamage(75879, "Метеорит", 1000):Build())
        dispatch(HalionTracker, Builder:New():FromPlayer("Шаман"):ToPlayer("Игрок1")
            :ApplyAura(32182, "Heroism"):Build())

        assert.are.equal("Халион", endedSegment.mobname)
        assert.are.equal("Халион Burst", _G.Skada.current.mobname)
    end)

    it('debug logs applied Halion materiality aura percentage', function()
        local debug = spy.new(function()
        end)
        RLHelper.Debug = debug

        dispatch(HalionTracker, Builder:New():FromEnemy("Халион"):ToEnemy("Халион")
            :ApplyAura(74835, "Материальность", "DEBUFF"):Build())

        assert.spy(debug).was_called_with(RLHelper, "HalionTracker: Материальность 10% во тьме (spellId=74835)")
    end)

    it('debug logs every known Halion materiality aura', function()
        local debug = spy.new(function()
        end)
        RLHelper.Debug = debug

        local spellIds = { 74826, 74827, 74828, 74829, 74830, 74831, 74832, 74833, 74834, 74835, 74836 }
        for _, spellId in ipairs(spellIds) do
            dispatch(HalionTracker, Builder:New():FromEnemy("Халион"):ToEnemy("Халион")
                :ApplyAura(spellId, "Материальность", "DEBUFF"):Build())
        end

        assert.spy(debug).was_called(11)
        assert.spy(debug).was_called_with(RLHelper, "HalionTracker: Материальность 50% баланс (spellId=74826)")
        assert.spy(debug).was_called_with(RLHelper, "HalionTracker: Материальность 100% физический мир (spellId=74831)")
        assert.spy(debug).was_called_with(RLHelper, "HalionTracker: Материальность 0% во тьме (spellId=74836)")
    end)

    it('starts a 15 second pull only when Halion materiality reaches 10 percent darkness', function()
        local pullDurations = {}
        RLHelper.IsHalionBurstPullEnabled = function()
            return true
        end
        RLHelper.StartPullCountdown = function(_, duration)
            error("StartPullCountdown should not be used for materiality drop")
        end
        RLHelper.StartDBMPullCommand = function(_, duration)
            table.insert(pullDurations, duration)
        end

        dispatch(HalionTracker, Builder:New():FromEnemy("Халион"):ToEnemy("Халион")
            :ApplyAura(74832, "Материальность", "DEBUFF"):Build())
        dispatch(HalionTracker, Builder:New():FromEnemy("Халион"):ToEnemy("Халион")
            :ApplyAura(74833, "Материальность", "DEBUFF"):Build())
        dispatch(HalionTracker, Builder:New():FromEnemy("Халион"):ToEnemy("Халион")
            :ApplyAura(74834, "Материальность", "DEBUFF"):Build())

        assert.are.same({}, pullDurations)

        dispatch(HalionTracker, Builder:New():FromEnemy("Халион"):ToEnemy("Халион")
            :ApplyAura(74835, "Материальность", "DEBUFF"):Build())
        dispatch(HalionTracker, Builder:New():FromEnemy("Халион"):ToEnemy("Халион")
            :ApplyAura(74836, "Материальность", "DEBUFF"):Build())

        assert.are.same({ 15 }, pullDurations)
    end)

    it('does not start a pull when Halion burst pull option is disabled', function()
        local pullDurations = {}
        RLHelper.IsHalionBurstPullEnabled = function()
            return false
        end
        RLHelper.StartPullCountdown = function(_, duration)
            table.insert(pullDurations, duration)
        end

        dispatch(HalionTracker, Builder:New():FromEnemy("Халион"):ToEnemy("Халион")
            :ApplyAura(74832, "Материальность", "DEBUFF"):Build())

        assert.are.same({}, pullDurations)
    end)

    it('does not start a pull for non-darkness materiality', function()
        local pullDurations = {}
        RLHelper.IsHalionBurstPullEnabled = function()
            return true
        end
        RLHelper.StartPullCountdown = function(_, duration)
            table.insert(pullDurations, duration)
        end

        dispatch(HalionTracker, Builder:New():FromEnemy("Халион"):ToEnemy("Халион")
            :ApplyAura(74826, "Материальность", "DEBUFF"):Build())
        dispatch(HalionTracker, Builder:New():FromEnemy("Халион"):ToEnemy("Халион")
            :ApplyAura(74831, "Материальность", "DEBUFF"):Build())

        assert.are.same({}, pullDurations)
    end)

    it('logs the first player damage to light Halion after dark materiality reaches 10 percent', function()
        dispatchWithGuids(HalionTracker, { Builder:New():FromEnemy("Халион"):ToEnemy("Халион")
            :ApplyAura(74835, "Материальность", "DEBUFF"):Build() }, npcGuid(40142), npcGuid(40142))

        dispatchWithGuids(HalionTracker, { Builder:New():FromPlayer("Игрок1"):ToEnemy("Халион")
            :SpellDamage(12345, "Праведная месть", 777):Build() }, nil, npcGuid(39863))
        dispatchWithGuids(HalionTracker, { Builder:New():FromPlayer("Игрок2"):ToEnemy("Халион")
            :SpellDamage(67890, "Второй удар", 888):Build() }, nil, npcGuid(39863))

        assert.spy(log).was_called(1)
        assertRecord(log, { sourceName = "Игрок1", spellId = 12345, kind = "FIRST_LIGHT_DAMAGE", type = "INFO" })
    end)

    it('stops tracking first light Halion damage when light Halion reaches full physical materiality', function()
        dispatchWithGuids(HalionTracker, { Builder:New():FromEnemy("Халион"):ToEnemy("Халион")
            :ApplyAura(74835, "Материальность", "DEBUFF"):Build() }, npcGuid(40142), npcGuid(40142))
        dispatchWithGuids(HalionTracker, { Builder:New():FromEnemy("Халион"):ToEnemy("Халион")
            :ApplyAura(74831, "Материальность", "BUFF"):Build() }, npcGuid(39863), npcGuid(39863))

        dispatchWithGuids(HalionTracker, { Builder:New():FromPlayer("Игрок1"):ToEnemy("Халион")
            :SpellDamage(12345, "Праведная месть", 777):Build() }, nil, npcGuid(39863))

        assert.spy(log).was_not_called()
    end)

    it('closes first light Halion damage tracking on heroism and logs the closing aura', function()
        dispatchWithGuids(HalionTracker, { Builder:New():FromEnemy("Халион"):ToEnemy("Халион")
            :ApplyAura(74835, "Материальность", "DEBUFF"):Build() }, npcGuid(40142), npcGuid(40142))

        dispatch(HalionTracker, Builder:New():FromPlayer("Шаман"):ToPlayer("Игрок1")
            :ApplyAura(32182, "Героизм"):Build())
        dispatchWithGuids(HalionTracker, { Builder:New():FromPlayer("Игрок1"):ToEnemy("Халион")
            :SpellDamage(12345, "Праведная месть", 777):Build() }, nil, npcGuid(39863))

        assert.spy(log).was_called(1)
        assertRecord(log, { spellId = 32182, kind = "LIGHT_DAMAGE_WINDOW_CLOSED", type = "INFO" })
    end)

    describe('phase two entry countdown', function()
        local pulls, timers, enabled, now, difficulty, dynamicDifficulty
        local originalTimerApi, originalGetInstanceInfo

        local function yell(message)
            HalionTracker:CHAT_MSG_MONSTER_YELL("CHAT_MSG_MONSTER_YELL", message, "Халион")
        end

        local function enterPhaseTwo()
            yell("Небеса в огне!")
            yell("Небеса в огне!")
            yell("В мире сумерек вы найдете лишь страдания! Входите, если посмеете!")
        end

        local function advance(seconds)
            now = now + seconds
            for _, timer in ipairs(timers) do
                if not timer.cancelled and not timer.fired and timer.at <= now then
                    timer.fired = true
                    timer.callback()
                end
            end
        end

        before_each(function()
            pulls, timers, enabled, now, difficulty = {}, {}, true, 0, 4
            dynamicDifficulty = nil
            originalTimerApi = RLHelper.C_Timer
            originalGetInstanceInfo = _G.GetInstanceInfo
            _G.GetInstanceInfo = function()
                return "Рубиновое святилище", "raid", difficulty, "", 25,
                    dynamicDifficulty, dynamicDifficulty ~= nil
            end
            RLHelper.C_Timer = {
                NewTimer = function(delay, callback)
                    local timer = { at = now + delay, callback = callback }
                    function timer:Cancel()
                        self.cancelled = true
                    end
                    table.insert(timers, timer)
                    return timer
                end
            }
            RLHelper.IsHalionPhaseTwoEntryTimerEnabled = function()
                return enabled
            end
            RLHelper.StartDBMPullCommand = function(_, duration)
                table.insert(pulls, { at = now, duration = duration })
            end
        end)

        after_each(function()
            HalionTracker:reset()
            RLHelper.C_Timer = originalTimerApi
            _G.GetInstanceInfo = originalGetInstanceInfo
        end)

        it('finishes at phase two +45 on heroic without waiting for the late cutter yell', function()
            enterPhaseTwo()
            advance(29)
            assert.are.same({}, pulls)
            advance(1)
            assert.are.same({ { at = 30, duration = 15 } }, pulls)
            advance(15)
            yell("Остерегайтесь теней!")
            assert.are.equal(1, #pulls)
            assert.are.equal(now, pulls[1].at + pulls[1].duration)
        end)

        it('finishes at phase two +50 on normal and recognizes English yells', function()
            difficulty = 2
            yell("The heavens burn!")
            yell("The heavens burn!")
            yell("You will find only suffering within the realm of twilight! Enter if you dare!")
            advance(34)
            assert.are.same({}, pulls)
            advance(1)
            assert.are.same({ { at = 35, duration = 15 } }, pulls)
        end)

        it('uses heroic timing for dynamic heroic raid difficulty', function()
            difficulty, dynamicDifficulty = 2, 1
            enterPhaseTwo()
            advance(30)
            assert.are.same({ { at = 30, duration = 15 } }, pulls)
        end)

        it('does not reschedule on duplicate phase or cutter yells', function()
            enterPhaseTwo()
            advance(10)
            yell("В мире сумерек вы найдете лишь страдания! Входите, если посмеете!")
            yell("Остерегайтесь теней!")
            advance(20)
            assert.are.same({ { at = 30, duration = 15 } }, pulls)
            assert.are.equal(1, #timers)
        end)

        it('requires two meteors before phase two and ignores later meteors', function()
            yell("Небеса в огне!")
            yell("В мире сумерек вы найдете лишь страдания! Входите, если посмеете!")
            yell("Небеса в огне!")
            yell("Остерегайтесь теней!")
            advance(60)
            assert.are.same({}, pulls)
        end)

        it('does not schedule when disabled or start if disabled while waiting', function()
            enabled = false
            enterPhaseTwo()
            assert.are.equal(0, #timers)
            HalionTracker:reset()
            enabled = true
            enterPhaseTwo()
            enabled = false
            advance(30)
            assert.are.same({}, pulls)
        end)

        it('cancels pending work and resets meteor counting between combats', function()
            enterPhaseTwo()
            local oldTimer = timers[1]
            advance(10)
            HalionTracker:reset()
            assert.is_true(oldTimer.cancelled)
            oldTimer.callback()
            advance(20)
            assert.are.same({}, pulls)

            yell("Небеса в огне!")
            yell("В мире сумерек вы найдете лишь страдания! Входите, если посмеете!")
            advance(30)
            assert.are.same({}, pulls)

            HalionTracker:reset()
            enterPhaseTwo()
            oldTimer.callback()
            advance(30)
            assert.are.same({ { at = 90, duration = 15 } }, pulls)
        end)

        it('cancels pending work when the module is disabled', function()
            enterPhaseTwo()
            HalionTracker:OnDisable()
            advance(30)
            assert.are.same({}, pulls)
            assert.is_true(timers[1].cancelled)
        end)
    end)
end)
