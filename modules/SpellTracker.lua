local TestAddon = LibStub("AceAddon-3.0"):GetAddon("TestAddon")
local SppellTracker = TestAddon:NewModule("TauntTracker", "AceEvent-3.0")

function SppellTracker:OnEnable()
    TestAddon:Print("RL Быдло: TauntTracker включен")
    TestAddon:withHandler(function(...)
        self:handleEvent(...)
    end)
end

-- Таунты, короны, диваны.
-- Список отслеживаемых способностей
local TRACKED_SPELLS = {
    [355] = true,    -- Warrior: Taunt
    [694] = true,    -- Warrior: Mocking Blow
    [1161] = true,   -- Warrior: Challenging Shout
    [49560] = true,  -- Death Knight: Death Grip
    [51399] = true,  -- Death Knight: Death Grip Taunt Effect
    [56222] = true,  -- Death Knight: Dark Command
    [62124] = true,  -- Paladin: Hand of Reckoning
    [6795] = true,   -- Druid: Growl
    [66009] = true,  -- Paladin: Корона
    [10278] = true,  -- Paladin: Hand of Protection (BoP)
}

function SppellTracker:OnInitialize()
    TestAddon:Print("RL Быдло: SppellTracker инициализируется")
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

-- TODO: Register only SPELL_CAST_SUCCESS
function SppellTracker:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
    self:handleEvent(blizzardEvent(...), function (...)
        TestAddon:OnCombatLogEvent(...)
    end)
end

function SppellTracker:handleEvent(eventData, log)
    if (eventData.event == "SPELL_AURA_APPLIED") then
        if TRACKED_SPELLS[eventData.spellId] then
            log(eventData.sourceName, string.format(
                "%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s", 
                date("%H:%M:%S", eventData.timestamp), 
                eventData.sourceName, 
                GetSpellTexture(eventData.spellName), 
                eventData.destName
            ))
        end
    end
end

return SppellTracker