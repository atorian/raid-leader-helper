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
        original = { recount = Recount, skada = Skada, details = Details, metadata = GetAddOnMetadata, debug = addon.Debug, hook = hooksecurefunc, raid = GetNumRaidMembers,
            guid = UnitGUID, class = UnitClass, spec = addon.GetUnitSpec, db = addon.db,
            active = awards.active, instance = addon.currentInstanceId }
        completed, hooks = {}, 0
        specs = { raid1 = 72, raid2 = 71 }
        _G.Skada, _G.Details = nil, nil
        _G.GetAddOnMetadata = function(name, key)
            local meter = _G[name]
            return meter and ((key == "Version" or key == "X-Curse-Packaged-Version") and meter.version or nil)
        end
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
        _G.Recount = { version = "r1127",
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
        _G.Details, _G.GetAddOnMetadata, addon.Debug = original.details, original.metadata, original.debug
        _G.Recount, _G.Skada, _G.hooksecurefunc = original.recount, original.skada, original.hook
        _G.GetNumRaidMembers, _G.UnitGUID, _G.UnitClass = original.raid, original.guid, original.class
        addon.GetUnitSpec, addon.db, addon.currentInstanceId = original.spec, original.db, original.instance
        awards.active = original.active
    end)

    local function oozeEvents()
        local first, second = '0xF130009341000001', '0xF130009341000002'
        meters:handleEvent({ event = 'SPELL_AURA_APPLIED', sourceGUID = first })
        meters:handleEvent({ event = 'SWING_DAMAGE', sourceGUID = '0x0000000000000001',
            sourceName = 'Fury', destGUID = first, amount = 60000, overkill = -1 })
        meters:handleEvent({ event = 'SPELL_PERIODIC_DAMAGE', sourceGUID = '0x0000000000000001',
            sourceName = 'Fury', destGUID = first, amount = 45000, overkill = 5000 })
        meters:handleEvent({ event = 'SPELL_SUMMON', sourceGUID = '0x0000000000000001',
            sourceName = 'Fury', destGUID = '0xF140000123000001' })
        meters:handleEvent({ event = 'SPELL_DAMAGE', sourceGUID = '0xF140000123000001',
            sourceName = 'Pet', destGUID = second, amount = 100000 })
        meters:handleEvent({ event = 'UNIT_DIED', destGUID = '0xF130009341000003' })
        meters:handleEvent({ event = 'SPELL_DAMAGE', sourceGUID = '0x0000000000000001',
            sourceName = 'Fury', destGUID = '0xF1300092BA000004', amount = 100000 })
        meters:handleEvent({ event = 'UNIT_DIED', destGUID = '0xF1300092BA000005' })
        return { [first] = { Fury = 100000 }, [second] = { Fury = 100000 }, ['0xF130009341000003'] = {},
            ['0xF1300092BA000004'] = { Fury = 100000 }, ['0xF1300092BA000005'] = {} }
    end

    it('keeps individual ooze GUIDs and pet ownership in a completed Recount fight', function()
        local expected = oozeEvents()
        meters:BossKilled(36678)
        Recount:LeaveCombat(1180)
        assert.same(expected, completed[1].oozeDamage)
        assert.equals(3, #completed[1].players)
    end)

    it('keeps individual ooze GUIDs in a completed Skada fight without a death callback', function()
        local set = { gotboss = 36678, success = true, starttime = 1000, endtime = 1180, players = {} }
        _G.Skada = { version = "1.8.78", actorPrototype = { GetDPS = function() end }, current = set, RegisterCallback = function() end, UnregisterCallback = function() end }
        meters:Start('Skada', function(fight) completed[#completed + 1] = fight end)
        local expected = oozeEvents()
        meters:SkadaSetComplete('Skada_SetComplete', set)
        assert.same(expected, completed[1].oozeDamage)
        -- A fresh fight never reuses damage from a wipe or the previous victory.
        set = { gotboss = 36678, success = true, starttime = 1200, endtime = 1380, players = {} }
        Skada.current = set
        meters:handleEvent({ event = 'SPELL_AURA_APPLIED', destGUID = '0xF130009341000004' })
        meters:SkadaSetComplete('Skada_SetComplete', set)
        assert.same({ ['0xF130009341000004'] = {} }, completed[2].oozeDamage)
    end)

    it('does not carry ooze damage from a Recount wipe into the next attempt', function()
        oozeEvents()
        Recount:LeaveCombat(1180)
        assert.equals(0, #completed)
        Recount.InCombat, Recount.InCombatT = true, 1200
        meters:handleEvent({ event = 'SPELL_AURA_APPLIED', destGUID = '0xF130009341000004' })
        meters:BossKilled(36678)
        Recount:LeaveCombat(1380)
        assert.same({ ['0xF130009341000004'] = {} }, completed[1].oozeDamage)
    end)

    local function gasEvent(kind, spell, name)
        return { event = kind, spellId = spell, sourceGUID = '0xF1300092BA000004',
            destGUID = '0x0000000000000001', destName = name or 'Fury' }
    end

    it('counts gas targeting applications across difficulties but ignores ticks, stacks and other gas', function()
        for _, spell in ipairs({ 70672, 72455, 72832, 72833 }) do
            meters:handleEvent(gasEvent('SPELL_AURA_APPLIED', spell))
            for _, kind in ipairs({ 'SPELL_AURA_REFRESH', 'SPELL_AURA_APPLIED_DOSE',
                'SPELL_AURA_REMOVED_DOSE', 'SPELL_PERIODIC_DAMAGE', 'SPELL_AURA_REMOVED' }) do
                meters:handleEvent(gasEvent(kind, spell))
            end
        end
        meters:handleEvent(gasEvent('SPELL_AURA_APPLIED', 72833, 'Arms'))
        meters:handleEvent(gasEvent('SPELL_AURA_APPLIED', 72553)) -- Festergut.
        meters:handleEvent(gasEvent('SPELL_AURA_APPLIED', 71278)) -- Choking Gas.
        meters:handleEvent(gasEvent('SPELL_AURA_APPLIED', 72860)) -- Cloud self-buff.
        meters:BossKilled(36678)
        Recount:LeaveCombat(1180)
        assert.same({ Fury = 4, Arms = 1 }, completed[1].gasTargets)
    end)

    it('saves Skada gas targets at the kill and clears them for the next segment and on stop', function()
        local set = { gotboss = 36678, success = true, starttime = 1000, endtime = 1180, players = {} }
        _G.Skada = { version = "1.8.78", actorPrototype = { GetDPS = function() end }, current = set, RegisterCallback = function() end, UnregisterCallback = function() end }
        meters:Start('Skada', function(fight) completed[#completed + 1] = fight end)
        meters:handleEvent(gasEvent('SPELL_AURA_APPLIED', 72833))
        meters:BossKilled(36678)
        Skada.current = {}
        meters:handleEvent(gasEvent('SPELL_AURA_APPLIED', 72833, 'Arms'))
        Skada.last = set
        meters:SkadaSetComplete('Skada_SetComplete', set)
        assert.same({ Fury = 1 }, completed[1].gasTargets)
        assert.same({ Arms = 1 }, meters.gasTargets)
        meters:Stop()
        assert.is_nil(meters.gasTargets)
    end)

    it('saves Skada gas targets without a kill callback and discards Recount wipe and reset targets', function()
        meters:handleEvent(gasEvent('SPELL_AURA_APPLIED', 72833))
        Recount:LeaveCombat(1180)
        Recount.InCombat, Recount.InCombatT = true, 1200
        meters:handleEvent({ event = 'UNIT_DIED', destGUID = '0xF130009341000001' })
        meters:BossKilled(36678)
        Recount:LeaveCombat(1380)
        assert.same({}, completed[1].gasTargets)
        Recount.InCombat = true
        meters:handleEvent(gasEvent('SPELL_AURA_APPLIED', 72833))
        Recount:ResetData()
        assert.is_nil(meters.gasTargets)
        local set = { gotboss = 36678, success = true, starttime = 1400, endtime = 1580, players = {} }
        _G.Skada = { version = "1.8.78", actorPrototype = { GetDPS = function() end }, current = set, RegisterCallback = function() end, UnregisterCallback = function() end }
        meters:Start('Skada', function(fight) completed[#completed + 1] = fight end)
        meters:handleEvent(gasEvent('SPELL_AURA_APPLIED', 72833))
        meters:SkadaSetComplete('Skada_SetComplete', set)
        assert.same({ Fury = 1 }, completed[2].gasTargets)
    end)

    it('retains ownership of a pet summoned before Skada starts the fight', function()
        _G.Skada = { version = "1.8.78", actorPrototype = { GetDPS = function() end }, current = {}, RegisterCallback = function() end, UnregisterCallback = function() end }
        meters:Start('Skada', function(fight) completed[#completed + 1] = fight end)
        meters:handleEvent({ event = 'SPELL_SUMMON', sourceGUID = '0x0000000000000001',
            sourceName = 'Fury', destGUID = '0xF140000123000001' })
        Skada.current = { gotboss = 36678, success = true, starttime = 1000, endtime = 1180, players = {} }
        meters:handleEvent({ event = 'SPELL_DAMAGE', sourceGUID = '0xF140000123000001', sourceName = 'Pet',
            destGUID = '0xF130009341000001', amount = 100000 })
        meters:SkadaSetComplete('Skada_SetComplete', Skada.current)
        assert.same({ ['0xF130009341000001'] = { Fury = 100000 } }, completed[1].oozeDamage)
    end)

    it('credits an already summoned raid pet to its owner and stops collecting when disabled', function()
        local originalName = UnitName
        _G.UnitName = function(unit) return unit == 'raid1' and 'Fury' or 'Arms' end
        meters:handleEvent({ event = 'RANGE_DAMAGE', sourceGUID = 'guid-raidpet1', sourceName = 'Pet',
            destGUID = '0xF130009341000001', amount = 100000 })
        _G.UnitName = originalName
        assert.same({ ['0xF130009341000001'] = { Fury = 100000 } }, meters.oozeDamage)
        meters:Stop()
        meters:handleEvent({ event = 'SPELL_DAMAGE', sourceGUID = '0x0000000000000001', sourceName = 'Fury',
            destGUID = '0xF130009341000001', amount = 100000 })
        assert.is_nil(meters.oozeDamage)
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

    it('falls back to Recount when the selected Skada is absent', function()
        meters:Start('Skada', function(fight) completed[#completed + 1] = fight end)
        meters:BossKilled(37813)
        Recount:LeaveCombat(1180)
        assert.is_false(meters:IsAvailable('Skada'))
        assert.equals('Recount', meters.source)
        assert.equals(1, #completed)
    end)

    it('unregisters Skada when switching and ignores its late completion', function()
        local unregistered = 0
        _G.Skada = { version = "1.8.78", actorPrototype = { GetDPS = function() end },
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
        _G.Skada = { version = "1.8.78", actorPrototype = { GetDPS = function() end }, current = set, RegisterCallback = function() end, UnregisterCallback = function() end }
        meters:Start('Skada', function(fight) completed[#completed + 1] = fight end)
        meters:BossKilled(40142)
        meters:SkadaSetComplete('Skada_SetComplete', set)
        assert.equals(1, #completed)
        assert.equals(39863, completed[1].boss)
    end)

    it('uses the confirmed encounter when Skada identifies a vehicle instead of its commander', function()
        local set = { gotboss = true, success = true, starttime = 1000, endtime = 1180, players = {} }
        _G.Skada = { version = "1.8.78", actorPrototype = { GetDPS = function() end }, current = set, RegisterCallback = function() end, UnregisterCallback = function() end }
        meters:Start('Skada', function(fight) completed[#completed + 1] = fight end)
        meters:BossKilled(36939)
        meters:SkadaSetComplete('Skada_SetComplete', set)
        assert.equals(36939, completed[1].boss)
    end)

    local function skada(version)
        return { version = version or "1.8.78", actorPrototype = { GetDPS = function() end },
            RegisterCallback = function() end, UnregisterCallback = function() end }
    end

    local function details()
        local events, removals = {}, {}
        local combat = {
            GetActorList = function() return {
                { nome = "Fury", classe = "WARRIOR", serial = "guid-raid1", grupo = true, total = 3600000 },
                { nome = "Pet", grupo = true, owner = {}, total = 1000000 },
                { nome = "Stranger", total = 9000000 }
            } end,
            GetCombatTime = function() return 180 end,
            GetStartTime = function() return 1000 end,
            GetEndTime = function() return 1180 end
        }
        local meter = { APIVersion = 140, current = combat,
            GetCurrentCombat = function(self) return self.current end,
            RegisterEvent = function() end, UnregisterEvent = function() end,
            CreateEventListener = function() return {
                RegisterEvent = function(_, event, callback) events[event] = callback end,
                UnregisterEvent = function(_, event) events[event] = nil; removals[#removals + 1] = event end
            } end }
        return meter, combat, events, removals
    end

    it('checks the Skada GetDPS revision boundary and missing APIs', function()
        for _, version in ipairs({ "1.8.73.360", "1.8.73", "1.8.9", "1.7.99", "unknown" }) do
            _G.Skada = skada(version)
            assert.is_false(meters:IsAvailable("Skada"))
        end
        for _, version in ipairs({ "1.8.73.361", "1.8.74", "1.8.78", "1.8.87" }) do
            _G.Skada = skada(version)
            assert.is_true(meters:IsAvailable("Skada"))
        end
        Skada.actorPrototype = nil
        local available, reason = meters:IsAvailable("Skada")
        assert.is_false(available)
        assert.equals("нет нужного API", reason)
        _G.Skada = skada("1.8.73")
        local previous = GetAddOnMetadata
        _G.GetAddOnMetadata = function(name, key)
            return key == "X-Revision" and "361" or previous(name, key)
        end
        assert.is_true(meters:IsAvailable("Skada"))
    end)

    it('checks Recount packaged revisions and its collection API', function()
        for _, version in ipairs({ "r1126", "r900", "unknown" }) do
            Recount.version = version
            assert.is_false(meters:IsAvailable("Recount"))
        end
        for _, version in ipairs({ "r1127", "r1200", "v3.3g" }) do
            Recount.version = version
            assert.is_true(meters:IsAvailable("Recount"))
        end
        Recount.MergedPetDamageDPS = nil
        assert.is_false(meters:IsAvailable("Recount"))
    end)

    it('supports the historical Recount v4.0.1 port only for interface 30300', function()
        Recount.version = "v4.0.1 release"
        assert.is_false(meters:IsAvailable("Recount"))
        local previous = GetAddOnMetadata
        _G.GetAddOnMetadata = function(name, key)
            return key == "Interface" and "30300" or previous(name, key)
        end
        assert.is_true(meters:IsAvailable("Recount"))
    end)

    it('preserves a supported choice and falls back in Details Skada Recount order', function()
        _G.Details = details()
        _G.Skada = skada()
        assert.equals("Recount", meters:ResolveSource("Recount"))
        assert.equals("Skada", meters:ResolveSource("Skada"))
        assert.equals("Details", meters:ResolveSource(nil))
        Details.APIVersion = 139
        assert.equals("Skada", meters:ResolveSource("Details"))
        Skada.actorPrototype.GetDPS = nil
        assert.equals("Recount", meters:ResolveSource("Details"))
        Recount.LeaveCombat = nil
        assert.equals("ErrorDPSCounter", meters:ResolveSource("Details"))
        _G.Details, _G.Skada, _G.Recount = nil, nil, nil
        assert.equals("ErrorDPSCounter", meters:ResolveSource(nil))
    end)

    it('logs every ErrorDPSCounter action without publishing results or installing hooks', function()
        _G.Recount = nil
        local messages = {}
        addon.Debug = function(_, message) messages[#messages + 1] = message end
        local before = hooks
        meters:Start("Skada", function(fight) completed[#completed + 1] = fight end)
        meters:handleEvent({ event = "SPELL_DAMAGE" })
        meters:BossKilled(37813)
        meters:SkadaSetComplete("Skada_SetComplete", {})
        meters:RecountFightComplete({}, 1180)
        meters:DetailsFightComplete({})
        meters:Stop()
        assert.equals(before, hooks)
        assert.equals(0, #completed)
        assert.equals(7, #messages)
        for _, message in ipairs(messages) do assert.is_not_nil(message:find("неправильная версия", 1, true)) end
    end)

    it('collects a Details victory with pets merged and unregisters on source change', function()
        local combat, events, removals
        _G.Details, combat, events, removals = details()
        meters:Start("Details", function(fight) completed[#completed + 1] = fight end)
        local expected = oozeEvents()
        meters:BossKilled(36678)
        specs.raid1 = 71
        events.COMBAT_PLAYER_LEAVE("COMBAT_PLAYER_LEAVE", combat)
        assert.equals(1, #completed)
        local fight = completed[1]
        assert.equals("Details", fight.source)
        assert.same(expected, fight.oozeDamage)
        assert.same({ { name = "Fury", class = "WARRIOR", spec = 72, dps = 20000 } }, fight.players)
        assert.equals(180, fight.endtime - fight.starttime)
        events.COMBAT_PLAYER_LEAVE("COMBAT_PLAYER_LEAVE", combat)
        assert.equals(1, #completed)
        meters:Start("Recount", function() end)
        assert.equals(3, #removals)
        assert.same({}, events)
    end)

    it('ignores Details wipes, replaced segments and resets', function()
        local combat, events
        _G.Details, combat, events = details()
        meters:Start("Details", function(fight) completed[#completed + 1] = fight end)
        events.COMBAT_PLAYER_LEAVE("COMBAT_PLAYER_LEAVE", combat)
        meters:BossKilled(37813)
        events.COMBAT_PLAYER_LEAVE("COMBAT_PLAYER_LEAVE", {})
        assert.equals(0, #completed)
        for _, event in ipairs({ "DETAILS_DATA_RESET", "COMBAT_PLAYER_ENTER" }) do
            meters:BossKilled(37813)
            events[event](event)
            events.COMBAT_PLAYER_LEAVE("COMBAT_PLAYER_LEAVE", combat)
        end
        assert.equals(0, #completed)
    end)

end)
