local M = require('tests.mocks')
local blizzardEvent = require('../lib/blizzardEvent')
local RLHelper = require("Core")

-- Test suites
describe("RLHelper.blizzardEvent", function()
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

describe("RLHelper debug helpers", function()
    it("does not crash when debug is called before db initialization", function()
        RLHelper.db = nil
        RLHelper.Print = function()
            error("Print should not be called when debug is unavailable")
        end

        assert.has_no.errors(function()
            RLHelper:Debug("test")
        end)
        assert.is_false(RLHelper:isDebugging())
    end)
end)

describe("RLHelper frame positioning", function()
    local originalUIParent

    before_each(function()
        originalUIParent = _G.UIParent
        _G.UIParent = {}
        RLHelper.db = {
            profile = {}
        }
        RLHelper.Print = function()
        end
    end)

    after_each(function()
        _G.UIParent = originalUIParent
    end)

    it("saves the current anchor point and restores it on minimize", function()
        local calls = {}
        RLHelper.mainFrame = {
            GetPoint = function()
                return "CENTER", UIParent, "CENTER", 120, -45
            end,
            GetWidth = function()
                return 420
            end,
            GetHeight = function()
                return 180
            end,
            ClearAllPoints = function()
            end,
            SetSize = function(_, width, height)
                calls.size = { width = width, height = height }
            end,
            SetPoint = function(_, point, relativeTo, relativePoint, x, y)
                calls.point = {
                    point = point,
                    relativeTo = relativeTo,
                    relativePoint = relativePoint,
                    x = x,
                    y = y
                }
            end
        }

        RLHelper:SaveAnchorPosition(true)
        RLHelper:MinimizeWindow()

        assert.are.same({
            point = "CENTER",
            relativePoint = "CENTER",
            x = 120,
            y = -45,
            width = 420,
            height = 180
        }, RLHelper.db.profile.savedPosition)
        assert.are.same({ width = 420, height = 180 }, calls.size)
        assert.are.same({
            point = "CENTER",
            relativeTo = UIParent,
            relativePoint = "CENTER",
            x = 120,
            y = -45
        }, calls.point)
    end)

    it("keeps compatibility with old saved positions that had no anchor metadata", function()
        local setPointCall
        RLHelper.db.profile.savedPosition = {
            x = 50,
            y = -20,
            width = 400,
            height = 150
        }
        RLHelper.mainFrame = {
            ClearAllPoints = function()
            end,
            SetSize = function()
            end,
            SetPoint = function(_, point, relativeTo, relativePoint, x, y)
                setPointCall = {
                    point = point,
                    relativeTo = relativeTo,
                    relativePoint = relativePoint,
                    x = x,
                    y = y
                }
            end
        }

        RLHelper:MinimizeWindow()

        assert.are.same({
            point = "TOPLEFT",
            relativeTo = UIParent,
            relativePoint = "TOPLEFT",
            x = 50,
            y = -20
        }, setPointCall)
    end)
end)

describe("RLHelper pull controls", function()
    local originalSlashCmdList
    local originalDBM

    local function newVisibilityProbe(initiallyVisible)
        return {
            visible = not not initiallyVisible,
            Show = function(self)
                self.visible = true
            end,
            Hide = function(self)
                self.visible = false
            end
        }
    end

    before_each(function()
        originalSlashCmdList = _G.SlashCmdList
        originalDBM = _G.DBM
        RLHelper.pullResetTimer = nil
        RLHelper.C_Timer = {
            NewTimer = function(_, callback)
                local timer = {
                    callback = callback,
                    cancelled = false
                }

                function timer:Cancel()
                    self.cancelled = true
                end

                return timer
            end
        }
        RLHelper.mainFrame = {
            pullButtons = {
                newVisibilityProbe(true),
                newVisibilityProbe(true)
            },
            cancelBtn = newVisibilityProbe(false)
        }
    end)

    after_each(function()
        _G.SlashCmdList = originalSlashCmdList
        _G.DBM = originalDBM
    end)

    it("restores pull buttons automatically when the countdown finishes", function()
        RLHelper:BeginPullCountdown(15)

        assert.is_false(RLHelper.mainFrame.pullButtons[1].visible)
        assert.is_false(RLHelper.mainFrame.pullButtons[2].visible)
        assert.is_true(RLHelper.mainFrame.cancelBtn.visible)
        assert.is_not_nil(RLHelper.pullResetTimer)

        RLHelper.pullResetTimer.callback()

        assert.is_nil(RLHelper.pullResetTimer)
        assert.is_true(RLHelper.mainFrame.pullButtons[1].visible)
        assert.is_true(RLHelper.mainFrame.pullButtons[2].visible)
        assert.is_false(RLHelper.mainFrame.cancelBtn.visible)
    end)

    it("cancels the scheduled reset when pull is cancelled manually", function()
        RLHelper:BeginPullCountdown(70)
        local timer = RLHelper.pullResetTimer

        RLHelper:ResetPullControls()

        assert.is_true(timer.cancelled)
        assert.is_nil(RLHelper.pullResetTimer)
        assert.is_true(RLHelper.mainFrame.pullButtons[1].visible)
        assert.is_true(RLHelper.mainFrame.pullButtons[2].visible)
        assert.is_false(RLHelper.mainFrame.cancelBtn.visible)
    end)

    it("uses the DBM slash pull command when it is available", function()
        local slashCalls = {}
        _G.SlashCmdList = {
            DEADLYBOSSMODSPULL = function(msg)
                table.insert(slashCalls, msg)
            end
        }
        _G.DBM = {
            CreatePizzaTimer = function()
                error("fallback should not be used when slash pull exists")
            end
        }

        local ok = RLHelper:InvokeDBMPullCommand(15)

        assert.is_true(ok)
        assert.are.same({ "15" }, slashCalls)
    end)

    it("does nothing when the DBM slash pull command is unavailable", function()
        _G.SlashCmdList = nil
        _G.DBM = nil

        local started = RLHelper:InvokeDBMPullCommand(70)
        local cancelled = RLHelper:InvokeDBMPullCommand(0)

        assert.is_false(started)
        assert.is_false(cancelled)
    end)
end)

describe("RLHelper.affectingGroup", function()
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

