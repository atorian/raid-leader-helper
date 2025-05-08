require('tests.mocks')
local TestAddon = require('../Core')
local Builder = require('../utils/CombatEventBuilder')

-- Вспомогательная функция для подсчета элементов в таблице
local function count(tbl)
    local count = 0
    for _, v  in pairs(tbl) do
        count = count + 1
    end
    return count
end

describe("Боевая система", function()
    local timestamp = GetTime()

    before_each(function()
        TestAddon.inCombat = false
        wipe(TestAddon.activeEnemies)
        wipe(TestAddon.activePlayers)
        TestAddon.db = { profile = { debug = false } }
    end)

    it("начинает бой когда игрок входит в бой", function()
        TestAddon:PLAYER_REGEN_DISABLED()
        assert.is_true(TestAddon.inCombat)
    end)

    it("отслеживает врагов, наносящих урон игрокам", function()
        -- Начинаем бой
        TestAddon:PLAYER_REGEN_DISABLED()

        -- Враг бьет игрока
        TestAddon:COMBAT_LOG_EVENT_UNFILTERED(Builder:New()
            :FromEnemy("Враг1")
            :ToPlayer("Игрок1")
            :Damage(100)
            :Build())

        assert.are.equal(1, count(TestAddon.activeEnemies))
        assert.are.equal(1, count(TestAddon.activePlayers))
        assert.is_true(TestAddon.inCombat)
    end)

    it("завершает бой при смерти всех врагов", function()
        -- Начинаем бой и добавляем врага
        TestAddon:PLAYER_REGEN_DISABLED()

        -- Враг бьет игрока
        TestAddon:COMBAT_LOG_EVENT_UNFILTERED(Builder:New()
            :FromEnemy("Враг1")
            :ToPlayer("Игрок1")
            :Damage(100)
            :Build())

        -- Убиваем врага
        TestAddon:COMBAT_LOG_EVENT_UNFILTERED(Builder:New()
            :ToEnemy("Враг1")
            :Death()
            :Build())

        assert.is_false(TestAddon.inCombat)
        assert.are.equal(0, count(TestAddon.activeEnemies))
    end)

    it("завершает бой если все живые игроки под Divine Intervention", function()
        -- Начинаем бой
        TestAddon:PLAYER_REGEN_DISABLED()

        -- Добавляем врага
        TestAddon:COMBAT_LOG_EVENT_UNFILTERED(Builder:New()
            :FromEnemy("Враг1")
            :ToPlayer("Паладин")
            :Damage(100)
            :Build())

        -- Накладываем Divine Intervention на всех игроков
        TestAddon:COMBAT_LOG_EVENT_UNFILTERED(Builder:New()
            :FromPlayer("Паладин")
            :ToPlayer("Паладин")
            :ApplyAura(19752, "Божественное вмешательство")
            :Build())

        assert.is_false(TestAddon.inCombat)
    end)

    it("не завершает бой если есть игроки без Divine Intervention", function()
        -- Начинаем бой
        TestAddon:PLAYER_REGEN_DISABLED()

        -- Добавляем врага и двух игроков
        TestAddon:COMBAT_LOG_EVENT_UNFILTERED(Builder:New()
            :FromEnemy("Враг1")
            :ToPlayer("Игрок1")
            :Damage(100)
            :Build())

        TestAddon:COMBAT_LOG_EVENT_UNFILTERED(Builder:New()
            :FromEnemy("Враг1") 
            :ToPlayer("Игрок2")
            :Damage(100)
            :Build())

        -- Накладываем Divine Intervention только на одного игрока
        TestAddon:COMBAT_LOG_EVENT_UNFILTERED(Builder:New()
            :FromPlayer("Паладин")
            :ToPlayer("Игрок1")
            :ApplyAura(19752, "Божественное вмешательство")
            :Build())

        assert.is_true(TestAddon.inCombat)
    end)

    it("завершает бой когда все игроки умерли", function()
        -- Начинаем бой
        TestAddon:PLAYER_REGEN_DISABLED()

        -- Добавляем врага и двух игроков
        TestAddon:COMBAT_LOG_EVENT_UNFILTERED(Builder:New()
            :FromEnemy("Враг1")
            :ToPlayer("Игрок1")
            :Damage(100)
            :Build())

        TestAddon:COMBAT_LOG_EVENT_UNFILTERED(Builder:New()
            :FromEnemy("Враг1") 
            :ToPlayer("Игрок2")
            :Damage(100)
            :Build())

        -- Убиваем обоих игроков
        TestAddon:COMBAT_LOG_EVENT_UNFILTERED(Builder:New()
            :ToPlayer("Игрок1")
            :Death()
            :Build())

        TestAddon:COMBAT_LOG_EVENT_UNFILTERED(Builder:New()
            :ToPlayer("Игрок2")
            :Death()
            :Build())

        assert.is_false(TestAddon.inCombat)
    end)
end)
