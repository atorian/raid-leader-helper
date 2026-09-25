local RLHelper = LibStub('AceAddon-3.0'):GetAddon('RLHelper')
local LichKingTracker = RLHelper:NewModule('LichKingTracker', 'AceEvent-3.0')
LichKingTracker.receivesCombatEvents = true
LichKingTracker.zoneGateInstanceId = 631 -- Icecrown Citadel

local SHADOW_TRAP_DAMAGE = 73529
local RAGING_SPIRIT = 69200

function LichKingTracker:OnInitialize()
    self.log = function(...)
        RLHelper:OnCombatLogEvent(...)
    end
end

function LichKingTracker:OnEnable()
    self:RegisterMessage('RLHelper_CombatEnded', 'reset')
end

function LichKingTracker:reset()
    self.lastShadowTrapTimestamp = nil
end

function LichKingTracker:handleEvent(event)
    if event.event == 'SPELL_CAST_SUCCESS' and event.spellId == RAGING_SPIRIT and event.destName then
        RLHelperJournal.Log(self.log, "RAGING_SPIRIT", event)
        return
    end

    if event.event ~= 'SPELL_DAMAGE' or event.spellId ~= SHADOW_TRAP_DAMAGE or not event.destName or
        not RLHelper:IsGroupMember(event.destGUID, event.destFlags) then
        return
    end

    if self.lastShadowTrapTimestamp == event.timestamp then
        return
    end

    self.lastShadowTrapTimestamp = event.timestamp
    RLHelperJournal.Log(self.log, "SHADOW_TRAP", event, "TACTIC_VIOLATION")
end

LichKingTracker.demoOrder = 7
function LichKingTracker:RunDemo(demo)
    self:reset()
    local boss = demo:Boss(36597, "Король-лич")
    demo:Event(self, "SPELL_DAMAGE", boss, demo.players.hunter, SHADOW_TRAP_DAMAGE, { amount = 15000 })
    demo:Event(self, "SPELL_CAST_SUCCESS", boss, demo.players.tank, RAGING_SPIRIT)
end


return LichKingTracker
