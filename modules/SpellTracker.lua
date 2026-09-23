local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local SppellTracker = RLHelper:NewModule("SppellTracker", "AceEvent-3.0")
SppellTracker.receivesCombatEvents = true
local CombatFilters = RLHelperCombatFilters

-- Флаг для отслеживания первого урона
local firstDamageDone = false
local firstValithriaHealDone = false
local HAND_OF_RECKONING = 62124
local HOLY_WRATH = 48817
local HAND_OF_PROTECTION = 10278
local RIGHTEOUS_DEFENSE = 31789
local ICECROWN_CITADEL = 631
local VALITHRIA_DREAMWALKER = "Валитрия Сноходица"
local LICH_KING = "Король-лич"
local TAUNTS = {
    [355] = true, [694] = true, [1161] = true, [49560] = true, [51399] = true,
    [56222] = true, [62124] = true, [31789] = true, [5209] = true, [20736] = true
}

function SppellTracker:GetSpellClassification(event)
    if not TAUNTS[event.spellId] and event.spellId ~= HAND_OF_PROTECTION then
        return "INFO"
    end

    local fields = {
        sourceAssignment = RLHelper.groupAssignments[event.sourceGUID],
        targetAssignment = RLHelper.groupAssignments[event.destGUID],
        targetIsBoss = RLHelper:IsBossGUID(event.destGUID)
    }
    if RLHelper.inCombat then
        if event.spellId == HAND_OF_PROTECTION then
            if RLHelper:IsAssignedTank(event.destGUID) then return "TACTIC_VIOLATION", fields end
        elseif RLHelper.hasTankAssignments and RLHelper.groupMembers[event.sourceGUID] and
            not RLHelper:IsAssignedTank(event.sourceGUID) then
            local tauntsTank = event.spellId == RIGHTEOUS_DEFENSE and event.sourceGUID ~= event.destGUID and
                RLHelper:IsAssignedTank(event.destGUID)
            if fields.targetIsBoss or tauntsTank then return "TACTIC_VIOLATION", fields end
        end
    end
    return "INFO", fields
end

function SppellTracker:logSpell(event, kind)
    kind = kind or (TAUNTS[event.spellId] and "TAUNT" or "SPELL_USE")
    local severity, fields
    if event.journalType then
        severity, fields = event.journalType, event.journalFields
    else
        severity, fields = self:GetSpellClassification(event)
    end
    RLHelperJournal.Log(self.log, kind, event, severity, fields)
end
function SppellTracker:OnEnable()
    RLHelper:Debug("RL Быдло: TauntTracker включен")
    firstDamageDone = false
    firstValithriaHealDone = false
end

-- Список отслеживаемых способностей
local TRACKED_SPELLS = {
    [355] = true, -- Warrior: Taunt
    [694] = true, -- Warrior: Mocking Blow
    [1161] = true, -- Warrior: Challenging Shout
    [49560] = true, -- Death Knight: Death Grip
    [51399] = true, -- Death Knight: Death Grip Taunt Effect
    [56222] = true, -- Death Knight: Dark Command
    [62124] = true, -- Paladin: Hand of Reckoning
    [31789] = true,
    [5209] = true, -- Druid: Growl
    [20736] = true, -- Hunter: Distracting Shot

    [10278] = true, -- Paladin: Корона
    [1044] = true, -- Paladin: Длань свободы
    [19752] = true, -- Paladin: Диван
    [6940] = true, -- Paladin: Длань жертвенности
    [31821] = true, -- Paladin: Мастер аур
    [48817] = true, -- Paladin: Гнев небес
    [49016] = true, -- Death Knight: Hysteria
    
    [26994] = true, -- Друид БР
    [48477] = true -- Друид БР
}

local TRACKED_CAST_SUCCESS_SPELLS = {
    [1044] = true, -- Длань свободы
    [19752] = true, -- Божественное вмешательство
    [31789] = true, -- Праведная защита
    [31821] = true, -- Мастер аур
    [20736] = true -- Отвлекающий выстрел
}

local IGNORED_AURA_APPLIED_SPELLS = {
    [1044] = true, -- Длань свободы
    [31821] = true, -- Мастер аур
    [48817] = true, -- Гнев небес
    [20736] = true -- Отвлекающий выстрел: логируем только попытку каста
}

local TRACKED_DISPEL_SPELLS = {
    [475] = true, -- Mage: Remove Curse
    [526] = true, -- Shaman: Cure Toxins
    [527] = true, -- Priest: Dispel Magic
    [528] = true, -- Priest: Cure Disease
    [552] = true, -- Priest: Abolish Disease
    [988] = true, -- Priest: Dispel Magic
    [1152] = true, -- Paladin: Purify
    [2782] = true, -- Druid: Remove Curse
    [4987] = true, -- Paladin: Cleanse
    [10872] = true, -- Priest: Abolish Disease Effect
    [32375] = true, -- Priest: Mass Dispel
    [32592] = true, -- Priest: Mass Dispel triggered
    [51886] = true -- Shaman: Cleanse Spirit
}

function SppellTracker:OnInitialize()
    self:RegisterEvent("UNIT_TARGET")
    self:RegisterMessage("RLHelper_CombatEnded", "reset")
    self.pendingHandOfReckonings = {}
    self.log = function(...)
        RLHelper:OnCombatLogEvent(...)
    end
end

function SppellTracker:reset()
    firstDamageDone = false
    firstValithriaHealDone = false
    self.pendingHandOfReckonings = {}
end

local ENEMY_FLAGS = 0xa48

local function isEnemy(flags, guid)
    return not RLHelper:IsGroupMember(guid, flags) and bit.band(flags or 0, ENEMY_FLAGS) > 0
end




local function isLichKingCombat()
    return RLHelper.currentInstanceId == ICECROWN_CITADEL and RLHelper.currentCombat and
        RLHelper.currentCombat.firstEnemy == LICH_KING
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
    local severity, fields = self:GetSpellClassification(eventData)
    self.pendingHandOfReckonings[eventData.destGUID] = {
        timestamp = eventData.timestamp,
        sourceGUID = eventData.sourceGUID,
        sourceName = eventData.sourceName,
        destName = eventData.destName,
        destGUID = eventData.destGUID,
        spellId = eventData.spellId,
        journalType = severity,
        journalFields = fields
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
        self:logSpell(pending)
        return true
    end

    return false
end

function SppellTracker:UNIT_TARGET(_, unitId)
    self:tryLogHandOfReckoningTarget(unitId)
end

function SppellTracker:handleEvent(eventData)
    if not firstDamageDone and (eventData.event == "SWING_DAMAGE" or eventData.event == "SPELL_DAMAGE") then
        if RLHelper:IsGroupMember(eventData.sourceGUID, eventData.sourceFlags) and
            isEnemy(eventData.destFlags, eventData.destGUID) then
            if not CombatFilters or not CombatFilters:IsIgnoredCombatEnemy(eventData.destName) then
                firstDamageDone = true
                RLHelperJournal.Log(self.log, "FIRST_DAMAGE", eventData)
            end
        end
    end

    if not firstValithriaHealDone and (eventData.event == "SPELL_HEAL" or eventData.event == "SPELL_PERIODIC_HEAL") then
        if RLHelper:IsGroupMember(eventData.sourceGUID, eventData.sourceFlags) and
            eventData.destName == VALITHRIA_DREAMWALKER and (eventData.amount or 0) > 0 then
            firstValithriaHealDone = true
            RLHelperJournal.Log(self.log, "FIRST_HEAL", eventData)
        end
    end

    if eventData.event and eventData.event:sub(1, 5) == "SPELL" and eventData.spellId ~= HAND_OF_RECKONING then
        self:clearPendingHandOfReckoningBySource(eventData.sourceGUID)
    end

    if eventData.event == "SPELL_DISPEL" and TRACKED_DISPEL_SPELLS[eventData.spellId] then
        self:logSpell(eventData, "DISPEL")
        return
    end

    if eventData.event == "SPELL_RESURRECT" and TRACKED_SPELLS[eventData.spellId] then
        self:logSpell(eventData, "RESURRECT")
        return
    end

    if eventData.event == "SPELL_CAST_SUCCESS" and TRACKED_CAST_SUCCESS_SPELLS[eventData.spellId] and
        TRACKED_SPELLS[eventData.spellId] then
        self:logSpell(eventData)
        return
    end

    if eventData.event == "SPELL_DAMAGE" and eventData.spellId == HOLY_WRATH and isLichKingCombat() then
        self:logSpell(eventData)
        return
    end

    if eventData.event == "SPELL_AURA_APPLIED" and TRACKED_SPELLS[eventData.spellId] and
        not IGNORED_AURA_APPLIED_SPELLS[eventData.spellId] then
        if eventData.spellId == HAND_OF_RECKONING then
            self:trackHandOfReckoningTarget(eventData)
        else
            self:logSpell(eventData)
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


return SppellTracker
