require('tests.mocks')
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
        assert.spy(log).was_called_with(
            'SOME DATE |cFFFFFFFFJatagun|r |TInterface\\Icons\\spell_shadow_gathershadows:24:24:0:0|t взорвал ловушку')
    end)

    it('ignores later Shadow Trap damage at the same timestamp', function()
        dispatch(LichKingTracker, Builder:New(100):FromEnemy('Темная ловушка'):ToPlayer('Jatagun')
            :SpellDamage(73529, 'Теневая ловушка', 13594):Build())
        dispatch(LichKingTracker, Builder:New(100):FromEnemy('Темная ловушка'):ToPlayer('Ragnboe')
            :SpellDamage(73529, 'Теневая ловушка', 17211):Build())

        assert.spy(log).was_called(1)
        assert.spy(log).was_called_with(
            'SOME DATE |cFFFFFFFFJatagun|r |TInterface\\Icons\\spell_shadow_gathershadows:24:24:0:0|t взорвал ловушку')
    end)

    it('logs another Shadow Trap explosion at a different timestamp', function()
        dispatch(LichKingTracker, Builder:New(100):FromEnemy('Темная ловушка'):ToPlayer('Jatagun')
            :SpellDamage(73529, 'Теневая ловушка', 13594):Build())
        dispatch(LichKingTracker, Builder:New(101):FromEnemy('Темная ловушка'):ToPlayer('Ragnboe')
            :SpellDamage(73529, 'Теневая ловушка', 17211):Build())

        assert.spy(log).was_called(2)
        assert.spy(log).was_called_with(
            'SOME DATE |cFFFFFFFFJatagun|r |TInterface\\Icons\\spell_shadow_gathershadows:24:24:0:0|t взорвал ловушку')
        assert.spy(log).was_called_with(
            'SOME DATE |cFFFFFFFFRagnboe|r |TInterface\\Icons\\spell_shadow_gathershadows:24:24:0:0|t взорвал ловушку')
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
        assert.spy(log).was_called_with('SOME DATE Гневный дух: Руперт')
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
        assert.spy(log).was_called_with(
            'SOME DATE |cFFFFFFFFRagnboe|r |TInterface\\Icons\\spell_shadow_gathershadows:24:24:0:0|t взорвал ловушку')
    end)

    it('logs representative Shadow Trap message in demo', function()
        LichKingTracker:demo()

        assert.spy(log).was_called_with(
            'SOME DATE |cFFFFFFFFDemoPlayer|r |TInterface\\Icons\\spell_shadow_gathershadows:24:24:0:0|t взорвал ловушку')
    end)
end)
