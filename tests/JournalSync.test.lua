local mocks = require('tests.mocks')
local Journal = require('lib.Journal')
local Sync = require('lib.JournalSync')
local addon = require('../Core')
local Halion = require('../modules/bosses/HalionTracker')

local function record(kind, stamp, source, target, spellId, fields)
    return Journal.Create(kind, {
        timestamp = stamp or 1000, sourceGUID = source or 'boss', sourceName = source or 'Халион',
        destGUID = target or 'victim', destName = target or 'Игрок', spellId = spellId or 77846,
    }, 'INFO', fields)
end

describe('Ruby Sanctum journal exchange', function()
    local peers, packets, now, active, savedGlobals, raidSize
    local function activate(peer) active = peer end
    local function peer(name, clock)
        local result = setmetatable({ name = name, clock = clock or 0,
            currentInstanceId = 724, activeEnemies = {}, activePlayers = {}, enemyEvents = {},
            db = { profile = {}, char = {} }, SendMessage = function() end,
        }, { __index = addon })
        activate(result)
        result:InitializeJournal()
        result:StartCombat('test')
        return result
    end
    local function flush(from)
        activate(from)
        while #from.journalSync.queue > 0 do now = now + 0.4; from.journalSync:Flush() end
    end
    local function deliver(to, sourcePackets)
        activate(to)
        for _, packet in ipairs(sourcePackets or packets) do
            to:CHAT_MSG_ADDON('CHAT_MSG_ADDON', packet.prefix, packet.body, packet.channel, packet.sender)
        end
    end

    before_each(function()
        savedGlobals = { UnitName = UnitName, GetTime = GetTime, SendAddonMessage = SendAddonMessage, time = time }
        raidSize = mocks.raidSize
        mocks.raidSize, now, packets = 2, 10, {}
        _G.UnitName = function(unit)
            if unit == 'player' then return active.name end
            if unit == 'raid1' then return 'Light' end
            if unit == 'raid2' then return 'Dark' end
        end
        _G.GetTime = function() return now + active.clock end
        _G.time = function() return 1000 + math.floor(now) end
        _G.SendAddonMessage = function(prefix, body, channel)
            assert.is_true(#prefix + #body <= 254)
            packets[#packets + 1] = { prefix = prefix, body = body, channel = channel, sender = active.name }
        end
        peers = { peer('Light'), peer('Dark', 500) }
    end)

    after_each(function()
        for _, value in ipairs(peers) do value.journalSync:Reset(); value:StopCombatTicker() end
        _G.UnitName, _G.GetTime, _G.SendAddonMessage = savedGlobals.UnitName, savedGlobals.GetTime, savedGlobals.SendAddonMessage
        _G.time = savedGlobals.time
        mocks.raidSize = raidSize
    end)

    it('shares a mechanic death across worlds once and persists the same hash without relaying', function()
        local light, dark = peers[1], peers[2]
        activate(dark)
        dark.currentCombat.isBoss, dark.currentCombat.firstEnemy = true, 'Халион'
        dark:OnCombatLogEvent(record('MECHANIC_DEATH', 1000, nil, nil, nil, { type = 'TACTIC_VIOLATION' }))
        flush(dark)
        deliver(light)
        deliver(light) -- duplicated packets, including fragmented delivery
        assert.are.equal(1, #light.currentCombat.events)
        assert.are.equal(dark.currentCombat.events[1].hash, light.currentCombat.events[1].hash)
        assert.are.equal('Халион', light.currentCombat.firstEnemy)
        assert.is_true(light.currentCombat.isBoss)
        assert.are.equal(0, #light.journalSync.queue)
        assert.is_true(Journal.Visible(light.currentCombat.events[1], 'ERRORS'))
        light:FinishCombat('test')
        assert.are.equal(1, #light.db.char.combatHistoryV2.combats[1].events)
        assert.are.equal(dark.currentCombat.events[1].hash, light.combatHistory[1].events[1].hash)
    end)

    it('matches local and remote observations in either order despite clocks and class differences', function()
        for _, localFirst in ipairs({ true, false }) do
            local light, dark = peers[1], peers[2]
            activate(light)
            light:ResetCombatState(); light:StartCombat('test')
            activate(dark)
            dark:ResetCombatState(); dark:StartCombat('test')
            packets = {}
            local first = record('SPELL_USE', 1000, 'paladin', 'tank', 10278)
            local second = record('SPELL_USE', 9500, 'paladin', 'tank', 10278, {
                source = { guid = 'paladin', name = 'Другое имя', class = 'PALADIN' }, type = 'TACTIC_VIOLATION',
            })
            assert.are.equal(Sync.Hash(first), Sync.Hash(second))
            activate(dark); dark:OnCombatLogEvent(first)
            if localFirst then activate(light); light:OnCombatLogEvent(second) end
            flush(dark); deliver(light)
            if not localFirst then activate(light); light:OnCombatLogEvent(second) end
            assert.are.equal(1, #light.currentCombat.events)
            assert.are.equal('PALADIN', light.currentCombat.events[1].source.class)
            assert.are.equal('TACTIC_VIOLATION', light.currentCombat.events[1].type)
        end
    end)

    it('retains repeated real casts and simultaneous events on different targets', function()
        local light, dark = peers[1], peers[2]
        for i = 1, 2 do
            activate(light); light:OnCombatLogEvent(record('SPELL_USE', 1000 + i * 0.1, 'paladin', 'tank', 10278))
            activate(dark); dark:OnCombatLogEvent(record('SPELL_USE', 2000 + i * 0.1, 'paladin', 'tank', 10278))
        end
        activate(dark); dark:OnCombatLogEvent(record('SPELL_USE', 2000.2, 'paladin', 'other', 10278))
        flush(dark); deliver(light)
        assert.are.equal(3, #light.currentCombat.events)
        assert.are.equal(light.currentCombat.events[1].hash, light.currentCombat.events[2].hash)
        assert.are_not.equal(light.currentCombat.events[1].hash, light.currentCombat.events[3].hash)
    end)

    it('identifies a polled death and UNIT_DIED as one death anchored to mechanic damage', function()
        local light, dark = peers[1], peers[2]
        for i, value in ipairs(peers) do
            activate(value)
            local tracker = setmetatable({ dmgEvents = {}, deathChecks = {} }, { __index = Halion })
            tracker:logDmg('Victim', { timestamp = 1000, sourceGUID = 'orb', source = 'Темный шар', spellId = 77846 })
            tracker:ProcessPlayerDeath(function(entry) value:OnCombatLogEvent(entry) end, 'Victim', 1000 + i * 0.2, 'victim')
        end
        flush(dark); deliver(light)
        assert.are.equal(1, #light.currentCombat.events)
        assert.are.equal(1000, light.currentCombat.events[1].identityTime)
        assert.are.equal(dark.currentCombat.events[1].hash, light.currentCombat.events[1].hash)
    end)

    it('maps different local pull counters and keeps damage and summary attached to one pull', function()
        local light, dark = peers[1], peers[2]
        activate(light)
        light:OnCombatLogEvent(record('MISDIRECTION_START', 1000, 'hunter', 'tank', 34477, { pullId = 8 }))
        light:OnCombatLogEvent(record('MISDIRECTION_SUMMARY', 1001, 'hunter', 'tank', 34477, { pullId = 8, amount = 50 }))
        activate(dark)
        dark:OnCombatLogEvent(record('MISDIRECTION_START', 1000.1, 'hunter', 'tank', 34477, { pullId = 1 }))
        dark:OnCombatLogEvent(record('MISDIRECTION_DAMAGE', 1000.2, 'hunter', 'boss', 53209, { pullId = 1, amount = 100, hidden = false }))
        dark:OnCombatLogEvent(record('MISDIRECTION_SUMMARY', 1001.1, 'hunter', 'tank', 34477, { pullId = 1, amount = 100 }))
        flush(dark); deliver(light)
        local entries = light.currentCombat.events
        assert.are.equal(3, #entries)
        assert.are.equal(entries[1].pullId, entries[2].pullId)
        assert.are.equal(entries[1].pullId, entries[3].pullId)
        assert.are.equal(100, entries[2].amount)
        assert.are.equal(1000.2, entries[2].timestamp)
        assert.are.equal(2, entries[2].seq)
        assert.are.equal(100, Journal.PullTargets(light.currentCombat, entries[1].pullId)[1].amount)
    end)

    it('reassembles reversed fragments and preserves Cyrillic effect names', function()
        activate(peers[2])
        peers[2]:OnCombatLogEvent(record('DISPEL', 1000, 'priest', 'victim', 988, {
            extraSpellId = 74792, extraSpellName = 'Пожирание души | %',
        }))
        flush(peers[2])
        assert.is_true(#packets > 1)
        local reverse = {}
        for i = #packets, 1, -1 do reverse[#reverse + 1] = packets[i] end
        deliver(peers[1], reverse)
        assert.are.equal(1, #peers[1].currentCombat.events)
        assert.are.equal('Пожирание души | %', peers[1].currentCombat.events[1].extraSpellName)
        assert.is_truthy(Journal.Format(peers[1].currentCombat.events[1]):find('Пожирание души', 1, true))
    end)

    it('drains final packets after combat and appends late events to saved history', function()
        local light, dark = peers[1], peers[2]
        activate(dark)
        dark:OnCombatLogEvent(record('MECHANIC_DEATH'))
        dark:FinishCombat('wipe')
        activate(light)
        light:OnCombatLogEvent(record('SPELL_USE', 999, 'paladin', 'tank', 10278))
        light:FinishCombat('wipe')
        flush(dark)
        deliver(light)
        assert.are.equal(0, #light.currentCombat.events)
        assert.are.equal(2, #light.combatHistory[1].events)
        assert.are.equal(2, #light.db.char.combatHistoryV2.combats[1].events)
        assert.are.equal(dark.combatHistory[1].events[1].hash, light.combatHistory[1].events[2].hash)
        local finished = light.combatHistory[1]
        now = now + 2
        light:StartCombat('next pull')
        deliver(light)
        assert.are.equal(0, #light.currentCombat.events)
        assert.are.same(finished, light.combatHistory[1])
    end)

    it('ignores foreign channels, outsiders, malformed packets and events outside RS or combat', function()
        activate(peers[2]); peers[2]:OnCombatLogEvent(record('MECHANIC_DEATH')); flush(peers[2])
        activate(peers[1])
        for _, packet in ipairs(packets) do
            peers[1]:CHAT_MSG_ADDON('CHAT_MSG_ADDON', packet.prefix, packet.body, 'WHISPER', 'Dark')
            peers[1]:CHAT_MSG_ADDON('CHAT_MSG_ADDON', packet.prefix, packet.body, 'RAID', 'Outsider')
        end
        peers[1]:CHAT_MSG_ADDON('CHAT_MSG_ADDON', Sync.PREFIX, '1-1:99:1:0:0:x', 'RAID', 'Dark')
        peers[1]:CHAT_MSG_ADDON('CHAT_MSG_ADDON', Sync.PREFIX, '1-1:1:1:0:0:nan', 'RAID', 'Dark')
        assert.are.equal(0, #peers[1].currentCombat.events)
        peers[1].currentInstanceId = 631
        deliver(peers[1]); peers[1]:OnCombatLogEvent(record('MECHANIC_DEATH'))
        assert.are.equal(0, #peers[1].journalSync.queue)
        assert.are.equal(1, #peers[1].currentCombat.events)
        peers[1].currentInstanceId = 724
        peers[1]:ResetCombatState()
        peers[1].journalSync.previous = nil
        deliver(peers[1])
        assert.are.equal(0, #peers[1].currentCombat.events)
        now = now + 20
        peers[1]:StartCombat('new pull')
        deliver(peers[1])
        assert.are.equal(0, #peers[1].currentCombat.events)
    end)
end)
