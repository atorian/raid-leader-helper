local M = require('tests.mocks')
local blizzardEvent = require('../lib/blizzardEvent')
local TestAddon = require("Core")

-- Test suites
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
        local args = blizzardEvent(timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags,
            damage, 0, 1, 0, 0, 0, nil, nil, nil)

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
        local args = blizzardEvent(timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags,
            missType)

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

    it("should parse SPELL_AURA_APPLIED event correctly", function()
        -- Example: SPELL_AURA_APPLIED,0x00000000003CDB62,"Охотник",0x514,0x00000000003CDB62,"Охотник",0x514,34477,"Перенаправление",0x1,BUFF
        local timestamp = 1696870838.300
        local event = "SPELL_AURA_APPLIED"
        local sourceGUID = 0x00000000003CDB62
        local sourceName = "Охотник"
        local sourceFlags = 0x514
        local destGUID = 0x00000000003CDB62
        local destName = "Охотник"
        local destFlags = 0x514
        local spellId = 34477
        local spellName = "Перенаправление"
        local spellSchool = 0x1
        local auraType = "BUFF"
        local args = blizzardEvent(timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags,
            spellId, spellName, spellSchool, auraType)

        assert.are.equal(args.timestamp, timestamp)
        assert.are.equal(args.event, event)
        assert.are.equal(args.sourceGUID, sourceGUID)
        assert.are.equal(args.sourceName, sourceName)
        assert.are.equal(args.destGUID, destGUID)
        assert.are.equal(args.destName, destName)
        assert.are.equal(args.spellId, spellId)
        assert.are.equal(args.spellName, spellName)
        assert.are.equal(args.spellSchool, spellSchool)
        assert.are.equal(args.auraType, auraType)
    end)
end)

describe("TestAddon.affectingGroup", function()
    it("should return true when source is player (0x511)", function()
        local event = {
            sourceFlags = 0x511,
            destFlags = 0xa48
        }
        assert.is_true(affectingGroup(event))
    end)

    it("should return true when source is party member (0x512)", function()
        local event = {
            sourceFlags = 0x512,
            destFlags = 0xa48
        }
        assert.is_true(affectingGroup(event))
    end)

    it("should return true when source is raid member (0x514)", function()
        local event = {
            sourceFlags = 0x514,
            destFlags = 0xa48
        }
        assert.is_true(affectingGroup(event))
    end)

    it("should return true when destination is player (0x511)", function()
        local event = {
            sourceFlags = 0xa48,
            destFlags = 0x511
        }
        assert.is_true(affectingGroup(event))
    end)

    it("should return true when destination is party member (0x512)", function()
        local event = {
            sourceFlags = 0xa48,
            destFlags = 0x512
        }
        assert.is_true(affectingGroup(event))
    end)

    it("should return true when destination is raid member (0x514)", function()
        local event = {
            sourceFlags = 0xa48,
            destFlags = 0x514
        }
        assert.is_true(affectingGroup(event))
    end)

    it("should return false when neither source nor destination is player/party/raid", function()
        local event = {
            sourceFlags = 0xa48,
            destFlags = 0xa48
        }
        assert.is_false(affectingGroup(event))
    end)

    it("should handle nil flags", function()
        local event = {
            sourceFlags = nil,
            destFlags = nil
        }
        assert.is_false(affectingGroup(event))
    end)

    it("should ignore events from other players (0x510)", function()
        local event = {
            sourceFlags = 0x510, -- Player but not in group/raid
            destFlags = 0xa48
        }
        assert.is_false(affectingGroup(event))
    end)

    it("should ignore events to other players (0x510)", function()
        local event = {
            sourceFlags = 0xa48,
            destFlags = 0x510 -- Player but not in group/raid
        }
        assert.is_false(affectingGroup(event))
    end)

    it("should ignore events from neutral NPCs (0x518)", function()
        local event = {
            sourceFlags = 0x518, -- NPC but not in group/raid
            destFlags = 0xa48
        }
        assert.is_false(affectingGroup(event))
    end)

    it("should ignore events to neutral NPCs (0x518)", function()
        local event = {
            sourceFlags = 0xa48,
            destFlags = 0x518 -- NPC but not in group/raid
        }
        assert.is_false(affectingGroup(event))
    end)
end)

describe("TestAddon.isPlayer", function()
    it("should return true for player flags (0x511)", function()
        assert.is_true(TestAddon:isPlayer(0x511))
    end)

    it("should return true for party member flags (0x512)", function()
        assert.is_true(TestAddon:isPlayer(0x512))
    end)

    it("should return true for raid member flags (0x514)", function()
        assert.is_true(TestAddon:isPlayer(0x514))
    end)

    it("should return false for enemy flags (0xa48)", function()
        assert.is_false(TestAddon:isPlayer(0xa48))
    end)

    it("should return false for nil flags", function()
        assert.is_false(TestAddon:isPlayer(nil))
    end)

    it("should return false for 0 flags", function()
        assert.is_false(TestAddon:isPlayer(0))
    end)
end)
