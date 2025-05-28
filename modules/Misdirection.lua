local TestAddon = LibStub("AceAddon-3.0"):GetAddon("TestAddon")
local MisdirectionTracker = TestAddon:NewModule("MisdirectionTracker", "AceEvent-3.0")

local List = List

-- hunt
local MISDIRECTION_START_SPELL_ID = 34477
local MISDIRECTION_SPELL_ID = 35079
-- roge
local SMALL_TRICKS_START_SPELL_ID = 57934
local SMALL_TRICKS_SPELL_ID = 59628
-- Список отслеживаемых способностей
local TRACKED_SPELLS = {
    -- Хант
    [34477] = "Interface\\Icons\\Ability_Hunter_Misdirection",
    [35079] = "Interface\\Icons\\Ability_Hunter_Misdirection",
    [58433] = "Interface\\Icons\\ability_marksmanship",
    [58434] = "Interface\\Icons\\ability_marksmanship",
    [53209] = "Interface\\Icons\\Ability_Hunter_ChimeraShot2",
    [49050] = "Interface\\Icons\\INV_Spear_07",
    [49052] = "Interface\\Icons\\Ability_Hunter_SteadyShot",
    [49045] = "Interface\\Icons\\Ability_Hunter_ImpalingBolt",
    [34490] = "Interface\\Icons\\Ability_TheBlackArrow",
    [49048] = "Interface\\Icons\\Ability_UpgradeMoonGlaive",
    [49065] = "Interface\\Icons\\spell_fire_selfdestruct",
    [53353] = "Interface\\Icons\\Ability_Hunter_ChimeraShot2",
    [53352] = "Interface\\Icons\\ability_hunter_explosiveshot",
    [48996] = "Interface\\Icons\\ability_meleedamage", -- удар ящера
    [75] = "Interface\\Icons\\inv_weapon_bow_55",
    -- Рога
    [57934] = "Interface\\Icons\\ability_rogue_tricksofthetrade",
    [59628] = "Interface\\Icons\\ability_rogue_tricksofthetrade",
    [48638] = "Interface\\Icons\\Spell_shadow_ritualofsacrifice",
    [2098] = "Interface\\Icons\\ability_rogue_eviscerate",
    [5171] = "Interface\\Icons\\ability_rogue_slicedice", -- 
    [57842] = "Interface\\Icons\\ability_rogue_murderspree",
    [13750] = "Interface\\Icons\\spell_shadow_shadowworddominate",
    [13877] = "Interface\\Icons\\ability_warrior_punishingblow",
    [11273] = "Interface\\Icons\\ability_rogue_rupture",
    [31224] = "Interface\\Icons\\spell_shadow_nethercloak",
    [1857] = "Interface\\Icons\\ability_vanish",
    [57970] = "Interface\\Icons\\ability_rogue_dualweild",
    [57965] = "Interface\\Icons\\ability_poisons",
    [57841] = "Interface\\Icons\\ability_rogue_murderspree",
    [51723] = "Interface\\Icons\\ability_rogue_fanofknives", -- веер клинков
    [22482] = "Interface\\Icons\\ability_rogue_slicedice", -- шквал клинков - todo: группировать, выводить иконку + счетчик целей
    [52874] = "Interface\\Icons\\ability_rogue_fanofknives",
    [48668] = "Interface\\Icons\\ability_rogue_eviscerate"
    -- 71834
}

local SKIP_SPELLS = {
    [57965] = true, -- яд роги
    [53254] = true, -- "мятежная стрела ханта(лук с леди?)"
    [71834] = true -- быстрая стрельба
}

-- Active pulls tracking
local activePulls = {}
local pullDamage = {}

function MisdirectionTracker:OnEnable()
    TestAddon:Print("RL Быдло: MisdirectionTracker включен")

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
    activePulls = {}
    pullDamage = {}
end

function MisdirectionTracker:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
    self:handleEvent(blizzardEvent(...), self.log)
end

function MisdirectionTracker:handleEvent(eventData, log)
    if eventData.event == "SPELL_CAST_SUCCESS" and
        (eventData.spellId == MISDIRECTION_START_SPELL_ID or eventData.spellId == SMALL_TRICKS_START_SPELL_ID) then
        self:OnMisdirection(eventData)
    end

    if eventData.event == "SPELL_AURA_REMOVED" and
        (eventData.spellId == MISDIRECTION_SPELL_ID or eventData.spellId == SMALL_TRICKS_SPELL_ID) then
        self:OnMisdirectionRemoved(eventData, log)
    end

    if activePulls[eventData.sourceName] then
        if eventData.event == "SPELL_DAMAGE" then
            self:OnDamage(eventData)
        end
    end
end

function MisdirectionTracker:OnMisdirection(eventData)
    activePulls[eventData.sourceName] = {
        ["time"] = eventData.timestamp,
        ["target"] = eventData.destName,
        ["spellId"] = eventData.spellId
    }
    pullDamage[eventData.sourceName] = {}
end

function MisdirectionTracker:OnMisdirectionRemoved(eventData, log)
    self:GenerateReport(eventData.sourceName, log)
    activePulls[eventData.sourceName] = nil
    pullDamage[eventData.sourceName] = nil
end

function MisdirectionTracker:OnDamage(eventData)
    if not SKIP_SPELLS[eventData.spellId] then
        if not pullDamage[eventData.sourceName][eventData.timestamp] then
            pullDamage[eventData.sourceName][eventData.timestamp] = {}
        end

        if not pullDamage[eventData.sourceName][eventData.timestamp][eventData.spellId] then
            pullDamage[eventData.sourceName][eventData.timestamp][eventData.spellId] = 0
        end

        local val = pullDamage[eventData.sourceName][eventData.timestamp][eventData.spellId]
        pullDamage[eventData.sourceName][eventData.timestamp][eventData.spellId] = val + 1
    end
end

function MisdirectionTracker:GenerateReport(hunterName, log)

    local allHits = pullDamage[hunterName]

    local report = string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:-2|t %s",
        date("%H:%M:%S", activePulls[hunterName].time), hunterName, TRACKED_SPELLS[activePulls[hunterName].spellId],
        activePulls[hunterName].target)

    for ts, bucket in pairs(allHits) do
        for spellId, hits in pairs(bucket) do
            if TRACKED_SPELLS[spellId] then
                local icon = TRACKED_SPELLS[spellId] or "Interface\\Icons\\INV_Misc_QuestionMark"
                if hits == 1 then
                    report = report .. string.format(" |T%s:24:24:0:-2|t", icon)
                else
                    report = report .. string.format(" %sx|T%s:24:24:0:-2|t", hits, icon)
                end
            else
                SendChatMessage('Spell => ' .. spellId, "WHISPER", nil, UnitName("player"))
            end

        end
    end

    log(hunterName, report)
end

return MisdirectionTracker
