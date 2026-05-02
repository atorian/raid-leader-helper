local mocks = require('tests.mocks')
local spy = require("luassert.spy")
local BloodPrincesTracker = require("../modules/bosses/BloodPrincesTracker")

describe('BloodPrincesTracker', function()
    local log

    local function vortexDamage(sourceName, destName, spellId)
        return {
            event = "SPELL_DAMAGE",
            spellId = spellId or 72817,
            spellName = "Могучий вихрь",
            timestamp = time(),
            sourceName = sourceName,
            destName = destName
        }
    end

    local function vortexMiss(sourceName, destName)
        return {
            event = "SPELL_MISSED",
            spellId = 72817,
            spellName = "Могучий вихрь",
            timestamp = time(),
            sourceName = sourceName,
            destName = destName
        }
    end

    before_each(function()
        log = spy.new(function()
        end)
        BloodPrincesTracker.log = log
        mocks:ClearRaidRoster()
        mocks.raidSize = 0
    end)

    it('receives combat events only in Icecrown Citadel', function()
        assert.is_true(BloodPrincesTracker.receivesCombatEvents)
        assert.are.equal(631, BloodPrincesTracker.zoneGateInstanceId)
    end)

    it('logs vortex damage to a group 5 priest', function()
        mocks.raidSize = 1
        mocks:SetRaidRosterInfo(1, "Вольно", 5, "PRIEST")

        BloodPrincesTracker:handleEvent(vortexDamage("Заблудшый", "Вольно"))

        assert.spy(log).was_called_with(
            "SOME DATE |cFFFFFFFFЗаблудшый|r |TInterface\\Icons\\Spell_Shadow_Teleport:24:24:0:0|t |cFFFFFFFFВольно|r")
    end)

    it('logs all Powerful Vortex dungeon-version spell ids', function()
        local spellIds = { 72817, 72816, 72815, 72038 }
        mocks.raidSize = 1
        mocks:SetRaidRosterInfo(1, "Вольно", 5, "PRIEST")

        for _, spellId in ipairs(spellIds) do
            log:clear()

            BloodPrincesTracker:handleEvent(vortexDamage("Источник", "Вольно", spellId))

            assert.spy(log).was_called()
        end
    end)

    it('logs vortex damage to each allowed healer class in group 5', function()
        local classes = {
            PRIEST = "Прист",
            PALADIN = "Паладин",
            SHAMAN = "Шаман",
            DRUID = "Друид"
        }

        for class, name in pairs(classes) do
            log:clear()
            mocks:ClearRaidRoster()
            mocks.raidSize = 1
            mocks:SetRaidRosterInfo(1, name, 5, class)

            BloodPrincesTracker:handleEvent(vortexDamage("Источник", name))

            assert.spy(log).was_called()
        end
    end)

    it('ignores a group 5 warlock', function()
        mocks.raidSize = 1
        mocks:SetRaidRosterInfo(1, "Варлок", 5, "WARLOCK")

        BloodPrincesTracker:handleEvent(vortexDamage("Источник", "Варлок"))

        assert.spy(log).was_not_called()
    end)

    it('ignores an allowed healer class outside group 5', function()
        mocks.raidSize = 1
        mocks:SetRaidRosterInfo(1, "Прист", 4, "PRIEST")

        BloodPrincesTracker:handleEvent(vortexDamage("Источник", "Прист"))

        assert.spy(log).was_not_called()
    end)

    it('logs vortex misses to a group 5 healer', function()
        mocks.raidSize = 1
        mocks:SetRaidRosterInfo(1, "Прист", 5, "PRIEST")

        BloodPrincesTracker:handleEvent(vortexMiss("Источник", "Прист"))

        assert.spy(log).was_called_with(
            "SOME DATE |cFFFFFFFFИсточник|r |TInterface\\Icons\\Spell_Shadow_Teleport:24:24:0:0|t |cFFFFFFFFПрист|r")
    end)

    it('does not filter the source player', function()
        mocks.raidSize = 2
        mocks:SetRaidRosterInfo(1, "ХилИсточник", 5, "PRIEST")
        mocks:SetRaidRosterInfo(2, "ХилЦель", 5, "DRUID")

        BloodPrincesTracker:handleEvent(vortexDamage("ХилИсточник", "ХилЦель"))

        assert.spy(log).was_called()
    end)
end)
