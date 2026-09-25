local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local MisdirectionTracker = RLHelper:NewModule("MisdirectionTracker", "AceEvent-3.0")
MisdirectionTracker.receivesCombatEvents = true

-- hunt
local MISDIRECTION_START_SPELL_ID = 34477
local MISDIRECTION_SPELL_ID = 35079
-- roge
local SMALL_TRICKS_START_SPELL_ID = 57934
local SMALL_TRICKS_SPELL_ID = 59628
-- Список отслеживаемых способностей
local TRACKED_SPELLS = {
    -- Хант
    [34477] = true,
    [35079] = true,
    [58433] = true,
    [58434] = true,
    [53209] = true,
    [49050] = true,
    [49052] = true,
    [49045] = true,
    [34490] = true,
    [49048] = true,
    [49065] = true,
    [53353] = true,
    [53352] = true,
    [48996] = true, -- удар ящера
    [61006] = true, -- Килшот
    [53339] = true,
    [75] = true,
    [72817] = true,
    -- Рога
    [57934] = true,
    [59628] = true,
    [48638] = true,
    [2098] = true,
    [5171] = true,
    [13750] = true,
    [13877] = true,
    [11273] = true,
    [31224] = true,
    [1857] = true,
    [57970] = true,
    -- [57965] = true,
    [57841] = true,
    [57842] = true,
    [51723] = true, -- веер клинков
    [22482] = true, -- шквал клинков
    [52874] = true,
    [57993] = true,
    [48665] = true,
    [14278] = true,
    [48668] = true
}

local HUNTER_DAMAGE_EVENTS = {
    SPELL_DAMAGE = true,
    RANGE_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true,
    SWING_DAMAGE = true
}

local HUNTER_VISIBLE_SKIP_SPELLS = {
    [75] = true,
    [53353] = true
}

local function isHunterDamageVisible(spellId)
    return TRACKED_SPELLS[spellId] ~= nil and not HUNTER_VISIBLE_SKIP_SPELLS[spellId]
end

function MisdirectionTracker:OnEnable()
    RLHelper:Debug("RL Быдло: MisdirectionTracker включен")
end

function MisdirectionTracker:OnInitialize()
    self:RegisterMessage("RLHelper_CombatEnding", "finishJournalPulls")
    self:RegisterMessage("RLHelper_CombatEnded", "reset")
    self.log = function(...)
        RLHelper:OnCombatLogEvent(...)
    end
end

function MisdirectionTracker:reset()
    self.journalPulls = {}
    self.nextJournalPullId = 1
end

function MisdirectionTracker:startJournalPull(pull)
    if pull.started then return end
    pull.started = true
    self.log(RLHelperJournal.Copy(pull.entry))
end

function MisdirectionTracker:finishJournalPull(guid, timestamp)
    local pull = self.journalPulls[guid]
    if not pull then return end
    self:startJournalPull(pull)
    self.log(RLHelperJournal.Create("MISDIRECTION_SUMMARY", { timestamp = timestamp }, "INFO", {
        pullId = pull.entry.pullId, source = pull.entry.source, target = pull.entry.target,
        spellId = pull.entry.spellId, amount = pull.totalDamage
    }))
    self.journalPulls[guid] = nil
end

function MisdirectionTracker:finishJournalPulls()
    local pending = {}
    for guid, pull in pairs(self.journalPulls or {}) do
        pending[#pending + 1] = { guid = guid, id = pull.entry.pullId }
    end
    table.sort(pending, function(a, b) return a.id < b.id end)
    for _, pull in ipairs(pending) do self:finishJournalPull(pull.guid, time()) end
end

function MisdirectionTracker:handleEvent(event)
    self.journalPulls = self.journalPulls or {}
    self.nextJournalPullId = self.nextJournalPullId or 1
    local guid = event.sourceGUID
    if event.event == "SPELL_CAST_SUCCESS" and
        (event.spellId == MISDIRECTION_START_SPELL_ID or event.spellId == SMALL_TRICKS_START_SPELL_ID) then
        if not guid then return end
        self:finishJournalPull(guid, event.timestamp)
        local pull = {
            entry = RLHelperJournal.Create("MISDIRECTION_START", event, "INFO", { pullId = self.nextJournalPullId }),
            totalDamage = 0
        }
        self.nextJournalPullId = self.nextJournalPullId + 1
        self.journalPulls[guid] = pull
        if (self.context or RLHelper).inCombat then self:startJournalPull(pull) end
        return
    end
    if event.event == "SPELL_AURA_REMOVED" and
        (event.spellId == MISDIRECTION_SPELL_ID or event.spellId == SMALL_TRICKS_SPELL_ID) then
        local owner = self.journalPulls[guid] and guid or event.destGUID
        if owner then self:finishJournalPull(owner, event.timestamp) end
        return
    end
    local pull = guid and self.journalPulls[guid]
    if not pull or not HUNTER_DAMAGE_EVENTS[event.event] or event.timestamp < pull.entry.timestamp then return end
    self:startJournalPull(pull)
    pull.totalDamage = pull.totalDamage + (event.amount or 0)
    self.log(RLHelperJournal.Create("MISDIRECTION_DAMAGE", event, "INFO", {
        pullId = pull.entry.pullId,
        hidden = not TRACKED_SPELLS[event.spellId] or
            (pull.entry.spellId == MISDIRECTION_START_SPELL_ID and not isHunterDamageVisible(event.spellId))
    }))
end

MisdirectionTracker.demoOrder = 2
function MisdirectionTracker:RunDemo(demo)
    self:reset()
    local p = demo.players
    local boss = demo:Boss(36678, "Профессор Мерзоцид")
    demo:Event(self, "SPELL_CAST_SUCCESS", p.hunter, p.tank, MISDIRECTION_START_SPELL_ID)
    demo:Event(self, "SPELL_DAMAGE", p.hunter, boss, 53209, { amount = 1000 })
    demo:Event(self, "SPELL_AURA_REMOVED", p.hunter, p.hunter, MISDIRECTION_SPELL_ID)
end


return MisdirectionTracker
