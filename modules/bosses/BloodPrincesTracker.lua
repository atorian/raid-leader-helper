local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local BloodPrincesTracker = RLHelper:NewModule("BloodPrincesTracker", "AceEvent-3.0")
BloodPrincesTracker.receivesCombatEvents = true
BloodPrincesTracker.zoneGateInstanceId = 631 -- Icecrown Citadel
BloodPrincesTracker.bossIds = {
    [37970] = "Кровавый совет", -- Prince Valanar
    [37972] = "Кровавый совет", -- Prince Keleseth
    [37973] = "Кровавый совет" -- Prince Taldaram
}

local POWERFUL_VORTEX_SPELLS = {
    [72038] = true,
    [72815] = true,
    [72816] = true,
    [72817] = true,
}

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

function BloodPrincesTracker:IsGroupFiveHealer(playerName)
    local GetNumRaidMembers = self.context and self.context.GetNumRaidMembers or GetNumRaidMembers
    local GetRaidRosterInfo = self.context and self.context.GetRaidRosterInfo or GetRaidRosterInfo
    if not playerName or type(GetRaidRosterInfo) ~= "function" then
        return false
    end
    local raidSize = type(GetNumRaidMembers) == "function" and GetNumRaidMembers() or 40
    for i = 1, raidSize do
        local name, _, subgroup, _, _, class = GetRaidRosterInfo(i)
        if name == playerName then
            return subgroup == 5 and HEALER_CLASSES[class] == true
        end
    end

    return false
end

function BloodPrincesTracker:handleEvent(event)
    if (event.event ~= "SPELL_DAMAGE" and event.event ~= "SPELL_MISSED") or not POWERFUL_VORTEX_SPELLS[event.spellId] then
        return
    end

    if not self:IsGroupFiveHealer(event.destName) then
        return
    end

    RLHelperJournal.Log(self.log, event.event == "SPELL_MISSED" and "VORTEX_MISSED" or "VORTEX_HIT", event,
        "TACTIC_VIOLATION")
end

BloodPrincesTracker.demoOrder = 5
function BloodPrincesTracker:RunDemo(demo)
    demo:Event(self, "SPELL_DAMAGE", demo.players.mage, demo.players.priest, 72817, { amount = 5000 })
    demo:Event(self, "SPELL_MISSED", demo.players.mage, demo.players.priest, 72817, { missType = "IMMUNE" })
end


return BloodPrincesTracker
