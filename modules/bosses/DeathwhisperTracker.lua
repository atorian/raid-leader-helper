local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local DeathwhisperTracker = RLHelper:NewModule("DeathwhisperTracker", "AceEvent-3.0")
DeathwhisperTracker.receivesCombatEvents = true

local TRACKED_SPELLS = {
    [71426] = "spirit_summon" -- Призыв духа
}
local LADY_DEATHWHISPER_MANA_BARRIER = 70842

local icon = "Interface\\Icons\\spell_shadow_deathsembrace"

function DeathwhisperTracker:OnInitialize()
    RLHelper:Debug("DeathwhisperTracker: Инициализация")
    self.currentSpirits = {}
    self.report = {}
    self.log = function(...)
        RLHelper:OnCombatLogEvent(...)
    end
    self:RegisterMessage("RLHelper_CombatEnding", "summarizeCombat")
    self:RegisterMessage("RLHelper_CombatEnded", "reset")
    self:RegisterMessage("RLHelper_Demo", "demo")
end

function DeathwhisperTracker:OnEnable()
    RLHelper:Debug("DeathwhisperTracker: Включен")
end

local function formatShieldBroken(ts)
    return string.format("%s Леди: Щит разбит", date("%H:%M:%S", ts))
end

local function buildSpiritHitSummary(report)
    local names = {}
    local total = 0

    for name, count in pairs(report) do
        total = total + count
        table.insert(names, name)
    end

    if total == 0 then
        return nil
    end

    table.sort(names, function(a, b)
        if report[a] == report[b] then
            return a < b
        end

        return report[a] > report[b]
    end)

    local details = {}
    for _, name in ipairs(names) do
        table.insert(details, string.format("%s(%s)", name, report[name]))
    end

    return {
        total = total,
        details = table.concat(details, " ")
    }
end

local function formatSpiritHitSummary(ts, total, details)
    return string.format("%s Духи ударили: всего %s %s", date("%H:%M:%S", ts), total, details)
end

-- function DeathwhisperTracker:ZONE_CHANGED_NEW_AREA()
-- local 
-- if 
-- end

-- function DeathwhisperTracker:PLAYER_ENTERING_WORLD()
--
-- end

function DeathwhisperTracker:reset()
    self.currentSpirits = {}
    self:sendSummaryToRaid()
    self.report = {}
end

function DeathwhisperTracker:summarizeCombat()
    local summary = buildSpiritHitSummary(self.report or {})
    if not summary then
        return
    end

    self.log(formatSpiritHitSummary(time(), summary.total, summary.details))
end

function DeathwhisperTracker:sendSummaryToRaid()
    local summary = buildSpiritHitSummary(self.report or {})
    if not summary then
        return
    end

    SendChatMessage(string.format("Духи ударили: всего %s %s", summary.total, summary.details), "RAID")
end

local function formatSpiritHit(ts, dest)
    return string.format("%s Дух ударил |cFFFFFFFF%s|r |T%s:24:24:0:0|t", date("%H:%M:%S", ts), dest, icon)
end

local function formatSpiritMiss(ts, dest)
    return string.format("%s Дух автоатачил |cFFFFFFFF%s|r", date("%H:%M:%S", ts), dest)
end

local function consumeTrackedSpirit(self, guid)
    local spiritInfo = self.currentSpirits[guid]
    if not spiritInfo then
        return nil
    end

    self.currentSpirits[guid] = nil
    return spiritInfo
end

function DeathwhisperTracker:handleEvent(eventData)
    if eventData.event == "SPELL_AURA_REMOVED" and eventData.spellId == LADY_DEATHWHISPER_MANA_BARRIER then
        self.log(formatShieldBroken(eventData.timestamp))
        return
    end

    if eventData.event == "SPELL_SUMMON" and eventData.spellId == 71426 then
        self.currentSpirits[eventData.destGUID] = {
            name = eventData.destName,
            summonTime = eventData.timestamp
        }
        return
    end

    if eventData.event == "SWING_DAMAGE" then
        local spiritInfo = consumeTrackedSpirit(self, eventData.sourceGUID)
        if not spiritInfo then
            return
        end

        self.report[eventData.destName] = self.report[eventData.destName] or 0
        self.report[eventData.destName] = self.report[eventData.destName] + 1

        self.log(formatSpiritHit(eventData.timestamp, eventData.destName))
        return
    end

    if eventData.event == "SWING_MISSED" then
        local spiritInfo = consumeTrackedSpirit(self, eventData.sourceGUID)
        if not spiritInfo then
            return
        end

        self.log(formatSpiritMiss(eventData.timestamp, eventData.destName))
        return
    end
end

function DeathwhisperTracker:demo()
    self.log(formatShieldBroken(time()))
    self.log(formatSpiritHit(time(), "Player"))
    self.log(formatSpiritMiss(time(), "Lucky"))
    self.report = {
        ["Player"] = 2
    }
    self:summarizeCombat()
    self.report = {}
end

return DeathwhisperTracker
