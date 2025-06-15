require('tests.mocks')
require('../lib/blizzardEvent')
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
        MisdirectionTracker:reset()
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
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFОхотник|r |T%s:24:24:0:-2|t Танк |TInterface\\Icons\\INV_Spear_07:24:24:0:-2|t",
            date("%H:%M:%S", GetTime()), misdirect))
    end)

    it("отслеживает урон во время активного напула Роги", function()
        local tricks = "Interface\\Icons\\ability_rogue_tricksofthetrade"
        local eviscerate = "Interface\\Icons\\Spell_shadow_ritualofsacrifice"
        local fan = "Interface\\Icons\\ability_rogue_fanofknives"
        local murder = "Interface\\Icons\\ability_rogue_murderspree"

        -- Начинаем напул
        MisdirectionTracker:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromPlayer("Рога"):ToPlayer("Танк")
            :CastSuccess(57934, "Маленькие хитрости"):Build())

        MisdirectionTracker:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromPlayer("Рога"):ToPlayer("Рога")
            :ApplyAura(59628, "Маленькие хитрости"):Build())

        -- Рога использует разные способности
        MisdirectionTracker:COMBAT_LOG_EVENT_UNFILTERED(Builder:New(GetTime() + 1):FromPlayer("Рога"):ToEnemy(
            "Враг"):SpellDamage(48638, "Эвисцерация", 1000):Build())

        MisdirectionTracker:COMBAT_LOG_EVENT_UNFILTERED(Builder:New(GetTime() + 2):FromPlayer("Рога"):ToEnemy(
            "Враг"):SpellDamage(51723, "Веер клинков", 500):Build())

        MisdirectionTracker:COMBAT_LOG_EVENT_UNFILTERED(Builder:New(GetTime() + 4):FromPlayer("Рога"):ToEnemy(
            "Враг"):SpellDamage(57841, "Убийственный разгул", 800):Build())

        -- Аура спадает
        MisdirectionTracker:COMBAT_LOG_EVENT_UNFILTERED(Builder:New(GetTime() + 6):FromPlayer("Рога"):ToPlayer(
            "Танк"):RemoveAura(59628, "Маленькие хитрости"):Build())

        -- Проверяем что был сгенерирован отчет
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFРога|r |T%s:24:24:0:-2|t Танк |T%s:24:24:0:-2|t |T%s:24:24:0:-2|t |T%s:24:24:0:-2|t",
            date("%H:%M:%S", GetTime()), tricks, eviscerate, fan, murder))
    end)

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

-- Misdirection Tracker отслеживает урон во время активного напула Роги
-- ./tests/misdirection.test.lua:72: Function was never called with matching arguments.
-- Called with (last call if any):
-- (values list) ((string) 'SOME DATE |cFFFFFFFFРога|r |TInterface\Icons\ability_rogue_tricksofthetrade:24:24:0:-2|t Танк |TInterface\Icons\Spell_shadow_ritualofsacrifice:24:24:0:-2|t |TInterface\Icons\ability_rogue_murderspree:24:24:0:-2|t |TInterface\Icons\ability_rogue_fanofknives:24:24:0:-2|t')
-- Expected:
-- (values list) ((string) 'SOME DATE |cFFFFFFFFРога|r |TInterface\Icons\ability_rogue_tricksofthetrade:24:24:0:-2|t Танк |TInterface\Icons\Spell_shadow_ritualofsacrifice:24:24:0:-2|t |TInterface\Icons\ability_rogue_fanofknives:24:24:0:-2|t |TInterface\Icons\ability_rogue_murderspree:24:24:0:-2|t')
