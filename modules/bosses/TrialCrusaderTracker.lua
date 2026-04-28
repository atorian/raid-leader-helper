local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local TrialCrusaderTracker = RLHelper:NewModule("TrialCrusaderTracker", "AceEvent-3.0")
TrialCrusaderTracker.receivesCombatEvents = true
TrialCrusaderTracker.zoneGateInstanceId = 649 -- Trial of the Crusader / Trial of the Grand Crusader

local ICEHOWL_TRAMPLE = 66734
local trampleIcon = "Interface\\Icons\\Ability_Druid_DemoralizingRoar"

function TrialCrusaderTracker:OnInitialize()
    RLHelper:Debug("TrialCrusaderTracker: Инициализация")
    self.log = function(...)
        RLHelper:OnCombatLogEvent(...)
    end
end

function TrialCrusaderTracker:OnEnable()
    RLHelper:Debug("TrialCrusaderTracker: Включен")
end

local function formatIcehowlTrample(ts, playerName)
    return string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t размазало об стену", date("%H:%M:%S", ts), playerName,
        trampleIcon)
end

function TrialCrusaderTracker:handleEvent(event)
    if event.event == "SPELL_DAMAGE" and event.spellId == ICEHOWL_TRAMPLE and event.destName then
        self.log(formatIcehowlTrample(event.timestamp, event.destName))
    end
end

return TrialCrusaderTracker
