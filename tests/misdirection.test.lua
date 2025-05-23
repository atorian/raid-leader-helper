require('tests.mocks')
require('../lib/blizzardEvent')
require('../lib/List')
local TestAddon = require('../Core')
local Builder = require('../utils/CombatEventBuilder')
local MisdirectionTracker = require('../modules/Misdirection')

local misdirect = "Interface\\Icons\\Ability_Hunter_Misdirection"
local bow = "Interface\\Icons\\inv_weapon_bow_55"
local aimedshot = "Interface\\Icons\\INV_Spear_07"
local chimera = "Interface\\Icons\\Ability_Hunter_ChimeraShot2"
local steady = "Interface\\Icons\\Ability_Hunter_SteadyShot"
local charming = "Interface\\Icons\\Ability_Hunter_ImpalingBolt"

describe("Misdirection Tracker", function()
    local log

    before_each(function()
        -- MisdirectionTracker:reset()
        MisdirectionTracker.log = spy.new(function()
        end)
    end)

    it("отслеживает урон во время активного напула", function()
        -- Начинаем напул
        MisdirectionTracker:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromPlayer("Охотник"):ToPlayer("Танк")
            :CastSuccess(34477, "Перенаправление"):Build())

        MisdirectionTracker:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromPlayer("Охотник"):ToPlayer(
            "Охотник"):ApplyAura(35079, "Перенаправление"):Build())

        -- Охотник наносит урон
        MisdirectionTracker:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromPlayer("Охотник"):ToEnemy("Враг")
            :SpellDamage(49050, "", 1000):Build())
        -- Аура спадает
        MisdirectionTracker:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromPlayer("Охотник"):ToPlayer("Танк")
            :RemoveAura(35079, "Перенаправление"):Build())

        -- Проверяем что был сгенерирован отчет
        assert.spy(MisdirectionTracker.log).was_called_with("Охотник",
            string.format(
                "%s |cFFFFFFFFОхотник|r |T%s:24:24:0:-2|t Танк |TInterface\\Icons\\INV_Spear_07:24:24:0:-2|t",
                date("%H:%M:%S", GetTime()), misdirect))
    end)

    -- it("генерирует отчет при спадении ауры", function()
    --     -- Начинаем напул
    --     MisdirectionTracker:handleEvent(
    --         Builder:New():FromPlayer("Охотник"):ToPlayer("Танк"):ApplyAura(34477,
    --             "Перенаправление"):Build(), log)

    --     -- Охотник наносит урон
    --     MisdirectionTracker:handleEvent(Builder:New():FromPlayer("Охотник"):ToEnemy("Враг"):Damage(1000)
    --         :Build(), log)

    --     -- Аура спадает
    --     MisdirectionTracker:handleEvent(Builder:New():FromPlayer("Охотник"):ToPlayer("Танк"):RemoveAura(
    --         34477, "Перенаправление"):Build(), log)

    --     -- Проверяем что был сгенерирован отчет
    --     assert.spy(log).was_called_with("Охотник",
    --         string.format("%s |cFFFFFFFF%s|r Pull Report:\n  Auto Attack: 1 hits, 1000 total damage",
    --             date("%H:%M:%S", GetTime()), "Охотник"))
    -- end)

    -- it("не отслеживает урон после спадения ауры", function()
    --     -- Начинаем напул
    --     MisdirectionTracker:handleEvent(
    --         Builder:New():FromPlayer("Охотник"):ToPlayer("Танк"):ApplyAura(34477,
    --             "Перенаправление"):Build(), log)

    --     -- Аура спадает
    --     MisdirectionTracker:handleEvent(Builder:New():FromPlayer("Охотник"):ToPlayer("Танк"):RemoveAura(
    --         34477, "Перенаправление"):Build(), log)

    --     -- Охотник наносит урон после спадения ауры
    --     MisdirectionTracker:handleEvent(Builder:New():FromPlayer("Охотник"):ToEnemy("Враг"):Damage(1000)
    --         :Build(), log)

    --     -- Проверяем что не было дополнительных вызовов логирования
    --     assert.spy(log).was_called(2) -- Только для применения и спадения ауры
    -- end)

    -- it("отслеживает несколько способностей во время напула", function()
    --     -- Начинаем напул
    --     MisdirectionTracker:handleEvent(
    --         Builder:New():FromPlayer("Охотник"):ToPlayer("Танк"):ApplyAura(34477,
    --             "Перенаправление"):Build(), log)

    --     -- Охотник использует разные способности
    --     MisdirectionTracker:handleEvent(
    --         Builder:New():FromPlayer("Охотник"):ToEnemy("Враг"):SpellDamage(1000, "Выстрел"):Build(),
    --         log)

    --     MisdirectionTracker:handleEvent(Builder:New():FromPlayer("Охотник"):ToEnemy("Враг"):SpellDamage(500,
    --         "Автоатака"):Build(), log)

    --     -- Аура спадает
    --     MisdirectionTracker:handleEvent(Builder:New():FromPlayer("Охотник"):ToPlayer("Танк"):RemoveAura(
    --         34477, "Перенаправление"):Build(), log)

    --     -- Проверяем что был сгенерирован отчет со всеми способностями
    --     assert.spy(log).was_called_with("Охотник", string.format(
    --         "%s |cFFFFFFFF%s|r Pull Report:\n  Выстрел: 1 hits, 1000 total damage\n  Автоатака: 1 hits, 500 total damage",
    --         date("%H:%M:%S", GetTime()), "Охотник"))
    -- end)
end)
