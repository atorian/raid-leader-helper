require('tests.mocks')
require("../lib/blizzardEvent")
require("../lib/CombatFilters")
local RLHelper = require("../Core")
local SpellTracker = require("../modules/SpellTracker")
local Builder = require("../utils/CombatEventBuilder")
local mocks = require('tests.mocks')

local function dispatch(module, ...)
    module:handleEvent(blizzardEvent(select(2, ...)))
end

describe('SpellTracker', function()
    describe('COMBAT_LOG_EVENT_UNFILTERED', function()
        local log

        before_each(function()
            log = spy.new(function()
            end)
            SpellTracker.log = log
            SpellTracker:reset()
            mocks:ClearUnitGUIDs()
            RLHelper.currentCombat.firstEnemy = nil
        end)

        it('logs first damage to enemy', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("TestPlayer"):ToEnemy("TestTarget")
                :SpellDamage(12345, "Test Spell", 100):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r Первый урон по |cFFFFFFFF%s|r",
                date("%H:%M:%S", GetTime()), "TestPlayer", "TestTarget"))
        end)

        it('does not log first damage to ignored combat enemy', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("TestPlayer"):ToEnemy('Робот "Бей-Молоти"')
                :SpellDamage(12345, "Test Spell", 100):Build())

            assert.spy(log).was_not_called()
        end)

        it('logs first direct heal to Valithria', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("Всёпадаем"):ToEnemy("Валитрия Сноходица")
                :SpellHeal(54968, "Символ Света небес", 6038):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r Первый хил по |cFFFFFFFF%s|r",
                date("%H:%M:%S", GetTime()), "Всёпадаем", "Валитрия Сноходица"))
        end)

        it('logs first periodic heal to Valithria', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("Bultuzor"):ToEnemy("Валитрия Сноходица")
                :PeriodicHeal(61301, "Быстрина", 1674):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r Первый хил по |cFFFFFFFF%s|r",
                date("%H:%M:%S", GetTime()), "Bultuzor", "Валитрия Сноходица"))
        end)

        it('ignores zero amount Valithria heals', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("Всёпадаем"):ToEnemy("Валитрия Сноходица")
                :SpellHeal(54968, "Символ Света небес", 0):Build())

            assert.spy(log).was_not_called()
        end)

        it('logs Valithria first heal only once per reset', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("Всёпадаем"):ToEnemy("Валитрия Сноходица")
                :SpellHeal(54968, "Символ Света небес", 6038):Build())
            dispatch(SpellTracker, Builder:New():FromPlayer("Bultuzor"):ToEnemy("Валитрия Сноходица")
                :SpellHeal(61301, "Быстрина", 5205):Build())

            assert.spy(log).was_called(1)
        end)

        it('logs taunt spell cast', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("TestWarrior"):ToEnemy("TestTarget")
                :ApplyAura(355, "Taunt"):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "TestWarrior", "Interface\\Icons\\spell_nature_reincarnation", "TestTarget"))
        end)

        it('logs death grip spell cast', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("TestDK"):ToEnemy("TestTarget"):ApplyAura(
                49560, "Death Grip"):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "TestDK", "Interface\\Icons\\Spell_DeathKnight_Strangulate", "TestTarget"))
        end)

        it('logs Корона', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("TestPaladin"):ToEnemy("TestTarget")
                :ApplyAura(10278, "Seal of Protection"):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "TestPaladin", "Interface\\Icons\\Spell_Holy_SealOfProtection",
                "TestTarget"))
        end)

        it('logs Divine Intervention on spell cast success', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("TestPaladin"):ToPlayer("TargetPlayer")
                :CastSuccess(19752, "Божественное вмешательство"):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "TestPaladin", "Interface\\Icons\\Spell_Nature_TimeStop",
                "TargetPlayer"))
        end)

        it('logs Righteous Defense on spell cast success', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("Julian"):ToPlayer("Soxen")
                :CastSuccess(31789, "Праведная защита"):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "Julian", "Interface\\Icons\\inv_shoulder_37", "Soxen"))
        end)

        it('logs Aura Mastery on spell cast success without target', function()
            dispatch(SpellTracker, "COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_CAST_SUCCESS",
                "0x0000000000000001", "Palanessa", 0x512, "0x0000000000000000", nil, 0x80000000,
                31821, "Мастер аур", 0x1)

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t",
                date("%H:%M:%S", GetTime()), "Palanessa", "Interface\\Icons\\Spell_Holy_AuraMastery"))
        end)

        it('logs Aura Mastery only on spell cast success', function()
            dispatch(SpellTracker, "COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_CAST_SUCCESS",
                "0x0000000000000001", "Palanessa", 0x512, "0x0000000000000000", nil, 0x80000000,
                31821, "Мастер аур", 0x1)
            dispatch(SpellTracker, "COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_AURA_APPLIED",
                "0x0000000000000001", "Palanessa", 0x512, "0x0000000000000001", "Palanessa", 0x512,
                31821, "Мастер аур", 0x1, "BUFF")

            assert.spy(log).was_called(1)
            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t",
                date("%H:%M:%S", GetTime()), "Palanessa", "Interface\\Icons\\Spell_Holy_AuraMastery"))
        end)

        it('logs Hand of Freedom on spell cast success with target', function()
            dispatch(SpellTracker, "COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_CAST_SUCCESS",
                "0x0000000000000001", "Tilasha", 0x511, "0x000000000016742E", "Sensei", 0x4000514,
                1044, "Длань свободы", 0x2)

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "Tilasha", "Interface\\Icons\\Spell_Holy_SealOfValor",
                "Sensei"))
        end)

        it('logs Hand of Freedom only on spell cast success', function()
            dispatch(SpellTracker, "COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_CAST_SUCCESS",
                "0x0000000000000001", "Tilasha", 0x511, "0x000000000016742E", "Sensei", 0x4000514,
                1044, "Длань свободы", 0x2)
            dispatch(SpellTracker, "COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_AURA_APPLIED",
                "0x0000000000000001", "Tilasha", 0x511, "0x000000000016742E", "Sensei", 0x4000514,
                1044, "Длань свободы", 0x2, "BUFF")

            assert.spy(log).was_called(1)
            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "Tilasha", "Interface\\Icons\\Spell_Holy_SealOfValor",
                "Sensei"))
        end)

        it('does not log Holy Wrath on spell cast success', function()
            RLHelper.currentCombat.firstEnemy = "Король-лич"
            RLHelper.currentInstanceId = 631

            dispatch(SpellTracker, "COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_CAST_SUCCESS",
                "0x0000000000000001", "Tilasha", 0x511, "0x0000000000000000", nil, 0x80000000,
                48817, "Гнев небес", 0x2)

            assert.spy(log).was_not_called()
        end)

        it('logs Holy Wrath damage hits during Lich King combat', function()
            RLHelper.currentCombat.firstEnemy = "Король-лич"
            RLHelper.currentInstanceId = 631
            dispatch(SpellTracker, Builder:New():FromPlayer("Primer"):ToEnemy("PrimerTarget")
                :SpellDamage(12345, "Primer Spell", 100):Build())
            log:clear()

            dispatch(SpellTracker, "COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_DAMAGE",
                "0x0000000000000001", "Tilasha", 0x511, "0xF13000872F5F75E2", "Нерубский землеглот", 0xa48,
                48817, "Гнев небес", 0x2, 4166, 0, 2, 0, 0, 0, nil, nil, nil)

            assert.spy(log).was_called(1)
            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "Tilasha", "Interface\\Icons\\Spell_Holy_Excorcism",
                "Нерубский землеглот"))
        end)

        it('does not log Holy Wrath aura applications', function()
            RLHelper.currentCombat.firstEnemy = "Король-лич"
            RLHelper.currentInstanceId = 631

            dispatch(SpellTracker, "COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_AURA_APPLIED",
                "0x0000000000000001", "Tilasha", 0x511, "0xF13000872F5F75E2", "Нерубский землеглот", 0xa48,
                48817, "Гнев небес", 0x2, "DEBUFF")

            assert.spy(log).was_not_called()
        end)

        it('does not log Holy Wrath damage outside Lich King combat', function()
            RLHelper.currentCombat.firstEnemy = "Халион"
            RLHelper.currentInstanceId = 631
            dispatch(SpellTracker, Builder:New():FromPlayer("Primer"):ToEnemy("PrimerTarget")
                :SpellDamage(12345, "Primer Spell", 100):Build())
            log:clear()

            dispatch(SpellTracker, "COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_DAMAGE",
                "0x0000000000000001", "Tilasha", 0x511, "0xF13000872F5F75E2", "Нерубский землеглот", 0xa48,
                48817, "Гнев небес", 0x2, 4166, 0, 2, 0, 0, 0, nil, nil, nil)

            assert.spy(log).was_not_called()
        end)

        it('does not log Holy Wrath damage outside Icecrown Citadel', function()
            RLHelper.currentCombat.firstEnemy = "Король-лич"
            RLHelper.currentInstanceId = 724
            dispatch(SpellTracker, Builder:New():FromPlayer("Primer"):ToEnemy("PrimerTarget")
                :SpellDamage(12345, "Primer Spell", 100):Build())
            log:clear()

            dispatch(SpellTracker, "COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_DAMAGE",
                "0x0000000000000001", "Tilasha", 0x511, "0xF13000872F5F75E2", "Нерубский землеглот", 0xa48,
                48817, "Гнев небес", 0x2, 4166, 0, 2, 0, 0, 0, nil, nil, nil)

            assert.spy(log).was_not_called()
        end)

        it('logs Hand of Sacrifice on aura applied', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("Всёпадаем"):ToPlayer("Брюсуиллис")
                :ApplyAura(6940, "Длань жертвенности"):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "Всёпадаем", "Interface\\Icons\\Spell_Holy_SealOfSacrifice",
                "Брюсуиллис"))
        end)

        it('ignores non-tracked spells', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("TestCaster"):ToEnemy("TestTarget")
                :ApplyAura(12345, "Random Spell"):Build())

            assert.spy(log).was_not_called()
        end)

        it('logs successful Dispel Magic dispel', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("Вольнож"):ToPlayer("Valgallaa")
                :Dispel(988, "Рассеивание заклинаний", 74792, "Пожирание души", 32, "BUFF"):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "Вольнож", "Interface\\Icons\\Spell_Holy_DispelMagic",
                "Valgallaa"))
        end)

        it('logs successful Remove Curse dispel', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("Волыно"):ToPlayer("Биполярник")
                :Dispel(2782, "Снятие проклятия", 74795, "Метка пожирания", 32, "BUFF"):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "Волыно", "Interface\\Icons\\Spell_Nature_RemoveCurse",
                "Биполярник"))
        end)

        it('ignores non-whitelisted dispels', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("Охотник"):ToEnemy("Леди Смертный Шепот")
                :Dispel(19801, "Усмиряющий выстрел", 33206, "Подавление боли", 2, "BUFF"):Build())

            assert.spy(log).was_not_called()
        end)

        it('does not log hand of reckoning on aura applied alone', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("TestPaladin"):ToEnemy("TestTarget")
                :ApplyAura(62124, "Hand of Reckoning"):Build())

            assert.spy(log).was_not_called()
        end)

        it('logs hand of reckoning once when target changes to paladin', function()
            local eventName, timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags,
                spellId, spellName, spellSchool, auraType =
                Builder:New():FromPlayer("TestPaladin"):ToEnemy("TestTarget"):ApplyAura(62124, "Hand of Reckoning")
                    :Build()

            dispatch(SpellTracker, eventName, timestamp, event, sourceGUID, sourceName, sourceFlags,
                destGUID, destName, destFlags, spellId, spellName, spellSchool, auraType)
            mocks:SetUnitGUID("target", destGUID)
            mocks:SetUnitGUID("targettarget", sourceGUID)
            SpellTracker:UNIT_TARGET("UNIT_TARGET", "target")

            assert.spy(log).was_called(1)
            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "TestPaladin", "Interface\\Icons\\Spell_Holy_UnyieldingFaith",
                "TestTarget"))
        end)

        it('logs druid battle resurrection on spell resurrect', function()
            dispatch(SpellTracker, Builder:New():FromPlayer("TestDruid"):ToPlayer("DeadPlayer")
                :Resurrect(48477, "Rebirth"):Build())

            assert.spy(log).was_called_with(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s",
                date("%H:%M:%S", GetTime()), "TestDruid", "Interface\\Icons\\spell_nature_reincarnation",
                "DeadPlayer"))
        end)

        it('clears pending hand of reckoning on the next paladin spell', function()
            local eventName, timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags,
                spellId, spellName, spellSchool, auraType =
                Builder:New():FromPlayer("TestPaladin"):ToEnemy("TestTarget"):ApplyAura(62124, "Hand of Reckoning")
                    :Build()

            dispatch(SpellTracker, eventName, timestamp, event, sourceGUID, sourceName, sourceFlags,
                destGUID, destName, destFlags, spellId, spellName, spellSchool, auraType)

            dispatch(SpellTracker, Builder:New():FromPlayer("TestPaladin"):ToEnemy("AnotherTarget")
                :ApplyAura(12345, "Random Spell"):Build())

            mocks:SetUnitGUID("target", destGUID)
            mocks:SetUnitGUID("targettarget", sourceGUID)
            SpellTracker:UNIT_TARGET("UNIT_TARGET", "target")

            assert.spy(log).was_not_called()
        end)
    end)
end)
