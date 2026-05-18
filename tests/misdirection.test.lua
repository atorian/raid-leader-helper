local M = require('tests.mocks')
require('../lib/blizzardEvent')
local RLHelper = require('../Core')
local Builder = require('../utils/CombatEventBuilder')
local MisdirectionTracker = require('../modules/Misdirection')

local function dispatch(module, ...)
    module:handleEvent(blizzardEvent(select(2, ...)))
end

local misdirect = "Interface\\Icons\\Ability_Hunter_Misdirection"
local bow = "Interface\\Icons\\inv_weapon_bow_55"
local aimedshot = "Interface\\Icons\\INV_Spear_07"
local chimera = "Interface\\Icons\\Ability_Hunter_ChimeraShot2"
local steady = "Interface\\Icons\\Ability_Hunter_SteadyShot"
local charming = "Interface\\Icons\\Ability_Hunter_ImpalingBolt"
local arcaneShot = "Interface\\Icons\\Ability_ImpalingBolt"

local function hunterDamageEvent(event, timestamp, spellId, spellName, amount, destName)
    return {
        event = event,
        timestamp = timestamp or GetTime(),
        sourceName = "Охотник",
        destName = destName or "Враг",
        spellId = spellId,
        spellName = spellName,
        amount = amount
    }
end

describe("Misdirection Tracker", function()
    local log
    local originalIterateModules

    before_each(function()
        originalIterateModules = RLHelper.IterateModules
        RLHelper:StopCombatTicker()
        RLHelper.inCombat = false
        RLHelper.lastCombatActivityAt = nil
        RLHelper.combatEndRequestedAt = nil
        RLHelper.combatEndRequiresRegen = false
        RLHelper.currentInstanceId = 0
        RLHelper.currentCombat = {
            startTime = nil,
            messages = {},
            firstEnemy = nil,
            isBoss = false
        }
        wipe(RLHelper.activeEnemies)
        wipe(RLHelper.activePlayers)
        wipe(RLHelper.enemyEvents)

        M.UnitAffectingCombat1 = false
        MisdirectionTracker:reset()
        MisdirectionTracker.log = spy.new(function()
        end)
    end)

    after_each(function()
        RLHelper.IterateModules = originalIterateModules
    end)

    it("logs hunter misdirection start and each tracked damage spell separately", function()
        RLHelper.inCombat = true

        dispatch(MisdirectionTracker, Builder:New():FromPlayer("Охотник"):ToPlayer("Танк")
            :CastSuccess(34477, "Перенаправление"):Build())

        dispatch(MisdirectionTracker, Builder:New():FromPlayer("Охотник"):ToEnemy("Враг")
            :SpellDamage(49050, "", 1000):Build())

        dispatch(MisdirectionTracker, Builder:New(GetTime() + 2):FromPlayer("Охотник"):ToEnemy("Другой враг")
            :SpellDamage(53209, "Выстрел химеры", 1000):Build())

        dispatch(MisdirectionTracker, Builder:New():FromPlayer("Охотник"):ToPlayer("Танк")
            :RemoveAura(35079, "Перенаправление"):Build())

        assert.spy(MisdirectionTracker.log).was_called(4)
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFОхотник|r |T%s:24:24:0:-2|t Танк",
            date("%H:%M:%S", GetTime()), misdirect))
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFОхотник|r |T%s:24:24:0:-2|t Враг",
            date("%H:%M:%S", GetTime()), aimedshot))
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFОхотник|r |T%s:24:24:0:-2|t Другой враг",
            date("%H:%M:%S", GetTime() + 2), chimera))
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFОхотник|r |T%s:24:24:0:-2|t Танк напул окончен 2000",
            date("%H:%M:%S", GetTime()), misdirect))
    end)

    it("logs tracked hunter range and periodic damage during misdirection", function()
        RLHelper.inCombat = true

        dispatch(MisdirectionTracker, Builder:New():FromPlayer("Охотник"):ToPlayer("Танк")
            :CastSuccess(34477, "Перенаправление"):Build())

        MisdirectionTracker:handleEvent(hunterDamageEvent("RANGE_DAMAGE", GetTime() + 1, 75, "Автоматическая стрельба", 100, "Враг"))
        MisdirectionTracker:handleEvent(hunterDamageEvent("SPELL_PERIODIC_DAMAGE", GetTime() + 2, 53352, "Разрывной выстрел", 200, "Другой враг"))

        dispatch(MisdirectionTracker, Builder:New(GetTime() + 3):FromPlayer("Охотник"):ToPlayer("Танк")
            :RemoveAura(35079, "Перенаправление"):Build())

        assert.spy(MisdirectionTracker.log).was_called(3)
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFОхотник|r |T%s:24:24:0:-2|t Другой враг",
            date("%H:%M:%S", GetTime() + 2), "Interface\\Icons\\ability_hunter_explosiveshot"))
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFОхотник|r |T%s:24:24:0:-2|t Танк напул окончен 300",
            date("%H:%M:%S", GetTime() + 3), misdirect))
    end)

    it("logs tracked hunter shots until misdirection aura is removed", function()
        RLHelper.inCombat = true

        dispatch(MisdirectionTracker, Builder:New():FromPlayer("Охотник"):ToPlayer("Танк")
            :CastSuccess(34477, "Перенаправление"):Build())

        MisdirectionTracker:handleEvent(hunterDamageEvent("RANGE_DAMAGE", GetTime() + 1, 75, "Автоматическая стрельба", 100, "Враг"))
        MisdirectionTracker:handleEvent(hunterDamageEvent("SPELL_PERIODIC_DAMAGE", GetTime() + 2, 49001, "Укус змеи", 200, "Враг"))
        MisdirectionTracker:handleEvent(hunterDamageEvent("SPELL_DAMAGE", GetTime() + 3, 53209, "Выстрел химеры", 300, "Враг"))
        MisdirectionTracker:handleEvent(hunterDamageEvent("SPELL_PERIODIC_DAMAGE", GetTime() + 4, 53353, "DoT химеры", 400, "Враг"))
        MisdirectionTracker:handleEvent(hunterDamageEvent("SPELL_DAMAGE", GetTime() + 5, 49050, "Прицельный выстрел", 500, "Враг"))
        MisdirectionTracker:handleEvent(hunterDamageEvent("SPELL_DAMAGE", GetTime() + 6, 49052, "Верный выстрел", 600, "Враг"))

        dispatch(MisdirectionTracker, Builder:New(GetTime() + 7):FromPlayer("Охотник"):ToPlayer("Танк")
            :RemoveAura(35079, "Перенаправление"):Build())

        assert.spy(MisdirectionTracker.log).was_called(5)
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFОхотник|r |T%s:24:24:0:-2|t Враг",
            date("%H:%M:%S", GetTime() + 3), chimera))
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFОхотник|r |T%s:24:24:0:-2|t Враг",
            date("%H:%M:%S", GetTime() + 5), aimedshot))
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFОхотник|r |T%s:24:24:0:-2|t Враг",
            date("%H:%M:%S", GetTime() + 6), steady))
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFОхотник|r |T%s:24:24:0:-2|t Танк напул окончен 2100",
            date("%H:%M:%S", GetTime() + 7), misdirect))
    end)

    it("показывает Чародейский выстрел правильной иконкой", function()
        RLHelper.inCombat = true

        dispatch(MisdirectionTracker, Builder:New():FromPlayer("Охотник"):ToPlayer("Танк")
            :CastSuccess(34477, "Перенаправление"):Build())

        dispatch(MisdirectionTracker, Builder:New():FromPlayer("Охотник"):ToEnemy("Враг")
            :SpellDamage(49045, "Чародейский выстрел", 1000):Build())

        dispatch(MisdirectionTracker, Builder:New():FromPlayer("Охотник"):ToPlayer("Танк")
            :RemoveAura(35079, "Перенаправление"):Build())

        assert.spy(MisdirectionTracker.log).was_called(3)
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFОхотник|r |T%s:24:24:0:-2|t Враг",
            date("%H:%M:%S", GetTime()), arcaneShot))
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFОхотник|r |T%s:24:24:0:-2|t Танк напул окончен 1000",
            date("%H:%M:%S", GetTime()), misdirect))
    end)

    it("does not log hunter damage after misdirection aura is removed", function()
        RLHelper.inCombat = true

        dispatch(MisdirectionTracker, Builder:New():FromPlayer("Охотник"):ToPlayer("Танк")
            :CastSuccess(34477, "Перенаправление"):Build())

        dispatch(MisdirectionTracker, Builder:New(GetTime() + 1):FromPlayer("Охотник"):ToPlayer("Танк")
            :RemoveAura(35079, "Перенаправление"):Build())
        dispatch(MisdirectionTracker, Builder:New(GetTime() + 2):FromPlayer("Охотник"):ToEnemy("Враг")
            :SpellDamage(49050, "Прицельный выстрел", 1000):Build())

        assert.spy(MisdirectionTracker.log).was_called(2)
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFОхотник|r |T%s:24:24:0:-2|t Танк",
            date("%H:%M:%S", GetTime()), misdirect))
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFОхотник|r |T%s:24:24:0:-2|t Танк напул окончен 0",
            date("%H:%M:%S", GetTime() + 1), misdirect))
    end)

    it("counts untracked hunter damage in the summary without logging a visible damage row", function()
        RLHelper.inCombat = true

        dispatch(MisdirectionTracker, Builder:New():FromPlayer("Охотник"):ToPlayer("Танк")
            :CastSuccess(34477, "Перенаправление"):Build())

        dispatch(MisdirectionTracker, Builder:New(GetTime() + 1):FromPlayer("Охотник"):ToEnemy("Враг")
            :SpellDamage(99999, "Неотслеживаемый выстрел", 1000):Build())

        dispatch(MisdirectionTracker, Builder:New(GetTime() + 2):FromPlayer("Охотник"):ToPlayer("Танк")
            :RemoveAura(35079, "Перенаправление"):Build())

        assert.spy(MisdirectionTracker.log).was_called(2)
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFОхотник|r |T%s:24:24:0:-2|t Танк",
            date("%H:%M:%S", GetTime()), misdirect))
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFОхотник|r |T%s:24:24:0:-2|t Танк напул окончен 1000",
            date("%H:%M:%S", GetTime() + 2), misdirect))
    end)

    it("does not count pet damage in hunter misdirection summary", function()
        RLHelper.inCombat = true

        dispatch(MisdirectionTracker, Builder:New():FromPlayer("Охотник"):ToPlayer("Танк")
            :CastSuccess(34477, "Перенаправление"):Build())

        dispatch(MisdirectionTracker, Builder:New(GetTime() + 1):FromPlayer("Охотник"):ToEnemy("Враг")
            :SpellDamage(99999, "Неотслеживаемый выстрел", 100):Build())
        dispatch(MisdirectionTracker, Builder:New(GetTime() + 2):FromPet("Питомец"):ToEnemy("Враг")
            :SpellDamage(99999, "Укус", 900):Build())

        dispatch(MisdirectionTracker, Builder:New(GetTime() + 3):FromPlayer("Охотник"):ToPlayer("Танк")
            :RemoveAura(35079, "Перенаправление"):Build())

        assert.spy(MisdirectionTracker.log).was_called(2)
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFОхотник|r |T%s:24:24:0:-2|t Танк напул окончен 100",
            date("%H:%M:%S", GetTime() + 3), misdirect))
    end)

    it("shows hunter misdirection demo messages like real combat", function()
        MisdirectionTracker:demo()

        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFHunterName|r |T%s:24:24:0:-2|t Tank",
            date("%H:%M:%S", GetTime()), misdirect))
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFHunterName|r |T%s:24:24:0:-2|t Training Dummy",
            date("%H:%M:%S", GetTime() + 3), chimera))
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFHunterName|r |T%s:24:24:0:-2|t Training Dummy",
            date("%H:%M:%S", GetTime() + 5), aimedshot))
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFHunterName|r |T%s:24:24:0:-2|t Training Dummy",
            date("%H:%M:%S", GetTime() + 6), steady))
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFHunterName|r |T%s:24:24:0:-2|t Tank напул окончен 2100",
            date("%H:%M:%S", GetTime() + 7), misdirect))
    end)

    it("отслеживает урон во время активного напула Роги", function()
        local tricks = "Interface\\Icons\\ability_rogue_tricksofthetrade"
        local eviscerate = "Interface\\Icons\\Spell_shadow_ritualofsacrifice"
        local fan = "Interface\\Icons\\ability_rogue_fanofknives"
        local murder = "Interface\\Icons\\ability_rogue_murderspree"

        -- Начинаем напул
        dispatch(MisdirectionTracker, Builder:New():FromPlayer("Рога"):ToPlayer("Танк")
            :CastSuccess(57934, "Маленькие хитрости"):Build())

        dispatch(MisdirectionTracker, Builder:New():FromPlayer("Рога"):ToPlayer("Рога")
            :ApplyAura(59628, "Маленькие хитрости"):Build())

        -- Рога использует разные способности
        dispatch(MisdirectionTracker, Builder:New(GetTime() + 1):FromPlayer("Рога"):ToEnemy(
            "Враг"):SpellDamage(48638, "Эвисцерация", 1000):Build())

        dispatch(MisdirectionTracker, Builder:New(GetTime() + 2):FromPlayer("Рога"):ToEnemy(
            "Враг"):SpellDamage(51723, "Веер клинков", 500):Build())

        dispatch(MisdirectionTracker, Builder:New(GetTime() + 4):FromPlayer("Рога"):ToEnemy(
            "Враг"):SpellDamage(57841, "Убийственный разгул", 800):Build())

        -- Аура спадает
        dispatch(MisdirectionTracker, Builder:New(GetTime() + 6):FromPlayer("Рога"):ToPlayer(
            "Танк"):RemoveAura(59628, "Маленькие хитрости"):Build())

        -- Проверяем что был сгенерирован отчет
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFРога|r |T%s:24:24:0:-2|t Танк |T%s:24:24:0:-2|t |T%s:24:24:0:-2|t |T%s:24:24:0:-2|t",
            date("%H:%M:%S", GetTime()), tricks, eviscerate, fan, murder))
    end)

    it("не падает на снятии ауры без активного напула", function()
        dispatch(MisdirectionTracker, Builder:New():FromPlayer("Охотник"):ToPlayer("Охотник")
            :RemoveAura(35079, "Перенаправление"):Build())

        assert.spy(MisdirectionTracker.log).was_not_called()
    end)

    it("сохраняет первый напул до начала боя и пишет отчет после пула", function()
        RLHelper.IterateModules = function()
            return ipairs({ MisdirectionTracker })
        end

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromPlayer("Охотник"):ToPlayer("Танк")
            :CastSuccess(34477, "Перенаправление"):Build())

        assert.is_false(RLHelper.inCombat)

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromPlayer("Охотник"):ToEnemy("Враг")
            :SpellDamage(49050, "Прицельный выстрел", 1000):Build())

        assert.is_true(RLHelper.inCombat)

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromPlayer("Охотник"):ToPlayer("Танк")
            :RemoveAura(35079, "Перенаправление"):Build())

        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFОхотник|r |T%s:24:24:0:-2|t Танк",
            date("%H:%M:%S", GetTime()), misdirect))
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFОхотник|r |T%s:24:24:0:-2|t Враг",
            date("%H:%M:%S", GetTime()), aimedshot))
        assert.spy(MisdirectionTracker.log).was_called_with(string.format(
            "%s |cFFFFFFFFОхотник|r |T%s:24:24:0:-2|t Танк напул окончен 1000",
            date("%H:%M:%S", GetTime()), misdirect))
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
