local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local PutricideTracker = RLHelper:NewModule("PutricideTracker", "AceEvent-3.0")

PutricideTracker.receivesCombatEvents = true
PutricideTracker.zoneGateInstanceId = 631 -- Icecrown Citadel
PutricideTracker.bossIds = {
    [36678] = "Профессор Мерзоцид"
}

local MALLEABLE_GOO_SPELLS = {
    [70853] = true,
    [72297] = true,
    [72458] = true,
    [72548] = true,
    [72549] = true,
    [72550] = true,
    [72873] = true,
    [72874] = true
}
local CHOKING_GAS_SPELLS = {
    [71278] = true, -- Normal 10
    [72460] = true, -- Normal 25
    [72619] = true, -- Heroic 10
    [72620] = true  -- Heroic 25
}

function PutricideTracker:OnInitialize()
    RLHelper:Debug("PutricideTracker: Инициализация")
    self.malleableGooReport = {}
    self.chokingGasReport = {}
    self.log = function(...)
        RLHelper:OnCombatLogEvent(...)
    end
    self:RegisterMessage("RLHelper_CombatEnding", "summarizeCombat")
    self:RegisterMessage("RLHelper_CombatEnded", "reset")
end

function PutricideTracker:OnEnable()
    RLHelper:Debug("PutricideTracker: Включен")
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

function PutricideTracker:reset()
    self.malleableGooReport = {}
    self.chokingGasReport = {}
end

function PutricideTracker:summarizeCombat()
    local malleableGooSummary = buildMalleableGooSummary(self.malleableGooReport)
    if malleableGooSummary then
        RLHelperJournal.Log(self.log, "MALLEABLE_GOO_SUMMARY", nil, "INFO", {
            text = string.format("Вязкая гадость: всего %s %s", malleableGooSummary.total, malleableGooSummary.details)
        })
    end

    local chokingGasSummary = buildMalleableGooSummary(self.chokingGasReport)
    if chokingGasSummary then
        RLHelperJournal.Log(self.log, "CHOKING_GAS_SUMMARY", nil, "INFO", {
            text = string.format("Удушливый газ: всего %s %s", chokingGasSummary.total, chokingGasSummary.details)
        })
    end
end

function PutricideTracker:handleEvent(event)
    if event.event == "SPELL_AURA_APPLIED" and CHOKING_GAS_SPELLS[event.spellId] and event.destName then
        self.chokingGasReport[event.destName] = (self.chokingGasReport[event.destName] or 0) + 1
        RLHelperJournal.Log(self.log, "CHOKING_GAS", event, "TACTIC_VIOLATION")
        return
    end

    if event.event ~= "SPELL_AURA_APPLIED" or not MALLEABLE_GOO_SPELLS[event.spellId] or not event.destName then
        return
    end

    self.malleableGooReport[event.destName] = (self.malleableGooReport[event.destName] or 0) + 1
    RLHelperJournal.Log(self.log, "MALLEABLE_GOO", event, "TACTIC_VIOLATION")
end

PutricideTracker.demoOrder = 3
function PutricideTracker:RunDemo(demo)
    self:reset()
    demo:Event(self, "SPELL_AURA_APPLIED", demo:Boss(36678, "Профессор Мерзоцид"), demo.players.mage, 70853)
    demo:Event(self, "SPELL_AURA_APPLIED", nil, demo.players.hunter, 71278)
    self:summarizeCombat()
end


return PutricideTracker
