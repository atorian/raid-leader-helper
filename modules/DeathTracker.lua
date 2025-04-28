local TestAddon = LibStub("AceAddon-3.0"):GetAddon("TestAddon")
local DeathTracker = TestAddon:NewModule("DeathTracker", "AceEvent-3.0")

function DeathTracker:OnInitialize()
    TestAddon:Print("RL Быдло: DeathTracker инициализируется")
    self.dmgEvents = {}
    self.healEvents = {}
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

function DeathTracker:OnEnable()
    TestAddon:Print("DeathTracker: Включен")
    TestAddon:withHandler(function(...)
        self:handleEvent(...)
    end)
end
    
function DeathTracker:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
    self:handleEvent(...)
end


function DeathTracker:logDmg(playerName, eventData)
    if self.dmgEvents[playerName] == nil then
        self.dmgEvents[playerName] = createRingBuffer(3)
    end

    self.dmgEvents[playerName]:add(eventData)
end

function DeathTracker:logHeal(playerName, event)
    -- TestAddon:Print("DeathTracker: Лог хилов", self.healEvents)
    if self.healEvents[playerName] == nil then
        self.healEvents[playerName] = createRingBuffer(3)
    end

    self.healEvents[playerName]:add(event)
end

function DeathTracker:handleEvent(...)
    local eventData = blizzardEvent(...)
    if eventData.event == "SPELL_HEAL" or eventData.event == "SPELL_PERIODIC_HEAL" then
        if bit.band(eventData.destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) > 0 then
            self:logHeal(eventData.destName, {
                timestamp = eventData.timestamp,
                type = eventData.event == "SPELL_PERIODIC_HEAL" and "hot" or "heal",
                source = eventData.sourceName,
                target = eventData.destName,
                amount = eventData.amount,
                overhealing = eventData.overhealing,
                absorbed = eventData.absorbed,
                spellName = eventData.spellName
            })
        end
    -- Обработка смерти
    elseif eventData.event == "UNIT_DIED" then
        if bit.band(eventData.destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) > 0 then
            self:ProcessPlayerDeath(eventData.destName, eventData.timestamp)
        end
    -- Обработка различных типов урона
    elseif eventData.event == "SWING_DAMAGE" then
        if bit.band(eventData.destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) > 0 then
            self:logDmg(eventData.destName, {
                timestamp = eventData.timestamp,
                type = "melee",
                source = eventData.sourceName,
                amount = eventData.amount,
                spellName = "Автоатака"
            })
        end
    elseif eventData.event == "RANGE_DAMAGE" then
        if bit.band(eventData.destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) > 0 then
            self:logDmg(eventData.destName, {
                timestamp = eventData.timestamp,
                type = "range",
                source = eventData.sourceName,
                amount = eventData.amount,
                spellName = eventData.spellName
            })
        end
    elseif eventData.event == "SPELL_DAMAGE" or eventData.event == "SPELL_PERIODIC_DAMAGE" then
        if bit.band(eventData.destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) > 0 then
            self:logDmg(eventData.destName, {
                timestamp = eventData.timestamp,
                type = "spell",
                source = eventData.sourceName,
                amount = eventData.amount,
                spellName = eventData.spellName
            })
        end
    elseif eventData.event == "ENVIRONMENTAL_DAMAGE" then
        if bit.band(eventData.destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) > 0 then
            self:logDmg(eventData.destName, {
                timestamp = eventData.timestamp,
                type = "environmental",
                source = eventData.environmentalType,
                amount = eventData.amount,
                spellName = "Урон от окружения (" .. eventData.environmentalType .. ")"
            })
        end
    end
end

-- function DeathTracker:OnCombatEnd()
--     -- очищаем данные при выходе из боя
--     table.wipe(self.lastHealTime)
-- end

function DeathTracker:ProcessPlayerDeath(playerName, timestamp)
    -- Первое событие: смерть и последний урон
    local deathData = {} 
    deathData[1] = Text(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t", date("%H:%M:%S", timestamp), playerName, "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"))
    -- Получаем информацию о последнем уроне
    local lastDamage = self.dmgEvents[playerName]:getAll()[1]
    if lastDamage then
        TestAddon:Print("DeathTracker: Последний урон", lastDamage.timestamp, lastDamage.source, lastDamage.spellName, lastDamage.amount)
        if lastDamage.type == "spell" or lastDamage.type == "range" then
            deathData[1] = Text(string.format(
                "%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t от |T%s:24:24:0:0|t(%s) %s", 
                date("%H:%M:%S", timestamp), 
                playerName, 
                "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", 
                GetSpellTexture(lastDamage.spellName) or "Interface\\Icons\\INV_Misc_QuestionMark", 
                lastDamage.amount,
                lastDamage.source
            )) 
        else
            deathData[1] = Text(string.format(
                "%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t от %s(%s) %s", 
                date("%H:%M:%S", timestamp), 
                playerName, 
                "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8", 
                lastDamage.spellName, 
                lastDamage.amount,
                lastDamage.source
            ))
        end
    end
    -- Отправляем первое событие
    TestAddon:OnCombatLogEvent(playerName, deathData)

    local healData = {}
    if self.healEvents[playerName] == nil then
        healData[1] = Text(string.format("%s |cFFFFFFFF%s|r никто не хилил", date("%H:%M:%S", timestamp), playerName))
    else
        local lastHeal = self.healEvents[playerName]:getAll()[1]
        
        if lastHeal then
            -- Парсим временные метки для расчета разницы во времени
            local t1 = self:ParseTimestamp(lastHeal.timestamp)
            local t2 = self:ParseTimestamp(timestamp)
            local timeDiff = t2 - t1
            
            healData[1] = Text(string.format("%s |cFFFFFFFF%s|r последний хил: %s от %s (%d) %.1f сек назад", 
                date("%H:%M:%S", timestamp), 
                playerName,
                lastHeal.spellName,
                lastHeal.source,
                lastHeal.amount,
                timeDiff
            ))
        end
    end

    -- Отправляем второе событие
    TestAddon:OnCombatLogEvent(playerName, healData)
end

-- Функция для парсинга временной метки из лога в секунды
function DeathTracker:ParseTimestamp(timestamp)
    -- Формат времени в логе: MM/DD HH:mm:ss.SSS
    local _, _, month, day, hour, min, sec, ms = string.find(timestamp, "(%d+)/(%d+)%s+(%d+):(%d+):(%d+)%.(%d+)")
    if month and day and hour and min and sec and ms then
        return hour * 3600 + min * 60 + sec + ms/1000
    end
    return 0
end

function DeathTracker:GetHealthPercent(unitName)
    local unit = self:GetUnitByName(unitName)
    if unit then
        local health = UnitHealth(unit)
        local maxHealth = UnitHealthMax(unit)
        if health and maxHealth and maxHealth > 0 then
            return math.floor((health / maxHealth) * 100)
        end
    end
    return 0
end

function DeathTracker:GetTimeSinceHeal(playerName)
    local lastHeal = self.lastHealEvents:getAll()[1]
    if lastHeal and lastHeal.target == playerName then
        return math.floor(GetTime() - self:ParseTimestamp(lastHeal.timestamp))
    end
    return 0
end

function DeathTracker:GetUnitByName(name)
    local units = {"player", "party1", "party2", "party3", "party4", "raid1", "raid2", "raid3", "raid4", "raid5"}
    for _, unit in ipairs(units) do
        if UnitName(unit) == name then
            return unit
        end
    end
    return nil
end
