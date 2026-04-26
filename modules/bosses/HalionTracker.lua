local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local HalionTracker = RLHelper:NewModule("HalionTracker", "AceEvent-3.0")
HalionTracker.receivesCombatEvents = true
HalionTracker.zoneGateInstanceId = 724 -- The Ruby Sanctum

function HalionTracker:OnInitialize()
    RLHelper:Debug("HalionTracker инициализируется")
    self.dmgEvents = {}
    self.healEvents = {}
    self.firstEntered = false
    self.log = function(...)
        RLHelper:OnCombatLogEvent(...)
    end

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
local HEROISM = 32182
local BLOODLUST = 2825
local MAX_DMG_EVENTS_PER_PLAYER = 10
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

local HEROISM_SPELLS = {
    [HEROISM] = true,
    [BLOODLUST] = true
}

function HalionTracker:OnEnable()
    self:RegisterMessage("RLHelper_CombatEnded", "reset")
    self:RegisterMessage("RLHelper_Demo", "demo")
end

function HalionTracker:reset()
    self.dmgEvents = {}
    self.healEvents = {}
    self.firstEntered = false
    self.damageMetersReset = false
end

function HalionTracker:debugReset(message, ...)
    RLHelper:Debug("HalionTracker: " .. string.format(message, ...))
end

function HalionTracker:tryResetRecount()
    if type(Recount) ~= "table" then
        return false, "Recount not loaded"
    end

    if type(Recount.ResetFightData) == "function" then
        Recount:ResetFightData()
        return true
    end

    return false, "Recount current-fight reset API not found"
end

function HalionTracker:tryResetDetails()
    local details = _G._detalhes or _G.Details
    if type(details) ~= "table" then
        return false, "Details not loaded"
    end

    if type(details.SairDoCombate) == "function" and type(details.EntrarEmCombate) == "function" then
        if details.in_combat then
            details:SairDoCombate()
        end

        details:EntrarEmCombate()
        return true
    end

    return false, "Details current-fight reset API not found"
end

function HalionTracker:tryResetSkada()
    if type(Skada) ~= "table" then
        return false, "Skada not loaded"
    end

    if type(Skada.NewSegment) == "function" and Skada.current then
        Skada:NewSegment()
        return true
    end

    if type(Skada.StartCombat) == "function" and not Skada.current then
        Skada:StartCombat()
        return true
    end

    return false, "Skada current-fight reset API not found"
end

function HalionTracker:resetDamageMeters()
    local resetters = {
        { name = "Recount", fn = self.tryResetRecount },
        { name = "Details", fn = self.tryResetDetails },
        { name = "Skada", fn = self.tryResetSkada }
    }
    local anyReset = false

    for _, resetter in ipairs(resetters) do
        local ok, success, err = pcall(resetter.fn, self)
        if not ok then
            self:debugReset("%s reset failed: %s", resetter.name, tostring(success))
        elseif not success then
            self:debugReset("%s reset skipped: %s", resetter.name, tostring(err))
        else
            anyReset = true
        end
    end

    return anyReset
end

function HalionTracker:tryResetDamageMetersOnHeroism(event)
    if self.damageMetersReset or event.event ~= "SPELL_AURA_APPLIED" or not HEROISM_SPELLS[event.spellId] then
        return
    end

    self.damageMetersReset = true
    self:resetDamageMeters()
end

function HalionTracker:logDmg(playerName, event)
    if not self.dmgEvents[playerName] then
        self.dmgEvents[playerName] = {}
    end

    table.insert(self.dmgEvents[playerName], event)

    while #self.dmgEvents[playerName] > MAX_DMG_EVENTS_PER_PLAYER do
        table.remove(self.dmgEvents[playerName], 1)
    end
end

function HalionTracker:logHeal(playerName, event)
    self.healEvents[playerName] = event
end

local function formatFirstInTwilight(ts, name)
    return string.format("%s |cFFFFFFFF%s|r зашел во тьму первый", date("%H:%M:%S", ts), name)
end

function HalionTracker:isFirstInDarkness(event, log)
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

function HalionTracker:handleEvent(event, log)
    if isPlayer(event.destFlags) then
        self:tryResetDamageMetersOnHeroism(event)

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

function HalionTracker:ProcessPlayerDeath(log, playerName, timestamp)
    local msg = formatDiedFrom(timestamp, playerName)
    local damageEvents = self.dmgEvents[playerName]

    if damageEvents then
        for i = #damageEvents, 1, -1 do
            local lastDamage = damageEvents[i]
            if spells[lastDamage.spellId] then
                log(msg .. spells[lastDamage.spellId])
                break
            end
        end
    end

    self.dmgEvents[playerName] = nil
end

function HalionTracker:demo()
    self.log(formatFirstInTwilight(time(), "PlayerName"))
    self.log(formatDiedFrom(time(), "PlayerName") .. spells[METEORIT])
    self.log(formatDiedFrom(time(), "PlayerName") .. spells[LUZHA])
    self.log(formatDiedFrom(time(), "PlayerName") .. spells[LEZVIA25HM])
end

return HalionTracker
