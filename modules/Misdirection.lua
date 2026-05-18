local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local MisdirectionTracker = RLHelper:NewModule("MisdirectionTracker", "AceEvent-3.0")
MisdirectionTracker.receivesCombatEvents = true

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
    [49045] = "Interface\\Icons\\Ability_ImpalingBolt",
    [34490] = "Interface\\Icons\\Ability_TheBlackArrow",
    [49048] = "Interface\\Icons\\Ability_UpgradeMoonGlaive",
    [49065] = "Interface\\Icons\\spell_fire_selfdestruct",
    [53353] = "Interface\\Icons\\Ability_Hunter_ChimeraShot2",
    [53352] = "Interface\\Icons\\ability_hunter_explosiveshot",
    [48996] = "Interface\\Icons\\ability_meleedamage", -- удар ящера
    [61006] = "Interface\\Icons\\ability_hunter_assassinate2", -- Килшот
    [53339] = "Interface\\Icons\\ability_hunter_swiftstrike",
    [75] = "Interface\\Icons\\inv_weapon_bow_55",
    [72817] = "Interface\\Icons\\spell_nature_earthbind",
    -- Рога
    [57934] = "Interface\\Icons\\ability_rogue_tricksofthetrade",
    [59628] = "Interface\\Icons\\ability_rogue_tricksofthetrade",
    [48638] = "Interface\\Icons\\Spell_shadow_ritualofsacrifice",
    [2098] = "Interface\\Icons\\ability_rogue_eviscerate",
    [5171] = "Interface\\Icons\\ability_rogue_slicedice", -- 
    [13750] = "Interface\\Icons\\spell_shadow_shadowworddominate",
    [13877] = "Interface\\Icons\\ability_warrior_punishingblow",
    [11273] = "Interface\\Icons\\ability_rogue_rupture",
    [31224] = "Interface\\Icons\\spell_shadow_nethercloak",
    [1857] = "Interface\\Icons\\ability_vanish",
    [57970] = "Interface\\Icons\\ability_rogue_dualweild",
    [57965] = "Interface\\Icons\\ability_poisons",
    [57841] = "Interface\\Icons\\ability_rogue_murderspree",
    [57842] = "Interface\\Icons\\ability_rogue_murderspree",
    [51723] = "Interface\\Icons\\ability_rogue_fanofknives", -- веер клинков
    [22482] = "Interface\\Icons\\ability_rogue_slicedice", -- шквал клинков
    [52874] = "Interface\\Icons\\ability_rogue_fanofknives",
    [57993] = "Interface\\Icons\\ability_rogue_disembowel",
    [48665] = "Interface\\Icons\\ability_dualwield",
    [14278] = "Interface\\Icons\\spell_shadow_curse",
    [48668] = "Interface\\Icons\\ability_rogue_eviscerate"
}

local SKIP_SPELLS = {
    [57965] = true, -- яд роги
    [53254] = true, -- "мятежная стрела ханта(лук с леди?)"
    [71834] = true, -- быстрая стрельба
    [69193] = true, -- Ранец Корабли
    [71341] = true, -- Пакт - Ланатель
    [71879] = true, -- какой-то дк спелл
    [72669] = true, -- прокалывание
    [57981] = true, -- яд роги 2
    [72817] = true, -- вихрь друля
    [51675] = true -- какой-то спелл роги
}

-- Active pulls tracking
local activePulls = {}
local pullDamage = {}

local HUNTER_DAMAGE_EVENTS = {
    SPELL_DAMAGE = true,
    RANGE_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true,
    SWING_DAMAGE = true
}

local HUNTER_VISIBLE_SKIP_SPELLS = {
    [75] = true,
    [53353] = true
}

function MisdirectionTracker:OnEnable()
    RLHelper:Debug("RL Быдло: MisdirectionTracker включен")
end

function MisdirectionTracker:OnInitialize()
    self:RegisterMessage("RLHelper_CombatEnded", "reset")
    self:RegisterMessage("RLHelper_Demo", "demo")
    self.log = function(...)
        RLHelper:OnCombatLogEvent(...)
    end
end

function MisdirectionTracker:reset()
    activePulls = {}
    pullDamage = {}
end

function MisdirectionTracker:handleEvent(eventData)
    if eventData.event == "SPELL_CAST_SUCCESS" and
        (eventData.spellId == MISDIRECTION_START_SPELL_ID or eventData.spellId == SMALL_TRICKS_START_SPELL_ID) then
        self:OnMisdirection(eventData)
    end

    if eventData.event == "SPELL_AURA_REMOVED" and
        (eventData.spellId == MISDIRECTION_SPELL_ID or eventData.spellId == SMALL_TRICKS_SPELL_ID) then
        self:GenerateReport(eventData.sourceName, eventData.timestamp)
    end

    if activePulls[eventData.sourceName] then
        local activePull = activePulls[eventData.sourceName]
        if activePull.spellId == MISDIRECTION_START_SPELL_ID and HUNTER_DAMAGE_EVENTS[eventData.event] then
            self:OnDamage(eventData)
        elseif eventData.event == "SPELL_DAMAGE" then
            self:OnDamage(eventData)
        end
    end
end

function MisdirectionTracker:OnMisdirection(eventData)
    activePulls[eventData.sourceName] = {
        ["time"] = eventData.timestamp,
        ["target"] = eventData.destName,
        ["spellId"] = eventData.spellId,
        ["startLogged"] = false,
        ["totalDamage"] = 0
    }
    pullDamage[eventData.sourceName] = {}

    if eventData.spellId == MISDIRECTION_START_SPELL_ID and RLHelper.inCombat then
        self:LogHunterMisdirectionStart(eventData.sourceName)
    end
end

function MisdirectionTracker:OnDamage(eventData)
    local activePull = activePulls[eventData.sourceName]
    if activePull and activePull.spellId == MISDIRECTION_START_SPELL_ID then
        self:OnHunterDamage(eventData, activePull)
        return
    end

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

local function formatMissdirectStart(ts, source, missdirectSpellId, dest)
    return string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:-2|t %s", date("%H:%M:%S", ts), source,
        TRACKED_SPELLS[missdirectSpellId], dest)
end

local function formatMissdirectDamage(ts, source, damageSpellId, dest)
    return string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:-2|t %s", date("%H:%M:%S", ts), source,
        TRACKED_SPELLS[damageSpellId], dest)
end

local function formatMissdirectSummary(ts, source, missdirectSpellId, dest, totalDamage)
    return string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:-2|t %s напул окончен %s", date("%H:%M:%S", ts),
        source, TRACKED_SPELLS[missdirectSpellId], dest, totalDamage)
end

function MisdirectionTracker:LogHunterMisdirectionStart(sourceName)
    local activePull = activePulls[sourceName]
    if not activePull or activePull.startLogged then
        return
    end

    activePull.startLogged = true
    self.log(formatMissdirectStart(activePull.time, sourceName, activePull.spellId, activePull.target))
end

function MisdirectionTracker:OnHunterDamage(eventData, activePull)
    if eventData.timestamp < activePull.time then
        return
    end

    activePull.totalDamage = activePull.totalDamage + (eventData.amount or 0)
    self:LogHunterMisdirectionStart(eventData.sourceName)

    if SKIP_SPELLS[eventData.spellId] or HUNTER_VISIBLE_SKIP_SPELLS[eventData.spellId] or not TRACKED_SPELLS[eventData.spellId] then
        return
    end

    self.log(formatMissdirectDamage(eventData.timestamp, eventData.sourceName, eventData.spellId, eventData.destName))
end

function MisdirectionTracker:LogHunterMisdirectionSummary(sourceName, timestamp)
    local activePull = activePulls[sourceName]
    if not activePull or not activePull.startLogged then
        return
    end

    self.log(formatMissdirectSummary(timestamp or activePull.time, sourceName, activePull.spellId, activePull.target,
        activePull.totalDamage or 0))
end

local function clearPullState(sourceName)
    activePulls[sourceName] = nil
    pullDamage[sourceName] = nil
end

local function formatMissdirect(ts, source, missdirectSpellId, dest, allHits)

    local report = string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:-2|t %s", date("%H:%M:%S", ts), source,
        TRACKED_SPELLS[missdirectSpellId], dest)

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

    return report
end

function MisdirectionTracker:demo()
    local ts = time()
    local hunterHits1 = {
        [10] = {
            [49050] = 1
        },
        [20] = {
            [53353] = 1
        },
        [30] = {
            [53353] = 1
        }
    }
    self.log(formatMissdirect(time(), "HunterName", MISDIRECTION_SPELL_ID, "Tank", hunterHits1))
    local hunterHits2 = {
        [1] = {
            [49052] = 1
        },
        [2] = {
            [49052] = 1
        }
    }
    self.log(formatMissdirect(time(), "HunterName", MISDIRECTION_SPELL_ID, "Tank", hunterHits2))
    local rogeHits1 = {
        [1] = {
            [48638] = 1
        },
        [2] = {
            [57841] = 1,
            [57842] = 1
        },
        [3] = {
            [48638] = 1
        },
        [4] = {
            [57841] = 1,
            [57842] = 1
        }
    }
    self.log(formatMissdirect(time(), "KRoga", SMALL_TRICKS_SPELL_ID, "Tank", rogeHits1))
    local rogeHits2 = {
        [1] = {
            [51723] = 3,
            [22482] = 2
        },
        [2] = {
            [51723] = 3,
            [22482] = 2
        },
        [3] = {
            [51723] = 3,
            [22482] = 2
        }
    }
    self.log(formatMissdirect(time(), "KRoga", SMALL_TRICKS_SPELL_ID, "Tank", rogeHits2))

end

function MisdirectionTracker:GenerateReport(hunterName, timestamp)
    local activePull = activePulls[hunterName]
    local allHits = pullDamage[hunterName]

    if activePull and activePull.spellId == MISDIRECTION_START_SPELL_ID then
        self:LogHunterMisdirectionSummary(hunterName, timestamp)
        clearPullState(hunterName)
        return
    end

    if not activePull or not allHits then
        clearPullState(hunterName)
        return
    end

    local report = formatMissdirect(activePull.time, hunterName, activePull.spellId, activePull.target, allHits)
    clearPullState(hunterName)
    self.log(report)
end

return MisdirectionTracker
