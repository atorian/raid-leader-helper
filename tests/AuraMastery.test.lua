require('tests.mocks')
require('../lib/blizzardEvent')
local RLHelper = require('../Core')
local tracker = require('../modules/SpellTracker')
local mocks = require('tests.mocks')

describe('Aura Mastery details', function()
    local records, oldBuff, oldMembers
    local function emit(event, source, target, id, name)
        tracker:handleEvent({ event = event, timestamp = 10,
            sourceGUID = source, sourceName = source, sourceFlags = 0x514,
            destGUID = target, spellId = id, spellName = name })
    end
    local function mastery(source)
        emit('SPELL_CAST_SUCCESS', source, '0x0000000000000000', 31821, 'Мастер аур')
        return records[#records]
    end
    before_each(function()
        records = {}
        tracker.log = function(entry) records[#records + 1] = entry end
        tracker:reset()
        tracker.paladinAuras = {}
        oldBuff, oldMembers = _G.UnitBuff, RLHelper.groupMembers
        RLHelper.groupMembers = {}
        _G.UnitBuff = nil
        mocks:ClearUnitGUIDs()
    end)
    after_each(function()
        _G.UnitBuff, RLHelper.groupMembers = oldBuff, oldMembers
        tracker.paladinAuras = {}
        mocks:ClearUnitGUIDs()
    end)

    it('renders an explicit unknown aura instead of the nonexistent target', function()
        local text = RLHelperJournal.Format(mastery('Paladin'))
        assert.is_truthy(text:find('Аура неизвестна', 1, true))
        assert.is_nil(text:find('?', 1, true))
    end)

    it('remembers changes per paladin across fights and persists the selected aura', function()
        emit('SPELL_CAST_SUCCESS', 'One', nil, 48943, 'Аура защиты от темной магии')
        emit('SPELL_CAST_SUCCESS', 'Two', nil, 19746, 'Аура сосредоточенности')
        tracker:reset()
        local first = mastery('One')
        assert.equals(48943, first.auraSpellId)
        emit('SPELL_CAST_SUCCESS', 'One', nil, 48947, 'Аура защиты от огня')
        -- Late removal of the old aura must not clear the new selection.
        emit('SPELL_AURA_REMOVED', 'One', 'One', 48943)
        assert.equals('Аура защиты от огня', mastery('One').auraName)
        assert.equals('Аура сосредоточенности', mastery('Two').auraName)
        assert.is_truthy(RLHelperJournal.Format(RLHelperJournal.Copy(first)):find(
            'Аура защиты от темной магии', 1, true))
        assert.equals(3, #records)
    end)

    it('learns the aura from its caster, not from its recipient', function()
        emit('SPELL_AURA_APPLIED', 'One', 'Two', 48945, 'Аура защиты от магии льда')
        assert.equals(48945, mastery('One').auraSpellId)
        assert.is_nil(mastery('Two').auraSpellId)
        emit('SPELL_AURA_REMOVED', 'One', 'Two', 48945)
        assert.equals(48945, mastery('One').auraSpellId)
        emit('SPELL_AURA_REMOVED', 'One', 'One', 48945)
        assert.is_nil(mastery('One').auraSpellId)
    end)

    it('forgets the aura on death and when entering the world', function()
        emit('SPELL_CAST_SUCCESS', 'One', nil, 48942, 'Аура благочестия')
        emit('UNIT_DIED', nil, 'One')
        assert.is_nil(mastery('One').auraSpellId)
        emit('SPELL_CAST_SUCCESS', 'One', nil, 48942, 'Аура благочестия')
        tracker:PLAYER_ENTERING_WORLD()
        assert.is_nil(mastery('One').auraSpellId)
    end)

    it('recovers an already active own aura from buffs without taking another paladin aura', function()
        RLHelper.groupMembers.One = 'raid1'
        mocks:SetUnitGUID('raid1', 'One')
        mocks:SetUnitGUID('raid2', 'Two')
        _G.UnitBuff = function(unit, index)
            assert.equals('raid1', unit)
            if index == 1 then return 'Аура защиты от огня', nil, nil, nil, nil, nil, nil, 'raid2', nil, nil, 48947 end
            if index == 2 then return 'Аура сосредоточенности', nil, nil, nil, nil, nil, nil, 'raid1', nil, nil, 19746 end
        end
        assert.equals(19746, mastery('One').auraSpellId)
    end)

    it('supports lower ranks and does not duplicate mastery on its buff event', function()
        emit('SPELL_CAST_SUCCESS', 'One', nil, 19899, 'Аура защиты от огня')
        assert.equals(19899, mastery('One').auraSpellId)
        emit('SPELL_AURA_APPLIED', 'One', 'One', 31821, 'Мастер аур')
        assert.equals(1, #records)
    end)
end)
