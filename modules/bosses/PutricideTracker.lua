local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local PutricideTracker = RLHelper:NewModule("PutricideTracker", "AceEvent-3.0")

PutricideTracker.receivesCombatEvents = true
PutricideTracker.zoneGateInstanceId = 631 -- Icecrown Citadel
PutricideTracker.bossIds = {
    [36678] = "Профессор Мерзоцид"
}

local PROFESSOR_PUTRICIDE = "Профессор Мерзоцид"
local MALLEABLE_GOO_SPELLS = {
    [70853] = true, -- Normal 10
    [72550] = true,
    [72873] = true, -- Heroic 10
    [72874] = true
}
local malleableGooIcon = "Interface\\Icons\\INV_Misc_Herb_EvergreenMoss"

function PutricideTracker:OnInitialize()
    RLHelper:Debug("PutricideTracker: Инициализация")
    self.log = function(...)
        RLHelper:OnCombatLogEvent(...)
    end
end

function PutricideTracker:OnEnable()
    RLHelper:Debug("PutricideTracker: Включен")
end

local function isPutricideCombat()
    return RLHelper.currentCombat and RLHelper.currentCombat.firstEnemy == PROFESSOR_PUTRICIDE
end

local function formatMalleableGoo(ts, destName)
    return string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t Вязкая гадость", date("%H:%M:%S", ts),
        destName, malleableGooIcon)
end

function PutricideTracker:handleEvent(event)
    if not isPutricideCombat() then
        return
    end

    if event.event ~= "SPELL_AURA_APPLIED" or not MALLEABLE_GOO_SPELLS[event.spellId] or not event.destName then
        return
    end

    self.log(formatMalleableGoo(event.timestamp, event.destName))
end

return PutricideTracker
