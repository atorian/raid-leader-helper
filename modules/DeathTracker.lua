local TestAddon = LibStub("AceAddon-3.0"):GetAddon("TestAddon")
local DeathTracker = TestAddon:NewModule("DeathTracker", "AceEvent-3.0")

function DeathTracker:OnInitialize()
    TestAddon:Print("RL Быдло: DeathTracker инициализируется")
    self.dmgEvents = {}
    self.healEvents = {}
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    -- TestAddon:withHandler(DeathTracker)
end

-- 67662 Ледной Рев
-- 75879,"Падение метеора"
-- Список отслеживаемых способностей

local METEORIT = 75879
local LUZHA = 75949
local LEZVIA = 77845
-- 74792 - metka

local spells = {
    [METEORIT] = " от метеорита",
    [LUZHA] = " в луже",
    [LEZVIA] = " в лезвиях"
}

function DeathTracker:OnEnable()
    self:RegisterMessage("TestAddon_CombatEnded", "reset")
end

function DeathTracker:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
    self:handleEvent(blizzardEvent(...), function(...)
        TestAddon:OnCombatLogEvent(...)
    end)
end

function DeathTracker:reset()
    self.dmgEvents = {}
    self.healEvents = {}
end

function DeathTracker:logDmg(playerName, event)
    self.dmgEvents[playerName] = event
end

function DeathTracker:logHeal(playerName, event)
    self.healEvents[playerName] = event
end

function DeathTracker:handleEvent(eventData, log)
    if bit.band(eventData.destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) > 0 then
        if eventData.event == "SPELL_DAMAGE" then
            self:logDmg(eventData.destName, {
                source = eventData.sourceName,
                amount = eventData.amount,
                spellId = eventData.spellId,
                spellName = eventData.spellName
            })
        elseif eventData.event == "SWING_DAMAGE" then
            self:logDmg(eventData.destName, {
                source = eventData.sourceName,
                amount = eventData.amount,
                spellName = "Автоатака"
            })
        elseif eventData.event == "UNIT_DIED" then
            self:ProcessPlayerDeath(log, eventData.destName, eventData.timestamp)
        end
        -- self:ProcessPlayerDeath(log, eventData.destName, eventData.timestamp)
    end
end

-- function DeathTracker:OnCombatEnd()
--     -- очищаем данные при выходе из боя
--     table.wipe(self.lastHealTime)
-- end

function DeathTracker:ProcessPlayerDeath(log, playerName, timestamp)
    local msg = string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t", date("%H:%M:%S", timestamp), playerName,
        "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")

    local lastDamage = self.dmgEvents[playerName]

    if lastDamage then
        TestAddon:Print("DeathTracker: Последний урон", lastDamage.source, lastDamage.spellName,
            lastDamage.amount)

        if spells[lastDamage.spellId] then
            msg = msg .. spells[lastDamage.spellId]
            log(playerName, msg)
        end
    end
end

-- -- Функция для парсинга временной метки из лога в секунды
-- function DeathTracker:ParseTimestamp(timestamp)
--     -- Формат времени в логе: MM/DD HH:mm:ss.SSS
--     local _, _, month, day, hour, min, sec, ms = string.find(timestamp, "(%d+)/(%d+)%s+(%d+):(%d+):(%d+)%.(%d+)")
--     if month and day and hour and min and sec and ms then
--         return hour * 3600 + min * 60 + sec + ms / 1000
--     end
--     return 0
-- end

-- function DeathTracker:GetHealthPercent(unitName)
--     local unit = self:GetUnitByName(unitName)
--     if unit then
--         local health = UnitHealth(unit)
--         local maxHealth = UnitHealthMax(unit)
--         if health and maxHealth and maxHealth > 0 then
--             return math.floor((health / maxHealth) * 100)
--         end
--     end
--     return 0
-- end

-- function DeathTracker:GetTimeSinceHeal(playerName)
--     local lastHeal = self.lastHealEvents:getAll()[1]
--     if lastHeal and lastHeal.target == playerName then
--         return math.floor(GetTime() - self:ParseTimestamp(lastHeal.timestamp))
--     end
--     return 0
-- end

function DeathTracker:GetUnitByName(name)
    local units = {"player", "party1", "party2", "party3", "party4", "raid1", "raid2", "raid3", "raid4", "raid5"}
    for _, unit in ipairs(units) do
        if UnitName(unit) == name then
            return unit
        end
    end
    return nil
end
