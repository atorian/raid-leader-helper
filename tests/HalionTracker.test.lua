require('tests.mocks')
require("../lib/blizzardEvent")
local HalionTracker = require("../modules/bosses/HalionTracker")
local Builder = require("../utils/CombatEventBuilder")

local function dispatch(module, ...)
    module:handleEvent(blizzardEvent(select(2, ...)), module.log)
end

describe('HalionTracker', function()
    local log

    before_each(function()
        HalionTracker:reset()
        log = spy.new(function()
        end)
        HalionTracker.log = log
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
end)
