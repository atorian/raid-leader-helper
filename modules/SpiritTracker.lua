-- TODO: enable only when entering ICC
local TestAddon = LibStub("AceAddon-3.0"):GetAddon("TestAddon")
local SpiritTracker = TestAddon:NewModule("SpiritTracker", "AceEvent-3.0")

local TRACKED_SPELLS = {
    [71809] = "spirit_attack", -- Spirit Attack (Атака духа)
    [71426] = "spirit_summon", -- Призыв духа
    [72010] = "vengeful_blast" -- Вспышка мщения
}

local icon = "Interface\\Icons\\spell_shadow_deathsembrace"

local shieldOffRu = "Довольно! Пришла пора взять все в свои руки!"
local shieldOffEn = "Enough! I see I must take matters into my own hands!"

function SpiritTracker:OnInitialize()
    TestAddon:Debug("SpiritTracker: Инициализация")
    self.currentSpirits = {}
    self.report = {}
    self.log = function(...)
        TestAddon:OnCombatLogEvent(...)
    end
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self:RegisterEvent("CHAT_MSG_RAID_BOSS_EMOTE")
    self:RegisterMessage("TestAddon_CombatEnded", "reset")
    self:RegisterMessage("TestAddon_Demo", "demo")
end

function SpiritTracker:OnEnable()
    TestAddon:Debug("SpiritTracker: Включен")
end

local function formatShieldBroken(ts)
    return string.format("%s Леди: Щит разбит", date("%H:%M:%S", ts))
end

function SpiritTracker:CHAT_MSG_RAID_BOSS_EMOTE(msg)
    if msg == shieldOffRu or msg == shieldOffEn then
        self.log(formatShieldBroken(time()))
    end
end

-- function SpiritTracker:ZONE_CHANGED_NEW_AREA()
-- local 
-- if 
-- end

-- function SpiritTracker:PLAYER_ENTERING_WORLD()
--
-- end

function SpiritTracker:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
    self:handleEvent(blizzardEvent(...))
end

function SpiritTracker:reset()
    self.currentSpirits = {}

    if not self.report then
        self.report = {}
    end

    local msg = ""
    local names = {}
    for name in pairs(self.report) do
        table.insert(names, name)
    end
    table.sort(names, function(a, b)
        return self.report[a] > self.report[b]
    end)

    for _, name in ipairs(names) do
        msg = msg .. string.format(" %s(%s)", name, self.report[name])
    end

    if msg ~= "" then
        SendChatMessage("Духов взорвали: " .. msg, "RAID")
    end

    self.report = {}
end

local function formatSpiritHit(ts, dest)
    return string.format("%s |cFFFFFFFF%s|r взорвал духа |T%s:24:24:0:0|t", date("%H:%M:%S", ts), dest, icon)
end

local function formatSpiritMiss(ts, dest)
    return string.format("%s Дух автоатачил |cFFFFFFFF%s|r", date("%H:%M:%S", ts), dest)
end

function SpiritTracker:handleEvent(eventData)
    if eventData.event == "SPELL_SUMMON" and eventData.spellId == 71426 then
        self.currentSpirits[eventData.destGUID] = {
            name = eventData.destName,
            summonTime = eventData.timestamp
        }
        return
    end

    if eventData.event == "SWING_DAMAGE" then
        local spiritInfo = self.currentSpirits[eventData.sourceGUID]
        if not spiritInfo then
            return
        end

        self.report[eventData.destName] = self.report[eventData.destName] or 0
        self.report[eventData.destName] = self.report[eventData.destName] + 1

        self.log(formatSpiritHit(eventData.timestamp, eventData.destName))
        return
    end

    if eventData.event == "SWING_MISSED" then
        local spiritInfo = self.currentSpirits[eventData.sourceGUID]
        if not spiritInfo then
            return
        end

        self.log(formatSpiritMiss(eventData.timestamp, eventData.destName))
        return
    end
end

function SpiritTracker:demo()
    self.log(formatShieldBroken(time()))
    self.log(formatSpiritHit(time(), "Player"))
    self.log(formatSpiritMiss(time(), "Lucky"))
end

return SpiritTracker
