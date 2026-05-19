require('tests.mocks')
local mocks = require('tests.mocks')
local GPAwardButtons = require("../modules/ui/GPAwardButtons")

describe('GPAwardButtons', function()
    local originalUnitIsPlayer
    local originalUnitName
    local originalUnitIsGroupLeader
    local originalUnitIsGroupAssistant
    local originalEPGP
    local originalSlashCmdList
    local originalCreateFrame

    before_each(function()
        mocks:ClearUnitGUIDs()
        originalUnitIsPlayer = _G.UnitIsPlayer
        originalUnitName = _G.UnitName
        originalUnitIsGroupLeader = _G.UnitIsGroupLeader
        originalUnitIsGroupAssistant = _G.UnitIsGroupAssistant
        originalEPGP = _G.EPGP
        originalSlashCmdList = _G.SlashCmdList
        originalCreateFrame = _G.CreateFrame

        GPAwardButtons.awardUndoStack = {}
        GPAwardButtons.undoButton = nil
        GPAwardButtons.footerFrame = nil
        GPAwardButtons.buttons = nil

        _G.UnitIsPlayer = function(unitId)
            return unitId == "target"
        end

        _G.UnitName = function(unitId)
            if unitId == "target" then
                return "TargetPlayer"
            end
        end

        _G.UnitIsGroupLeader = function()
            return false
        end

        _G.UnitIsGroupAssistant = function()
            return false
        end
    end)

    after_each(function()
        _G.UnitIsPlayer = originalUnitIsPlayer
        _G.UnitName = originalUnitName
        _G.UnitIsGroupLeader = originalUnitIsGroupLeader
        _G.UnitIsGroupAssistant = originalUnitIsGroupAssistant
        _G.EPGP = originalEPGP
        _G.SlashCmdList = originalSlashCmdList
        _G.CreateFrame = originalCreateFrame
    end)

    it('awards GP to the current player target through the EPGP slash command', function()
        local slashCalls = {}
        mocks:SetUnitGUID("target", "0x0001")
        _G.UnitIsGroupLeader = function(unitId)
            return unitId == "player"
        end
        _G.SlashCmdList = {
            EPGP = function(command)
                table.insert(slashCalls, command)
            end
        }

        local ok, awardedName = GPAwardButtons:AwardTargetGP("Каспер", 100)

        assert.is_true(ok)
        assert.are.equal("TargetPlayer", awardedName)
        assert.are.same({ "gp TargetPlayer Каспер 100" }, slashCalls)
    end)

    it('awards GP through the AceConsole slash handler registered by EPGP', function()
        local slashCalls = {}
        mocks:SetUnitGUID("target", "0x0001")
        _G.UnitIsGroupLeader = function(unitId)
            return unitId == "player"
        end
        _G.SlashCmdList = {
            ACECONSOLE_EPGP = function(command)
                table.insert(slashCalls, command)
            end
        }

        local ok, awardedName = GPAwardButtons:AwardTargetGP("Каспер", 100)

        assert.is_true(ok)
        assert.are.equal("TargetPlayer", awardedName)
        assert.are.same({ "gp TargetPlayer Каспер 100" }, slashCalls)
    end)

    it('uses the configured reason phrase when a GP button is clicked', function()
        local slashCalls = {}
        mocks:SetUnitGUID("target", "0x0001")
        _G.SlashCmdList = {
            EPGP = function(command)
                table.insert(slashCalls, command)
            end
        }

        GPAwardButtons:handleButtonClick({ label = "200", reason = "Мертвый_Оппосум", amount = 200 })

        assert.are.same({ "gp TargetPlayer Мертвый_Оппосум 200" }, slashCalls)
    end)

    it('stores successful GP awards and undoes the latest award with negative GP', function()
        local slashCalls = {}
        mocks:SetUnitGUID("target", "0x0001")
        _G.SlashCmdList = {
            EPGP = function(command)
                table.insert(slashCalls, command)
            end
        }

        assert.is_true(GPAwardButtons:AwardTargetGP("Каспер", 100))
        assert.is_true(GPAwardButtons:AwardTargetGP("Бэтмен", 250))

        local ok, targetName = GPAwardButtons:UndoLastGPAward()

        assert.is_true(ok)
        assert.are.equal("TargetPlayer", targetName)
        assert.are.same({
            "gp TargetPlayer Каспер 100",
            "gp TargetPlayer Бэтмен 250",
            "gp TargetPlayer Бэтмен -250"
        }, slashCalls)
    end)

    it('keeps only the last 10 GP awards in the undo stack', function()
        local slashCalls = {}
        mocks:SetUnitGUID("target", "0x0001")
        _G.SlashCmdList = {
            EPGP = function(command)
                table.insert(slashCalls, command)
            end
        }

        for i = 1, 11 do
            assert.is_true(GPAwardButtons:AwardTargetGP("Причина" .. i, i))
        end

        assert.are.equal(10, #GPAwardButtons.awardUndoStack)
        assert.are.equal("Причина2", GPAwardButtons.awardUndoStack[1].reason)
        assert.are.equal("Причина11", GPAwardButtons.awardUndoStack[10].reason)
    end)

    it('does not undo anything when the undo stack is empty', function()
        local slashCalls = {}
        _G.SlashCmdList = {
            EPGP = function(command)
                table.insert(slashCalls, command)
            end
        }

        local ok, err = GPAwardButtons:UndoLastGPAward()

        assert.is_false(ok)
        assert.are.equal("Нет начислений для отмены", err)
        assert.are.same({}, slashCalls)
    end)

    it('leaves the undo stack intact when EPGP is unavailable during undo', function()
        mocks:SetUnitGUID("target", "0x0001")
        _G.SlashCmdList = {
            EPGP = function()
            end
        }
        assert.is_true(GPAwardButtons:AwardTargetGP("Каспер", 100))
        _G.SlashCmdList = nil

        local ok, err = GPAwardButtons:UndoLastGPAward()

        assert.is_false(ok)
        assert.are.equal("Slash-команда EPGP недоступна", err)
        assert.are.equal(1, #GPAwardButtons.awardUndoStack)
    end)

    it('updates the undo button enabled state after award and undo', function()
        local slashCalls = {}
        local createdFrames = {}
        local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
        RLHelper.mainFrame = {}
        RLHelper.SetMainFrameBottomPanel = function()
        end
        mocks:SetUnitGUID("target", "0x0001")
        _G.SlashCmdList = {
            EPGP = function(command)
                table.insert(slashCalls, command)
            end
        }
        _G.CreateFrame = function(frameType, name, parent, template)
            local frame = {
                frameType = frameType,
                name = name,
                parent = parent,
                template = template,
                visible = true,
                points = {},
                scripts = {},
                enabled = true
            }
            function frame:SetSize(width, height)
                self.width = width
                self.height = height
            end
            function frame:SetPoint(...)
                table.insert(self.points, { ... })
            end
            function frame:SetHeight(height)
                self.height = height
            end
            function frame:SetText(text)
                self.text = text
            end
            function frame:SetScript(event, callback)
                self.scripts[event] = callback
            end
            function frame:Show()
                self.visible = true
            end
            function frame:Enable()
                self.enabled = true
            end
            function frame:Disable()
                self.enabled = false
            end
            table.insert(createdFrames, frame)
            return frame
        end

        GPAwardButtons:attachToMainFrame()

        assert.is_false(GPAwardButtons.undoButton.enabled)
        GPAwardButtons:handleButtonClick({ label = "100", reason = "Каспер", amount = 100 })
        assert.is_true(GPAwardButtons.undoButton.enabled)
        GPAwardButtons.undoButton.scripts.OnClick()
        assert.is_false(GPAwardButtons.undoButton.enabled)
        assert.are.same({ "gp TargetPlayer Каспер 100", "gp TargetPlayer Каспер -100" }, slashCalls)
    end)

    it('fails when the target is missing', function()
        _G.UnitIsGroupLeader = function(unitId)
            return unitId == "player"
        end
        local ok, err = GPAwardButtons:AwardTargetGP("100", 100)

        assert.is_false(ok)
        assert.are.equal("Нет выбранной цели", err)
    end)

    it('fails when the target is not a player', function()
        mocks:SetUnitGUID("target", "0x0001")
        _G.UnitIsGroupLeader = function(unitId)
            return unitId == "player"
        end
        _G.UnitIsPlayer = function()
            return false
        end

        local ok, err = GPAwardButtons:AwardTargetGP("100", 100)

        assert.is_false(ok)
        assert.are.equal("Цель должна быть игроком", err)
    end)

    it('fails when the EPGP slash command is unavailable', function()
        mocks:SetUnitGUID("target", "0x0001")
        _G.UnitIsGroupLeader = function(unitId)
            return unitId == "player"
        end
        _G.SlashCmdList = nil

        local ok, err = GPAwardButtons:AwardTargetGP("250", 250)

        assert.is_false(ok)
        assert.are.equal("Slash-команда EPGP недоступна", err)
    end)
end)
