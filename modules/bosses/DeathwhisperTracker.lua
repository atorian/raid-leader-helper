-- TODO: enable only when entering ICC
local TestAddon = LibStub("AceAddon-3.0"):GetAddon("RlHelper")
local DeathwhisperTracker = TestAddon:NewModule("DeathwhisperTracker", "AceEvent-3.0")
DeathwhisperTracker.receivesCombatEvents = true
DeathwhisperTracker.zoneGateInstanceId = 631 -- Icecrown Citadel

local TRACKED_SPELLS = {
    [71809] = "spirit_attack", -- Spirit Attack (Атака духа)
    [71426] = "spirit_summon", -- Призыв духа
    [72010] = "vengeful_blast" -- Вспышка мщения
}
local LADY_DEATHWHISPER_MANA_BARRIER = 70842

local icon = "Interface\\Icons\\spell_shadow_deathsembrace"

function DeathwhisperTracker:OnInitialize()
    TestAddon:Debug("DeathwhisperTracker: Инициализация")
    self.currentSpirits = {}
    self.report = {}
    self.log = function(...)
        TestAddon:OnCombatLogEvent(...)
    end
    self:RegisterMessage("TestAddon_CombatEnding", "summarizeCombat")
    self:RegisterMessage("TestAddon_CombatEnded", "reset")
    self:RegisterMessage("TestAddon_Demo", "demo")
end

function DeathwhisperTracker:OnEnable()
    TestAddon:Debug("DeathwhisperTracker: Включен")
end

local function formatShieldBroken(ts)
    return string.format("%s Леди: Щит разбит", date("%H:%M:%S", ts))
end

local function buildSpiritExplosionSummary(report)
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

local function formatSpiritExplosionSummary(ts, total, details)
    return string.format("%s Духов взорвали: всего %s %s", date("%H:%M:%S", ts), total, details)
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
    local summary = buildSpiritExplosionSummary(self.report or {})
    if not summary then
        return
    end

    self.log(formatSpiritExplosionSummary(time(), summary.total, summary.details))
end

function DeathwhisperTracker:sendSummaryToRaid()
    local summary = buildSpiritExplosionSummary(self.report or {})
    if not summary then
        return
    end

    SendChatMessage(string.format("Духов взорвали: всего %s %s", summary.total, summary.details), "RAID")
end

local function formatSpiritHit(ts, dest)
    return string.format("%s |cFFFFFFFF%s|r взорвал духа |T%s:24:24:0:0|t", date("%H:%M:%S", ts), dest, icon)
end

local function formatSpiritMiss(ts, dest)
    return string.format("%s Дух автоатачил |cFFFFFFFF%s|r", date("%H:%M:%S", ts), dest)
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
        local spiritInfo = self.currentSpirits[eventData.sourceGUID]
        if not spiritInfo then
            return
        end

        self.report[eventData.destName] = self.report[eventData.destName] or 0
        self.report[eventData.destName] = self.report[eventData.destName] + 1

        self.log(formatSpiritHit(eventData.timestamp, eventData.destName))
        return
    end

    if eventData.event == "SWING_MISSED" then
        local spiritInfo = self.currentSpirits[eventData.sourceGUID]
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
