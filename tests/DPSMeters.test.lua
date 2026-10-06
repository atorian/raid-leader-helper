require('tests.mocks')
require('Core')
require('data.BossIds')
local addon = LibStub('AceAddon-3.0'):GetAddon('RLHelper')
local meters = require('modules.DPSMeters')
local awards = require('modules.EPAwards')
addon.modules.EPAwards = nil

describe('DPS meter sources', function()
    local original, completed, hooks, specs
    before_each(function()
        meters:Stop()
        original = { recount = Recount, skada = Skada, hook = hooksecurefunc, raid = GetNumRaidMembers,
            guid = UnitGUID, class = UnitClass, spec = addon.GetUnitSpec, db = addon.db,
            active = awards.active, instance = addon.currentInstanceId }
        completed, hooks = {}, 0
        specs = { raid1 = 72, raid2 = 71 }
        _G.Skada = nil
        _G.GetNumRaidMembers = function() return 3 end
        _G.UnitGUID = function(unit) return 'guid-' .. unit end
        _G.UnitClass = function() return 'Воин', 'WARRIOR' end
        addon.GetUnitSpec = function(unit, class)
            assert.equals('WARRIOR', class)
            return specs[unit]
        end
        _G.hooksecurefunc = function(target, method, after)
            hooks = hooks + 1
            local before = target[method]
            target[method] = function(...)
                before(...)
                after(...)
            end
        end
        local function player(name, unit, kind, number)
            return { Name = name, GUID = 'guid-' .. unit, type = kind or 'Grouped', enClass = 'WARRIOR',
                LastFightIn = number or 7, Fights = { CurrentFightData = { Damage = 2000000, ActiveTime = 100 } } }
        end
        _G.Recount = {
            InCombat = true, InCombatT = 1000,
            db = { profile = { CurDataSet = 'OverallData' } },
            db2 = { FightNum = 7, combatants = {
                Fury = player('Fury', 'raid1', 'Self'), Arms = player('Arms', 'raid2'),
                Unknown = player('Unknown', 'raid3'), Pet = player('Pet', 'pet', 'Pet'),
                Stranger = player('Stranger', 'stranger', 'Ungrouped'), Old = player('Old', 'old', 'Grouped', 6)
            } },
            -- Recount 3.3.5a LeaveCombat first moves the data, then increments FightNum.
            LeaveCombat = function(self, finish)
                self.InCombat = false
                if finish - self.InCombatT <= 3 then return end
                for _, p in pairs(self.db2.combatants) do
                    p.Fights.LastFightData = p.Fights.CurrentFightData
                    p.Fights.CurrentFightData = { Damage = 0, ActiveTime = 0 }
                end
                self.db2.FightNum = self.db2.FightNum + 1
            end,
            ResetData = function(self) self.db2.FightNum = 0; self.db2.combatants = {} end,
            MergedPetDamageDPS = function(self, p, fight)
                assert.equals('LastFightData', fight)
                assert.is_false(self.InCombat)
                local data = p.Fights[fight]
                return data.Damage, data.Damage / data.ActiveTime
            end
        }
        addon.db = { profile = { gpAwardButtonsEnabled = true }, char = {} }
        addon.currentInstanceId = 631
        awards.active = false
        meters:Start('Recount', function(fight) completed[#completed + 1] = fight end)
    end)
    after_each(function()
        meters:Stop()
        _G.Recount, _G.Skada, _G.hooksecurefunc = original.recount, original.skada, original.hook
        _G.GetNumRaidMembers, _G.UnitGUID, _G.UnitClass = original.raid, original.guid, original.class
        addon.GetUnitSpec, addon.db, addon.currentInstanceId = original.spec, original.db, original.instance
        awards.active = original.active
    end)

    it('reads the completed Recount segment with no Skada, excludes pets, outsiders and stale players', function()
        meters:BossKilled(37813)
        assert.equals(0, #completed)
        Recount:LeaveCombat(1180)
        assert.equals(1, #completed)
        local fight = completed[1]
        assert.equals('Recount', fight.source)
        assert.equals(37813, fight.boss)
        assert.equals(1000, fight.starttime)
        assert.equals(1180, fight.endtime)
        assert.equals(3, #fight.players)
        local names = {}
        for _, p in ipairs(fight.players) do
            names[p.name] = p
            assert.equals(20000, p.dps)
        end
        assert.equals(72, names.Fury.spec)
        assert.equals(71, names.Arms.spec)
        assert.is_nil(names.Unknown.spec)
        assert.is_nil(names.Pet)
        assert.is_nil(names.Old)
        assert.equals('OverallData', Recount.db.profile.CurDataSet)
    end)

    it('uses the meter DPS including its pet calculation instead of recalculating from fight duration', function()
        Recount.MergedPetDamageDPS = function(_, _, key)
            assert.equals('LastFightData', key)
            return 3000000, 25000
        end
        meters:BossKilled(37813)
        Recount:LeaveCombat(1180)
        for _, p in ipairs(completed[1].players) do assert.equals(25000, p.dps) end
    end)

    it('freezes talent specializations at the kill', function()
        meters:BossKilled(37813)
        specs.raid1 = 71
        Recount:LeaveCombat(1180)
        for _, p in ipairs(completed[1].players) do
            if p.name == 'Fury' then assert.equals(72, p.spec) end
        end
    end)

    it('ignores wipes and a death outside an active Recount fight', function()
        Recount:LeaveCombat(1180)
        meters:BossKilled(37813)
        Recount:LeaveCombat(1190)
        assert.equals(0, #completed)
    end)

    it('rejects a reset or a different fight after the kill', function()
        for _, change in ipairs({
            function() Recount.db2.FightNum = 0 end,
            function() Recount.InCombatT = 1100 end,
            function() Recount.db2 = { FightNum = 7, combatants = Recount.db2.combatants } end
        }) do
            Recount.InCombat, Recount.InCombatT, Recount.db2.FightNum = true, 1000, 7
            meters:BossKilled(37813)
            change()
            Recount:LeaveCombat(1180)
        end
        assert.equals(0, #completed)
    end)

    it('invalidates a reset even when the first fight number remains zero', function()
        Recount.db2.FightNum = 0
        meters:BossKilled(37813)
        Recount:ResetData()
        Recount:LeaveCombat(1180)
        assert.equals(0, #completed)
    end)

    it('does not attach a discarded short fight kill to the next fight', function()
        meters:BossKilled(37813)
        Recount:LeaveCombat(1002)
        Recount.InCombat, Recount.InCombatT = true, 1004
        Recount:LeaveCombat(1180)
        assert.equals(0, #completed)
    end)

    it('clears pending collection on stop and does not duplicate hooks on restart', function()
        meters:BossKilled(37813)
        meters:Stop()
        Recount:LeaveCombat(1180)
        meters:Start('Recount', function(fight) completed[#completed + 1] = fight end)
        assert.equals(2, hooks)
        Recount.InCombat, Recount.InCombatT = true, 1200
        for _, p in pairs(Recount.db2.combatants) do
            p.LastFightIn = 8
            p.Fights.CurrentFightData = { Damage = 1000, ActiveTime = 1 }
        end
        meters:BossKilled(37813)
        Recount:LeaveCombat(1380)
        assert.equals(1, #completed)
    end)

    it('does not fall back to Recount when the selected Skada is absent', function()
        meters:Start('Skada', function(fight) completed[#completed + 1] = fight end)
        meters:BossKilled(37813)
        Recount:LeaveCombat(1180)
        assert.is_false(meters:IsAvailable('Skada'))
        assert.equals(0, #completed)
    end)

    it('unregisters Skada when switching and ignores its late completion', function()
        local unregistered = 0
        _G.Skada = {
            RegisterCallback = function() end,
            UnregisterCallback = function(target, event)
                assert.equals(meters, target)
                assert.equals('Skada_SetComplete', event)
                unregistered = unregistered + 1
            end
        }
        meters:Start('Skada', function() error('old consumer') end)
        meters:Start('Recount', function(fight) completed[#completed + 1] = fight end)
        local set = { gotboss = 37813, success = true, starttime = 1000, endtime = 1180,
            players = { { GetDPS = function() error('wrong source') end } } }
        Skada.current = set
        meters:SkadaSetComplete('Skada_SetComplete', set)
        assert.equals(1, unregistered)
        assert.equals(0, #completed)
    end)

    it('persists Recount results and unknown specs through meter reset and source changes', function()
        awards.active = true
        awards:SetDPSSource('Recount')
        awards:handleEvent({ event = 'UNIT_DIED', destGUID = '0xF1300093B5000001' })
        Recount:LeaveCombat(1180)
        local saved = awards:GetDPSResults()[37813]
        assert.equals('Recount', saved.source)
        assert.equals(2, #saved.players)
        assert.equals(1, saved.unknown)
        assert.equals(20000, saved.players[1].dps)
        awards:SetDPSSource('Skada')
        Recount.db2.combatants = {}
        assert.equals(saved, awards:GetDPSResults()[37813])
        assert.equals(2, #saved.players)
    end)

    it('preserves saved results when the feature is disabled during a Recount fight', function()
        awards.active = true
        awards:SetDPSSource('Recount')
        local saved = { players = {}, source = 'Skada' }
        awards:GetDPSResults()[37813] = saved
        awards:handleEvent({ event = 'UNIT_DIED', destGUID = '0xF1300093B5000001' })
        addon.db.profile.gpAwardButtonsEnabled = false
        awards:RefreshEnabledState()
        Recount:LeaveCombat(1180)
        assert.equals(saved, awards:GetDPSResults()[37813])
        assert.is_nil(meters.source)
    end)
    it('collects shared encounters and rescued bosses after a DBM victory and unregisters on stop', function()
        local previousDBM, callbacks, registered = DBM, {}, 0
        _G.DBM = {
            RegisterCallback = function(_, event, callback)
                assert.equals('DBM_Kill', event)
                assert.is_nil(callbacks[event])
                callbacks[event] = callback
                registered = registered + 1
            end,
            UnregisterCallback = function(_, event, callback)
                assert.equals(callbacks[event], callback)
                callbacks[event] = nil
            end
        }
        local ok, err = pcall(function()
            meters:Start('Recount', function(fight) completed[#completed + 1] = fight end)
            addon.currentInstanceId = 649
            awards:AddDPSBoss(34496)
            -- One twin's death is not evidence that the whole encounter ended.
            awards:handleEvent({ event = 'UNIT_DIED', destGUID = string.format('0xF130%06X000001', 34496) })
            Recount:LeaveCombat(1180)
            assert.equals(0, #completed)
            Recount.InCombat, Recount.InCombatT = true, 1200
            callbacks.DBM_Kill('DBM_Kill', { creatureId = 34497 })
            Recount:LeaveCombat(1380)
            assert.equals(1, #completed)
            assert.equals(34497, completed[1].boss)
            meters:Start('Recount', function(fight) completed[#completed + 1] = fight end)
            assert.equals(2, registered)
            addon.currentInstanceId = 631
            Recount.InCombat, Recount.InCombatT = true, 1400
            callbacks.DBM_Kill('DBM_Kill', { creatureId = 36789 })
            Recount:LeaveCombat(1580)
            assert.equals(36789, completed[2].boss)
            Recount.InCombat, Recount.InCombatT = true, 1600
            callbacks.DBM_Kill('DBM_Kill', { creatureId = 34497 }) -- Wrong instance.
            Recount:LeaveCombat(1780)
            assert.equals(2, #completed)
            meters:Stop()
            assert.is_nil(callbacks.DBM_Kill)
        end)
        meters:Stop()
        _G.DBM = previousDBM
        assert.is_true(ok, tostring(err))
    end)

    it('matches alternate NPCs to the same complete Skada encounter', function()
        local set = { gotboss = 39863, starttime = 1000, endtime = 1180, players = {} }
        _G.Skada = { current = set, RegisterCallback = function() end, UnregisterCallback = function() end }
        meters:Start('Skada', function(fight) completed[#completed + 1] = fight end)
        meters:BossKilled(40142)
        meters:SkadaSetComplete('Skada_SetComplete', set)
        assert.equals(1, #completed)
        assert.equals(39863, completed[1].boss)
    end)

    it('uses the confirmed encounter when Skada identifies a vehicle instead of its commander', function()
        local set = { gotboss = true, success = true, starttime = 1000, endtime = 1180, players = {} }
        _G.Skada = { current = set, RegisterCallback = function() end, UnregisterCallback = function() end }
        meters:Start('Skada', function(fight) completed[#completed + 1] = fight end)
        meters:BossKilled(36939)
        meters:SkadaSetComplete('Skada_SetComplete', set)
        assert.equals(36939, completed[1].boss)
    end)

end)
