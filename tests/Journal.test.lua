local mocks = require('tests.mocks')
local Journal = require('lib.Journal')
require('../lib/blizzardEvent')
require('../lib/CombatFilters')
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

describe('Structured journal', function()
    local oldRoster, oldClass, oldIterate, oldSend, oldFrame, oldTooltip, oldSpellInfo, lines

    before_each(function()
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
        addon.db = { profile = { journalV2 = true }, char = { combatHistory = { { messages = { 'old' } } } } }
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
        _G.GetRaidRosterInfo, _G.UnitClass = oldRoster, oldClass
        _G.CreateFrame, _G.GameTooltip = oldFrame, oldTooltip
        _G.GetSpellInfo = oldSpellInfo
        addon.IterateModules, addon.SendMessage = oldIterate, oldSend
        addon.journalV2Enabled = false
        addon:StopCombatTicker()
        mocks.raidSize = 0
    end)

    it('starts V2 empty without reading or converting legacy records', function()
        assert.are.equal(0, #addon.combatHistory)
        assert.are.same({ { messages = { 'old' } } }, addon.db.char.combatHistory)
        assert.is_nil(addon.currentCombat.messages)
        assert.are.equal(2, addon.db.char.combatHistoryV2.schemaVersion)
    end)

    it('preserves timestamp, actors, classes and both spells through save/reload', function()
        mocks:SetUnitGUID('player', 'priest')
        _G.UnitClass = function() return 'Жрец', 'PRIEST' end
        local dispel = event('SPELL_DISPEL', 988, 'priest', 'tank')
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
        assert.are.equal('old', addon.db.char.combatHistory[1].messages[1])
    end)

    it('switches only on reload and V1 writes do not change V2', function()
        addon.currentCombat.startTime = 1000
        addon:OnCombatLogEvent(Journal.Create('FIRST_DAMAGE', event('SWING_DAMAGE')))
        addon:HandleSlashCommand('journal v1')
        assert.is_true(addon.journalV2Enabled)
        addon:FinishCombat('test')
        local v2 = Journal.Copy(addon.db.char.combatHistoryV2)
        addon:InitializeJournal()
        assert.is_false(addon.journalV2Enabled)
        assert.are.equal('old', addon.combatHistory[1].messages[1])
        addon:ResetCombatState()
        addon:OnCombatLogEvent('new legacy')
        addon.currentCombat.startTime = 1001
        addon:FinishCombat('test')
        assert.are.same(v2, addon.db.char.combatHistoryV2)
        assert.are.equal('new legacy', addon.db.char.combatHistory[1].messages[1])
        addon:HandleSlashCommand('journal v2')
        addon:InitializeJournal()
        assert.are.same(v2.combats, addon.combatHistory)
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
        assert.are.equal('old', addon.db.char.combatHistory[1].messages[1])
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

    it('classifies only known non-tanks as taunt violations', function()
        mocks.raidSize = 2
        mocks:SetUnitGUID('raid1', 'tank')
        mocks:SetUnitGUID('raid2', 'dps')
        _G.GetRaidRosterInfo = function(i)
            return i == 1 and 'Tank' or 'Dps', nil, 1, nil, nil, 'WARRIOR', nil, nil, nil,
                i == 1 and 'MAINTANK' or nil
        end
        spells:handleEvent(event('SPELL_AURA_APPLIED', 355, 'tank'))
        spells:handleEvent(event('SPELL_AURA_APPLIED', 355, 'dps'))
        spells:handleEvent(event('SPELL_AURA_APPLIED', 355, 'unknown'))
        local entries = addon.currentCombat.events
        assert.are.equal('INFO', entries[1].type)
        assert.are.equal('TACTIC_VIOLATION', entries[2].type)
        assert.are.equal('TAUNT', entries[2].kind)
        assert.are.equal('INFO', entries[3].type)
        assert.is_truthy(lines[2]:find('[НАРУШЕНИЕ]', 1, true))
        _G.GetRaidRosterInfo = function() return 'Dps' end
        spells:handleEvent(event('SPELL_AURA_APPLIED', 355, 'dps'))
        assert.are.equal('INFO', entries[4].type)
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

    it('renders first damage and healing like V1 without using their spell icons', function()
        _G.GetSpellInfo = function() return 'Spell', nil, 'SpellTexture' end
        spells:handleEvent(event('SPELL_DAMAGE', 53209, 'Hunter', 'Boss', 1001, 100))
        spells:handleEvent(event('SPELL_HEAL', 48782, 'Healer', 'Валитрия Сноходица', 1002, 200))
        local expected = {
            date('%H:%M:%S', 1001) .. ' |cFFFFFFFFHunter|r Первый урон по |cFFFFFFFFBoss|r',
            date('%H:%M:%S', 1002) .. ' |cFFFFFFFFHealer|r Первый хил по |cFFFFFFFFВалитрия Сноходица|r',
        }
        assert.are.same(expected, lines)
        assert.are.equal(53209, addon.currentCombat.events[1].spellId)
        addon:DisplayCombat(Journal.Copy(addon.currentCombat))
        assert.are.same(expected, lines)
        local ability = Journal.Create('SPELL_USE', event('SPELL_CAST_SUCCESS', 53209))
        assert.is_truthy(Journal.Format(ability):find('|TSpellTexture:', 1, true))
    end)

    it('renders the entire violation message in red, including any highlighted names', function()
        local entry = Journal.Create('SHADOW_TRAP', event('SPELL_DAMAGE', 73529), 'TACTIC_VIOLATION', {
            text = '|cFFFFFFFFPlayer|r взорвал ловушку',
        })
        addon:OnCombatLogEvent(entry)
        local expected = '|cFFFF0000[НАРУШЕНИЕ] ' .. date('%H:%M:%S', entry.timestamp) ..
            ' Player взорвал ловушку|r'
        assert.are.equal(expected, lines[1])
        addon:DisplayCombat(Journal.Copy(addon.currentCombat))
        assert.are.equal(expected, lines[1])
        assert.is_nil(Journal.Format(Journal.Create('SPELL_USE', event('SPELL_CAST_SUCCESS'))):find('|cFFFF0000', 1, true))
    end)

    it('filters hunter damage like V1 while retaining all damage in totals and saved target details', function()
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
                assert.is_truthy(lines[#lines]:find(caster[1] .. ' → ' .. target, 1, true))
                assert.is_truthy(lines[#lines]:find(tostring(i * 100), 1, true))
                assert.is_nil(lines[#lines]:find('Tank', 1, true))
            end
        end
        addon:FinishCombat('test')
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
        addon:SetJournalView('DEATHS')
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

    it('filters saved history without switching live event collection into that combat', function()
        local historic = { events = { Journal.Create('MECHANIC_DEATH', event('UNIT_DIED')) } }
        addon:DisplayCombat(historic)
        local before = #lines
        queen:handleEvent(event('SPELL_DAMAGE', 71483))
        assert.are.equal(before, #lines)
        assert.are.equal(1, #addon.currentCombat.events)
        assert.are.equal(1, #historic.events)
        addon:SetJournalView('DEATHS')
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

    it('writes structured demo records only', function()
        addon:DemoJournal()
        assert.is_true(#addon.currentCombat.events > 20)
        for _, entry in ipairs(addon.currentCombat.events) do
            assert.is_string(entry.kind)
            assert.is_string(entry.text)
            assert.is_nil(entry.text:find('|c', 1, true))
        end
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
                if key == 'GetFontString' or key == 'CreateFontString' then return frame end
                if key == 'IsShown' then return function() return false end end
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
