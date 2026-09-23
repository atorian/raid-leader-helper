local assertRecord = require('tests.journal_assertions')
require('tests.mocks')
require('../Core')
require('../lib/blizzardEvent')

local spy = require('luassert.spy')
local Builder = require('../utils/CombatEventBuilder')
local LichKingTracker = require('../modules/bosses/LichKingTracker')

local function dispatch(module, ...)
    module:handleEvent(blizzardEvent(select(2, ...)))
end

describe('LichKingTracker', function()
    local log

    before_each(function()
        log = spy.new(function()
        end)
        LichKingTracker.log = log
        LichKingTracker:reset()
    end)

    it('receives combat events only in Icecrown Citadel', function()
        assert.is_true(LichKingTracker.receivesCombatEvents)
        assert.are.equal(631, LichKingTracker.zoneGateInstanceId)
    end)

    it('logs the first player damaged by Shadow Trap with icon', function()
        dispatch(LichKingTracker, Builder:New(100):FromEnemy('Темная ловушка'):ToPlayer('Jatagun')
            :SpellDamage(73529, 'Теневая ловушка', 13594):Build())

        assert.spy(log).was_called(1)
        assertRecord(log, { targetName = "Jatagun", spellId = 73529, kind = "SHADOW_TRAP", type = "TACTIC_VIOLATION" })
    end)

    it('ignores later Shadow Trap damage at the same timestamp', function()
        dispatch(LichKingTracker, Builder:New(100):FromEnemy('Темная ловушка'):ToPlayer('Jatagun')
            :SpellDamage(73529, 'Теневая ловушка', 13594):Build())
        dispatch(LichKingTracker, Builder:New(100):FromEnemy('Темная ловушка'):ToPlayer('Ragnboe')
            :SpellDamage(73529, 'Теневая ловушка', 17211):Build())

        assert.spy(log).was_called(1)
        assertRecord(log, { targetName = "Jatagun", spellId = 73529, kind = "SHADOW_TRAP", type = "TACTIC_VIOLATION" })
    end)

    it('logs another Shadow Trap explosion at a different timestamp', function()
        dispatch(LichKingTracker, Builder:New(100):FromEnemy('Темная ловушка'):ToPlayer('Jatagun')
            :SpellDamage(73529, 'Теневая ловушка', 13594):Build())
        dispatch(LichKingTracker, Builder:New(101):FromEnemy('Темная ловушка'):ToPlayer('Ragnboe')
            :SpellDamage(73529, 'Теневая ловушка', 17211):Build())

        assert.spy(log).was_called(2)
        assertRecord(log, { targetName = "Jatagun", spellId = 73529, kind = "SHADOW_TRAP", type = "TACTIC_VIOLATION" })
        assertRecord(log, { targetName = "Ragnboe", spellId = 73529, kind = "SHADOW_TRAP", type = "TACTIC_VIOLATION" })
    end)

    it('ignores Shadow Trap damage to non-players', function()
        dispatch(LichKingTracker, Builder:New(100):FromEnemy('Темная ловушка'):ToEnemy('Вурдалак')
            :SpellDamage(73529, 'Теневая ловушка', 13594):Build())

        assert.spy(log).was_not_called()
    end)

    it('ignores non-damage Shadow Trap events', function()
        dispatch(LichKingTracker, Builder:New(100):FromEnemy('Темная ловушка'):ToPlayer('Jatagun')
            :ApplyAura(73529, 'Теневая ловушка', 'DEBUFF'):Build())

        assert.spy(log).was_not_called()
    end)

    it('logs Raging Spirit target from Lich King cast success', function()
        dispatch(LichKingTracker, Builder:New(100):FromEnemy('Король-лич'):ToPlayer('Руперт')
            :CastSuccess(69200, 'Гневный дух'):Build())

        assert.spy(log).was_called(1)
        assertRecord(log, { targetName = "Руперт", spellId = 69200, kind = "RAGING_SPIRIT", type = "INFO" })
    end)

    it('ignores Raging Spirit named casts with another spell id', function()
        dispatch(LichKingTracker, Builder:New(100):FromEnemy('Король-лич'):ToPlayer('Руперт')
            :CastSuccess(69201, 'Гневный дух'):Build())

        assert.spy(log).was_not_called()
    end)

    it('resets same-timestamp suppression on reset', function()
        dispatch(LichKingTracker, Builder:New(100):FromEnemy('Темная ловушка'):ToPlayer('Jatagun')
            :SpellDamage(73529, 'Теневая ловушка', 13594):Build())

        LichKingTracker:reset()

        dispatch(LichKingTracker, Builder:New(100):FromEnemy('Темная ловушка'):ToPlayer('Ragnboe')
            :SpellDamage(73529, 'Теневая ловушка', 17211):Build())

        assert.spy(log).was_called(2)
        assertRecord(log, { targetName = "Ragnboe", spellId = 73529, kind = "SHADOW_TRAP", type = "TACTIC_VIOLATION" })
    end)

end)
