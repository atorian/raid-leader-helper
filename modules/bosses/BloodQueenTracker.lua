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

function BloodQueenTracker:OnInitialize()
    RLHelper:Debug("BloodQueenTracker: Инициализация")
    self.log = function(...)
        RLHelper:OnCombatLogEvent(...)
    end
end

function BloodQueenTracker:OnEnable()
    RLHelper:Debug("BloodQueenTracker: Включен")
end

function BloodQueenTracker:handleEvent(event)
    if event.event ~= "SPELL_DAMAGE" or not BLOODBOLT_SPLASH_SPELLS[event.spellId] then
        return
    end

    if not RLHelper:IsGroupMember(event.sourceGUID, event.sourceFlags) then
        return
    end

    RLHelperJournal.Log(self.log, "BLOODBOLT_SPLASH", event, "TACTIC_VIOLATION")
end

BloodQueenTracker.demoOrder = 6
function BloodQueenTracker:RunDemo(demo)
    demo:Event(self, "SPELL_DAMAGE", demo.players.mage, demo.players.priest, 71483, { amount = 9000 })
end


return BloodQueenTracker
