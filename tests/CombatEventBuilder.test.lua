require('tests.mocks')
require('../lib/blizzardEvent')
local Builder = require('../utils/CombatEventBuilder')

local BOSS_FLAGS = 0x60a48
local ENEMY_FLAGS = 0xa48
local PLAYER_FLAGS = 0x511

describe("Combat Event Builder", function()
    before_each(function()
        -- Reset generator state between tests
        Builder:Reset()
    end)

    it("создает событие урона от моба по игроку", function()
        local clue, timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, amount =
            Builder:New():FromEnemy("Леди Смертный Шепот"):ToPlayer("Игрок"):Damage(1000):Build()

        -- Проверяем базовые параметры
        assert.equals("SWING_DAMAGE", event)
        assert.equals("Леди Смертный Шепот", sourceName)
        assert.equals(ENEMY_FLAGS, sourceFlags)
        assert.equals("Игрок", destName)
        assert.equals(PLAYER_FLAGS, destFlags)
        assert.equals(1000, amount)

        -- Проверяем точные значения GUID'ов
        assert.equals("0xF130000000000001", sourceGUID)
        assert.equals("0x0000000000000001", destGUID)
    end)

    it("создает уникальные GUID'ы для разных игроков", function()
        local _, _, _, sourceGUID1 = Builder:New():FromPlayer("Игрок1"):ToEnemy("Цель"):Damage(100):Build()
        local _, _, _, sourceGUID2 = Builder:New():FromPlayer("Игрок2"):ToEnemy("Цель"):Damage(100):Build()

        assert.equals("0x0000000000000001", sourceGUID1)
        assert.equals("0x0000000000000002", sourceGUID2)
    end)

    it("генерирует правильный формат GUID'а для петов", function()
        local _, _, _, sourceGUID = Builder:New():FromPet("Питомец"):ToEnemy("Цель"):Damage(100):Build()

        assert.equals("0xF140000000000001", sourceGUID)
    end)

    for _, case in ipairs({
        { "создает событие наложения баффа Божественного вмешательства", "Паладин", "Игрок", 19752,
            "Божественное вмешательство" },
        { "создает событие наложения баффа с правильными флагами и GUID'ами", "Охотник", "Танк", 34477,
            "Перенаправление" },
    }) do
        it(case[1], function()
            local _, _, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, spellId,
                spellName = Builder:New():FromPlayer(case[2]):ToPlayer(case[3]):ApplyAura(case[4], case[5]):Build()

            assert.equals("SPELL_AURA_APPLIED", event)
            assert.equals(case[2], sourceName)
            assert.equals(PLAYER_FLAGS, sourceFlags)
            assert.equals(case[3], destName)
            assert.equals(PLAYER_FLAGS, destFlags)
            assert.equals(case[4], spellId)
            assert.equals(case[5], spellName)
            assert.equals("0x0000000000000001", sourceGUID)
            assert.equals("0x0000000000000002", destGUID)
        end)
    end

    it("создает событие смерти моба", function()
        local _, timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags = Builder:New()
            :ToEnemy("Леди Смертный Шепот"):Death():Build()

        assert.equals("UNIT_DIED", event)
        assert.equals("Леди Смертный Шепот", destName)
        assert.equals(ENEMY_FLAGS, destFlags)
        assert.equals("0xF130000000000001", destGUID)
    end)

    it("parses successful dispel combat log events", function()
        local eventData = blizzardEvent(select(2, Builder:New():FromPlayer("Диспеллер"):ToPlayer("Цель")
            :Dispel(988, "Рассеивание заклинаний", 74562, "Пылающий огонь", 4, "BUFF"):Build()))

        assert.equals("SPELL_DISPEL", eventData.event)
        assert.equals(988, eventData.spellId)
        assert.equals("Рассеивание заклинаний", eventData.spellName)
        assert.equals(74562, eventData.extraSpellId)
        assert.equals("Пылающий огонь", eventData.extraSpellName)
        assert.equals(4, eventData.extraSpellSchool)
        assert.equals("BUFF", eventData.auraType)
    end)
end)
