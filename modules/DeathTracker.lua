local TestAddon = LibStub("AceAddon-3.0"):GetAddon("TestAddon")
local DeathTracker = TestAddon:NewModule("DeathTracker", "AceEvent-3.0")

function DeathTracker:OnInitialize()
    TestAddon:Print("RL Быдло: DeathTracker инициализируется")
    self.dmgEvents = {}
    self.healEvents = {}
    self.firstEntered = false
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
end

function DeathTracker:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
    self:handleEvent(blizzardEvent(...), function(...)
        TestAddon:OnCombatLogEvent(...)
    end)
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

local function isFirstInDarkness(event, log)
    if not self.firstEntered and event.spellId >= pelena10 and event.spellId <= pelena25hm then
        self.firstEntered = true
        log(string.format("%s |cFFFFFFFF%s|r зашел во тьму первый", date("%H:%M:%S", event.timestamp),
            event.destName))
    end
end

function DeathTracker:handleEvent(event, log)
    if TestAddon:isPlayer(event.destFlags) then
        if event.spellId == event.spellId >= pelena10 and event.spellId <= pelena25hm then
            isFirstInDarkness(event, log)
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

function DeathTracker:ProcessPlayerDeath(log, playerName, timestamp)
    local msg = string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t", date("%H:%M:%S", timestamp), playerName,
        "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8")

    local lastDamage = self.dmgEvents[playerName]

    if lastDamage then
        if spells[lastDamage.spellId] then
            msg = msg .. spells[lastDamage.spellId]
            log(msg)
        end
    end
end
