local TestAddon = LibStub("AceAddon-3.0"):GetAddon("TestAddon")
local SppellTracker = TestAddon:NewModule("SppellTracker", "AceEvent-3.0")

-- Флаг для отслеживания первого урона
local firstDamageDone = false

function SppellTracker:OnEnable()
    TestAddon:Print("RL Быдло: TauntTracker включен")
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
    [5209] = "Interface\\Icons\\Ability_Druid_ChallangingRoar", -- Druid: Growl
    [10278] = "Interface\\Icons\\Spell_Holy_SealOfProtection", -- Paladin: Корона
    [31789] = "Interface\\Icons\\inv_shoulder_37", -- Paladin: Праведна защита
    [19752] = "Interface\\Icons\\Spell_Nature_TimeStop", -- Paladin: Hand of Protection (BoP)
    [26994] = "Interface\\Icons\\spell_nature_reincarnation", -- Друид БР
    [48477] = "Interface\\Icons\\spell_nature_reincarnation" -- Друид БР
}

function SppellTracker:OnInitialize()
    TestAddon:Debug("RL Быдло: SppellTracker инициализируется")
    self.log = function(...)
        TestAddon:OnCombatLogEvent(...)
    end
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self:RegisterMessage("TestAddon_CombatEnded", "reset")
end

function SppellTracker:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
    self:handleEvent(blizzardEvent(...), self.log)
end

function SppellTracker:reset()
    TestAddon:Debug("SppellTracker Got Reset")
    firstDamageDone = false
end

local PLAYER_FLAGS = 0x7
local ENEMY_FLAGS = 0xa48

local function isPlayer(flags)
    return bit.band(flags or 0, PLAYER_FLAGS) > 0
end

local function isEnemy(flags)
    return bit.band(flags or 0, ENEMY_FLAGS) > 0
end

function SppellTracker:handleEvent(eventData, log)
    if not firstDamageDone and (eventData.event == "SWING_DAMAGE" or eventData.event == "SPELL_DAMAGE") then
        if isPlayer(eventData.sourceFlags) and isEnemy(eventData.destFlags) then
            TestAddon:Debug("First damage", eventData.sourceName, eventData.destName)
            firstDamageDone = true
            log(string.format("%s |cFFFFFFFF%s|r Первый урон по |cFFFFFFFF%s|r",
                date("%H:%M:%S", eventData.timestamp), eventData.sourceName, eventData.destName))
        end
    end

    if (eventData.event == "SPELL_AURA_APPLIED") then
        if TRACKED_SPELLS[eventData.spellId] then
            log(string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t %s", date("%H:%M:%S", eventData.timestamp),
                eventData.sourceName, TRACKED_SPELLS[eventData.spellId], eventData.destName))
        end
    end
end

return SppellTracker
