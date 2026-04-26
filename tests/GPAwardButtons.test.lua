require('tests.mocks')
local mocks = require('tests.mocks')
local GPAwardButtons = require("../modules/ui/GPAwardButtons")

describe('GPAwardButtons', function()
    local originalUnitIsPlayer
    local originalUnitName
    local originalUnitIsGroupLeader
    local originalUnitIsGroupAssistant
    local originalEPGP

    before_each(function()
        mocks:ClearUnitGUIDs()
        originalUnitIsPlayer = _G.UnitIsPlayer
        originalUnitName = _G.UnitName
        originalUnitIsGroupLeader = _G.UnitIsGroupLeader
        originalUnitIsGroupAssistant = _G.UnitIsGroupAssistant
        originalEPGP = _G.EPGP

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
    end)

    it('awards GP to the current player target', function()
        local incCalls = {}
        mocks:SetUnitGUID("target", "0x0001")
        _G.UnitIsGroupLeader = function(unitId)
            return unitId == "player"
        end
        _G.EPGP = {
            GetEPGP = function(_, name)
                if name == "TargetPlayer" then
                    return 100, 200
                end
            end,
            CanIncGPBy = function(_, reason, amount)
                return reason == "1к" and amount == 1000
            end,
            IncGPBy = function(_, name, reason, amount)
                table.insert(incCalls, {
                    name = name,
                    reason = reason,
                    amount = amount
                })
                return name
            end
        }

        local ok, awardedName = GPAwardButtons:AwardTargetGP("1к", 1000)

        assert.is_true(ok)
        assert.are.equal("TargetPlayer", awardedName)
        assert.are.same({
            name = "TargetPlayer",
            reason = "1к",
            amount = 1000
        }, incCalls[1])
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

    it('fails when EPGP cannot award GP', function()
        mocks:SetUnitGUID("target", "0x0001")
        _G.UnitIsGroupLeader = function(unitId)
            return unitId == "player"
        end
        _G.EPGP = {
            GetEPGP = function()
                return 100, 200
            end,
            CanIncGPBy = function()
                return false
            end,
            IncGPBy = function()
                error("should not be called")
            end
        }

        local ok, err = GPAwardButtons:AwardTargetGP("250", 250)

        assert.is_false(ok)
        assert.are.equal("EPGP не позволяет начислить GP: нет прав или данные не готовы", err)
    end)
end)
