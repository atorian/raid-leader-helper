local TestAddon = LibStub("AceAddon-3.0"):GetAddon("TestAddon")
local DeathTracker = TestAddon:NewModule("DeathTracker", "AceEvent-3.0")

function DeathTracker:OnInitialize()
    TestAddon:Print("RL Быдло: DeathTracker инициализируется")
    self.dmgEvents = {}
    self.healEvents = {}
    self.firstEntered = false
    self.log = function(...)
        TestAddon:OnCombatLogEvent(...)
    end

    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
end

-- 67662 Ледной Рев
-- Список отслеживаемых способностей
local METEORIT = 75879
local LUZHA = 75949
local LEZVIA25OB = 77844
local LEZVIA10HM = 77845
local LEZVIA25HM = 77846
local pelena10 = 75483
local pelena25 = 75484
local pelena10hm = 75485
local pelena25hm = 75486
-- 74792 - metka

local meteor_icon = "Interface\\Icons\\spell_fire_meteorstorm"
local meteor_burn_icon = "Interface\\Icons\\spell_fire_fire"
local lezvia_icon = "Interface\\Icons\\Spell_Shadow_ShadowMend"

local spells = {
    [METEORIT] = string.format(" от метеорита |T%s:24:24:0:0|t", meteor_icon),
    [LUZHA] = string.format(" в луже |T%s:24:24:0:0|t", meteor_burn_icon),
    [LEZVIA10HM] = string.format(" в лезвиях |T%s:24:24:0:0|t", lezvia_icon),
    [LEZVIA25HM] = string.format(" в лезвиях |T%s:24:24:0:0|t", lezvia_icon),
    [LEZVIA25OB] = string.format(" в лезвиях |T%s:24:24:0:0|t", lezvia_icon)
}

function DeathTracker:OnEnable()
    self:RegisterMessage("TestAddon_CombatEnded", "reset")
    self:RegisterMessage("TestAddon_Demo", "demo")
end

function DeathTracker:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
    self:handleEvent(blizzardEvent(...), self.log)
end

function DeathTracker:reset()
    self.dmgEvents = {}
    self.healEvents = {}
    self.firstEntered = false
end

function DeathTracker:logDmg(playerName, event)
    self.dmgEvents[playerName] = event
end

function DeathTracker:logHeal(playerName, event)
    self.healEvents[playerName] = event
end

local function formatFirstInTwilight(ts, name)
    return string.format("%s |cFFFFFFFF%s|r зашел во тьму первый", date("%H:%M:%S", ts), name)
end

function DeathTracker:isFirstInDarkness(event, log)
    if not self.firstEntered and event.spellId >= pelena10 and event.spellId <= pelena25hm then
        self.firstEntered = true
        log(formatFirstInTwilight(event.timestamp, event.destName))
    end
end

local function isPlayer(flags)
    return bit.band(flags or 0, 0x7) > 0
end

-- todo: rename this method
local function isTwilightCutter(spellId)
    if not spellId then
        return false
    end
    return spellId >= pelena10 and spellId <= pelena25hm
end

function DeathTracker:handleEvent(event, log)
    if isPlayer(event.destFlags) then
        if isTwilightCutter(event.spellId) then
            self:isFirstInDarkness(event, log)
        elseif event.event == "SPELL_DAMAGE" then
            self:logDmg(event.destName, {
                source = event.sourceName,
                amount = event.amount,
                spellId = event.spellId,
                spellName = event.spellName
            })
        elseif event.event == "SWING_DAMAGE" then
            self:logDmg(event.destName, {
                source = event.sourceName,
                amount = event.amount,
                spellName = "Автоатака"
            })
        elseif event.event == "UNIT_DIED" then
            self:ProcessPlayerDeath(log, event.destName, event.timestamp)
        end
    end
end

local function formatDiedFrom(ts, name)
    return string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t", date("%H:%M:%S", ts), name,
        "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")
end

function DeathTracker:ProcessPlayerDeath(log, playerName, timestamp)
    local msg = formatDiedFrom(timestamp, playerName)
    local lastDamage = self.dmgEvents[playerName]

    if lastDamage then
        if spells[lastDamage.spellId] then
            log(msg .. spells[lastDamage.spellId])
        end
    end
end

function DeathTracker:demo()
    self.log(formatFirstInTwilight(time(), "PlayerName"))
    self.log(formatDiedFrom(time(), "PlayerName") .. spells[METEORIT])
    self.log(formatDiedFrom(time(), "PlayerName") .. spells[LUZHA])
    self.log(formatDiedFrom(time(), "PlayerName") .. spells[LEZVIA25HM])
end

return DeathTracker
