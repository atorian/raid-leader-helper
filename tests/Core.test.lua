local M = require('tests.mocks')
local TestAddon = require("Core")

-- TODO: check values when needed
describe("TestAddon.blizzardEvent", function()
    it("should parse SWING_DAMAGE event correctly", function()
        -- 4/22 19:42:31.683  SWING_DAMAGE,0x00000000003CDB62,"Котозавр",0x514,0xF1500087EC5C09CA,"Гормок Пронзающий Бивень",0x10a48,5010,0,1,0,0,0,1,nil,nil
        local timestamp = 1696870808.708
        local event = "SWING_DAMAGE"
        local sourceGUID = 0xF13000954E394779
        local sourceName = "Мстительный дух"
        local sourceFlags = 0xa48
        local destGUID = 0x0000000000250FF2
        local destName = "Мыша"
        local destFlags = 0x514
        local damage = 234
        local args = blizzardEvent(timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, damage, 0, 1, 0, 0, 0, nil, nil, nil)

        assert.are.equal(args.timestamp, timestamp)
        assert.are.equal(args.event, event)
        assert.are.equal(args.sourceGUID, sourceGUID)
        assert.are.equal(args.sourceName, sourceName)
        assert.are.equal(args.destGUID, destGUID)
        assert.are.equal(args.destName, destName)
    end)

    it("should parse SWING_MISSED event correctly", function()
        -- 4/22 19:42:31.619  SWING_MISSED,0x000000000037B677,"Zxcurse",0x514,0xF1500087EC5C09CA,"Гормок Пронзающий Бивень",0x10a48,MISS
        local timestamp = 1696870825.763
        local event = "SWING_MISSED"
        local sourceGUID = 0xF13000954E3947A1
        local sourceName = "Мстительный дух"
        local sourceFlags = 0xa48
        local destGUID = 0x00000000003F6153
        local destName = "Movagorn"
        local destFlags = 0x514
        local missType = "DODGE"
        local args = blizzardEvent(timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, missType)

        assert.are.equal(args.timestamp, timestamp)
        assert.are.equal(args.event, event)
        assert.are.equal(args.sourceGUID, sourceGUID)
        assert.are.equal(args.sourceName, sourceName)
        assert.are.equal(args.destGUID, destGUID)
        assert.are.equal(args.destName, destName)
        assert.are.equal(args.missType, missType)
    end)

    it("should parse UNIT_DIED event correctly", function()
        -- 4/22 19:42:29.916  UNIT_DIED,0x0000000000000000,nil,0x80000000,0xF140A5754D0032AC,"Камнерез",0x1114
        local timestamp = 1696870838.300
        local event = "UNIT_DIED"
        local sourceGUID = 0x0000000000000000
        local sourceName = nil
        local sourceFlags = 0x80000000
        local destGUID = 0x00000000003B8668
        local destName = "Биполярник"
        local destFlags = 0x511
        local args = blizzardEvent(timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags)

        assert.are.equal(args.timestamp, timestamp)
        assert.are.equal(args.event, event)
        assert.are.equal(args.sourceGUID, destGUID)
        assert.are.equal(args.sourceName, destName)
        assert.are.equal(args.sourceFlags, destFlags)
        assert.are.equal(args.destGUID, destGUID)
        assert.are.equal(args.destName, destName)
        assert.are.equal(args.destFlags, destFlags)
    end)
end)

-- Combat tracking tests
describe("TestAddon combat tracking", function()
    local timestamp = GetTime()

    before_each(function()
        -- Reset combat state
        TestAddon.inCombat = false
        TestAddon.activeEnemies = {}
        TestAddon.activePlayers = {}
        TestAddon.db = { profile = { debug = false } }
    end)

    it("should start combat when player takes damage", function()
        -- Simulate player taking damage
        TestAddon:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", timestamp, 
            "SWING_DAMAGE",      -- event
            "mob1",             -- sourceGUID
            "Enemy1",           -- sourceName
            0xa48,              -- sourceFlags
            "player1",          -- destGUID
            "Player1",          -- destName
            0x514,              -- destFlags
            100,               -- amount
            0, 1, 0, 0, 0, nil, nil, nil)  -- other combat log params
        
        assert.is_true(TestAddon.inCombat)
        assert.are.equal(1, #TestAddon.activeEnemies)
        assert.are.equal(1, #TestAddon.activePlayers)
    end)

    it("should track multiple enemies and players", function()
        -- First enemy hits first player
        TestAddon:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", timestamp,
            "SWING_DAMAGE",
            "mob1",
            "Enemy1",
            0xa48,
            "player1",
            "Player1",
            0x514,
            100,
            0, 1, 0, 0, 0, nil, nil, nil)

        -- Second enemy hits second player
        TestAddon:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", timestamp,
            "SWING_DAMAGE",
            "mob2",
            "Enemy2",
            0xa48,
            "player2",
            "Player2",
            0x514,
            100,
            0, 1, 0, 0, 0, nil, nil, nil)

        assert.are.equal(2, #TestAddon.activeEnemies)
        assert.are.equal(2, #TestAddon.activePlayers)
    end)

    it("should end combat when all enemies die", function()
        -- Start combat
        TestAddon:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", timestamp,
            "SWING_DAMAGE",
            "mob1",
            "Enemy1",
            0xa48,
            "player1",
            "Player1",
            0x514,
            100,
            0, 1, 0, 0, 0, nil, nil, nil)

        -- Kill the enemy
        TestAddon:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", timestamp,
            "UNIT_DIED",
            "0x0000000000000000",
            nil,
            0x80000000,
            "mob1",
            "Enemy1",
            0xa48)

        assert.is_false(TestAddon.inCombat)
        assert.are.equal(0, #TestAddon.activeEnemies)
    end)

    it("should end combat when all players get health regen", function()
        -- Start combat
        TestAddon:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", timestamp,
            "SWING_DAMAGE",
            "mob1",
            "Enemy1",
            0xa48,
            "player1",
            "Player1",
            0x514,
            100,
            0, 1, 0, 0, 0, nil, nil, nil)

        M:SetUnitGUID("player1", "player1")

        -- Simulate health regen for the player
        TestAddon:PLAYER_REGEN_ENABLED("PLAYER_REGEN_ENABLED")

        assert.is_false(TestAddon.inCombat)
    end)

    it("should check regen for all raid members", function()
        -- Настраиваем рейд из 3 человек
        M.isInRaid = true
        M.raidSize = 3
        
        -- Начинаем бой
        TestAddon:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", timestamp,
            "SWING_DAMAGE",
            "mob1",
            "Enemy1",
            0xa48,
            "player1",
            "Player1",
            0x514,
            100,
            0, 1, 0, 0, 0, nil, nil, nil)

        -- Имитируем 3 игроков в рейде
        M:SetUnitGUID("raid1", "player1")
        M:SetUnitGUID("raid2", "player2")
        M:SetUnitGUID("raid3", "player3")

        -- Добавляем их в активных игроков
        TestAddon.activePlayers["player1"] = { guid = "player1", name = "Player1", hasRegen = false }
        TestAddon.activePlayers["player2"] = { guid = "player2", name = "Player2", hasRegen = false }
        TestAddon.activePlayers["player3"] = { guid = "player3", name = "Player3", hasRegen = false }
        
        -- Проверяем что бой не заканчивается если не все вышли из боя
        TestAddon:PLAYER_REGEN_ENABLED()
        assert.is_true(TestAddon.inCombat)
        
        -- Имитируем что все вышли из боя
        for i = 1, 3 do
            M["UnitAffectingCombat" .. i] = false
        end
        
        -- Теперь бой должен закончиться
        TestAddon:PLAYER_REGEN_ENABLED()
        assert.is_false(TestAddon.inCombat)
        
        -- Очищаем моки
        M:ClearUnitGUIDs()
    end)

    it("should check regen for all party members", function()
        -- Настраиваем группу из 4 человек (3 + игрок)
        M.isInRaid = false
        M.partySize = 3
        
        -- Начинаем бой
        TestAddon:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", timestamp,
            "SWING_DAMAGE",
            "mob1",
            "Enemy1",
            0xa48,
            "player1",
            "Player1",
            0x514,
            100,
            0, 1, 0, 0, 0, nil, nil, nil)

        -- Имитируем 3 игроков в группе + сам игрок
        M:SetUnitGUID("player", "player1")
        M:SetUnitGUID("party1", "player2")
        M:SetUnitGUID("party2", "player3")
        M:SetUnitGUID("party3", "player4")

        -- Добавляем их в активных игроков
        TestAddon.activePlayers["player1"] = { guid = "player1", name = "Player1", hasRegen = false }
        TestAddon.activePlayers["player2"] = { guid = "player2", name = "Player2", hasRegen = false }
        TestAddon.activePlayers["player3"] = { guid = "player3", name = "Player3", hasRegen = false }
        TestAddon.activePlayers["player4"] = { guid = "player4", name = "Player4", hasRegen = false }
        
        -- Проверяем что бой не заканчивается если не все вышли из боя
        TestAddon:PLAYER_REGEN_ENABLED()
        assert.is_true(TestAddon.inCombat)
        
        -- Имитируем что все вышли из боя
        for i = 1, 4 do
            M["UnitAffectingCombat" .. i] = false
        end
        
        -- Теперь бой должен закончиться
        TestAddon:PLAYER_REGEN_ENABLED()
        assert.is_false(TestAddon.inCombat)
        
        -- Очищаем моки
        M:ClearUnitGUIDs()
    end)

end)