require('tests.mocks')
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
        local clue, timestamp, event, sourceGUID, sourceName, sourceFlags, 
              destGUID, destName, destFlags, amount = Builder:New()
            :FromEnemy("Леди Смертный Шепот")
            :ToPlayer("Игрок")
            :Damage(1000)
            :Build()

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
        local _, _, _, sourceGUID = Builder:New()
            :FromPet("Питомец")
            :ToEnemy("Цель")
            :Damage(100)
            :Build()

        assert.equals("0xF140000000000001", sourceGUID)
    end)

    it("создает событие наложения баффа Божественного вмешательства", function()
        local _, timestamp, event, sourceGUID, sourceName, sourceFlags,
              destGUID, destName, destFlags, spellId, spellName = Builder:New()
            :FromPlayer("Паладин")
            :ToPlayer("Игрок")
            :ApplyAura(19752, "Божественное вмешательство")
            :Build()

        assert.equals("SPELL_AURA_APPLIED", event)
        assert.equals("Паладин", sourceName) 
        assert.equals("Игрок", destName)
        assert.equals(19752, spellId)
        assert.equals("Божественное вмешательство", spellName)
        assert.equals("0x0000000000000001", sourceGUID)
        assert.equals("0x0000000000000002", destGUID)
    end)

    it("создает событие смерти моба", function()
        local _, timestamp, event, sourceGUID, sourceName, sourceFlags,
              destGUID, destName, destFlags = Builder:New()
            :ToEnemy("Леди Смертный Шепот")
            :Death()
            :Build()

        assert.equals("UNIT_DIED", event)
        assert.equals("Леди Смертный Шепот", destName)
        assert.equals(ENEMY_FLAGS, destFlags)
        assert.equals("0xF130000000000001", destGUID)
    end)
end)