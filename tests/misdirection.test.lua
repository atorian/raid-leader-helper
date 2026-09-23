local mocks = require('tests.mocks')
require('../lib/blizzardEvent')
local addon = require('../Core')
local tracker = require('../modules/Misdirection')
local Journal = require('lib.Journal')
local assertRecord = require('tests.journal_assertions')
local spy = require('luassert.spy')

local function event(subevent, spellId, amount, timestamp, source, target)
    return {
        event = subevent, spellId = spellId, amount = amount, timestamp = timestamp or 100,
        sourceGUID = source or 'hunter', sourceName = source or 'hunter', sourceFlags = 0x514,
        destGUID = target or 'enemy', destName = target or 'enemy', destFlags = target == 'tank' and 0x514 or 0xa48,
    }
end

local function start(source, spellId)
    tracker:handleEvent(event('SPELL_CAST_SUCCESS', spellId or 34477, nil, 100, source, 'tank'))
end

local function finish(source, spellId)
    tracker:handleEvent(event('SPELL_AURA_REMOVED', spellId or 35079, nil, 110, source, 'tank'))
end

describe('Misdirection tracker', function()
    local oldCombat, oldModules, oldFrame, oldCurrent, oldDisplayed, oldView
    before_each(function()
        oldCombat, oldModules, oldFrame = addon.inCombat, addon.IterateModules, addon.mainFrame
        oldCurrent, oldDisplayed, oldView = addon.currentCombat, addon.displayedCombat, addon.journalView
        addon.inCombat, addon.mainFrame, addon.journalView = true, nil, 'ALL'
        addon.currentCombat = { events = {} }
        addon.displayedCombat = addon.currentCombat
        tracker:reset()
        tracker.log = spy.new(function() end)
    end)
    after_each(function()
        addon:StopCombatTicker()
        addon.inCombat, addon.IterateModules, addon.mainFrame = oldCombat, oldModules, oldFrame
        addon.currentCombat, addon.displayedCombat, addon.journalView = oldCurrent, oldDisplayed, oldView
    end)

    it('records start, separate tracked hits with their targets, and total damage', function()
        start()
        tracker:handleEvent(event('SPELL_DAMAGE', 49050, 1000, 101))
        tracker:handleEvent(event('SPELL_DAMAGE', 53209, 2000, 102, 'hunter', 'other enemy'))
        finish()
        assert.spy(tracker.log).was_called(4)
        assertRecord(tracker.log, { kind = 'MISDIRECTION_START', sourceName = 'hunter', targetName = 'tank', spellId = 34477 })
        assertRecord(tracker.log, { kind = 'MISDIRECTION_DAMAGE', targetName = 'enemy', spellId = 49050, amount = 1000 })
        assertRecord(tracker.log, { kind = 'MISDIRECTION_DAMAGE', targetName = 'other enemy', spellId = 53209, amount = 2000 })
        assertRecord(tracker.log, { kind = 'MISDIRECTION_SUMMARY', targetName = 'tank', amount = 3000 })
    end)

    it('includes ranged and periodic damage in totals but hides excluded shots', function()
        start()
        tracker:handleEvent(event('RANGE_DAMAGE', 75, 100, 101))
        tracker:handleEvent(event('SPELL_PERIODIC_DAMAGE', 53352, 200, 102))
        finish()
        assertRecord(tracker.log, { kind = 'MISDIRECTION_DAMAGE', spellId = 75, hidden = true })
        assertRecord(tracker.log, { kind = 'MISDIRECTION_DAMAGE', spellId = 53352, hidden = false })
        assertRecord(tracker.log, { kind = 'MISDIRECTION_SUMMARY', amount = 300 })
    end)

    it('keeps the tracked-shot whitelist while totaling every damage event', function()
        start()
        for i, spellId in ipairs({ 75, 49001, 53209, 53353, 49050, 49052 }) do
            tracker:handleEvent(event('SPELL_DAMAGE', spellId, i * 100, 100 + i))
        end
        finish()
        local visible = {}
        for _, call in ipairs(tracker.log.calls) do
            local entry = call.vals[1]
            if entry.kind == 'MISDIRECTION_DAMAGE' and Journal.Visible(entry, 'MISDIRECTION') then
                visible[#visible + 1] = entry.spellId
            end
        end
        assert.are.same({ 53209, 49050, 49052 }, visible)
        assertRecord(tracker.log, { kind = 'MISDIRECTION_SUMMARY', amount = 2100 })
    end)

    it('retains Arcane Shot identity for rendering its spell icon', function()
        start()
        tracker:handleEvent(event('SPELL_DAMAGE', 49045, 1000))
        finish()
        assertRecord(tracker.log, { kind = 'MISDIRECTION_DAMAGE', spellId = 49045, amount = 1000, hidden = false })
    end)

    it('ignores damage after the pull aura is removed', function()
        start()
        finish()
        tracker:handleEvent(event('SPELL_DAMAGE', 49050, 1000, 111))
        assert.spy(tracker.log).was_called(2)
        assertRecord(tracker.log, { kind = 'MISDIRECTION_SUMMARY', amount = 0 })
    end)

    it('does not finish the hunter pull when the transfer aura is applied', function()
        start()
        tracker:handleEvent(event('SPELL_AURA_APPLIED', 35079, nil, 101))
        tracker:handleEvent(event('SPELL_DAMAGE', 49050, 1000, 102))
        assert.spy(tracker.log).was_called(2)
        finish()
        assert.spy(tracker.log).was_called(3)
        assertRecord(tracker.log, { kind = 'MISDIRECTION_SUMMARY', amount = 1000 })
    end)

    it('stores untracked damage for totals without displaying the hit', function()
        start()
        tracker:handleEvent(event('SPELL_DAMAGE', 99999, 1000))
        finish()
        assertRecord(tracker.log, { kind = 'MISDIRECTION_DAMAGE', hidden = true, amount = 1000 })
        assertRecord(tracker.log, { kind = 'MISDIRECTION_SUMMARY', amount = 1000 })
    end)

    it('hides untracked rogue hits while preserving total damage', function()
        start('rogue', 57934)
        tracker:handleEvent(event('SPELL_DAMAGE', 99999, 1000, 101, 'rogue'))
        tracker:handleEvent(event('SPELL_DAMAGE', 51723, 500, 102, 'rogue'))
        finish('rogue', 59628)
        assertRecord(tracker.log, { kind = 'MISDIRECTION_DAMAGE', spellId = 99999, hidden = true })
        assertRecord(tracker.log, { kind = 'MISDIRECTION_DAMAGE', spellId = 51723, hidden = false })
        assertRecord(tracker.log, { kind = 'MISDIRECTION_SUMMARY', amount = 1500 })
    end)

    it('does not add pet damage to the owner pull', function()
        start()
        tracker:handleEvent(event('SPELL_DAMAGE', 49050, 100, 101))
        tracker:handleEvent(event('SPELL_DAMAGE', 49050, 900, 102, 'pet'))
        finish()
        assert.spy(tracker.log).was_called(3)
        assertRecord(tracker.log, { kind = 'MISDIRECTION_SUMMARY', amount = 100 })
    end)

    it('records each rogue hit separately even at the same timestamp', function()
        start('rogue', 57934)
        for _, spellId in ipairs({ 48668, 51723, 57841 }) do
            tracker:handleEvent(event('SPELL_DAMAGE', spellId, 100, 101, 'rogue'))
        end
        finish('rogue', 59628)
        assert.spy(tracker.log).was_called(5)
        for _, spellId in ipairs({ 48668, 51723, 57841 }) do
            assertRecord(tracker.log, { kind = 'MISDIRECTION_DAMAGE', spellId = spellId, sourceName = 'rogue' })
        end
    end)

    it('ignores aura removal without an active pull', function()
        finish()
        assert.spy(tracker.log).was_not_called()
    end)

    it('keeps a precombat cast and emits it on the first hit through the dispatcher', function()
        addon.inCombat = false
        addon.IterateModules = function() return ipairs({ tracker }) end
        mocks.UnitAffectingCombat1 = false
        addon:DispatchCombatEvent(event('SPELL_CAST_SUCCESS', 34477, nil, 100, 'hunter', 'tank'))
        assert.spy(tracker.log).was_not_called()
        addon:DispatchCombatEvent(event('SPELL_DAMAGE', 49050, 1000, 101))
        finish()
        assertRecord(tracker.log, { kind = 'MISDIRECTION_START', timestamp = 100 })
        assertRecord(tracker.log, { kind = 'MISDIRECTION_DAMAGE', amount = 1000 })
        assertRecord(tracker.log, { kind = 'MISDIRECTION_SUMMARY', amount = 1000 })
    end)
end)
