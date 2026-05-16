local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local HalionTracker = RLHelper:NewModule("HalionTracker", "AceEvent-3.0")
HalionTracker.receivesCombatEvents = true
HalionTracker.zoneGateInstanceId = 724 -- The Ruby Sanctum
HalionTracker.bossIds = {
    [39863] = "Халион",
    [40142] = "Халион"
}

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

local MATERIALITY_AURAS = {
    [74826] = "50% баланс",
    [74827] = "60% физический мир",
    [74828] = "70% физический мир",
    [74829] = "80% физический мир",
    [74830] = "90% физический мир",
    [74831] = "100% физический мир",
    [74832] = "40% во тьме",
    [74833] = "30% во тьме",
    [74834] = "20% во тьме",
    [74835] = "10% во тьме",
    [74836] = "0% во тьме"
}

local DARKNESS_MATERIALITY_DROPS = {
    [74832] = true,
    [74833] = true,
    [74834] = true,
    [74835] = true,
    [74836] = true
}

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

local function isHalionBurstPullEnabled()
    return type(RLHelper.IsHalionBurstPullEnabled) == "function" and RLHelper:IsHalionBurstPullEnabled()
end

local function isHalionBurstResetEnabled()
    return type(RLHelper.IsHalionBurstResetEnabled) ~= "function" or RLHelper:IsHalionBurstResetEnabled()
end

local function isEnemy(flags)
    return bit.band(flags or 0, RLHelper.ENEMY_FLAGS or 0xa48) > 0
end

local function prepareSkadaBossSegment(set, mobname, gotboss, suffix)
    if type(set) ~= "table" then
        return mobname, gotboss
    end

    mobname = mobname or set.mobname or "Halion"
    gotboss = gotboss or set.gotboss or true

    set.mobname = suffix and (mobname .. suffix) or (set.mobname or mobname)
    set.gotboss = set.gotboss or gotboss

    return mobname, gotboss
end

local function getDetailsCurrentCombat(details)
    if type(details) ~= "table" then
        return nil
    end

    if type(details.GetCurrentCombat) == "function" then
        return details:GetCurrentCombat()
    end

    if type(details.GetCombat) == "function" then
        return details:GetCombat("current")
    end

    return details.tabela_vigente
end

local function prepareDetailsBossSegment(details, mobname, suffix)
    local combat = getDetailsCurrentCombat(details)
    if type(combat) ~= "table" then
        return mobname
    end

    local boss = type(combat.is_boss) == "table" and combat.is_boss or nil
    mobname = mobname or (boss and (boss.encounter or boss.name)) or combat.enemy or "Halion"

    local segmentName = suffix and (mobname .. suffix) or mobname
    combat.enemy = segmentName
    combat.is_boss = boss or {}
    combat.is_boss.name = segmentName
    combat.is_boss.encounter = segmentName

    return mobname
end

function HalionTracker:OnEnable()
    self:RegisterMessage("RLHelper_CombatEnded", "reset")
    self:RegisterMessage("RLHelper_Demo", "demo")
end

function HalionTracker:reset()
    self.dmgEvents = {}
    self.healEvents = {}
    self.firstEntered = false
    self.damageMetersReset = false
    self.materialityPullStarted = false
    self.bossName = nil
end

function HalionTracker:debugReset(message, ...)
    RLHelper:Debug("HalionTracker: " .. string.format(message, ...))
end

function HalionTracker:GetBossSegmentName()
    if self.bossName then
        return self.bossName
    end

    if RLHelper.currentCombat and RLHelper.currentCombat.firstEnemy then
        return RLHelper.currentCombat.firstEnemy
    end

    if type(UnitName) == "function" then
        return UnitName("boss1")
    end
end

function HalionTracker:RememberBossName(event)
    if isEnemy(event.sourceFlags) and event.sourceName then
        self.bossName = event.sourceName
    elseif isEnemy(event.destFlags) and event.destName then
        self.bossName = event.destName
    end
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
        local mobname = prepareDetailsBossSegment(details, self:GetBossSegmentName())
        if details.in_combat then
            details:SairDoCombate()
        end

        details:EntrarEmCombate()
        prepareDetailsBossSegment(details, mobname, " Burst")
        return true
    end

    return false, "Details current-fight reset API not found"
end

function HalionTracker:tryResetSkada()
    if type(Skada) ~= "table" then
        return false, "Skada not loaded"
    end

    if type(Skada.NewSegment) == "function" and Skada.current then
        local mobname, gotboss = prepareSkadaBossSegment(Skada.current, self:GetBossSegmentName())
        Skada:NewSegment()
        prepareSkadaBossSegment(Skada.current, mobname, gotboss, " Burst")
        return true
    end

    if type(Skada.StartCombat) == "function" and not Skada.current then
        Skada:StartCombat()
        prepareSkadaBossSegment(Skada.current, self:GetBossSegmentName())
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
    if not isHalionBurstResetEnabled() or self.damageMetersReset or event.event ~= "SPELL_AURA_APPLIED" or not HEROISM_SPELLS[event.spellId] then
        return
    end

    self.damageMetersReset = true
    self:resetDamageMeters()
end

function HalionTracker:debugMateriality(event)
    local materiality = MATERIALITY_AURAS[event.spellId]
    if event.event ~= "SPELL_AURA_APPLIED" or not materiality then
        return
    end

    RLHelper:Debug(string.format("HalionTracker: Материальность %s (spellId=%s)", materiality, event.spellId))
end

function HalionTracker:tryStartPullOnMaterialityDrop(event)
    if type(RLHelper.StartDBMPullCommand) ~= "function" or not isHalionBurstPullEnabled() or self.materialityPullStarted or event.event ~= "SPELL_AURA_APPLIED" or not DARKNESS_MATERIALITY_DROPS[event.spellId] then
        return
    end

    self.materialityPullStarted = true
    RLHelper:StartDBMPullCommand(15)
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
    self:RememberBossName(event)
    self:debugMateriality(event)
    self:tryStartPullOnMaterialityDrop(event)

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
