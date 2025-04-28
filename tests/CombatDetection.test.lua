require('tests.mocks')
local TestAddon = require("Core")

local BOSS_FLAGS = 0x10a48
local PLAYER_FLAGS = 0x514

describe("Combat Detection", function()
    before_each(function()
        TestAddon.inCombat = false
        TestAddon.currentBossGUID = nil
        TestAddon.db = {
            profile = {
                debug = false,
            }
        }
    end)

    it("should start detecting boss when dealing damage", function()
        -- Player deals damage to boss
        TestAddon:BossStateHandler(
            time(),
            "SPELL_DAMAGE", 
            "Player-1234", "TestPlayer", PLAYER_FLAGS,
            "Boss-1234", "TestBoss", BOSS_FLAGS,
            12345, "Test Spell", 1000
        )
        
        assert.are.equal("Boss-1234", TestAddon.currentBossGUID)
        assert.are.equal(true, TestAddon.inCombat)
    end)

    it("should detect boss death", function()
        -- Set initial state - in combat with boss
        TestAddon.currentBossGUID = "Boss-1234"
        
        -- Boss dies
        TestAddon:BossStateHandler(
            time(),
            "UNIT_DIED",
            nil, nil, nil,
            "Boss-1234", "TestBoss", BOSS_FLAGS
        )

        assert.are.equal(nil, TestAddon.currentBossGUID)
        assert.are.equal(false, TestAddon.inCombat)
    end)

    it("should detect boss evade", function()
        -- Set initial state - in combat with boss
        TestAddon.currentBossGUID = "Boss-1234"
        
        -- Boss evades
        TestAddon:BossStateHandler(
            time(),
            "SPELL_AURA_APPLIED",
            "Boss-1234", "TestBoss", BOSS_FLAGS,
            "Boss-1234", "TestBoss", BOSS_FLAGS,
            8988, "Evade", "BUFF"
        )

        assert.are.equal(nil, TestAddon.currentBossGUID)
        assert.are.equal(false, TestAddon.inCombat)
    end)
end)