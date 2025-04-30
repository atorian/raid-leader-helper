local TestAddon = LibStub("AceAddon-3.0"):GetAddon("TestAddon")
local SpiritTracker = TestAddon:NewModule("SpiritTracker", "AceEvent-3.0")

local TRACKED_SPELLS = {
    [71809] = "spirit_attack", -- Spirit Attack (Атака духа)
    [71426] = "spirit_summon", -- Призыв духа
    [72010] = "vengeful_blast" -- Вспышка мщения
}

function SpiritTracker:OnInitialize()
    TestAddon:Print("SpiritTracker: Инициализация")
    self.currentSpirits = {}
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

function SpiritTracker:OnEnable()
    TestAddon:Print("SpiritTracker: Включен")
    TestAddon:withHandler(function(...)
        self:handleEvent(...)
    end)
end

function SpiritTracker:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
    self:handleEvent(blizzardEvent(...), function (...)
        TestAddon:OnCombatLogEvent(...)
    end)
end

function SpiritTracker:reset()
    self.currentSpirits = {};
end

function SpiritTracker:handleEvent(eventData, log)
    if eventData.event == "SPELL_SUMMON" and eventData.spellId == 71426 then
        self.currentSpirits[eventData.destGUID] = {
            name = eventData.destName,
            summonTime = eventData.timestamp,
        }
        return
    end
    
    if eventData.event == "SWING_DAMAGE" then
        local spiritInfo = self.currentSpirits[eventData.sourceGUID]
        if not spiritInfo then return end
        
        log(eventData.destName, string.format(
            "%s |cFFFFFFFF%s|r взорвал духа", 
            date("%H:%M:%S", eventData.timestamp), 
            eventData.destName
        ))

        return
    end
    
    if eventData.event == "SWING_MISSED" then
        local spiritInfo = self.currentSpirits[eventData.sourceGUID]
        if not spiritInfo then return end
        
        log(eventData.destName, string.format(
            "%s Дух автоатачил |cFFFFFFFF%s|r", 
            date("%H:%M:%S", eventData.timestamp), 
            eventData.destName
        ))

        return
    end
end


return SpiritTracker