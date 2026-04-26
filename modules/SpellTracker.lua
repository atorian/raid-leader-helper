local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local SppellTracker = RLHelper:NewModule("SppellTracker", "AceEvent-3.0")
SppellTracker.receivesCombatEvents = true

-- Флаг для отслеживания первого урона
local firstDamageDone = false
local HAND_OF_RECKONING = 62124
function SppellTracker:OnEnable()
    RLHelper:Debug("RL Быдло: TauntTracker включен")
    firstDamageDone = false
end

-- Список отслеживаемых способностей
local TRACKED_SPELLS = {
    [355] = "Interface\\Icons\\spell_nature_reincarnation", -- Warrior: Taunt
    [694] = "Interface\\Icons\\ability_warrior_punishingblow", -- Warrior: Mocking Blow
    [1161] = "Interface\\Icons\\ability_bullrush", -- Warrior: Challenging Shout
    [49560] = "Interface\\Icons\\Spell_DeathKnight_Strangulate", -- Death Knight: Death Grip
    [51399] = "Interface\\Icons\\Spell_DeathKnight_Strangulate", -- Death Knight: Death Grip Taunt Effect
    [56222] = "Interface\\Icons\\Spell_Nature_ShamanRage", -- Death Knight: Dark Command
    [62124] = "Interface\\Icons\\Spell_Holy_UnyieldingFaith", -- Paladin: Hand of Reckoning
    [31789] = "Interface\\Icons\\inv_shoulder_37",
    [5209] = "Interface\\Icons\\Ability_Druid_ChallangingRoar", -- Druid: Growl

    [10278] = "Interface\\Icons\\Spell_Holy_SealOfProtection", -- Paladin: Корона
    [19752] = "Interface\\Icons\\Spell_Nature_TimeStop", -- Paladin: Диван
    [6940] = "Interface\\Icons\\Spell_Holy_SealOfSacrifice", -- Paladin: Длань жертвенности
    
    [26994] = "Interface\\Icons\\spell_nature_reincarnation", -- Друид БР
    [48477] = "Interface\\Icons\\spell_nature_reincarnation" -- Друид БР
}

local TRACKED_CAST_SUCCESS_SPELLS = {
    [19752] = true, -- Божественное вмешательство
    [31789] = true -- Праведная защита
}

function SppellTracker:OnInitialize()
    self:RegisterEvent("UNIT_TARGET")
    self:RegisterMessage("RLHelper_CombatEnded", "reset")
    self:RegisterMessage("RLHelper_Demo", "demo")
    self.pendingHandOfReckonings = {}
    self.log = function(...)
        RLHelper:OnCombatLogEvent(...)
    end
end

function SppellTracker:reset()
    firstDamageDone = false
    self.pendingHandOfReckonings = {}
end

local PLAYER_FLAGS = 0x7
local ENEMY_FLAGS = 0xa48

local function isPlayer(flags)
    return bit.band(flags or 0, PLAYER_FLAGS) > 0
end

local function isEnemy(flags)
    return bit.band(flags or 0, ENEMY_FLAGS) > 0
end

local function formatFirstHit(ts, source, dest)
    return string.format("%s |cFFFFFFFF%s|r Первый урон по |cFFFFFFFF%s|r", date("%H:%M:%S", ts), source,
        dest)
end

local function formatSpellCast(ts, source, spellIcon, dest)
    return string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s", date("%H:%M:%S", ts), source, spellIcon, dest)
end

function SppellTracker:clearPendingHandOfReckoning(destGUID)
    self.pendingHandOfReckonings[destGUID] = nil
end

function SppellTracker:clearPendingHandOfReckoningBySource(sourceGUID)
    if not sourceGUID then
        return
    end

    for destGUID, pending in pairs(self.pendingHandOfReckonings) do
        if pending.sourceGUID == sourceGUID then
            self.pendingHandOfReckonings[destGUID] = nil
        end
    end
end

function SppellTracker:trackHandOfReckoningTarget(eventData)
    self.pendingHandOfReckonings[eventData.destGUID] = {
        timestamp = eventData.timestamp,
        spellIcon = TRACKED_SPELLS[eventData.spellId],
        sourceGUID = eventData.sourceGUID,
        sourceName = eventData.sourceName,
        destName = eventData.destName
    }
end

function SppellTracker:tryLogHandOfReckoningTarget(unitId)
    if not unitId then
        return false
    end

    local pending = self.pendingHandOfReckonings[UnitGUID(unitId)]
    if not pending then
        return false
    end

    local targetUnit = unitId .. "target"
    if UnitExists(targetUnit) and UnitGUID(targetUnit) == pending.sourceGUID then
        self:clearPendingHandOfReckoning(UnitGUID(unitId))
        self.log(formatSpellCast(pending.timestamp, pending.sourceName, pending.spellIcon, pending.destName))
        return true
    end

    return false
end

function SppellTracker:UNIT_TARGET(_, unitId)
    self:tryLogHandOfReckoningTarget(unitId)
end

function SppellTracker:handleEvent(eventData)
    if not firstDamageDone and (eventData.event == "SWING_DAMAGE" or eventData.event == "SPELL_DAMAGE") then
        if isPlayer(eventData.sourceFlags) and isEnemy(eventData.destFlags) then
            firstDamageDone = true
            self.log(formatFirstHit(eventData.timestamp, eventData.sourceName, eventData.destName))
        end
    end

    if eventData.event and eventData.event:sub(1, 5) == "SPELL" and eventData.spellId ~= HAND_OF_RECKONING then
        self:clearPendingHandOfReckoningBySource(eventData.sourceGUID)
    end

    if eventData.event == "SPELL_RESURRECT" and TRACKED_SPELLS[eventData.spellId] then
        self.log(formatSpellCast(eventData.timestamp, eventData.sourceName, TRACKED_SPELLS[eventData.spellId],
            eventData.destName))
        return
    end

    if eventData.event == "SPELL_CAST_SUCCESS" and TRACKED_CAST_SUCCESS_SPELLS[eventData.spellId] and
        TRACKED_SPELLS[eventData.spellId] then
        self.log(formatSpellCast(eventData.timestamp, eventData.sourceName, TRACKED_SPELLS[eventData.spellId],
            eventData.destName))
        return
    end

    if eventData.event == "SPELL_AURA_APPLIED" and TRACKED_SPELLS[eventData.spellId] then
        if eventData.spellId == HAND_OF_RECKONING then
            self:trackHandOfReckoningTarget(eventData)
        else
            self.log(formatSpellCast(eventData.timestamp, eventData.sourceName, TRACKED_SPELLS[eventData.spellId],
                eventData.destName))
        end
        return
    end

    if eventData.spellId == HAND_OF_RECKONING and eventData.destGUID then
        if eventData.event == "SPELL_AURA_REMOVED" or eventData.event == "UNIT_DIED" or eventData.event == "UNIT_DESTROYED" or
            eventData.event == "PARTY_KILL" then
            self:clearPendingHandOfReckoning(eventData.destGUID)
        end
    end
end

function SppellTracker:demo()
    self.log(formatFirstHit(time(), "CrazyDkPet", "Halion"))

    for _, v in pairs({355, 694, 1161, 51399, 56222, 62124, 5209, 31789}) do
        self.log(formatSpellCast(time(), "NotTank", TRACKED_SPELLS[v], "Halion"))
    end

    for _, v in pairs({10278, 19752}) do
        self.log(formatSpellCast(time(), "Paladin", TRACKED_SPELLS[v], "OtherPlayer"))
    end
end

return SppellTracker
