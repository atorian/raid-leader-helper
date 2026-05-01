local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local BloodPrincesTracker = RLHelper:NewModule("BloodPrincesTracker", "AceEvent-3.0")
BloodPrincesTracker.receivesCombatEvents = true
BloodPrincesTracker.zoneGateInstanceId = 631 -- Icecrown Citadel

local POWERFUL_VORTEX = 72817
local vortexIcon = "Interface\\Icons\\Spell_Shadow_Teleport"

local HEALER_CLASSES = {
    PRIEST = true,
    PALADIN = true,
    SHAMAN = true,
    DRUID = true
}

function BloodPrincesTracker:OnInitialize()
    RLHelper:Debug("BloodPrincesTracker: Инициализация")
    self.log = function(...)
        RLHelper:OnCombatLogEvent(...)
    end
end

function BloodPrincesTracker:OnEnable()
    RLHelper:Debug("BloodPrincesTracker: Включен")
end

local function isGroupFiveHealer(playerName)
    if not playerName or type(GetRaidRosterInfo) ~= "function" then
        return false
    end

    local raidSize = type(GetNumRaidMembers) == "function" and GetNumRaidMembers() or 40
    for i = 1, raidSize do
        local name, _, subgroup, _, class = GetRaidRosterInfo(i)
        if name == playerName then
            return subgroup == 5 and HEALER_CLASSES[class] == true
        end
    end

    return false
end

local function formatVortexHealerHit(ts, sourceName, destName)
    return string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t |cFFFFFFFF%s|r",
        date("%H:%M:%S", ts), sourceName, vortexIcon, destName)
end

function BloodPrincesTracker:handleEvent(event)
    if event.event ~= "SPELL_DAMAGE" or event.spellId ~= POWERFUL_VORTEX then
        return
    end

    if not isGroupFiveHealer(event.destName) then
        return
    end

    self.log(formatVortexHealerHit(event.timestamp, event.sourceName or "Unknown", event.destName))
end

return BloodPrincesTracker
