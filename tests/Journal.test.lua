local mocks = require('tests.mocks')
local Journal = require('lib.Journal')
require('../lib/blizzardEvent')
require('../lib/CombatFilters')
require('../data/BossIds')
local addon = require('../Core')
local spells = require('../modules/SpellTracker')
local pulls = require('../modules/Misdirection')
local lady = require('../modules/bosses/DeathwhisperTracker')
local professor = require('../modules/bosses/PutricideTracker')
local queen = require('../modules/bosses/BloodQueenTracker')
local princes = require('../modules/bosses/BloodPrincesTracker')
local lich = require('../modules/bosses/LichKingTracker')
local trial = require('../modules/bosses/TrialCrusaderTracker')
local halion = require('../modules/bosses/HalionTracker')
local modules = { spells, pulls, lady, professor, queen, princes, lich, trial, halion }

-- SavedVariables are plain Lua data: round-trip through actual Lua source.
local function serialize(value)
    if type(value) == 'string' then return string.format('%q', value) end
    if type(value) ~= 'table' then return tostring(value) end
    local parts = {}
    for key, child in pairs(value) do
        parts[#parts + 1] = '[' .. serialize(key) .. ']=' .. serialize(child)
    end
    return '{' .. table.concat(parts, ',') .. '}'
end

local function event(kind, spellId, source, target, timestamp, amount)
    return {
        event = kind, spellId = spellId, timestamp = timestamp or 1000.125,
        sourceGUID = source or 'hunter', sourceName = source or 'Hunter', sourceFlags = 0x514,
        destGUID = target or 'boss', destName = target or 'Boss', destFlags = 0xa48,
        amount = amount,
    }
end

local function cast(source, target, spellId)
    pulls:handleEvent(event('SPELL_CAST_SUCCESS', spellId or 34477, source, target))
end

local bossGUID = '0xF130008FF75CADA4'

local function setAssignedRaid(tankRole)
    mocks.raidSize = 3
    for i, guid in ipairs({ 'tank', 'assist', 'dps' }) do
        mocks:SetUnitGUID('raid' .. i, guid)
        mocks:SetRaidRosterInfo(i, guid, 1, 'Warrior', 'WARRIOR',
            i == 1 and (tankRole or 'MAINTANK') or (i == 2 and 'MAINASSIST' or nil))
    end
    addon:RAID_ROSTER_UPDATE('RAID_ROSTER_UPDATE')
end

describe('Structured journal', function()
    local oldRoster, oldClass, oldIterate, oldSend, oldFrame, oldTooltip, oldSpellInfo, lines

    local oldMembers, oldAssignments, oldHasTanks

    before_each(function()
        oldMembers, oldAssignments, oldHasTanks = addon.groupMembers, addon.groupAssignments, addon.hasTankAssignments
        addon.groupMembers, addon.groupAssignments, addon.hasTankAssignments = {}, {}, false
        oldRoster, oldClass = GetRaidRosterInfo, UnitClass
        oldFrame, oldTooltip = CreateFrame, GameTooltip
        oldSpellInfo = GetSpellInfo
        oldIterate, oldSend = addon.IterateModules, addon.SendMessage
        mocks:ClearUnitGUIDs()
        mocks:ClearRaidRoster()
        mocks.raidSize, mocks.partySize = 0, 0
        addon:StopCombatTicker()
        addon.inCombat = false
        addon.currentInstanceId = 631
        addon.db = { profile = {}, char = { combatHistory = { { messages = { 'old' } } } } }
        addon:InitializeJournal()
        lines = {}
        addon.mainFrame = { logText = {
            AddMessage = function(_, text) lines[#lines + 1] = text end,
            Clear = function() for i = #lines, 1, -1 do lines[i] = nil end end,
        } }
        for _, module in ipairs(modules) do
            module.log = function(entry) addon:OnCombatLogEvent(entry) end
        end
        spells:reset()
        pulls:reset()
        lady.currentSpirits, lady.report = {}, {}
        professor:reset()
        lich:reset()
        halion:reset()
        addon.SendMessage = function(_, message)
            if message == 'RLHelper_CombatEnding' then pulls:finishJournalPulls() end
            if message == 'RLHelper_CombatEnded' then pulls:reset() end
        end
    end)

    after_each(function()
        addon.groupMembers, addon.groupAssignments, addon.hasTankAssignments = oldMembers, oldAssignments, oldHasTanks
        _G.GetRaidRosterInfo, _G.UnitClass = oldRoster, oldClass
        _G.CreateFrame, _G.GameTooltip = oldFrame, oldTooltip
        _G.GetSpellInfo = oldSpellInfo
        addon.IterateModules, addon.SendMessage = oldIterate, oldSend
        addon:StopCombatTicker()
        mocks.raidSize = 0
    end)

    it('starts V2 empty without reading or converting legacy records', function()
        assert.are.equal(0, #addon.combatHistory)
        assert.is_nil(addon.db.char.combatHistory)
        assert.is_nil(addon.currentCombat.messages)
        assert.are.equal(2, addon.db.char.combatHistoryV2.schemaVersion)
    end)

    it('always uses structured records and removes obsolete history across characters without losing V2 or settings', function()
        local store = { schemaVersion = 2, nextCombatId = 2, combats = {
            { id = 1, events = { Journal.Create('FIRST_DAMAGE', event('SWING_DAMAGE')) } }
        } }
        local current = { combatHistory = { { messages = { 'old' } } }, combatHistoryV2 = Journal.Copy(store) }
        local other = { combatHistory = { { messages = { 'other old' } } },
            combatHistoryV2 = Journal.Copy(store), unrelatedSetting = 42 }
        addon.db = { profile = { journalV2 = false }, char = current,
            sv = { char = { current = current, other = other }, profiles = { other = { journalV2 = false } } } }
        for _ = 1, 2 do
            addon:InitializeJournal()
            assert.is_nil(addon.db.profile.journalV2)
            assert.is_nil(current.combatHistory)
            assert.is_nil(other.combatHistory)
            assert.is_nil(addon.db.sv.profiles.other.journalV2)
            assert.are.same(store, current.combatHistoryV2)
            assert.are.same(store, other.combatHistoryV2)
            assert.are.same(store.combats, addon.combatHistory)
            assert.are.equal(42, other.unrelatedSetting)
        end
        local saved = assert(loadstring('return ' .. serialize(addon.db.sv)))()
        assert.is_nil(saved.char.current.combatHistory)
        assert.is_nil(saved.char.other.combatHistory)
        assert.are.same(store, saved.char.other.combatHistoryV2)
    end)

    it('preserves timestamp, actors, classes and both spells through save/reload', function()
        mocks:SetUnitGUID('player', 'priest')
        _G.UnitClass = function() return 'Жрец', 'PRIEST' end
        local dispel = event('SPELL_DISPEL', 988, 'priest', 'tank')
        dispel.sourceClass = 'PRIEST'
        dispel.extraSpellId = 71289
        spells:handleEvent(dispel)
        addon.currentCombat.startTime = 1000
        addon:FinishCombat('test')
        local saved = addon.db.char.combatHistoryV2.combats[1]
        assert.is_nil(saved.messages)
        assert.are.equal('DISPEL', saved.events[1].kind)
        assert.are.equal('INFO', saved.events[1].type)
        assert.are.equal(1000.125, saved.events[1].timestamp)
        assert.are.same({ guid = 'priest', name = 'priest', class = 'PRIEST' }, saved.events[1].source)
        assert.are.equal(71289, saved.events[1].extraSpellId)
        assert.is_nil(saved.events[1].event)
        local expected = Journal.Copy(saved)
        addon.db = assert(loadstring('return ' .. serialize(addon.db)))()
        _G.UnitClass = nil
        addon:InitializeJournal()
        assert.are.same(expected, addon.combatHistory[1])
        assert.is_nil(addon.db.char.combatHistory)
    end)


    it('does not duplicate a saved combat, shares no mutable record references and retains 30 fights', function()
        for i = 1, 31 do
            local combat = { startTime = i, events = { Journal.Create('FIRST_DAMAGE', { timestamp = i }) } }
            addon:SaveCombatToProfile(combat)
            addon:SaveCombatToProfile(combat)
            combat.events[1].text = 'modified after save'
        end
        local saved = addon.db.char.combatHistoryV2.combats
        assert.are.equal(30, #saved)
        assert.are.equal(31, saved[1].startTime)
        assert.are.equal(2, saved[30].startTime)
        assert.are_not.equal('modified after save', saved[1].events[1].text)
        assert.are.equal(32, addon.db.char.combatHistoryV2.nextCombatId)
    end)

    it('clears only the selected store and retains the ID sequence', function()
        addon:SaveCombatToProfile({ events = {} })
        addon:ClearCombatHistory()
        assert.are.equal(0, #addon.db.char.combatHistoryV2.combats)
        assert.are.equal(2, addon.db.char.combatHistoryV2.nextCombatId)
        assert.is_nil(addon.db.char.combatHistory)
    end)

    it('records distinct events at the same timestamp in insertion order', function()
        local hit = event('SWING_DAMAGE', nil, 'spirit1', 'player')
        lady.currentSpirits.spirit1 = {}
        lady.currentSpirits.spirit2 = {}
        lady:handleEvent(hit)
        hit.sourceGUID = 'spirit2'
        lady:handleEvent(hit)
        local records = addon.currentCombat.events
        assert.are.equal(2, #records)
        assert.are.equal(records[1].timestamp, records[2].timestamp)
        assert.are.equal(1, records[1].seq)
        assert.are.equal(2, records[2].seq)
        assert.are.equal('spirit1', records[1].source.guid)
        assert.are.equal('spirit2', records[2].source.guid)
        assert.is_nil(records[1].spellId)
        assert.are.equal('TACTIC_VIOLATION', records[1].type)
    end)

    it('classifies only known non-tanks taunting a boss in combat as violations', function()
        setAssignedRaid()
        addon.inCombat = true
        for _, guid in ipairs({ 'tank', 'assist', 'dps', 'unknown' }) do
            spells:handleEvent(event('SPELL_AURA_APPLIED', 355, guid, bossGUID))
        end
        local entries = addon.currentCombat.events
        assert.are.equal('INFO', entries[1].type)
        assert.are.equal('INFO', entries[2].type)
        assert.are.equal('TACTIC_VIOLATION', entries[3].type)
        assert.are.equal('TAUNT', entries[3].kind)
        assert.are.equal('INFO', entries[4].type)
        assert.is_truthy(lines[3]:find('|cFFFF0000', 1, true))

        mocks:ClearRaidRoster()
        addon:RAID_ROSTER_UPDATE('RAID_ROSTER_UPDATE')
        spells:handleEvent(event('SPELL_AURA_APPLIED', 355, 'dps', bossGUID))
        assert.are.equal('INFO', entries[5].type)
    end)

    it('uses the target and combat state for taunts and paladin protection', function()
        setAssignedRaid()
        addon.currentCombat.isBoss = true
        addon.currentCombat.firstEnemy = 'Леди Смертный Шепот'
        local cases = {
            { 355, 'dps', 'ordinary-mob', true, 'INFO' },
            { 355, 'dps', bossGUID, false, 'INFO' },
            { 20736, 'dps', 'ordinary-mob', true, 'INFO', 'SPELL_CAST_SUCCESS' },
            { 20736, 'dps', bossGUID, true, 'TACTIC_VIOLATION', 'SPELL_CAST_SUCCESS' },
            { 31789, 'dps', 'tank', true, 'TACTIC_VIOLATION', 'SPELL_CAST_SUCCESS' },
            { 31789, 'dps', 'assist', true, 'TACTIC_VIOLATION', 'SPELL_CAST_SUCCESS' },
            { 31789, 'tank', 'assist', true, 'INFO', 'SPELL_CAST_SUCCESS' },
            { 31789, 'assist', 'tank', true, 'INFO', 'SPELL_CAST_SUCCESS' },
            { 31789, 'tank', 'tank', true, 'INFO', 'SPELL_CAST_SUCCESS' },
            { 31789, 'dps', 'dps', true, 'INFO', 'SPELL_CAST_SUCCESS' },
            { 31789, 'unknown', 'tank', true, 'INFO', 'SPELL_CAST_SUCCESS' },
            { 31789, 'dps', 'tank', false, 'INFO', 'SPELL_CAST_SUCCESS' },
            { 10278, 'dps', 'tank', true, 'TACTIC_VIOLATION' },
            { 10278, 'dps', 'assist', true, 'TACTIC_VIOLATION' },
            { 10278, 'dps', 'dps', true, 'INFO' },
            { 10278, 'dps', 'tank', false, 'INFO' },
        }
        for i, case in ipairs(cases) do
            addon.inCombat = case[4]
            spells:handleEvent(event(case[6] or 'SPELL_AURA_APPLIED', case[1], case[2], case[3]))
            assert.are.equal(case[5], addon.currentCombat.events[i].type, 'case ' .. i)
        end
    end)

    it('updates assignments but preserves the classification and roles of saved events', function()
        setAssignedRaid()
        addon.inCombat = true
        spells:handleEvent(event('SPELL_AURA_APPLIED', 355, 'assist', bossGUID))
        local saved = Journal.Copy(addon.currentCombat)
        assert.are.equal('MAINASSIST', saved.events[1].sourceAssignment)
        assert.is_true(saved.events[1].targetIsBoss)

        mocks:SetRaidRosterInfo(2, 'assist', 1, 'Warrior', 'WARRIOR')
        addon:RAID_ROSTER_UPDATE('RAID_ROSTER_UPDATE')
        spells:handleEvent(event('SPELL_AURA_APPLIED', 355, 'assist', bossGUID))
        assert.are.equal('TACTIC_VIOLATION', addon.currentCombat.events[2].type)
        assert.are.equal('INFO', saved.events[1].type)
        assert.are.equal('MAINASSIST', saved.events[1].sourceAssignment)
        addon:DisplayCombat(saved)
        assert.is_nil(lines[1]:find('|cFFFF0000', 1, true))

        mocks.raidSize = 0
        addon:PARTY_MEMBERS_CHANGED('PARTY_MEMBERS_CHANGED')
        assert.is_false(addon:IsAssignedTank('tank'))
        assert.is_false(addon.hasTankAssignments)
    end)

    it('captures assignments when a delayed paladin taunt happens, before UNIT_TARGET arrives', function()
        setAssignedRaid()
        addon.inCombat = true
        mocks:SetUnitGUID('target', bossGUID)
        mocks:SetUnitGUID('targettarget', 'dps')
        spells:handleEvent(event('SPELL_AURA_APPLIED', 62124, 'dps', bossGUID))
        mocks:SetRaidRosterInfo(3, 'dps', 1, 'Warrior', 'WARRIOR', 'MAINTANK')
        addon:RAID_ROSTER_UPDATE('RAID_ROSTER_UPDATE')
        spells:UNIT_TARGET('UNIT_TARGET', 'target')
        local entry = addon.currentCombat.events[1]
        assert.are.equal('TACTIC_VIOLATION', entry.type)
        assert.is_nil(entry.sourceAssignment)
        assert.is_true(entry.targetIsBoss)
    end)

    it('keeps the delayed paladin taunt timestamp and identity', function()
        mocks:SetUnitGUID('target', 'boss')
        mocks:SetUnitGUID('targettarget', 'paladin')
        spells:handleEvent(event('SPELL_AURA_APPLIED', 62124, 'paladin', 'boss'))
        assert.are.equal(0, #addon.currentCombat.events)
        spells:UNIT_TARGET('UNIT_TARGET', 'target')
        local entry = addon.currentCombat.events[1]
        assert.are.equal(1000.125, entry.timestamp)
        assert.are.equal('paladin', entry.source.guid)
        assert.are.equal('boss', entry.target.guid)
        assert.are.equal(62124, entry.spellId)
        assert.are.equal('TAUNT', entry.kind)
    end)

    it('stores misses and summaries without manufacturing actors or spell IDs', function()
        addon.currentCombat.firstEnemy = 'Леди Смертный Шепот'
        local miss = event('SPELL_MISSED', 33786)
        miss.missType = 'IMMUNE'
        lady:handleEvent(miss)
        lady.report = { Player = 2 }
        lady:summarizeCombat()
        local entries = addon.currentCombat.events
        assert.are.equal('IMMUNE', entries[1].missType)
        assert.are.equal('CYCLONE_MISSED', entries[1].kind)
        assert.are.equal('SPIRIT_SUMMARY', entries[2].kind)
        assert.is_nil(entries[2].source)
        assert.is_nil(entries[2].target)
        assert.is_nil(entries[2].spellId)
        assert.is_truthy(entries[2].text:find('Player(2)', 1, true))
    end)

    it('renders first damage and healing with the established filters without using their spell icons', function()
        _G.GetSpellInfo = function() return 'Spell', nil, 'SpellTexture' end
        spells:handleEvent(event('SPELL_DAMAGE', 53209, 'Hunter', 'Boss', 1001, 100))
        spells:handleEvent(event('SPELL_HEAL', 48782, 'Healer', 'Валитрия Сноходица', 1002, 200))
        local expected = {
            date('%H:%M:%S', 1001) .. ' |cFFFFFFFFHunter|r |TInterface\\Icons\\Ability_SteelMelee:24:24:0:-2|t Первый урон по |cFFFFFFFFBoss|r',
            date('%H:%M:%S', 1002) .. ' |cFFFFFFFFHealer|r |TSpellTexture:24:24:0:-2|t Первый хил по |cFFFFFFFFВалитрия Сноходица|r',
        }
        assert.are.same(expected, lines)
        assert.are.equal(53209, addon.currentCombat.events[1].spellId)
        addon:DisplayCombat(Journal.Copy(addon.currentCombat))
        assert.are.same(expected, lines)
        local ability = Journal.Create('SPELL_USE', event('SPELL_CAST_SUCCESS', 53209))
        assert.is_truthy(Journal.Format(ability):find('|TSpellTexture:', 1, true))
    end)

    it('colors known source classes with the standard WoW palette', function()
        _G.GetSpellInfo = function() return 'Spell', nil, 'SpellTexture' end
        mocks.raidSize = 1
        mocks:SetRaidRosterInfo(1, 'hunter', 1, 'Охотник', 'HUNTER')
        local entry = Journal.Create('SPELL_USE', event('SPELL_CAST_SUCCESS', 53209, 'hunter', 'boss', 1001))

        assert.are.equal('HUNTER', entry.source.class)
        assert.are.equal(date('%H:%M:%S', 1001) ..
            ' |cFFABD473hunter|r |TSpellTexture:24:24:0:-2|t |cFFFFFFFFboss|r',
            Journal.Format(entry))
    end)

    it('keeps the violation prefix and message red while preserving white time and source', function()
        local entry = Journal.Create('SHADOW_TRAP', event('SPELL_DAMAGE', 73529), 'TACTIC_VIOLATION', {
            text = '|cFFFFFFFFPlayer|r взорвал ловушку',
        })
        addon:OnCombatLogEvent(entry)
        local expected = '|cFFFFFFFF' .. date('%H:%M:%S', entry.timestamp) ..
            '|r |cFFABD473Hunter|r |cFFFF0000Player взорвал ловушку|r'
        assert.are.equal(expected, lines[1])
        addon:DisplayCombat(Journal.Copy(addon.currentCombat))
        assert.are.equal(expected, lines[1])
        assert.is_nil(Journal.Format(Journal.Create('SPELL_USE', event('SPELL_CAST_SUCCESS'))):find('|cFFFF0000', 1, true))
    end)

    it('logs snake trap placement without a target once as a raid error', function()
        addon.inCombat = true
        local trap = event('SPELL_CAST_SUCCESS', 34600, 'hunter')
        trap.destGUID, trap.destName = '0x0000000000000000', nil
        spells:handleEvent(trap)
        for _, subevent in ipairs({ 'SPELL_AURA_APPLIED', 'SPELL_SUMMON', 'SPELL_CREATE', 'SPELL_CAST_FAILED' }) do
            spells:handleEvent(event(subevent, 34600, 'hunter'))
        end

        assert.are.equal(1, #addon.currentCombat.events)
        local entry = addon.currentCombat.events[1]
        assert.are.equal('SPELL_USE', entry.kind)
        assert.are.equal(34600, entry.spellId)
        assert.are.equal('hunter', entry.source.guid)
        assert.is_nil(entry.target.name)
        assert.are.equal('TACTIC_VIOLATION', entry.type)
        assert.is_true(Journal.Visible(entry, 'ALL'))
        assert.is_true(Journal.Visible(entry, 'ERRORS'))
    end)

    it('classifies distracting shot as a tactic violation and colors only its message red', function()
        setAssignedRaid()
        addon.inCombat = true
        _G.GetSpellInfo = function() return 'Отвлекающий выстрел', nil, 'DistractingShotTexture' end

        local shot = event('SPELL_CAST_SUCCESS', 20736, 'dps', bossGUID, 1001)
        shot.sourceName, shot.destName = 'Dps', 'boss'
        spells:handleEvent(shot)
        spells:handleEvent(event('SPELL_AURA_APPLIED', 20736, 'dps', 'boss', 1001))

        local entry = addon.currentCombat.events[1]
        assert.are.equal(1, #addon.currentCombat.events)
        assert.are.equal(1, #lines)
        assert.are.equal('TAUNT', entry.kind)
        assert.are.equal('TACTIC_VIOLATION', entry.type)
        assert.are.equal('|cFFFFFFFF' .. date('%H:%M:%S', 1001) ..
            '|r |cFFC79C6EDps|r |TDistractingShotTexture:24:24:0:-2|t |cFFFF0000boss|r', lines[1])
    end)

    it('filters hunter damage with the established filters while retaining all damage in totals and saved target details', function()
        addon.inCombat = true
        addon.currentCombat.startTime = 1000
        addon:SetJournalView('MISDIRECTION')
        cast('hunter', 'tank')
        local hits = {
            { 'RANGE_DAMAGE', 75 }, { 'SPELL_DAMAGE', 53353 },
            { 'SPELL_PERIODIC_DAMAGE', 49001 }, { 'SWING_DAMAGE' },
            { 'SPELL_DAMAGE', 53209 }, { 'SPELL_PERIODIC_DAMAGE', 53352 },
        }
        for _, hit in ipairs(hits) do
            pulls:handleEvent(event(hit[1], hit[2], 'hunter', 'enemy', 1001, 100))
        end
        pulls:handleEvent(event('SPELL_AURA_REMOVED', 35079, 'hunter', 'hunter', 1002))
        assert.are.equal(4, #lines) -- Start, two tracked spells, summary.
        local entries = addon.currentCombat.events
        assert.are.equal(8, #entries)
        assert.are.equal(600, entries[8].amount)
        assert.are.same({ { target = { guid = 'enemy', name = 'enemy' }, amount = 600 } },
            Journal.PullTargets(addon.currentCombat, 1))
        local expected = Journal.Copy(lines)
        addon:FinishCombat('test')
        addon.db = assert(loadstring('return ' .. serialize(addon.db)))()
        addon:InitializeJournal()
        addon:DisplayCombat(addon.combatHistory[1])
        addon:SetJournalView('MISDIRECTION')
        assert.are.same(expected, lines)
        assert.are.equal(600, Journal.PullTargets(addon.combatHistory[1], 1)[1].amount)
    end)

    it('filters rogue damage by the existing whitelist without removing damage from the total', function()
        addon.inCombat = true
        addon:SetJournalView('MISDIRECTION')
        cast('rogue', 'tank', 57934)
        pulls:handleEvent(event('SWING_DAMAGE', nil, 'rogue', 'enemy', 1001, 100))
        pulls:handleEvent(event('SPELL_DAMAGE', 57965, 'rogue', 'enemy', 1001, 200))
        pulls:handleEvent(event('SPELL_DAMAGE', 51723, 'rogue', 'enemy', 1001, 300))
        pulls:handleEvent(event('SPELL_PERIODIC_DAMAGE', 57970, 'rogue', 'enemy', 1001, 400))
        pulls:handleEvent(event('SPELL_AURA_REMOVED', 59628, 'rogue', 'rogue', 1002))
        assert.are.equal(4, #lines) -- Start, two whitelisted hits, summary.
        assert.is_truthy(lines[2]:find('300', 1, true))
        assert.is_truthy(lines[3]:find('400', 1, true))
        assert.are.equal(6, #addon.currentCombat.events)
        assert.are.equal(1000, addon.currentCombat.events[6].amount)
    end)

    it('shows each simultaneous hunter and rogue hit with its target name live and after reload', function()
        _G.GetSpellInfo = function(spellId) return 'Spell', nil, 'SpellTexture-' .. spellId end
        addon.inCombat = true
        addon.currentCombat.startTime = 1000
        addon:SetJournalView('MISDIRECTION')
        for _, caster in ipairs({ { 'Hunter', 34477, 53209 }, { 'Rogue', 57934, 51723 } }) do
            cast(caster[1], 'Tank', caster[2])
            local before = #lines
            for i, target in ipairs({ 'Первая цель', 'Вторая цель', 'Первая цель' }) do
                local hit = event('SPELL_DAMAGE', caster[3], caster[1], 'enemy-' .. i, 1001, i * 100)
                hit.destName = target
                pulls:handleEvent(hit)
                assert.are.equal(before + i, #lines)
                assert.are.equal(string.format('%s |cFFFFFFFF%s|r |TSpellTexture-%s:24:24:0:-2|t %s %s',
                    date('%H:%M:%S', 1001), caster[1], caster[3], target, i * 100), lines[#lines])
            end
            pulls:handleEvent(event('SPELL_AURA_REMOVED', caster[2] == 34477 and 35079 or 59628,
                caster[1], caster[1], 1002))
        end
        addon:FinishCombat('test')
        assert.are.equal(string.format('|Hrlhpull:1|h%s |cFFFFFFFFHunter|r |TSpellTexture-34477:24:24:0:-2|t Напул окончен 600|h',
            date('%H:%M:%S', 1002)), lines[5])
        assert.are.equal(string.format('|Hrlhpull:2|h%s |cFFFFFFFFRogue|r |TSpellTexture-57934:24:24:0:-2|t Напул окончен 600|h',
            date('%H:%M:%S', 1002)), lines[10])
        local expected = Journal.Copy(lines)
        addon.db = assert(loadstring('return ' .. serialize(addon.db)))()
        addon:InitializeJournal()
        addon:DisplayCombat(addon.combatHistory[1])
        addon:SetJournalView('MISDIRECTION')
        assert.are.same(expected, lines)
        assert.are.equal(10, #lines) -- Two starts, six individual hits, two summaries.
    end)

    it('records all hunter and rogue damage independently of the view, including simultaneous hits', function()
        addon.inCombat = true
        cast('hunter', 'tank')
        cast('rogue', 'tank', 57934)
        pulls:handleEvent(event('RANGE_DAMAGE', 75, 'hunter', 'enemy1', 1001, 100))
        pulls:handleEvent(event('SPELL_DAMAGE', 53353, 'hunter', 'enemy2', 1001, 200))
        pulls:handleEvent(event('SWING_DAMAGE', nil, 'rogue', 'enemy1', 1001, 300))
        pulls:handleEvent(event('SPELL_PERIODIC_DAMAGE', 57970, 'rogue', 'enemy2', 1001, 400))
        pulls:handleEvent(event('SPELL_AURA_REMOVED', 35079, 'hunter', 'hunter', 1002))
        pulls:handleEvent(event('SPELL_AURA_REMOVED', 59628, 'rogue', 'rogue', 1002))
        local entries = addon.currentCombat.events
        assert.are.equal(8, #entries)
        assert.are.equal(4, #lines) -- Only starts and summaries.
        assert.are.equal(1, entries[3].pullId)
        assert.are.equal(2, entries[5].pullId)
        assert.are.equal(300, entries[7].amount)
        assert.are.equal(700, entries[8].amount)
        assert.are.equal('tank', entries[7].target.guid)
        assert.are.equal('enemy1', entries[3].target.guid)
        local targets = Journal.PullTargets(addon.currentCombat, 1)
        assert.are.equal(2, #targets)
        assert.are.equal(100, targets[1].amount)
        assert.are.equal(200, targets[2].amount)
        addon:SetJournalView('MISDIRECTION')
        assert.are.equal(5, #lines) -- Auto-attacks and the Chimera proc stay out of the visible log.
        addon:SetJournalView('ERRORS')
        assert.are.equal(0, #lines)
        assert.are.equal(8, #addon.currentCombat.events)
    end)

    it('tracks simultaneous casters by GUID even if names match', function()
        addon.inCombat = true
        local first = event('SPELL_CAST_SUCCESS', 34477, 'hunter1', 'tank')
        local second = event('SPELL_CAST_SUCCESS', 34477, 'hunter2', 'tank')
        first.sourceName, second.sourceName = 'SameName', 'SameName'
        pulls:handleEvent(first)
        pulls:handleEvent(second)
        pulls:handleEvent(event('SPELL_DAMAGE', 53209, 'hunter1', 'enemy', 1001, 11))
        pulls:handleEvent(event('SPELL_DAMAGE', 53209, 'hunter2', 'enemy', 1001, 22))
        pulls:finishJournalPulls()
        assert.are.equal(11, addon.currentCombat.events[5].amount)
        assert.are.equal(22, addon.currentCombat.events[6].amount)
    end)

    it('retains a precombat cast, finalizes before saving and resets for the next combat', function()
        cast('hunter', 'tank')
        assert.are.equal(0, #addon.currentCombat.events)
        addon.currentCombat.startTime = 1001
        addon.inCombat = true
        pulls:handleEvent(event('SPELL_DAMAGE', 53209, 'hunter', 'enemy', 1001, 99))
        addon:FinishCombat('test')
        local saved = addon.db.char.combatHistoryV2.combats[1]
        assert.are.equal(3, #saved.events)
        assert.are.equal(1000.125, saved.events[1].timestamp)
        assert.are.equal('MISDIRECTION_SUMMARY', saved.events[3].kind)
        assert.are.equal(99, saved.events[3].amount)
        assert.are.same({}, pulls.journalPulls)
        addon:InitializeJournal()
        local targets = Journal.PullTargets(addon.combatHistory[1], 1)
        assert.are.equal('enemy', targets[1].target.guid)
        assert.are.equal(99, targets[1].amount)
    end)

    it('finishes repeated casts separately and ignores duplicate end notifications', function()
        addon.inCombat = true
        cast('hunter', 'tank')
        cast('hunter', 'otherTank')
        pulls:handleEvent(event('SPELL_AURA_REMOVED', 35079, 'hunter'))
        pulls:handleEvent(event('SPELL_AURA_REMOVED', 35079, 'hunter'))
        assert.are.equal(4, #addon.currentCombat.events)
        assert.are.equal(1, addon.currentCombat.events[2].pullId)
        assert.are.equal(2, addon.currentCombat.events[4].pullId)
        assert.are.equal('otherTank', addon.currentCombat.events[4].target.guid)
    end)

    it('shows violations and Halion deaths but excludes summaries live and after saving', function()
        addon.inCombat = true
        addon.currentCombat.startTime = 1000
        addon:SetJournalView('ERRORS')
        local expected = {}
        for _, kind in ipairs({ 'TAUNT', 'SPELL_USE', 'SPIRIT_HIT', 'SHADOW_TRAP',
            'VORTEX_HIT', 'VORTEX_MISSED', 'MECHANIC_DEATH' }) do
            local severity = (kind == 'MECHANIC_DEATH' or kind == 'VORTEX_HIT' or kind == 'VORTEX_MISSED') and 'INFO' or 'TACTIC_VIOLATION'
            local entry = Journal.Create(kind, event('SPELL_DAMAGE'), severity)
            addon:OnCombatLogEvent(entry)
            expected[#expected + 1] = Journal.Format(entry, true)
        end
        for _, kind in ipairs({ 'FIRST_DAMAGE', 'SPELL_USE', 'TAUNT', 'DISPEL', 'RESURRECT',
            'MIND_CONTROL', 'CYCLONE_APPLIED',
            'SPIRIT_SUMMARY', 'MALLEABLE_GOO_SUMMARY', 'CHOKING_GAS_SUMMARY' }) do
            addon:OnCombatLogEvent(Journal.Create(kind, event('SPELL_CAST_SUCCESS')))
        end
        cast('hunter', 'tank')
        pulls:handleEvent(event('SPELL_DAMAGE', 53209, 'hunter', 'enemy', 1001, 99))
        addon:FinishCombat('test')
        assert.are.same(expected, lines)
        local saved = addon.db.char.combatHistoryV2.combats[1]
        assert.are.equal(20, #saved.events)

        addon.db = assert(loadstring('return ' .. serialize(addon.db)))()
        addon:InitializeJournal()
        addon:DisplayCombat(addon.combatHistory[1])
        addon:SetJournalView('ERRORS')
        assert.are.same(expected, lines)
        addon:SetJournalView('ALL')
        assert.are.equal(19, #lines)
        addon:SetJournalView('MISDIRECTION')
        assert.are.equal(3, #lines)
    end)

    it('filters saved history without switching live event collection into that combat', function()
        local historic = { events = { Journal.Create('MECHANIC_DEATH', event('UNIT_DIED')) } }
        addon:DisplayCombat(historic)
        local before = #lines
        queen:handleEvent(event('SPELL_DAMAGE', 71483))
        assert.are.equal(before, #lines)
        assert.are.equal(1, #addon.currentCombat.events)
        assert.are.equal(1, #historic.events)
        addon:SetJournalView('ERRORS')
        assert.are.equal(1, #lines)
    end)

    it('bounds events and explicitly marks incomplete history', function()
        local previousLimit = Journal.MAX_EVENTS
        Journal.MAX_EVENTS = 2
        for i = 1, 3 do addon:OnCombatLogEvent(Journal.Create('FIRST_DAMAGE', { timestamp = i })) end
        Journal.MAX_EVENTS = previousLimit
        assert.are.equal(2, #addon.currentCombat.events)
        assert.are.equal(1, addon.currentCombat.droppedEvents)
        addon:DisplayCombat(addon.currentCombat)
        assert.is_truthy(lines[3]:find('Лимит истории', 1, true))
    end)

    it('rejects legacy text in V2 instead of parsing or saving it', function()
        assert.has_error(function() addon:OnCombatLogEvent('old text') end)
        assert.are.equal(0, #addon.currentCombat.events)
    end)

    it('writes fixed demo records shaped like the tracked encounters', function()
        addon:DemoJournal()
        assert.are.equal(68, #addon.currentCombat.events)
        local errors, misdirections = 0, 0
        for _, entry in ipairs(addon.currentCombat.events) do
            assert.is_string(entry.kind)
            assert.is_string(entry.text)
            assert.is_nil(entry.text:find('|c', 1, true))
            assert.is_nil(entry.text:find('Демо-босс', 1, true))
            assert.is_nil(entry.text:find('→', 1, true))
            if entry.source then assert.is_string(entry.source.name) end
            if Journal.Visible(entry, 'ERRORS') then errors = errors + 1 end
            if Journal.Visible(entry, 'MISDIRECTION') then misdirections = misdirections + 1 end
        end
        assert.are.equal(26, errors)
        assert.are.equal(6, misdirections)
        local first = addon.currentCombat.events[1]
        assert.are.equal('Бочок', first.source.name)
        assert.are.equal('WARRIOR', first.source.class)
        assert.is_truthy(Journal.Format(first):find('|cFFC79C6EБочок|r', 1, true))
        local taunt = addon.currentCombat.events[6]
        assert.is_nil(taunt.icon)
        assert.are.equal(355, taunt.spellId)
        local goo = addon.currentCombat.events[10]
        assert.are.equal('Профессор Мерзоцид', goo.source.name)
        assert.are.equal('Чародей', goo.target.name)
        assert.is_truthy(Journal.Format(goo):find('|cFF69CCF0Чародей|r', 1, true))
        assert.is_nil(Journal.Format(goo):find('Профессор Мерзоцид', 1, true))
        local gas = addon.currentCombat.events[11]
        assert.is_nil(gas.source)
        assert.are.equal('Стрелок', gas.target.name)
        assert.is_truthy(Journal.Format(gas):find('|cFFABD473Стрелок|r', 1, true))
        assert.is_nil(addon.currentCombat.events[12].source)
        for i, player in ipairs({ 'Чародей', 'Целитель' }) do
            local spirit = addon.currentCombat.events[13 + i]
            assert.are.equal('SPIRIT_HIT', spirit.kind)
            assert.are.equal('Мстительный дух', spirit.source.name)
            assert.are.equal(player, spirit.target.name)
            assert.are.equal('TACTIC_VIOLATION', spirit.type)
            assert.are.equal(i == 1 and 344 or 194, spirit.amount)
            assert.are.equal('Взорвал духа ' .. spirit.amount, spirit.text)
        end
        assert.are.equal('Духов взорвали: всего 2 Целитель(1) Чародей(1)',
            addon.currentCombat.events[16].text)
        for i = 17, 18 do
            local death = addon.currentCombat.events[i]
            assert.are.equal('MECHANIC_DEATH', death.kind)
            assert.are.equal('TACTIC_VIOLATION', death.type)
            assert.are.equal('Темный шар', death.source.name)
            assert.are.equal(77846, death.spellId)
            assert.are.equal('Умер в лезвиях', death.text)
            assert.is_nil(death.icon)
            assert.is_truthy(Journal.Format(death):find(death.target.name, 1, true))
        end
    end)

    it('matches demo spirit hits and blade deaths to records emitted by their trackers', function()
        addon:DemoJournal()
        local demoSpirit = addon.currentCombat.events[14]
        local demoDeath = addon.currentCombat.events[17]

        lady:handleEvent(blizzardEvent(2000, 'SPELL_SUMMON', 'demo-lady', 'Леди Смертный Шепот',
            0xa48, 'demo-spirit-1', 'Мстительный дух', 0xa48, 71426, 'Призыв духа', 1))
        lady:handleEvent(blizzardEvent(2001, 'SWING_DAMAGE', 'demo-spirit-1', 'Мстительный дух',
            0xa48, 'demo-mage', 'Чародей', 0x514, 344, 0, 1, 0, 0, 0))
        local actualSpirit = addon.currentCombat.events[#addon.currentCombat.events]

        halion:handleEvent(blizzardEvent(2002, 'SPELL_DAMAGE', 'demo-orb', 'Темный шар',
            0xa48, 'demo-mage', 'Чародей', 0x514, 77846, 'Лезвие сумерек', 0x20,
            26977, 0, 32, 0, 0, 0))
        halion:handleEvent(blizzardEvent(2005, 'UNIT_DIED', nil, nil, 0x80000000,
            'demo-mage', 'Чародей', 0x514))
        local actualDeath = addon.currentCombat.events[#addon.currentCombat.events]

        for _, field in ipairs({ 'kind', 'type', 'source', 'target', 'spellId', 'amount', 'text', 'icon' }) do
            assert.are.same(demoSpirit[field], actualSpirit[field])
            assert.are.same(demoDeath[field], actualDeath[field])
        end
    end)

    it('includes every journal kind and every SpellTracker ability in V2 demo', function()
        addon:DemoJournal()
        local kinds, abilities = {}, {}
        for _, entry in ipairs(addon.currentCombat.events) do
            kinds[entry.kind] = true
            if entry.spellId then abilities[entry.spellId] = true end
        end
        for _, kind in ipairs({ 'FIRST_DAMAGE', 'FIRST_HEAL', 'TAUNT', 'SPELL_USE', 'DISPEL', 'RESURRECT',
            'VORTEX_HIT', 'VORTEX_MISSED', 'BLOODBOLT_SPLASH', 'MANA_BARRIER_REMOVED', 'MIND_CONTROL',
            'CYCLONE_APPLIED', 'CYCLONE_MISSED', 'SPIRIT_HIT', 'SPIRIT_MISSED', 'SPIRIT_SUMMARY',
            'MALLEABLE_GOO', 'CHOKING_GAS', 'MALLEABLE_GOO_SUMMARY', 'CHOKING_GAS_SUMMARY',
            'SHADOW_TRAP', 'RAGING_SPIRIT', 'TRAMPLE_HIT', 'FIRST_TWILIGHT_ENTRY', 'FIRST_LIGHT_DAMAGE',
            'LIGHT_DAMAGE_WINDOW_CLOSED', 'MECHANIC_DEATH', 'MISDIRECTION_START', 'MISDIRECTION_DAMAGE',
            'MISDIRECTION_SUMMARY' }) do
            assert.is_true(kinds[kind], kind)
        end
        for _, spellId in ipairs({ 355, 694, 1161, 49560, 51399, 56222, 62124, 31789, 5209, 20736,
            34600, 10278, 1044, 19752, 6940, 31821, 48817, 49016, 26994, 48477,
            475, 526, 527, 528, 552, 988, 1152, 2782, 4987, 10872, 32375, 32592, 51886 }) do
            assert.is_true(abilities[spellId], tostring(spellId))
        end
    end)

    it('keeps Lady cyclones informational in live tracking and V2 demo', function()
        addon:DemoJournal()
        local examples = {}
        for _, entry in ipairs(addon.currentCombat.events) do examples[entry.kind] = entry end
        addon.currentCombat.firstEnemy = 'Леди Смертный Шепот'
        for i, subevent in ipairs({ 'SPELL_AURA_APPLIED', 'SPELL_MISSED' }) do
            local raw = event(subevent, 33786, 'demo-druid', 'demo-mage')
            raw.sourceName, raw.destName = 'Лист', 'Чародей'
            raw.sourceClass, raw.destClass = 'DRUID', 'MAGE'
            if i == 2 then raw.missType = 'IMMUNE' end
            lady:handleEvent(raw)
            local actual = addon.currentCombat.events[#addon.currentCombat.events]
            assert.are.equal(i == 1 and 'CYCLONE_APPLIED' or 'CYCLONE_MISSED', actual.kind)
            assert.are.equal('INFO', actual.type)
            assert.is_false(Journal.Visible(actual, 'ERRORS'))
            for _, field in ipairs({ 'kind', 'type', 'source', 'target', 'spellId', 'missType', 'text', 'icon' }) do
                assert.are.same(examples[actual.kind][field], actual[field])
            end
        end
    end)

    it('keeps demo summaries informational and identical to tracker totals', function()
        addon:DemoJournal()
        local demo = addon.currentCombat.events
        local expected = { demo[12], demo[13], demo[16] }
        local count = #demo
        professor.malleableGooReport = { ['Чародей'] = 1 }
        professor.chokingGasReport = { ['Стрелок'] = 1 }
        lady.report = { ['Целитель'] = 1, ['Чародей'] = 1 }
        professor:summarizeCombat()
        lady:summarizeCombat()
        for i, example in ipairs(expected) do
            local actual = addon.currentCombat.events[count + i]
            assert.are.equal('INFO', actual.type)
            assert.is_false(Journal.Visible(actual, 'ERRORS'))
            assert.is_false(Journal.Visible(example, 'ERRORS'))
            assert.is_true(Journal.Visible(actual, 'ALL'))
            for _, field in ipairs({ 'kind', 'type', 'source', 'target', 'spellId', 'text', 'icon' }) do
                assert.are.same(example[field], actual[field])
            end
        end
    end)

    it('matches demo vortex hits and misses to the healer tracker classification', function()
        addon:DemoJournal()
        mocks.raidSize = 1
        mocks:SetRaidRosterInfo(1, 'Целитель', 5, 'Жрец', 'PRIEST')
        for i, subevent in ipairs({ 'SPELL_DAMAGE', 'SPELL_MISSED' }) do
            local demoEntry = addon.currentCombat.events[18 + i]
            local raw = event(subevent, 72817, 'demo-mage', 'demo-priest', 2000)
            raw.sourceName, raw.destName = 'Чародей', 'Целитель'
            raw.sourceClass, raw.destClass = 'MAGE', 'PRIEST'
            if i == 1 then raw.amount = 5000 else raw.missType = 'IMMUNE' end
            princes:handleEvent(raw)
            local actual = addon.currentCombat.events[#addon.currentCombat.events]
            assert.are.equal(i == 1 and 'VORTEX_HIT' or 'VORTEX_MISSED', actual.kind)
            assert.are.equal('TACTIC_VIOLATION', actual.type)
            assert.is_true(Journal.Visible(actual, 'ERRORS'))
            for _, field in ipairs({ 'kind', 'type', 'source', 'target', 'spellId', 'amount', 'missType', 'text', 'icon' }) do
                assert.are.same(demoEntry[field], actual[field])
            end
        end
    end)

    it('classifies each tracked Halion mechanic death as a violation', function()
        for _, spellId in ipairs({ 75879, 75949, 77844, 77845, 77846 }) do
            local damage = event('SPELL_DAMAGE', spellId, 'orb', 'player')
            damage.destFlags = 0x514
            halion:handleEvent(damage)
            local death = event('UNIT_DIED', nil, 'orb', 'player')
            death.destFlags = 0x514
            halion:handleEvent(death)
            local entry = addon.currentCombat.events[#addon.currentCombat.events]
            assert.are.equal('MECHANIC_DEATH', entry.kind)
            assert.are.equal(spellId, entry.spellId)
            assert.are.equal('TACTIC_VIOLATION', entry.type)
            assert.is_true(Journal.Visible(entry, 'ERRORS'))
        end
    end)

    it('renders mechanic deaths with a skull followed by the specific cause and spell icon', function()
        _G.GetSpellInfo = function(id) return 'Spell', nil, 'Cause' .. id end
        for id, reason in pairs({
            [75879] = 'Умер от метеорита', [75949] = 'Умер в луже',
            [77844] = 'Умер в лезвиях', [77845] = 'Умер в лезвиях', [77846] = 'Умер в лезвиях',
        }) do
            local entry = Journal.Create('MECHANIC_DEATH', event('UNIT_DIED', id), 'TACTIC_VIOLATION')
            assert.are.equal(reason, entry.text)
            entry.text = 'Смерть после попадания механики' -- Previously saved records.
            for _, record in ipairs({ entry, Journal.Copy(entry) }) do
                local text = Journal.Format(record, true)
                local skull = assert(text:find('UI-RaidTargetingIcon_8:24:24:0:-2|t', 1, true))
                local cause = assert(text:find(reason .. ' |TCause' .. id .. ':24:24:0:-2|t', 1, true))
                assert.is_true(skull < cause)
            end
        end
    end)

    it('renders a spirit icon for spell-less melee events live and from history', function()
        for _, kind in ipairs({ 'SPIRIT_HIT', 'SPIRIT_MISSED' }) do
            local entry = Journal.Create(kind, event('SWING_DAMAGE'))
            entry.spellId = nil
            for _, record in ipairs({ entry, Journal.Copy(entry) }) do
                assert.is_truthy(Journal.Format(record):find('spell_shadow_deathsembrace:24:24:0:-2|t', 1, true))
            end
        end
    end)

    it('opens demo in All so informational druid control is visible after using Errors', function()
        addon:SetJournalView('ERRORS')
        addon.mainFrame.Show = function() end
        addon:HandleSlashCommand('demo')
        assert.are.equal('ALL', addon.journalView)
        local found = false
        for _, text in ipairs(lines) do
            if text:find('Контроль циклоном', 1, true) then
                assert.is_truthy(text:find('Лист', 1, true))
                assert.is_truthy(text:find('Чародей', 1, true))
                found = true
            end
        end
        assert.is_true(found)
    end)

    it('opens the V2 demo from a saved combat so its filters show the new records', function()
        addon.displayedCombat = { events = {} }
        local shown = false
        addon.mainFrame.Show = function() shown = true end
        addon:HandleSlashCommand('demo')
        assert.are.equal('current', addon.selectedCombatKind)
        assert.are.equal(addon.currentCombat, addon.displayedCombat)
        assert.is_true(shown)
        assert.are.equal(68, #addon.currentCombat.events)
        addon:SetJournalView('ERRORS')
        assert.is_true(#lines > 0)
        addon:SetJournalView('MISDIRECTION')
        assert.is_true(#lines > 0)
    end)

    it('records existing boss mechanics using addon kinds', function()
        professor:handleEvent(event('SPELL_AURA_APPLIED', 71278))
        professor:handleEvent(event('SPELL_AURA_APPLIED', 70853))
        professor:summarizeCombat()
        queen:handleEvent(event('SPELL_DAMAGE', 71483))
        lich:handleEvent(event('SPELL_CAST_SUCCESS', 69200))
        trial.AreChampionMarksDone = function() return true end
        trial:handleEvent(event('SPELL_DAMAGE', 66734))
        local expected = { 'CHOKING_GAS', 'MALLEABLE_GOO', 'MALLEABLE_GOO_SUMMARY',
            'CHOKING_GAS_SUMMARY', 'BLOODBOLT_SPLASH', 'RAGING_SPIRIT', 'TRAMPLE_HIT' }
        for i, kind in ipairs(expected) do assert.are.equal(kind, addon.currentCombat.events[i].kind) end
    end)

    it('routes raw simultaneous game events through dispatcher to V2 history', function()
        addon.IterateModules = function() return ipairs({ pulls }) end
        addon.inCombat = true
        addon.currentCombat.startTime = 1000
        cast('hunter', 'tank')
        for _, target in ipairs({ 'enemy1', 'enemy2' }) do
            addon:COMBAT_LOG_EVENT_UNFILTERED('COMBAT_LOG_EVENT_UNFILTERED', 1001.375, 'SPELL_DAMAGE',
                'hunter', 'Hunter', 0x514, target, target, 0xa48, 53209, 'Chimera Shot', 1,
                100, 0, 1, 0, 0, 0, false, false, false)
        end
        addon:FinishCombat('test')
        local entries = addon.db.char.combatHistoryV2.combats[1].events
        assert.are.equal(4, #entries)
        assert.are.equal(1001.375, entries[2].timestamp)
        assert.are.equal(1001.375, entries[3].timestamp)
        assert.are.equal('enemy1', entries[2].target.guid)
        assert.are.equal('enemy2', entries[3].target.guid)
        assert.are.equal(200, entries[4].amount)
    end)

    it('keeps completed details visible until the next fight unless history was explicitly selected', function()
        addon.inCombat = true
        addon.currentCombat.startTime = 1000
        cast('hunter', 'tank')
        pulls:handleEvent(event('SPELL_DAMAGE', 53209, 'hunter', 'enemy', 1001, 77))
        addon:FinishCombat('test')
        assert.are.equal(77, Journal.PullTargets(addon.displayedCombat, 1)[1].amount)
        addon:SetJournalView('MISDIRECTION')
        assert.are.equal(3, #lines)
        addon:StartCombat('next')
        assert.are.equal(addon.currentCombat, addon.displayedCombat)
        assert.are.equal(0, #lines)
    end)

    it('connects filter buttons and a tooltip to the displayed historical pull', function()
        local function frame()
            return setmetatable({ scripts = {} }, { __index = function(_, key)
                if key == 'SetScript' then return function(self, name, fn) self.scripts[name] = fn end end
                if key == 'GetFontString' or key == 'CreateFontString' or key == 'CreateTexture' then return frame end
                if key == 'IsShown' then return function() return false end end
                if key == 'GetFont' then return function() return 'Fonts\\FRIZQT__.TTF', 12 end end
                if key == 'GetSpacing' then return function() return 0 end end
                if key == 'GetHeight' then return function() return 400 end end
                if key == 'GetWidth' then return function() return 400 end end
                if key == 'GetStringHeight' then return function() return 24 end end
                if key == 'GetVerticalScroll' or key == 'GetVerticalScrollRange' then return function() return 0 end end
                -- Data fields must stay nil; only emulate frame methods.
                if key:match('^[A-Z]') then return function() end end
            end })
        end
        _G.CreateFrame = frame
        local tooltipRows, hidden = {}, false
        _G.GameTooltip = {
            SetOwner = function() end, AddLine = function() end, Show = function() end,
            AddDoubleLine = function(_, name, amount) tooltipRows[#tooltipRows + 1] = { name, amount } end,
            Hide = function() hidden = true end,
        }
        addon:CreateMainFrame()
        local filterNames = {}
        for name in pairs(addon.mainFrame.journalFilterButtons) do
            filterNames[#filterNames + 1] = name
        end
        table.sort(filterNames)
        assert.are.same({ 'ALL', 'ERRORS', 'MISDIRECTION' }, filterNames)
        addon.mainFrame.journalFilterButtons.ERRORS.scripts.OnClick()
        assert.are.equal('ERRORS', addon.journalView)
        local history = { events = {
            Journal.Create('MISDIRECTION_DAMAGE', event('SWING_DAMAGE', nil, 'hunter', 'OldEnemy', 1001, 250),
                'INFO', { pullId = 4 }),
            Journal.Create('MISDIRECTION_SUMMARY', { timestamp = 1002 }, 'INFO', { pullId = 4, amount = 250 }),
        } }
        addon:DisplayCombat(history)
        addon.mainFrame.journalFilterButtons.MISDIRECTION.scripts.OnClick()
        assert.are.equal('MISDIRECTION', addon.journalView)
        local log = addon.mainFrame.logText
        log.scripts.OnHyperlinkEnter(log, 'rlhpull:4')
        assert.are.same({ { 'OldEnemy', '250' } }, tooltipRows)
        log.scripts.OnHyperlinkLeave()
        assert.is_true(hidden)
        assert.are.equal(0, #addon.currentCombat.events)
    end)
end)
