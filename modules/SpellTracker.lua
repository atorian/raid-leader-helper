local TestAddon = LibStub("AceAddon-3.0"):GetAddon("TestAddon")
local SppellTracker = TestAddon:NewModule("SppellTracker", "AceEvent-3.0")

function SppellTracker:OnEnable()
    TestAddon:Print("RL Быдло: TauntTracker включен")

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
    [5209] = "Interface\\Icons\\Ability_Druid_ChallangingRoar", -- Druid: Growl
    [10278] = "Interface\\Icons\\Spell_Holy_SealOfProtection", -- Paladin: Корона
    [31789] = "Interface\\Icons\\inv_shoulder_37", -- Paladin: Праведна защита
    [19752] = "Interface\\Icons\\Spell_Nature_TimeStop" -- Paladin: Hand of Protection (BoP)
}

function SppellTracker:OnInitialize()
    TestAddon:Print("RL Быдло: SppellTracker инициализируется")
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

function SppellTracker:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
    self:handleEvent(blizzardEvent(...), function(...)
        TestAddon:OnCombatLogEvent(...)
    end)
end

function SppellTracker:reset()
end

function SppellTracker:handleEvent(eventData, log)
    if (eventData.event == "SPELL_AURA_APPLIED") then
        if TRACKED_SPELLS[eventData.spellId] then
            log(eventData.sourceName,
                string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s", date("%H:%M:%S", eventData.timestamp),
                    eventData.sourceName, TRACKED_SPELLS[eventData.spellId], eventData.destName))
        end
    end
end

return SppellTracker
