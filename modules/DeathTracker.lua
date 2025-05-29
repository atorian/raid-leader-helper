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

-- COMBATLOG_OBJECT_TYPE_PLAYER
function DeathTracker:handleEvent(eventData, log)
    if bit.band(eventData.destFlags, COMBATLOG_OBJECT_AFFILIATION_RAID) > 0 then
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
            log(msg)
        end
    end
end
