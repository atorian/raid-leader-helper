local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local IgorDeathTracker = RLHelper:NewModule("IgorDeathTracker")
IgorDeathTracker.receivesCombatEvents = true

local IGOR_DEATH_COOLDOWN = 15
local COMBATLOG_OBJECT_TYPE_PLAYER_FLAG = COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400
local COMBATLOG_OBJECT_TYPE_PET_FLAG = COMBATLOG_OBJECT_TYPE_PET or 0x00001000
local COMBATLOG_OBJECT_TYPE_GUARDIAN_FLAG = COMBATLOG_OBJECT_TYPE_GUARDIAN or 0x00002000

local IGOR_DEATH_PHRASES = {
    "Игорь осуждает смерть %s.",
    "Игорь делает вид, что так и было задумано.",
    "Игорь записал %s в список слабых.",
    "Игорь молча смотрит на тело %s.",
    "Игорь считает, что %s мог бы и пожить.",
    "Игорь плюет на бездыханное тело %s.",
    "Игорь тяжело вздыхает.",
    "Игорь говорит: минус мораль.",
    "Игорь делает пометку: %s умер не по плану.",
    "Игорь не одобряет происходящее.",
    "Игорь подозревает, что %s нажал не ту кнопку.",
    "Игорь просит %s больше так не делать.",
    "Игорь считает эту смерть обучающим моментом.",
    "Игорь смотрит на %s с разочарованием.",
    "Игорь считает что %s напрашивается в список друзей.",
    "Игорь говорит: зато красиво.",
    "Игорь говорит: %s, так ты 2800 не возьмешь.",
    "Игорь добавляет смерть %s в отчет."
}

local IGOR_PET_DEATH_PHRASES = {
    "Игорь зажимает нос. %s воняет.",
    "Игорь скорбит по %s.",
    "Игорь считает, что %s заслуживал большего.",
    "Игорь делает пометку: %s погиб за чужие ошибки.",
    "Игорь подозревает, что %s просто хотел домой.",
    "Игорь смотрит на тело %s и молчит.",
    "Игорь напоминает: питомцев тоже надо лечить.",
    "Игорь записал смерть %s в отчет о халатности.",
    "Игорь говорит: зверя жалко.",
    "Игорь считает, что кто-то должен ответить за жестокое обращение с %s.",
    "Игорь бормочет под нос: пуп-пу-пу...",
    "Игорь надеется что Спилберг снимет фильм про %s.",
    "Игорь считает, что %s был лучшим из нас."
}

local function isPlayerType(flags)
    return bit.band(flags or 0, COMBATLOG_OBJECT_TYPE_PLAYER_FLAG) > 0
end

local function isPetOrGuardianType(flags)
    local value = flags or 0
    return bit.band(value, COMBATLOG_OBJECT_TYPE_PET_FLAG) > 0 or
        bit.band(value, COMBATLOG_OBJECT_TYPE_GUARDIAN_FLAG) > 0
end

function IgorDeathTracker:GetGroupDeathMessagePhrases(event)
    if not event or event.event ~= "UNIT_DIED" then
        return nil
    end

    local destFlags = event.destFlags or 0
    local groupFlags = bit.bor and bit.bor(RLHelper.GROUP_AFFILIATION_PARTY, RLHelper.GROUP_AFFILIATION_RAID) or
        (RLHelper.GROUP_AFFILIATION_PARTY + RLHelper.GROUP_AFFILIATION_RAID)
    if bit.band(destFlags, groupFlags) <= 0 then
        return nil
    end

    if isPlayerType(destFlags) then
        return IGOR_DEATH_PHRASES
    end

    if isPetOrGuardianType(destFlags) then
        return IGOR_PET_DEATH_PHRASES
    end

    return nil
end

function IgorDeathTracker:FormatDeathMessage(playerName, phrases)
    local phrase = phrases[math.random(#phrases)]
    if phrase:find("%%s") then
        return string.format(phrase, playerName or "кто-то")
    end

    return phrase
end

function IgorDeathTracker:handleEvent(event)
    if not RLHelper.db or not RLHelper.db.profile or not RLHelper.db.profile.igor then
        return false
    end

    local phrases = self:GetGroupDeathMessagePhrases(event)
    if not phrases then
        return false
    end

    local now = RLHelper:GetCombatNow()
    if self.lastDeathMessageAt and now - self.lastDeathMessageAt < IGOR_DEATH_COOLDOWN then
        return false
    end

    if type(SendChatMessage) ~= "function" then
        return false
    end

    SendChatMessage(self:FormatDeathMessage(event.destName, phrases), "EMOTE")
    self.lastDeathMessageAt = now
    return true
end

return IgorDeathTracker
