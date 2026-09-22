local RLHelper = LibStub('AceAddon-3.0'):GetAddon('RLHelper')
local LichKingTracker = RLHelper:NewModule('LichKingTracker', 'AceEvent-3.0')
LichKingTracker.receivesCombatEvents = true
LichKingTracker.zoneGateInstanceId = 631 -- Icecrown Citadel

local SHADOW_TRAP_DAMAGE = 73529
local SHADOW_TRAP_ICON = 'Interface\\Icons\\spell_shadow_gathershadows'
local RAGING_SPIRIT = 69200

function LichKingTracker:OnInitialize()
    self.log = function(...)
        RLHelper:OnCombatLogEvent(...)
    end
end

function LichKingTracker:OnEnable()
    self:RegisterMessage('RLHelper_CombatEnded', 'reset')
    self:RegisterMessage('RLHelper_Demo', 'demo')
end

function LichKingTracker:reset()
    self.lastShadowTrapTimestamp = nil
end

local function formatShadowTrap(ts, playerName)
    return string.format('%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t взорвал ловушку', date('%H:%M:%S', ts),
        playerName, SHADOW_TRAP_ICON)
end

local function formatRagingSpirit(ts, playerName)
    return string.format('%s Гневный дух: %s', date('%H:%M:%S', ts), playerName)
end

function LichKingTracker:handleEvent(event)
    if event.event == 'SPELL_CAST_SUCCESS' and event.spellId == RAGING_SPIRIT and event.destName then
        RLHelperJournal.Log(RLHelper, self.log, "RAGING_SPIRIT", event, formatRagingSpirit(event.timestamp, event.destName))
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
    RLHelperJournal.Log(RLHelper, self.log, "SHADOW_TRAP", event,
        formatShadowTrap(event.timestamp, event.destName), "TACTIC_VIOLATION")
end

function LichKingTracker:demo()
    self.log(formatShadowTrap(time(), 'DemoPlayer'))
end

return LichKingTracker
