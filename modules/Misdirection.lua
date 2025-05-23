local TestAddon = LibStub("AceAddon-3.0"):GetAddon("TestAddon")
local MisdirectionTracker = TestAddon:NewModule("MisdirectionTracker", "AceEvent-3.0")

local MISDIRECTION_START_SPELL_ID = 34477
local MISDIRECTION_SPELL_ID = 35079
-- Список отслеживаемых способностей
local TRACKED_SPELLS = {
    [34477] = "Interface\\Icons\\Ability_Hunter_Misdirection",
    [35079] = "Interface\\Icons\\Ability_Hunter_Misdirection",
    [58434] = "Interface\\Icons\\Ability_Marksmansmanship",
    [53209] = "Interface\\Icons\\Ability_Hunter_ChimeraShot2",
    [49050] = "Interface\\Icons\\INV_Spear_07",
    [49052] = "Interface\\Icons\\Ability_Hunter_SteadyShot",
    [49045] = "Interface\\Icons\\Ability_Hunter_ImpalingBolt",
    [34490] = "Interface\\Icons\\Ability_TheBlackArrow",
    [49048] = "Interface\\Icons\\Ability_UpgradeMoonGlaive",
    [53353] = "Interface\\Icons\\Ability_Hunter_ChimeraShot2",
    [75] = "Interface\\Icons\\inv_weapon_bow_55"
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
    if eventData.event == "SPELL_CAST_SUCCESS" and eventData.spellId == MISDIRECTION_START_SPELL_ID then
        self:OnMisdirection(eventData)
    end

    -- Track Misdirection removal
    if eventData.event == "SPELL_AURA_REMOVED" and eventData.spellId == MISDIRECTION_SPELL_ID then
        self:OnMisdirectionRemoved(eventData, log)
    end

    if activePulls[eventData.sourceName] then
        -- if eventData.event == "SPELL_DAMAGE" or eventData.event == "RANGE_DAMAGE" or eventData.event == "SWING_DAMAGE" then
        if eventData.event == "SPELL_DAMAGE" then
            self:OnDamage(eventData)
        end
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
    for _, spellId in pairs(pullDamage[hunterName]:getAll()) do
        TestAddon:Print("SPELL => ", spellId)
        report = report .. string.format(" |T%s:24:24:0:0|t", TRACKED_SPELLS[spellId] or TRACKED_SPELLS[75])
    end

    log(hunterName, report)
end

return MisdirectionTracker
