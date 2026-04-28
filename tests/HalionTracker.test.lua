require('tests.mocks')
require("../lib/blizzardEvent")
local HalionTracker = require("../modules/bosses/HalionTracker")
local Builder = require("../utils/CombatEventBuilder")

local function dispatch(module, ...)
    module:handleEvent(blizzardEvent(select(2, ...)), module.log)
end

describe('HalionTracker', function()
    local log
    local originalDetails
    local originalSkada
    local originalRecount

    before_each(function()
        HalionTracker:reset()
        log = spy.new(function()
        end)
        HalionTracker.log = log
        originalDetails = _G._detalhes
        originalSkada = _G.Skada
        originalRecount = _G.Recount
        _G._detalhes = nil
        _G.Skada = nil
        _G.Recount = nil
    end)

    after_each(function()
        _G._detalhes = originalDetails
        _G.Skada = originalSkada
        _G.Recount = originalRecount
    end)

    it('logs player death with last damage from meteor', function()

        dispatch(HalionTracker, Builder:New():FromEnemy("Босс"):ToPlayer("Игрок1")
            :SpellDamage(75879, "Метеорит", 1000):Build())

        dispatch(HalionTracker, Builder:New():ToPlayer("Игрок1"):Death():Build())

        assert.spy(log).was_called_with(string.format(
            "%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t от метеорита |T%s:24:24:0:0|t",
            date("%H:%M:%S", deathTimestamp), "Игрок1", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
            "Interface\\Icons\\spell_fire_meteorstorm"))
    end)

    it('logs player death with last damage from blades', function()
        dispatch(HalionTracker, Builder:New():FromEnemy("Босс"):ToPlayer("Игрок1")
            :SpellDamage(77844, "Лезвия", 1000):Build())

        dispatch(HalionTracker, Builder:New():ToPlayer("Игрок1"):Death():Build())

        assert.spy(log).was_called_with(string.format(
            "%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t в лезвиях |T%s:24:24:0:0|t", date("%H:%M:%S", deathTimestamp),
            "Игрок1", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
            "Interface\\Icons\\Spell_Shadow_ShadowMend"))
    end)

    it('checks up to the last 10 damage events on player death', function()
        dispatch(HalionTracker, Builder:New():FromEnemy("Босс"):ToPlayer("Игрок1")
            :SpellDamage(75879, "Метеорит", 1000):Build())

        for i = 1, 9 do
            dispatch(HalionTracker, Builder:New():FromEnemy("Босс"):ToPlayer("Игрок1")
                :SpellDamage(12345 + i, "Обычный урон", 1000):Build())
        end

        dispatch(HalionTracker, Builder:New():ToPlayer("Игрок1"):Death():Build())

        assert.spy(log).was_called_with(string.format(
            "%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t от метеорита |T%s:24:24:0:0|t",
            date("%H:%M:%S", deathTimestamp), "Игрок1", "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8",
            "Interface\\Icons\\spell_fire_meteorstorm"))
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
        assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r зашел во тьму первый",
            date("%H:%M:%S", GetTime()), "Игрок1"))
    end)

    it('logs first Shadow Trap SPELL_MISSED', function()
        dispatch(HalionTracker, Builder:New():FromEnemy("Босс"):ToPlayer("Игрок1")
            :SpellMissed(75483, "Пелена Тени", "MISS"):Build())

        dispatch(HalionTracker, Builder:New():FromEnemy("Босс"):ToPlayer("Игрок2")
            :SpellMissed(75483, "Пелена Тени", "MISS"):Build())

        assert.spy(log).was_called(1)
        assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r зашел во тьму первый",
            date("%H:%M:%S", GetTime()), "Игрок1"))
    end)

    it('logs first Shadow Trap DAMAGE_SHIELD_MISSED', function()
        dispatch(HalionTracker, Builder:New():FromEnemy("Босс"):ToPlayer("Игрок1")
            :DamageShieldMissed(75483, "Пелена Тени", "MISS"):Build())

        dispatch(HalionTracker, Builder:New():FromEnemy("Босс"):ToPlayer("Игрок2")
            :DamageShieldMissed(75483, "Пелена Тени", "MISS"):Build())

        assert.spy(log).was_called(1)
        assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r зашел во тьму первый",
            date("%H:%M:%S", GetTime()), "Игрок1"))
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
end)
