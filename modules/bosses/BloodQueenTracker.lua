local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local BloodQueenTracker = RLHelper:NewModule("BloodQueenTracker", "AceEvent-3.0")
BloodQueenTracker.receivesCombatEvents = true
BloodQueenTracker.zoneGateInstanceId = 631 -- Icecrown Citadel
BloodQueenTracker.bossIds = {
    [37955] = "Кровавая королева Лана'тель"
}

local BLOODBOLT_SPLASH_SPELLS = {
    [71483] = true,
    [71481] = true,
    [71447] = true
}
local GROUP_AFFILIATION_ANY = 0x7
local splashIcon = "Interface\\Icons\\Spell_Shadow_BloodBoil"

function BloodQueenTracker:OnInitialize()
    RLHelper:Debug("BloodQueenTracker: Инициализация")
    self.log = function(...)
        RLHelper:OnCombatLogEvent(...)
    end
end

function BloodQueenTracker:OnEnable()
    RLHelper:Debug("BloodQueenTracker: Включен")
end

local function isPlayerSource(sourceFlags)
    return bit.band(sourceFlags or 0, GROUP_AFFILIATION_ANY) > 0
end

local function formatSplashHit(ts, sourceName, destName)
    return string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t |cFFFFFFFF%s|r",
        date("%H:%M:%S", ts), sourceName, splashIcon, destName)
end

function BloodQueenTracker:handleEvent(event)
    if event.event ~= "SPELL_DAMAGE" or not BLOODBOLT_SPLASH_SPELLS[event.spellId] then
        return
    end

    if not isPlayerSource(event.sourceFlags) then
        return
    end

    self.log(formatSplashHit(event.timestamp, event.sourceName or "Unknown", event.destName or "Unknown"))
end

return BloodQueenTracker
