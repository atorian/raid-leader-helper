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

    it("logs current zone and module gate status in debug mode", function()
        local originalDb = RLHelper.db
        local originalPrint = RLHelper.Print
        local originalIterateModules = RLHelper.IterateModules
        local originalGetInstanceInfo = _G.GetInstanceInfo
        local originalIsInInstance = _G.IsInInstance
        local originalGetRealZoneText = _G.GetRealZoneText
        local originalGetZoneText = _G.GetZoneText
        local originalGetSubZoneText = _G.GetSubZoneText
        local originalGetMinimapZoneText = _G.GetMinimapZoneText
        local printedMessages = {}

        RLHelper.db = {
            profile = {
                debug = true
            }
        }
        RLHelper.Print = function(_, message)
            table.insert(printedMessages, message)
        end
        RLHelper.IterateModules = function()
            return ipairs({
                {
                    name = "TrialCrusaderTracker",
                    receivesCombatEvents = true,
                    zoneGateInstanceId = 649
                },
                {
                    name = "HalionTracker",
                    receivesCombatEvents = true,
                    zoneGateInstanceId = 724
                },
                {
                    name = "DeathwhisperTracker",
                    receivesCombatEvents = true
                }
            })
        end
        _G.GetInstanceInfo = function()
            return "Испытание крестоносца", "raid", 4, "25 Player", 25, 0, false, 649
        end
        _G.IsInInstance = function()
            return true, "raid"
        end
        _G.GetRealZoneText = function()
            return "Испытание крестоносца"
        end
        _G.GetZoneText = function()
            return "Колизей Авангарда"
        end
        _G.GetSubZoneText = function()
            return "Арена"
        end
        _G.GetMinimapZoneText = function()
            return "Арена"
        end

        RLHelper:UpdateZoneContext("test")

        assert.are.equal(649, RLHelper.currentInstanceId)
        assert.are.equal("Зона [test]: name='Испытание крестоносца', mapId=649", printedMessages[1])
        assert.is_true(printedMessages[2]:find("TrialCrusaderTracker:ON gate=649", 1, true) ~= nil)
        assert.is_true(printedMessages[2]:find("HalionTracker:OFF gate=724", 1, true) ~= nil)
        assert.is_true(printedMessages[2]:find("DeathwhisperTracker:ON gate=any", 1, true) ~= nil)

        RLHelper.db = originalDb
        RLHelper.Print = originalPrint
        RLHelper.IterateModules = originalIterateModules
        _G.GetInstanceInfo = originalGetInstanceInfo
        _G.IsInInstance = originalIsInInstance
        _G.GetRealZoneText = originalGetRealZoneText
        _G.GetZoneText = originalGetZoneText
        _G.GetSubZoneText = originalGetSubZoneText
        _G.GetMinimapZoneText = originalGetMinimapZoneText
    end)

    it("uses GetInstanceInfo zone name before map API ids", function()
        local originalDb = RLHelper.db
        local originalPrint = RLHelper.Print
        local originalIterateModules = RLHelper.IterateModules
        local originalGetInstanceInfo = _G.GetInstanceInfo
        local originalGetCurrentMapAreaID = _G.GetCurrentMapAreaID
        local originalSetMapToCurrentZone = _G.SetMapToCurrentZone
        local originalGetRealZoneText = _G.GetRealZoneText
        local originalGetZoneText = _G.GetZoneText
        local printedMessages = {}

        RLHelper.db = {
            profile = {
                debug = true
            }
        }
        RLHelper.Print = function(_, message)
            table.insert(printedMessages, message)
        end
        RLHelper.IterateModules = function()
            return ipairs({
                {
                    name = "HalionTracker",
                    receivesCombatEvents = true,
                    zoneGateInstanceId = 724
                }
            })
        end
        _G.GetInstanceInfo = function()
            return "Рубиновое святилище", "raid", 4, "25 Player", 25, 0, false
        end
        _G.SetMapToCurrentZone = function()
            error("SetMapToCurrentZone should not be used when instance name is known")
        end
        _G.GetCurrentMapAreaID = function()
            error("GetCurrentMapAreaID should not be used when instance name is known")
        end
        _G.GetRealZoneText = function()
            return "Рубиновое святилище"
        end
        _G.GetZoneText = function()
            return "Рубиновое святилище"
        end

        RLHelper:UpdateZoneContext("test")

        assert.are.equal(724, RLHelper.currentInstanceId)
        assert.are.equal("Зона [test]: name='Рубиновое святилище', mapId=724", printedMessages[1])
        assert.is_true(printedMessages[2]:find("HalionTracker:ON gate=724", 1, true) ~= nil)

        RLHelper.db = originalDb
        RLHelper.Print = originalPrint
        RLHelper.IterateModules = originalIterateModules
        _G.GetInstanceInfo = originalGetInstanceInfo
        _G.GetCurrentMapAreaID = originalGetCurrentMapAreaID
        _G.SetMapToCurrentZone = originalSetMapToCurrentZone
        _G.GetRealZoneText = originalGetRealZoneText
        _G.GetZoneText = originalGetZoneText
    end)

    it("uses Ulduar zone name before map API ids", function()
        local originalDb = RLHelper.db
        local originalPrint = RLHelper.Print
        local originalIterateModules = RLHelper.IterateModules
        local originalGetInstanceInfo = _G.GetInstanceInfo
        local originalGetCurrentMapAreaID = _G.GetCurrentMapAreaID
        local originalSetMapToCurrentZone = _G.SetMapToCurrentZone
        local printedMessages = {}

        RLHelper.db = {
            profile = {
                debug = true
            }
        }
        RLHelper.Print = function(_, message)
            table.insert(printedMessages, message)
        end
        RLHelper.IterateModules = function()
            return ipairs({
                {
                    name = "UlduarBossRegistry",
                    receivesCombatEvents = true,
                    zoneGateInstanceId = 603
                }
            })
        end
        _G.GetInstanceInfo = function()
            return "Ульдуар", "raid", 4, "25 Player", 25, 0, false
        end
        _G.SetMapToCurrentZone = function()
            error("SetMapToCurrentZone should not be used when Ulduar instance name is known")
        end
        _G.GetCurrentMapAreaID = function()
            error("GetCurrentMapAreaID should not be used when Ulduar instance name is known")
        end

        RLHelper:UpdateZoneContext("test")

        assert.are.equal(603, RLHelper.currentInstanceId)
        assert.are.equal("Зона [test]: name='Ульдуар', mapId=603", printedMessages[1])
        assert.is_true(printedMessages[2]:find("UlduarBossRegistry:ON gate=603", 1, true) ~= nil)

        RLHelper.db = originalDb
        RLHelper.Print = originalPrint
        RLHelper.IterateModules = originalIterateModules
        _G.GetInstanceInfo = originalGetInstanceInfo
        _G.GetCurrentMapAreaID = originalGetCurrentMapAreaID
        _G.SetMapToCurrentZone = originalSetMapToCurrentZone
    end)
end)

describe("RLHelper damage meter reset command", function()
    local originalGetModule
    local originalIterateModules
    local originalPrint
    local originalDb
    local originalTriggerDamageMeterReset

    before_each(function()
        originalGetModule = RLHelper.GetModule
        originalIterateModules = RLHelper.IterateModules
        originalPrint = RLHelper.Print
        originalDb = RLHelper.db
        originalTriggerDamageMeterReset = RLHelper.TriggerDamageMeterReset
        RLHelper.db = {
            profile = {
                debug = true
            }
        }
    end)

    after_each(function()
        RLHelper.GetModule = originalGetModule
        RLHelper.IterateModules = originalIterateModules
        RLHelper.Print = originalPrint
        RLHelper.db = originalDb
        RLHelper.TriggerDamageMeterReset = originalTriggerDamageMeterReset
    end)

    it("finds a module by name through GetModule first", function()
        local target = { name = "HalionTracker" }
        RLHelper.GetModule = function(_, name, silent)
            assert.are.equal("HalionTracker", name)
            assert.is_true(silent)
            return target
        end
        RLHelper.IterateModules = function()
            error("IterateModules fallback should not be used when GetModule succeeds")
        end

        assert.are.equal(target, RLHelper:FindModuleByName("HalionTracker"))
    end)

    it("finds a module by name through IterateModules", function()
        RLHelper.GetModule = function()
            return nil
        end
        local target = { name = "HalionTracker" }
        RLHelper.IterateModules = function()
            return ipairs({
                { name = "SpellTracker" },
                target,
                { name = "GPAwardButtons" }
            })
        end

        assert.are.equal(target, RLHelper:FindModuleByName("HalionTracker"))
        assert.is_nil(RLHelper:FindModuleByName("UnknownModule"))
    end)

    it("logs debug output when damage meter reset succeeds", function()
        local resetCalls = 0
        local printedMessages = {}
        RLHelper.IterateModules = function()
            return ipairs({
                {
                    name = "HalionTracker",
                    resetDamageMeters = function()
                        resetCalls = resetCalls + 1
                        return true
                    end
                }
            })
        end
        RLHelper.Print = function(_, message)
            table.insert(printedMessages, message)
        end

        local ok = RLHelper:TriggerDamageMeterReset()

        assert.is_true(ok)
        assert.are.equal(1, resetCalls)
        assert.are.same({ "Сброс сегментов урона запущен" }, printedMessages)
    end)

    it("logs debug output when no damage meter was actually reset", function()
        local printedMessages = {}
        RLHelper.IterateModules = function()
            return ipairs({
                {
                    name = "HalionTracker",
                    resetDamageMeters = function()
                        return false
                    end
                }
            })
        end
        RLHelper.Print = function(_, message)
            table.insert(printedMessages, message)
        end

        local ok = RLHelper:TriggerDamageMeterReset()

        assert.is_false(ok)
        assert.are.same({ "Не удалось переключить сегмент у meter addon" }, printedMessages)
    end)

    it("logs debug output when HalionTracker is unavailable", function()
        local printedMessages = {}
        RLHelper.IterateModules = function()
            return ipairs({
                { name = "SpellTracker" }
            })
        end
        RLHelper.Print = function(_, message)
            table.insert(printedMessages, message)
        end

        local ok = RLHelper:TriggerDamageMeterReset()

        assert.is_false(ok)
        assert.are.same({ "HalionTracker недоступен" }, printedMessages)
    end)

end)

describe("RLHelper combat event dispatch", function()
    local originalIterateModules
    local originalShouldDispatchCombatEventToModule
    local originalDispatchCombatEvent
    local originalTrackCombatants
    local originalMarkBossCombat
    local originalFirstEnemy
    local originalInCombat

    before_each(function()
        originalIterateModules = RLHelper.IterateModules
        originalShouldDispatchCombatEventToModule = RLHelper.ShouldDispatchCombatEventToModule
        originalDispatchCombatEvent = RLHelper.DispatchCombatEvent
        originalTrackCombatants = RLHelper.trackCombatants
        originalMarkBossCombat = RLHelper.MarkBossCombat
        originalFirstEnemy = RLHelper.currentCombat.firstEnemy
        originalInCombat = RLHelper.inCombat
    end)

    after_each(function()
        RLHelper.IterateModules = originalIterateModules
        RLHelper.ShouldDispatchCombatEventToModule = originalShouldDispatchCombatEventToModule
        RLHelper.DispatchCombatEvent = originalDispatchCombatEvent
        RLHelper.trackCombatants = originalTrackCombatants
        RLHelper.MarkBossCombat = originalMarkBossCombat
        RLHelper.currentCombat.firstEnemy = originalFirstEnemy
        RLHelper.inCombat = originalInCombat
    end)

    it("skips UI modules that do not handle combat events", function()
        local eventData = { event = "SPELL_DAMAGE" }
        local handled = 0
        local modules = {
            { name = "GPAwardButtons" },
            {
                name = "SpellTracker",
                handleEvent = function(_, event)
                    handled = handled + 1
                    assert.are.same(eventData, event)
                end
            }
        }

        RLHelper.IterateModules = function()
            return ipairs(modules)
        end
        RLHelper.ShouldDispatchCombatEventToModule = function()
            return true
        end

        assert.has_no.errors(function()
            RLHelper:DispatchCombatEvent(eventData)
        end)
        assert.are.equal(1, handled)
    end)

    it("does not dispatch events from outside players", function()
        local dispatchCount = 0
        RLHelper.DispatchCombatEvent = function()
            dispatchCount = dispatchCount + 1
        end
        RLHelper.trackCombatants = function()
        end
        RLHelper.MarkBossCombat = function()
        end

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_DAMAGE",
            "0x0000000000000001", "Чужой", 0x510, "0xF130009BB75AF023", "Халион", 0x10a48,
            12345, "Удар", 0x1, 1000, 0, 1, 0, 0, 0, nil, nil, nil)

        assert.are.equal(0, dispatchCount)
    end)

    it("does not dispatch events to outside players", function()
        local dispatchCount = 0
        RLHelper.DispatchCombatEvent = function()
            dispatchCount = dispatchCount + 1
        end
        RLHelper.trackCombatants = function()
        end
        RLHelper.MarkBossCombat = function()
        end

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_DAMAGE",
            "0xF130009BB75AF023", "Халион", 0x10a48, "0x0000000000000001", "Чужой", 0x510,
            12345, "Удар", 0x1, 1000, 0, 1, 0, 0, 0, nil, nil, nil)

        assert.are.equal(0, dispatchCount)
    end)

    it("dispatches events from raid players", function()
        local dispatchCount = 0
        RLHelper.DispatchCombatEvent = function()
            dispatchCount = dispatchCount + 1
        end
        RLHelper.trackCombatants = function()
        end
        RLHelper.MarkBossCombat = function()
        end
        RLHelper.inCombat = true

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_DAMAGE",
            "0x0000000000000001", "Свой", 0x514, "0xF130009BB75AF023", "Халион", 0x10a48,
            12345, "Удар", 0x1, 1000, 0, 1, 0, 0, 0, nil, nil, nil)

        assert.are.equal(1, dispatchCount)
    end)

    it("does not dispatch non-combat events before combat starts", function()
        local dispatchCount = 0
        RLHelper.DispatchCombatEvent = function()
            dispatchCount = dispatchCount + 1
        end
        RLHelper.trackCombatants = function()
            return false
        end
        RLHelper.MarkBossCombat = function()
        end
        RLHelper.inCombat = false

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_CAST_SUCCESS",
            "0x0000000000000001", "Palanessa", 0x514, "0x0000000000000000", nil, 0x80000000,
            31821, "Мастер аур", 0x1)

        assert.are.equal(0, dispatchCount)
    end)

    it("updates first enemy before dispatching events to modules", function()
        local firstEnemyDuringDispatch
        RLHelper.DispatchCombatEvent = function()
            firstEnemyDuringDispatch = RLHelper.currentCombat.firstEnemy
        end
        RLHelper.trackCombatants = function()
        end
        RLHelper.MarkBossCombat = function()
            return false
        end
        RLHelper.currentCombat.firstEnemy = nil
        RLHelper.inCombat = true

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", GetTime(), "SPELL_DAMAGE",
            "0x0000000000000001", "Свой", 0x514, "0xF130009BB75AF023", "Новый моб", 0x10a48,
            12345, "Удар", 0x1, 1000, 0, 1, 0, 0, 0, nil, nil, nil)

        assert.are.equal("Новый моб", firstEnemyDuringDispatch)
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

describe("RLHelper settings helpers", function()
    local originalDb
    local originalPrint
    local originalOpenToCategory
    local originalOpenOptionsPanel
    local originalGetRealNumRaidMembers
    local originalGetRealNumPartyMembers
    local originalCreateFrame
    local originalUIParent
    local originalAddCategory
    local originalGlobalPrint
    local originalStartCombat
    local originalSendMessage
    local originalInCombat
    local originalCombatEndRequestedAt

    before_each(function()
        originalDb = RLHelper.db
        originalPrint = RLHelper.Print
        originalOpenToCategory = _G.InterfaceOptionsFrame_OpenToCategory
        originalOpenOptionsPanel = RLHelper.OpenOptionsPanel
        originalGetRealNumRaidMembers = _G.GetRealNumRaidMembers
        originalGetRealNumPartyMembers = _G.GetRealNumPartyMembers
        originalCreateFrame = _G.CreateFrame
        originalUIParent = _G.UIParent
        originalAddCategory = _G.InterfaceOptions_AddCategory
        originalGlobalPrint = _G.print
        originalStartCombat = RLHelper.StartCombat
        originalSendMessage = RLHelper.SendMessage
        originalInCombat = RLHelper.inCombat
        originalCombatEndRequestedAt = RLHelper.combatEndRequestedAt
        RLHelper.db = {
            profile = {
                displayOnlyInGroup = true
            }
        }
    end)

    after_each(function()
        RLHelper.db = originalDb
        RLHelper.Print = originalPrint
        RLHelper.OpenOptionsPanel = originalOpenOptionsPanel
        _G.InterfaceOptionsFrame_OpenToCategory = originalOpenToCategory
        _G.GetRealNumRaidMembers = originalGetRealNumRaidMembers
        _G.GetRealNumPartyMembers = originalGetRealNumPartyMembers
        _G.CreateFrame = originalCreateFrame
        _G.UIParent = originalUIParent
        _G.InterfaceOptions_AddCategory = originalAddCategory
        _G.print = originalGlobalPrint
        RLHelper.StartCombat = originalStartCombat
        RLHelper.SendMessage = originalSendMessage
        RLHelper.inCombat = originalInCombat
        RLHelper.combatEndRequestedAt = originalCombatEndRequestedAt
    end)

    it("treats Halion burst pull as disabled when the saved value is missing", function()
        RLHelper.db = {
            profile = {}
        }

        assert.is_false(RLHelper:IsHalionBurstPullEnabled())
    end)

    it("treats Halion burst reset as enabled when the saved value is missing", function()
        RLHelper.db = {
            profile = {}
        }

        assert.is_true(RLHelper:IsHalionBurstResetEnabled())
    end)

    it("treats Halion phase two entry timer as disabled when the saved value is missing", function()
        RLHelper.db = {
            profile = {}
        }

        assert.is_false(RLHelper:IsHalionPhaseTwoEntryTimerEnabled())
    end)

    it("reads enabled Halion burst pull, disabled reset, and enabled phase two entry timer from profile", function()
        RLHelper.db = {
            profile = {
                halionBurstPull = true,
                halionBurstReset = false,
                halionPhaseTwoEntryTimer = true
            }
        }

        assert.is_true(RLHelper:IsHalionBurstPullEnabled())
        assert.is_false(RLHelper:IsHalionBurstResetEnabled())
        assert.is_true(RLHelper:IsHalionPhaseTwoEntryTimerEnabled())
    end)

    it("creates options panel with Russian setting labels", function()
        local texts = {}

        local function newFrame(frameType, name, parent, template)
            local frame = {
                frameType = frameType,
                name = name,
                parent = parent,
                template = template,
                scripts = {}
            }

            function frame:GetName()
                return self.name
            end

            function frame:CreateFontString()
                return newFrame("FontString", nil, self)
            end

            function frame:SetText(text)
                self.text = text
                table.insert(texts, text)
            end

            function frame:SetPoint()
            end

            function frame:SetSize()
            end

            function frame:SetAutoFocus()
            end

            function frame:SetScript(event, callback)
                self.scripts[event] = callback
            end

            function frame:GetText()
                return self.text or ""
            end

            function frame:ClearFocus()
            end

            function frame:SetChecked(value)
                self.checked = value
            end

            if frameType == "CheckButton" and name then
                _G[name .. "Text"] = {
                    SetText = function(_, text)
                        table.insert(texts, text)
                    end
                }
            end

            return frame
        end

        _G.UIParent = newFrame("Frame", "UIParent")
        _G.CreateFrame = newFrame
        _G.InterfaceOptions_AddCategory = function()
        end

        RLHelper:CreateOptionsPanel()

        assert.is_nil(table.concat(texts, " "):find("Pull Cancel", 1, true))
        assert.is_nil(table.concat(texts, " "):find("Display only", 1, true))
        assert.is_true(table.concat(texts, " "):find("Текст сообщения отмены пула", 1, true) ~= nil)
        assert.is_true(table.concat(texts, " "):find("Показывать только в группе", 1, true) ~= nil)
        assert.is_true(table.concat(texts, " "):find("РС Бурст", 1, true) ~= nil)
        assert.is_true(table.concat(texts, " "):find("Сброс Бурста", 1, true) ~= nil)
        assert.is_true(table.concat(texts, " "):find("РС Бурст - Таймер на вход после 2го метеорита", 1, true) ~= nil)
    end)

    it("opens the registered options panel", function()
        local openedPanel
        RLHelper.optionsPanel = { name = "RL Helper" }
        _G.InterfaceOptionsFrame_OpenToCategory = function(panel)
            openedPanel = panel
        end

        assert.is_true(RLHelper:OpenOptionsPanel())
        assert.are.same(RLHelper.optionsPanel, openedPanel)
    end)

    it("handles the slash config command", function()
        local opened = false
        RLHelper.OpenOptionsPanel = function()
            opened = true
            return true
        end

        RLHelper:HandleSlashCommand("config")

        assert.is_true(opened)
    end)

    it("does not advertise the removed fill slash command", function()
        local printed = {}
        _G.print = function(message)
            table.insert(printed, message)
        end

        RLHelper:HandleSlashCommand("help")

        assert.is_nil(table.concat(printed, "\n"):find("/rlh fill", 1, true))
    end)

    it("starts demo combat before sending demo messages", function()
        local startReason
        local sentWhileInCombat = false
        RLHelper.inCombat = false
        RLHelper.StartCombat = function(_, reason)
            startReason = reason
            RLHelper.inCombat = true
        end
        RLHelper.SendMessage = function(_, message)
            if message == "RLHelper_Demo" then
                sentWhileInCombat = RLHelper.inCombat
            end
        end

        RLHelper:HandleSlashCommand("demo")

        assert.are.equal("demo", startReason)
        assert.is_true(sentWhileInCombat)
    end)

    it("requests demo combat end after sending demo messages", function()
        RLHelper.inCombat = false
        RLHelper.combatEndRequestedAt = nil
        RLHelper.StartCombat = function()
            RLHelper.inCombat = true
        end
        RLHelper.SendMessage = function()
        end

        RLHelper:HandleSlashCommand("demo")

        assert.is_not_nil(RLHelper.combatEndRequestedAt)
    end)

    it("allows manual show outside a group when displayOnlyInGroup is enabled", function()
        local shown = false
        local hidden = false
        local printedMessage
        RLHelper.mainFrame = {
            Hide = function()
                hidden = true
            end,
            Show = function()
                shown = true
            end
        }
        RLHelper.Print = function(_, message)
            printedMessage = message
        end
        _G.GetRealNumRaidMembers = function()
            return 0
        end
        _G.GetRealNumPartyMembers = function()
            return 0
        end

        RLHelper:SetMainFrameVisible(true)

        assert.is_true(shown)
        assert.is_false(hidden)
        assert.is_nil(printedMessage)
    end)

    it("automatically hides the main frame outside a group when displayOnlyInGroup is enabled", function()
        local shown = false
        local hidden = false
        RLHelper.mainFrame = {
            Hide = function()
                hidden = true
            end,
            Show = function()
                shown = true
            end
        }
        _G.GetRealNumRaidMembers = function()
            return 0
        end
        _G.GetRealNumPartyMembers = function()
            return 0
        end

        RLHelper:RefreshMainFrameVisibility()

        assert.is_true(hidden)
        assert.is_false(shown)
    end)

    it("automatically shows the main frame in a group when displayOnlyInGroup is enabled", function()
        local shown = false
        local hidden = false
        RLHelper.mainFrame = {
            Hide = function()
                hidden = true
            end,
            Show = function()
                shown = true
            end
        }
        _G.GetRealNumRaidMembers = function()
            return 1
        end
        _G.GetRealNumPartyMembers = function()
            return 0
        end

        RLHelper:RefreshMainFrameVisibility()

        assert.is_true(shown)
        assert.is_false(hidden)
    end)

    it("does not force visibility when displayOnlyInGroup is disabled", function()
        local shown = false
        local hidden = false
        RLHelper.db.profile.displayOnlyInGroup = false
        RLHelper.mainFrame = {
            Hide = function()
                hidden = true
            end,
            Show = function()
                shown = true
            end
        }
        _G.GetRealNumRaidMembers = function()
            return 1
        end
        _G.GetRealNumPartyMembers = function()
            return 0
        end

        RLHelper:RefreshMainFrameVisibility()

        assert.is_false(shown)
        assert.is_false(hidden)
    end)
end)

describe("RLHelper main frame raid check button", function()
    local originalCreateFrame
    local originalUIParent
    local originalUIDropDownMenuSetWidth
    local originalUIDropDownMenuCreateInfo
    local originalUIDropDownMenuAddButton
    local originalUIDropDownMenuInitialize
    local originalUIDropDownMenuSetText
    local originalDoReadyCheck
    local originalPrint
    local originalLayoutMainFrame
    local originalSendMessage
    local frames
    local printedMessages

    local function newFrame(frameType, name, parent, template)
        local frame = {
            frameType = frameType,
            name = name,
            parent = parent,
            template = template,
            visible = true,
            points = {},
            scripts = {}
        }

        function frame:SetSize(width, height)
            self.width = width
            self.height = height
        end

        function frame:SetPoint(...)
            table.insert(self.points, { ... })
        end

        function frame:SetMovable(value)
            self.movable = value
        end

        function frame:SetResizable(value)
            self.resizable = value
        end

        function frame:SetMinResize(width, height)
            self.minResize = { width, height }
        end

        function frame:SetMaxResize(width, height)
            self.maxResize = { width, height }
        end

        function frame:EnableMouse(value)
            self.mouseEnabled = value
        end

        function frame:RegisterForDrag(button)
            self.dragButton = button
        end

        function frame:SetScript(event, callback)
            self.scripts[event] = callback
        end

        function frame:SetBackdrop(backdrop)
            self.backdrop = backdrop
        end

        function frame:CreateFontString()
            return newFrame("FontString", nil, self)
        end

        function frame:SetText(text)
            self.text = text
        end

        function frame:GetFontString()
            return {
                SetFont = function(_, font, size, flags)
                    frame.font = { font, size, flags }
                end,
                SetPoint = function(_, ...)
                    frame.fontPoint = { ... }
                end
            }
        end

        function frame:SetNormalTexture(texture)
            self.normalTexture = texture
        end

        function frame:SetPushedTexture(texture)
            self.pushedTexture = texture
        end

        function frame:SetHighlightTexture(texture)
            self.highlightTexture = texture
        end

        function frame:SetDisabledTexture(texture)
            self.disabledTexture = texture
        end

        function frame:SetHeight(height)
            self.height = height
        end

        function frame:Show()
            self.visible = true
        end

        function frame:Hide()
            self.visible = false
        end

        function frame:SetFont(font, size, flags)
            self.font = { font, size, flags }
        end

        function frame:SetJustifyV(value)
            self.justifyV = value
        end

        function frame:SetJustifyH(value)
            self.justifyH = value
        end

        function frame:SetFading(value)
            self.fading = value
        end

        function frame:SetMaxLines(value)
            self.maxLines = value
        end

        function frame:EnableMouseWheel(value)
            self.mouseWheelEnabled = value
        end

        function frame:SetHyperlinksEnabled(value)
            self.hyperlinksEnabled = value
        end

        function frame:SetIndentedWordWrap(value)
            self.indentedWordWrap = value
        end

        function frame:SetInsertMode(value)
            self.insertMode = value
        end

        function frame:StartMoving()
            self.startedMoving = true
        end

        function frame:StopMovingOrSizing()
            self.stoppedMoving = true
        end

        function frame:StartSizing(direction)
            self.startedSizing = direction
        end

        function frame:Clear()
            self.cleared = true
        end

        function frame:ScrollUp()
            self.scrolledUp = true
        end

        function frame:ScrollDown()
            self.scrolledDown = true
        end

        table.insert(frames, frame)
        return frame
    end

    before_each(function()
        originalCreateFrame = _G.CreateFrame
        originalUIParent = _G.UIParent
        originalUIDropDownMenuSetWidth = _G.UIDropDownMenu_SetWidth
        originalUIDropDownMenuCreateInfo = _G.UIDropDownMenu_CreateInfo
        originalUIDropDownMenuAddButton = _G.UIDropDownMenu_AddButton
        originalUIDropDownMenuInitialize = _G.UIDropDownMenu_Initialize
        originalUIDropDownMenuSetText = _G.UIDropDownMenu_SetText
        originalDoReadyCheck = _G.DoReadyCheck
        originalPrint = _G.print
        originalLayoutMainFrame = RLHelper.LayoutMainFrame
        originalSendMessage = RLHelper.SendMessage
        frames = {}
        printedMessages = {}

        _G.UIParent = newFrame("Frame", "UIParent")
        _G.CreateFrame = newFrame
        _G.UIDropDownMenu_SetWidth = function(frame, width)
            frame.dropdownWidth = width
        end
        _G.UIDropDownMenu_CreateInfo = function()
            return {}
        end
        _G.UIDropDownMenu_AddButton = function()
        end
        _G.UIDropDownMenu_Initialize = function(frame, initialize)
            frame.initialize = initialize
        end
        _G.UIDropDownMenu_SetText = function(frame, text)
            frame.text = text
        end
        _G.print = function(message)
            table.insert(printedMessages, message)
        end

        RLHelper.mainFrame = nil
        RLHelper.currentCombat = {}
        RLHelper.combatHistory = {}
        RLHelper.LayoutMainFrame = function()
        end
        RLHelper.SendMessage = function()
        end
    end)

    after_each(function()
        _G.CreateFrame = originalCreateFrame
        _G.UIParent = originalUIParent
        _G.UIDropDownMenu_SetWidth = originalUIDropDownMenuSetWidth
        _G.UIDropDownMenu_CreateInfo = originalUIDropDownMenuCreateInfo
        _G.UIDropDownMenu_AddButton = originalUIDropDownMenuAddButton
        _G.UIDropDownMenu_Initialize = originalUIDropDownMenuInitialize
        _G.UIDropDownMenu_SetText = originalUIDropDownMenuSetText
        _G.DoReadyCheck = originalDoReadyCheck
        _G.print = originalPrint
        RLHelper.LayoutMainFrame = originalLayoutMainFrame
        RLHelper.SendMessage = originalSendMessage
    end)

    it("adds Raid Check before pull buttons and hides cleanup", function()
        RLHelper:CreateMainFrame()

        assert.equals("РЧ", RLHelper.mainFrame.raidCheckBtn.text)
        assert.equals(32, RLHelper.mainFrame.raidCheckBtn.width)
        assert.equals(25, RLHelper.mainFrame.raidCheckBtn.height)
        assert.equals(RLHelper.mainFrame.raidCheckBtn, RLHelper.mainFrame.pullButtons[1])
        assert.equals("Пул 15", RLHelper.mainFrame.pullButtons[2].text)
        assert.equals("Пул 70", RLHelper.mainFrame.pullButtons[3].text)
        assert.are.same({ "LEFT", RLHelper.mainFrame.buttonContainer, "LEFT", 0, 0 }, RLHelper.mainFrame.raidCheckBtn.points[1])
        assert.are.same({ "LEFT", RLHelper.mainFrame.raidCheckBtn, "RIGHT", 4, 0 }, RLHelper.mainFrame.pullButtons[2].points[1])
        assert.are.same({ "LEFT", RLHelper.mainFrame.pullButtons[2], "RIGHT", 4, 0 }, RLHelper.mainFrame.pullButtons[3].points[1])
        assert.is_false(RLHelper.mainFrame.resetBtn.visible)
        assert.are.same({ "LEFT", RLHelper.mainFrame.pullButtons[3], "RIGHT", -8, -2 }, RLHelper.mainFrame.combatDropdown.points[1])
    end)

    it("calls the global DoReadyCheck function", function()
        local readyCheckCalls = 0
        _G.DoReadyCheck = function()
            readyCheckCalls = readyCheckCalls + 1
        end

        RLHelper:CreateMainFrame()
        RLHelper.mainFrame.raidCheckBtn.scripts.OnClick()

        assert.equals(1, readyCheckCalls)
        assert.are.same({}, printedMessages)
    end)

    it("prints a warning when DoReadyCheck is unavailable", function()
        _G.DoReadyCheck = nil

        RLHelper:CreateMainFrame()
        RLHelper.mainFrame.raidCheckBtn.scripts.OnClick()

        assert.are.same({ "ReadyCheck недоступен" }, printedMessages)
    end)
end)

describe("RLHelper pull controls", function()
    local originalSlashCmdList
    local originalDBM
    local originalSendChatMessage
    local originalPlaySoundFile
    local originalTimerTracker
    local originalTimerTrackerOnEvent
    local originalSendAddonMessage
    local originalIsInInstance
    local originalGetRealNumRaidMembers
    local originalGetRealNumPartyMembers
    local originalDb
    local originalBeginPullCountdown
    local originalInvokeDBMPullCommand
    local originalMinimizeWindow

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
        originalSendChatMessage = _G.SendChatMessage
        originalPlaySoundFile = _G.PlaySoundFile
        originalTimerTracker = _G.TimerTracker
        originalTimerTrackerOnEvent = _G.TimerTracker_OnEvent
        originalSendAddonMessage = _G.SendAddonMessage
        originalIsInInstance = _G.IsInInstance
        originalGetRealNumRaidMembers = _G.GetRealNumRaidMembers
        originalGetRealNumPartyMembers = _G.GetRealNumPartyMembers
        originalDb = RLHelper.db
        originalBeginPullCountdown = RLHelper.BeginPullCountdown
        originalInvokeDBMPullCommand = RLHelper.InvokeDBMPullCommand
        originalMinimizeWindow = RLHelper.MinimizeWindow
        _G.IsInInstance = function()
            return false, "raid"
        end
        _G.GetRealNumRaidMembers = function()
            return 25
        end
        _G.GetRealNumPartyMembers = function()
            return 0
        end
        RLHelper.db = {
            profile = {
                pullCancelMessage = "ГАЛЯ, ОТМЕНА!"
            }
        }
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
                newVisibilityProbe(true),
                newVisibilityProbe(true)
            },
            cancelBtn = newVisibilityProbe(false)
        }
    end)

    after_each(function()
        _G.SlashCmdList = originalSlashCmdList
        _G.DBM = originalDBM
        _G.SendChatMessage = originalSendChatMessage
        _G.PlaySoundFile = originalPlaySoundFile
        _G.TimerTracker = originalTimerTracker
        _G.TimerTracker_OnEvent = originalTimerTrackerOnEvent
        _G.SendAddonMessage = originalSendAddonMessage
        _G.IsInInstance = originalIsInInstance
        _G.GetRealNumRaidMembers = originalGetRealNumRaidMembers
        _G.GetRealNumPartyMembers = originalGetRealNumPartyMembers
        RLHelper.db = originalDb
        RLHelper.BeginPullCountdown = originalBeginPullCountdown
        RLHelper.InvokeDBMPullCommand = originalInvokeDBMPullCommand
        RLHelper.MinimizeWindow = originalMinimizeWindow
    end)

    it("restores pull buttons automatically when the countdown finishes", function()
        RLHelper:BeginPullCountdown(15)

        assert.is_false(RLHelper.mainFrame.pullButtons[1].visible)
        assert.is_false(RLHelper.mainFrame.pullButtons[2].visible)
        assert.is_false(RLHelper.mainFrame.pullButtons[3].visible)
        assert.is_true(RLHelper.mainFrame.cancelBtn.visible)
        assert.is_not_nil(RLHelper.pullResetTimer)

        RLHelper.pullResetTimer.callback()

        assert.is_nil(RLHelper.pullResetTimer)
        assert.is_true(RLHelper.mainFrame.pullButtons[1].visible)
        assert.is_true(RLHelper.mainFrame.pullButtons[2].visible)
        assert.is_true(RLHelper.mainFrame.pullButtons[3].visible)
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
        assert.is_true(RLHelper.mainFrame.pullButtons[3].visible)
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

    it("starts DBM-only pull without touching pull controls, window, or log", function()
        local invokedDuration
        RLHelper.BeginPullCountdown = function()
            error("BeginPullCountdown should not be used")
        end
        RLHelper.MinimizeWindow = function()
            error("MinimizeWindow should not be used")
        end
        RLHelper.InvokeDBMPullCommand = function(_, duration)
            invokedDuration = duration
            return true
        end
        RLHelper.mainFrame.logText = {
            Clear = function()
                error("log should not be cleared")
            end
        }

        local ok = RLHelper:StartDBMPullCommand(15)

        assert.is_true(ok)
        assert.are.equal(15, invokedDuration)
        assert.is_nil(RLHelper.pullResetTimer)
        assert.is_true(RLHelper.mainFrame.pullButtons[1].visible)
        assert.is_true(RLHelper.mainFrame.pullButtons[2].visible)
        assert.is_true(RLHelper.mainFrame.pullButtons[3].visible)
        assert.is_false(RLHelper.mainFrame.cancelBtn.visible)
    end)

    it("cancels pull through DBM scheduled messages, sounds, and bars", function()
        local addonMessages = {}
        local chatMessages = {}
        local unscheduled = {}
        local pizzaTimers = {}
        local cancelledBars = {}
        local dummyTextCancelled = false
        local dummyTimerStopped = false
        local timerTrackerReset = false
        _G.SendAddonMessage = function(prefix, msg, channel)
            table.insert(addonMessages, { prefix = prefix, msg = msg, channel = channel })
        end
        _G.SendChatMessage = function(message, channel)
            table.insert(chatMessages, { message = message, channel = channel })
        end
        _G.PlaySoundFile = function()
        end
        _G.TimerTracker = {}
        _G.TimerTracker_OnEvent = function(frame, event)
            if frame == _G.TimerTracker and event == "PLAYER_ENTERING_WORLD" then
                timerTrackerReset = true
            end
        end
        _G.DBM = {
            Unschedule = function(_, fn)
                table.insert(unscheduled, fn)
            end,
            CreatePizzaTimer = function(_, time, text)
                table.insert(pizzaTimers, { time = time, text = text })
            end,
            Bars = {
                CancelBar = function(_, name)
                    table.insert(cancelledBars, name)
                end
            },
            GetModByName = function(_, name)
                if name ~= "PullTimerCountdownDummy" then
                    return nil
                end

                return {
                    text = {
                        Cancel = function()
                            dummyTextCancelled = true
                        end
                    },
                    timer = {
                        Stop = function()
                            dummyTimerStopped = true
                        end
                    }
                }
            end
        }

        RLHelper:BeginPullCountdown(15)
        local timer = RLHelper.pullResetTimer

        RLHelper:CancelPullCountdown()

        assert.are.same({
            { prefix = "DBMv4-PT", msg = "0", channel = "RAID" },
            { prefix = "DBMv4-Pizza", msg = "0\tАТAKA!!", channel = "RAID" },
            { prefix = "DBMv4-Pizza", msg = "0\tАтака", channel = "RAID" },
            { prefix = "DBMv4-Pizza", msg = "0\tPull in", channel = "RAID" }
        }, addonMessages)
        assert.are.same({ { message = "ГАЛЯ, ОТМЕНА!", channel = "RAID_WARNING" } }, chatMessages)
        assert.are.same({ _G.SendChatMessage, _G.PlaySoundFile }, unscheduled)
        assert.are.same({
            { time = 0, text = "АТAKA!!" },
            { time = 0, text = "Атака" },
            { time = 0, text = "Pull in" }
        }, pizzaTimers)
        assert.are.same({ "АТAKA!!", "Атака", "Pull in" }, cancelledBars)
        assert.is_true(dummyTextCancelled)
        assert.is_true(dummyTimerStopped)
        assert.is_true(timerTrackerReset)
        assert.is_true(timer.cancelled)
        assert.is_nil(RLHelper.pullResetTimer)
        assert.is_true(RLHelper.mainFrame.pullButtons[1].visible)
        assert.is_true(RLHelper.mainFrame.pullButtons[2].visible)
        assert.is_true(RLHelper.mainFrame.pullButtons[3].visible)
        assert.is_false(RLHelper.mainFrame.cancelBtn.visible)
    end)

    it("uses the configured pull cancel message", function()
        local chatMessages = {}
        _G.SendChatMessage = function(message, channel)
            table.insert(chatMessages, { message = message, channel = channel })
        end
        _G.DBM = nil
        RLHelper.db.profile.pullCancelMessage = "Стоп пул"

        RLHelper:CancelDBMPullCountdown()

        assert.are.same({ { message = "Стоп пул", channel = "RAID_WARNING" } }, chatMessages)
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

