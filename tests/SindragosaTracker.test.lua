require('tests.mocks')
local RLHelper = require('../Core')
require('../lib/blizzardEvent')
local tracker = require('../modules/bosses/SindragosaTracker')
local AIR_YELL = 'Здесь ваше вторжение и окончится! Никто не уцелеет.'

describe('SindragosaTracker', function()
    local saved, records, difficulty, now
    local function event(kind, spell, source, target, amount, timestamp)
        local e = blizzardEvent(timestamp or now, kind,
            source or 'mage', source or 'Чародей', 0x514,
            target or 'mage', target or 'Чародей', 0x514,
            spell, 'Заклинание', 64, kind == 'SPELL_DAMAGE' and (amount or 1000) or 'DEBUFF', amount)
        tracker:handleEvent(e)
    end
    local function stacks(count, player)
        event('SPELL_AURA_APPLIED', 69766, player, player)
        if count > 1 then event('SPELL_AURA_APPLIED_DOSE', 69766, player, player, count) end
    end
    before_each(function()
        saved = { GetInstanceInfo = _G.GetInstanceInfo, GetTime = _G.GetTime,
            Skada = _G.Skada, Details = _G.Details, _detalhes = _G._detalhes, Recount = _G.Recount,
            inCombat = RLHelper.inCombat, instance = RLHelper.currentInstanceId,
            groupMembers = RLHelper.groupMembers }
        difficulty, now, records = 4, 100, {}
        _G.GetInstanceInfo = function() return 'Icecrown Citadel', 'raid', difficulty end
        _G.GetTime = function() return now end
        _G.Skada, _G.Details, _G._detalhes, _G.Recount = nil, nil, nil, nil
        RLHelper.inCombat, RLHelper.currentInstanceId = true, 631
        RLHelper.groupMembers = {}
        tracker:reset()
        tracker.log = function(entry) records[#records + 1] = entry end
    end)
    after_each(function()
        _G.GetInstanceInfo, _G.GetTime = saved.GetInstanceInfo, saved.GetTime
        _G.Skada, _G.Details, _G._detalhes, _G.Recount = saved.Skada, saved.Details, saved._detalhes, saved.Recount
        RLHelper.inCombat, RLHelper.currentInstanceId = saved.inCombat, saved.instance
        RLHelper.groupMembers = saved.groupMembers
        tracker:reset()
    end)

    it('logs one explosion per source after aura removal, with the last stack count', function()
        stacks(5)
        event('SPELL_AURA_REMOVED', 69766)
        event('SPELL_DAMAGE', 71046, 'mage', 'priest')
        event('SPELL_DAMAGE', 71046, 'mage', 'hunter')
        assert.equal(1, #records)
        assert.equal(5, records[1].stacks)
        assert.equal('mage', records[1].source.guid)
        assert.equal('TACTIC_VIOLATION', records[1].type)
        assert.matches('Взрыв Освобожденной магии: 5 стаков', RLHelperJournal.Format(records[1]), 1, true)
        assert.is_true(RLHelperJournal.Visible(records[1], 'ERRORS'))
    end)
    it('supports 10 heroic and a one-stack explosion before aura removal', function()
        difficulty = 3
        stacks(1)
        event('SPELL_DAMAGE', 71045)
        event('SPELL_AURA_REMOVED', 69766)
        assert.equal(1, records[1].stacks)
    end)
    it('classifies only explosions above two stacks as errors in both heroic modes', function()
        for _, mode in ipairs({ { 3, 71045 }, { 4, 71046 } }) do
            difficulty = mode[1]
            for count = 1, 3 do
                stacks(count)
                event('SPELL_DAMAGE', mode[2])
                local entry = records[#records]
                assert.equal(count > 2 and 'TACTIC_VIOLATION' or 'INFO', entry.type)
                assert.equal(count > 2, RLHelperJournal.Visible(entry, 'ERRORS'))
                local savedEntry = RLHelperJournal.Copy(entry)
                assert.equal(count > 2, RLHelperJournal.Visible(savedEntry, 'ERRORS'))
            end
        end
    end)
    it('ignores normal raids and non-raid difficulty 3', function()
        for _, normal in ipairs({ 1, 2 }) do
            difficulty = normal
            stacks(5)
            event('SPELL_DAMAGE', 71046)
        end
        _G.GetInstanceInfo = function() return 'Dungeon', 'party', 3 end
        stacks(5)
        event('SPELL_DAMAGE', 71045)
        assert.equal(0, #records)
    end)
    it('handles dynamic heroic mode but not numeric zero as enabled', function()
        _G.GetInstanceInfo = function() return 'ICC', 'raid', 2, nil, 25, 1, 0 end
        assert.is_false(tracker:IsHeroic())
        _G.GetInstanceInfo = function() return 'ICC', 'raid', 2, nil, 25, 1, 1 end
        assert.is_true(tracker:IsHeroic())
    end)
    it('does not log bubble removal, and starts the next stack series at one', function()
        stacks(7)
        event('SPELL_AURA_REMOVED', 69766)
        event('SPELL_AURA_REMOVED', 69762)
        assert.equal(0, #records)
        now = now + 20
        stacks(1)
        event('SPELL_DAMAGE', 71046)
        assert.equal(1, #records)
        assert.equal(1, records[1].stacks)
    end)
    it('does not reuse stale removed stacks', function()
        stacks(7)
        event('SPELL_AURA_REMOVED', 69766)
        now = now + 20
        event('SPELL_DAMAGE', 71046)
        assert.equal(0, #records)
    end)
    it('counts a confirmed explosion even when its first target absorbs it', function()
        stacks(3)
        tracker:handleEvent(blizzardEvent(now, 'SPELL_MISSED', 'mage', 'Чародей', 0x514,
            'priest', 'Целитель', 0x514, 71046, 'Ответный удар', 64, 'ABSORB', 3000))
        event('SPELL_DAMAGE', 71046)
        assert.equal(1, #records)
        assert.equal(3, records[1].stacks)
    end)
    it('keeps simultaneous players and repeated explosions independent', function()
        stacks(2, 'mage')
        stacks(6, 'priest')
        event('SPELL_AURA_REMOVED', 69762, 'boss', 'mage')
        event('SPELL_DAMAGE', 71046, 'priest', 'mage')
        event('SPELL_DAMAGE', 71046, 'mage', 'priest')
        stacks(3, 'mage')
        event('SPELL_DAMAGE', 71046, 'mage', 'priest')
        assert.same({ 6, 2, 3 }, { records[1].stacks, records[2].stacks, records[3].stacks })
    end)
    it('clears stacks on death, combat end and disable', function()
        for _, reset in ipairs({ function() event('UNIT_DIED') end,
            function() tracker:reset() end, function() tracker:OnDisable() end }) do
            stacks(5)
            reset()
            event('SPELL_DAMAGE', 71046)
        end
        assert.equal(0, #records)
    end)
    it('dispatches through Core only in Icecrown Citadel', function()
        assert.is_true(RLHelper:ShouldDispatchCombatEventToModule(tracker))
        stacks(2)
        RLHelper:DispatchCombatEvent({ event = 'SPELL_DAMAGE', spellId = 71046, timestamp = now,
            sourceGUID = 'mage', sourceName = 'Чародей', sourceFlags = 0x514 })
        assert.equal(1, #records)
        RLHelper.currentInstanceId = 724
        assert.is_false(RLHelper:ShouldDispatchCombatEventToModule(tracker))
    end)
    it('ignores outsiders but tracks members whose combat flags changed', function()
        tracker:handleEvent({ event = 'SPELL_AURA_APPLIED', spellId = 69766,
            destGUID = 'outsider', destFlags = 0x548 })
        event('SPELL_DAMAGE', 71046, 'outsider')
        assert.equal(0, #records)
        RLHelper.groupMembers.mage = true
        tracker:handleEvent({ event = 'SPELL_AURA_APPLIED_DOSE', spellId = 69766,
            destGUID = 'mage', destFlags = 0x548, amount = 4 })
        event('SPELL_DAMAGE', 71046)
        assert.equal(4, records[1].stacks)
    end)
    it('starts one Skada segment per air phase and preserves boss history', function()
        local old = {}
        local calls = 0
        _G.Skada = { current = old, NewSegment = function(self)
            calls = calls + 1
            self.current = {}
        end }
        tracker:CHAT_MSG_MONSTER_YELL('CHAT_MSG_MONSTER_YELL', AIR_YELL)
        assert.equal('Синдрагоса', old.mobname)
        assert.is_true(old.gotboss)
        assert.equal('Синдрагоса — глыбы 1', _G.Skada.current.mobname)
        assert.is_true(_G.Skada.current.gotboss)
        tracker:CHAT_MSG_MONSTER_YELL('CHAT_MSG_MONSTER_YELL', AIR_YELL)
        assert.equal(1, calls)
        now = now + 110
        tracker:CHAT_MSG_MONSTER_YELL('CHAT_MSG_MONSTER_YELL', AIR_YELL)
        assert.equal(2, calls)
        assert.equal('Синдрагоса — глыбы 2', _G.Skada.current.mobname)
    end)
    it('resets Recount current fight once on each takeoff without requiring other meters', function()
        local resets = 0
        _G.Recount = {
            ResetFightData = function(self)
                assert.equal(_G.Recount, self)
                resets = resets + 1
            end,
            ResetData = function() error('must not erase meter history') end,
        }
        tracker:CHAT_MSG_MONSTER_YELL('CHAT_MSG_MONSTER_YELL', AIR_YELL)
        tracker:CHAT_MSG_MONSTER_YELL('CHAT_MSG_MONSTER_YELL', AIR_YELL)
        assert.equal(1, resets)
        now = now + 110
        tracker:CHAT_MSG_MONSTER_YELL('CHAT_MSG_MONSTER_YELL', AIR_YELL)
        assert.equal(2, resets)
        tracker:reset()
        tracker:CHAT_MSG_MONSTER_YELL('CHAT_MSG_MONSTER_YELL', AIR_YELL)
        assert.equal(3, resets)
    end)
    it('switches Skada and Recount together through the same APIs as Halion', function()
        local calls = {}
        _G.Skada = { current = {}, NewSegment = function(self)
            assert.equal(_G.Skada, self)
            calls[#calls + 1] = 'Skada:NewSegment'
            self.current = {}
        end }
        _G.Recount = { ResetFightData = function(self)
            assert.equal(_G.Recount, self)
            calls[#calls + 1] = 'Recount:ResetFightData'
        end }
        tracker:CHAT_MSG_MONSTER_YELL('CHAT_MSG_MONSTER_YELL', AIR_YELL)
        assert.same({ 'Skada:NewSegment', 'Recount:ResetFightData' }, calls)
        assert.equal('Синдрагоса — глыбы 1', _G.Skada.current.mobname)
    end)
    it('splits Details while retaining the previous segment', function()
        local old = { enemy = 'Синдрагоса', is_boss = { id = 36853 } }
        local ended
        _G.Details = { in_combat = true, tabela_vigente = old,
            SairDoCombate = function(self) ended = self.tabela_vigente end,
            EntrarEmCombate = function(self) self.tabela_vigente = {} end }
        tracker:CHAT_MSG_MONSTER_YELL('CHAT_MSG_MONSTER_YELL', AIR_YELL)
        assert.equal(old, ended)
        assert.equal(36853, old.is_boss.id)
        assert.equal('Синдрагоса — глыбы 1', _G.Details.tabela_vigente.enemy)
        assert.equal('Синдрагоса — глыбы 1', _G.Details.tabela_vigente.is_boss.name)
    end)
    it('starts meters without a current segment and isolates a failing meter', function()
        local resets = 0
        _G.Skada = { StartCombat = function(self) self.current = {} end }
        _G.Details = { SairDoCombate = function() error('must not end absent combat') end,
            EntrarEmCombate = function(self) self.tabela_vigente = {} end }
        _G.Recount = { ResetFightData = function() resets = resets + 1 end }
        tracker:CHAT_MSG_MONSTER_YELL('CHAT_MSG_MONSTER_YELL', AIR_YELL)
        assert.equal('Синдрагоса — глыбы 1', _G.Skada.current.mobname)
        assert.equal('Синдрагоса — глыбы 1', _G.Details.tabela_vigente.enemy)
        _G.Skada.NewSegment = function() error('unsupported meter') end
        now = now + 110
        tracker:CHAT_MSG_MONSTER_YELL('CHAT_MSG_MONSTER_YELL', AIR_YELL)
        assert.equal(2, resets)
        assert.equal('Синдрагоса — глыбы 2', _G.Details.tabela_vigente.enemy)
    end)
    it('does not split for final-phase tombs, other yells, outside ICC or outside combat', function()
        local calls = 0
        _G.Recount = { ResetFightData = function() calls = calls + 1 end }
        event('SPELL_AURA_APPLIED', 70157)
        tracker:CHAT_MSG_MONSTER_YELL('CHAT_MSG_MONSTER_YELL', 'А теперь почувствуйте всю мощь господина и погрузитесь в отчаяние!')
        RLHelper.currentInstanceId = 724
        tracker:CHAT_MSG_MONSTER_YELL('CHAT_MSG_MONSTER_YELL', AIR_YELL)
        RLHelper.currentInstanceId, RLHelper.inCombat = 631, false
        tracker:CHAT_MSG_MONSTER_YELL('CHAT_MSG_MONSTER_YELL', AIR_YELL)
        assert.equal(0, calls)
    end)
    it('supports English and demonic air yells on normal difficulty', function()
        difficulty = 1
        tracker:CHAT_MSG_MONSTER_YELL('CHAT_MSG_MONSTER_YELL', 'Your incursion ends here! None shall survive!')
        now = now + 110
        tracker:CHAT_MSG_MONSTER_YELL('CHAT_MSG_MONSTER_YELL', 'Rikk zilthuras rikk zila Aman adare tiriosh ')
        assert.equal(2, tracker.airPhase)
    end)
    it('generates its demo through an isolated handler without touching meters or live stacks', function()
        stacks(7)
        local demo = { players = { mage = 'mage', priest = 'priest' } }
        function demo:IsGroupMember() return true end
        function demo:Event(module, kind, source, target, spell, fields)
            local e = { timestamp = 100, event = kind, sourceGUID = source, sourceName = source,
                destGUID = target, destName = target, spellId = spell }
            for k, v in pairs(fields or {}) do e[k] = v end
            module:handleEvent(e)
        end
        local instance = setmetatable({ context = demo, log = tracker.log }, { __index = tracker })
        _G.Recount = { ResetFightData = function() error('demo must not reset meters') end }
        instance:RunDemo(demo)
        assert.equal(4, records[1].stacks)
        assert.equal('TACTIC_VIOLATION', records[1].type)
        assert.is_true(RLHelperJournal.Visible(records[1], 'ERRORS'))
        assert.equal(7, tracker.stacks.mage.count)
    end)
end)
