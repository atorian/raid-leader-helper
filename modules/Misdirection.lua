local TestAddon = LibStub("AceAddon-3.0"):GetAddon("TestAddon")
local MisdirectionTracker = TestAddon:NewModule("MisdirectionTracker", "AceEvent-3.0")

local MISDIRECTION_SPELL_ID = 34477
-- Список отслеживаемых способностей
local TRACKED_SPELLS = {
    [34477] = "Interface\\Icons\\Ability_Hunter_Misdirection",
    [75] = "Interface\\Icons\\inv_weapon_bow_55",
    [53209] = "Interface\\Icons\\Ability_Hunter_ChimeraShot2"
}

-- Active pulls tracking
local activePulls = {} -- {hunterGUID = targetGUID}
local pullDamage = {} -- {hunterGUID = ringBuffer of SpellID }

function MisdirectionTracker:OnEnable()
    TestAddon:Print("RL Быдло: MisdirectionTracker включен")
    TestAddon:withHandler(function(...)
        self:handleEvent(...)
    end)
end

function MisdirectionTracker:OnInitialize()
    TestAddon:Print("RL Быдло: MisdirectionTracker инициализируется")
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self.log = function(...)
        TestAddon:Print("RL Быдло: MisdirectionTracker =>", ...)
        TestAddon:OnCombatLogEvent(...)
    end
end

function MisdirectionTracker:reset()
    wipe(activePulls)
    wipe(pullDamage)
end

function MisdirectionTracker:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
    self:handleEvent(blizzardEvent(...), self.log)
end

function MisdirectionTracker:handleEvent(eventData, log)
    -- Track Misdirection application
    if eventData.event == "SPELL_AURA_APPLIED" and eventData.spellId == MISDIRECTION_SPELL_ID then
        self:OnMisdirection(eventData)
    end
    -- Track Misdirection removal
    if eventData.event == "SPELL_AURA_REMOVED" and eventData.spellId == MISDIRECTION_SPELL_ID then
        self:OnMisdirectionRemoved(eventData, log)
    end
    -- Track damage during active pull
    if eventData.event == "SPELL_DAMAGE" or eventData.event == "SWING_DAMAGE" then
        self:OnDamage(eventData)
    end
end

function MisdirectionTracker:OnMisdirection(eventData)
    activePulls[eventData.sourceName] = eventData.destName
    pullDamage[eventData.sourceName] = createRingBuffer()
end

function MisdirectionTracker:OnMisdirectionRemoved(eventData, log)
    -- Generate final report
    self:GenerateReport(eventData.sourceName, log)
    -- Clear tracking data
    activePulls[eventData.sourceName] = nil
    pullDamage[eventData.sourceName] = nil
end

function MisdirectionTracker:OnDamage(eventData)
    pullDamage[eventData.sourceName]:add(eventData.spellId)
end

function MisdirectionTracker:GenerateReport(hunterName, log)
    -- Create damage report
    local report = string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s", date("%H:%M:%S", GetTime()), hunterName,
        TRACKED_SPELLS[MISDIRECTION_SPELL_ID], activePulls[hunterName])

    -- Add damage breakdown
    for _, spellId in pairs(pullDamage) do
        report = report .. string.format(" |T%s:24:24:0:0|t", TRACKED_SPELLS[spellId] or TRACKED_SPELLS[75])
    end

    log(hunterName, report)
end

return MisdirectionTracker
