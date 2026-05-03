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

    before_each(function()
        mocks:ClearUnitGUIDs()
        originalUnitIsPlayer = _G.UnitIsPlayer
        originalUnitName = _G.UnitName
        originalUnitIsGroupLeader = _G.UnitIsGroupLeader
        originalUnitIsGroupAssistant = _G.UnitIsGroupAssistant
        originalEPGP = _G.EPGP
        originalSlashCmdList = _G.SlashCmdList

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

        local ok, awardedName = GPAwardButtons:AwardTargetGP("1к", 1000)

        assert.is_true(ok)
        assert.are.equal("TargetPlayer", awardedName)
        assert.are.same({ "gp TargetPlayer 1к 1000" }, slashCalls)
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
