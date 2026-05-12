local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local PutricideTracker = RLHelper:NewModule("PutricideTracker", "AceEvent-3.0")

PutricideTracker.receivesCombatEvents = true
PutricideTracker.zoneGateInstanceId = 631 -- Icecrown Citadel
PutricideTracker.bossIds = {
    [36678] = "Профессор Мерзоцид"
}

local PROFESSOR_PUTRICIDE = "Профессор Мерзоцид"
local FESTERGUT = "Тухлопуз"
local MALLEABLE_GOO_SPELLS = {
    [70853] = true, -- Normal 10
    [72550] = true,
    [72873] = true, -- Heroic 10
    [72874] = true
}
local malleableGooIcon = "Interface\\Icons\\INV_Misc_Herb_EvergreenMoss"

function PutricideTracker:OnInitialize()
    RLHelper:Debug("PutricideTracker: Инициализация")
    self.malleableGooReport = {}
    self.log = function(...)
        RLHelper:OnCombatLogEvent(...)
    end
    self:RegisterMessage("RLHelper_CombatEnding", "summarizeCombat")
    self:RegisterMessage("RLHelper_CombatEnded", "reset")
end

function PutricideTracker:OnEnable()
    RLHelper:Debug("PutricideTracker: Включен")
end

local function isMalleableGooCombat()
    return RLHelper.currentCombat and
        (RLHelper.currentCombat.firstEnemy == PROFESSOR_PUTRICIDE or RLHelper.currentCombat.firstEnemy == FESTERGUT)
end

local function formatMalleableGoo(ts, destName)
    return string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t Вязкая гадость", date("%H:%M:%S", ts),
        destName, malleableGooIcon)
end

local function buildMalleableGooSummary(report)
    local names = {}
    local total = 0

    for name, count in pairs(report or {}) do
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

local function formatMalleableGooSummary(ts, summary)
    return string.format("%s Вязкая гадость: всего %s %s", date("%H:%M:%S", ts), summary.total, summary.details)
end

function PutricideTracker:reset()
    self.malleableGooReport = {}
end

function PutricideTracker:summarizeCombat()
    local summary = buildMalleableGooSummary(self.malleableGooReport)
    if not summary then
        return
    end

    self.log(formatMalleableGooSummary(time(), summary))
end

function PutricideTracker:handleEvent(event)
    if not isMalleableGooCombat() then
        return
    end

    if event.event ~= "SPELL_AURA_APPLIED" or not MALLEABLE_GOO_SPELLS[event.spellId] or not event.destName then
        return
    end

    self.malleableGooReport[event.destName] = (self.malleableGooReport[event.destName] or 0) + 1
    self.log(formatMalleableGoo(event.timestamp, event.destName))
end

return PutricideTracker
