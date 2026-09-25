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
local LIGHT_HALION_ID = 39863
local DARK_HALION_ID = 40142
local pelena10 = 75483
local pelena25 = 75484
local pelena10hm = 75485
local pelena25hm = 75486
local HEROISM = 32182
local BLOODLUST = 2825
local MAX_DMG_EVENTS_PER_PLAYER = 10
local DEATH_CHECK_INTERVAL = 0.2
local DEATH_CHECK_DURATION = 3
-- DBM-RS: first cutters end 30/35 + 5 + 10 seconds after the phase-two yell.
local PHASE_TWO_ENTRY_TIMER_DURATION = 15
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
    [74835] = true
}

local spells = {
    [METEORIT] = true,
    [LUZHA] = true,
    [LEZVIA10HM] = true,
    [LEZVIA25HM] = true,
    [LEZVIA25OB] = true
}

local HEROISM_SPELLS = {
    [HEROISM] = true,
    [BLOODLUST] = true
}

local DAMAGE_EVENTS = {
    SWING_DAMAGE = true,
    RANGE_DAMAGE = true,
    SPELL_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true,
    DAMAGE_SHIELD = true
}

local PHASE_TWO_YELLS = {
    ["В мире сумерек вы найдете лишь страдания! Входите, если посмеете!"] = true,
    ["You will find only suffering within the realm of twilight! Enter if you dare!"] = true
}

local METEOR_YELLS = {
    ["Небеса в огне!"] = true,
    ["The heavens burn!"] = true
}

local function isHalionBurstPullEnabled()
    return type(RLHelper.IsHalionBurstPullEnabled) == "function" and RLHelper:IsHalionBurstPullEnabled()
end

local function isHalionBurstResetEnabled()
    return type(RLHelper.IsHalionBurstResetEnabled) ~= "function" or RLHelper:IsHalionBurstResetEnabled()
end

local function isHalionPhaseTwoEntryTimerEnabled()
    return type(RLHelper.IsHalionPhaseTwoEntryTimerEnabled) == "function" and RLHelper:IsHalionPhaseTwoEntryTimerEnabled()
end

local function isEnemy(flags, guid)
    return not RLHelper:IsGroupMember(guid, flags) and bit.band(flags or 0, RLHelper.ENEMY_FLAGS or 0xa48) > 0
end

local function creatureIdFromGuid(guid)
    if type(RLHelper.GetCreatureId) == "function" then
        return RLHelper.GetCreatureId(guid)
    end

    return type(guid) == "string" and tonumber(guid:sub(9, 12), 16) or nil
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
    self:RegisterEvent("CHAT_MSG_MONSTER_YELL")
end

function HalionTracker:reset()
    for _, check in pairs(self.deathChecks or {}) do
        check.timer:Cancel()
    end
    self.deathChecks = {}
    if self.phaseTwoEntryTimer then
        self.phaseTwoEntryTimer:Cancel()
        self.phaseTwoEntryTimer = nil
    end
    self.dmgEvents = {}
    self.healEvents = {}
    self.firstEntered = false
    self.damageMetersReset = false
    self.materialityPullStarted = false
    self.phaseTwoStarted = false
    self.meteorYellCount = 0
    self.bossName = nil
    self.firstLightDamageWindowOpen = false
    self.firstLightDamageLogged = false
end

function HalionTracker:OnDisable()
    self:reset()
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
    if isEnemy(event.sourceFlags, event.sourceGUID) and event.sourceName then
        self.bossName = event.sourceName
    elseif isEnemy(event.destFlags, event.destGUID) and event.destName then
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

function HalionTracker:trackFirstLightHalionDamage(event, log)
    if event.event == "SPELL_AURA_APPLIED" and event.spellId == 74835 and creatureIdFromGuid(event.destGUID) == DARK_HALION_ID then
        self.firstLightDamageWindowOpen = true
        self.firstLightDamageLogged = false
        return
    end

    if not self.firstLightDamageWindowOpen then
        return
    end

    if event.event == "SPELL_AURA_APPLIED" and event.spellId == 74831 and creatureIdFromGuid(event.destGUID) == LIGHT_HALION_ID then
        self.firstLightDamageWindowOpen = false
        return
    end

    if event.event == "SPELL_AURA_APPLIED" and HEROISM_SPELLS[event.spellId] then
        self.firstLightDamageWindowOpen = false
        RLHelperJournal.Log(log, "LIGHT_DAMAGE_WINDOW_CLOSED", event)
        return
    end

    if not self.firstLightDamageLogged and DAMAGE_EVENTS[event.event] and
        RLHelper:IsGroupMember(event.sourceGUID, event.sourceFlags) and creatureIdFromGuid(event.destGUID) == LIGHT_HALION_ID then
        self.firstLightDamageLogged = true
        RLHelperJournal.Log(log, "FIRST_LIGHT_DAMAGE", event)
    end
end

function HalionTracker:CHAT_MSG_MONSTER_YELL(eventName, message)
    if METEOR_YELLS[message] then
        self.meteorYellCount = (self.meteorYellCount or 0) + 1
        return
    end

    if not PHASE_TWO_YELLS[message] or self.phaseTwoStarted then
        return
    end

    self.phaseTwoStarted = true
    if type(RLHelper.StartDBMPullCommand) ~= "function" or not isHalionPhaseTwoEntryTimerEnabled() or (self.meteorYellCount or 0) < 2 then
        return
    end

    local _, _, difficulty, _, _, dynamicDifficulty, isDynamic = GetInstanceInfo()
    local heroic = difficulty == 3 or difficulty == 4 or (isDynamic and dynamicDifficulty == 1)
    local timerApi = RLHelper.C_Timer or C_Timer
    local handle
    handle = timerApi.NewTimer(heroic and 30 or 35, function()
        if self.phaseTwoEntryTimer ~= handle then
            return
        end

        self.phaseTwoEntryTimer = nil
        if isHalionPhaseTwoEntryTimerEnabled() then
            RLHelper:StartDBMPullCommand(PHASE_TWO_ENTRY_TIMER_DURATION)
        end
    end)
    self.phaseTwoEntryTimer = handle
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

-- Roster state can confirm a death when UNIT_DIED is missing from the combat log.
function HalionTracker:StopDeathCheck(guid)
    local check = self.deathChecks and self.deathChecks[guid]
    if check then
        check.timer:Cancel()
        self.deathChecks[guid] = nil
    end
end

function HalionTracker:StartDeathCheck(event)
    if self.context or not event.destGUID or not spells[event.spellId] then
        return
    end

    local guid = event.destGUID
    self:StopDeathCheck(guid)
    self.deathChecks = self.deathChecks or {}
    local startedAt = GetTime()
    local check = {}
    self.deathChecks[guid] = check
    local timerApi = RLHelper.C_Timer or C_Timer
    check.timer = timerApi.NewTicker(DEATH_CHECK_INTERVAL, function()
        if self.deathChecks[guid] ~= check then return end
        local elapsed = GetTime() - startedAt
        if elapsed > DEATH_CHECK_DURATION then
            self:StopDeathCheck(guid)
            return
        end
        local found = false
        for i = 1, GetNumRaidMembers() do
            if UnitGUID("raid" .. i) == guid then
                found = true
                local _, _, _, _, _, _, _, online, isDead = GetRaidRosterInfo(i)
                if online and isDead then
                    self:ProcessPlayerDeath(self.log, event.destName, event.timestamp + elapsed, guid)
                    return
                end
                break
            end
        end
        if not found or elapsed >= DEATH_CHECK_DURATION then
            self:StopDeathCheck(guid)
        end
    end)
end

function HalionTracker:logHeal(playerName, event)
    self.healEvents[playerName] = event
end

function HalionTracker:isFirstInDarkness(event, log)
    if not self.firstEntered and event.spellId >= pelena10 and event.spellId <= pelena25hm then
        self.firstEntered = true
        RLHelperJournal.Log(log, "FIRST_TWILIGHT_ENTRY", event)
    end
end

-- todo: rename this method
local function isTwilightCutter(spellId)
    if not spellId then
        return false
    end
    return spellId >= pelena10 and spellId <= pelena25hm
end

function HalionTracker:handleEvent(event)
    local log = self.log
    self:RememberBossName(event)
    self:debugMateriality(event)
    self:tryStartPullOnMaterialityDrop(event)
    self:trackFirstLightHalionDamage(event, log)

    if RLHelper:IsGroupMember(event.destGUID, event.destFlags) then
        self:tryResetDamageMetersOnHeroism(event)

        if isTwilightCutter(event.spellId) then
            self:isFirstInDarkness(event, log)
        elseif event.event == "SPELL_DAMAGE" then
            self:logDmg(event.destName, {
                source = event.sourceName,
                sourceGUID = event.sourceGUID,
                amount = event.amount,
                spellId = event.spellId,
                spellName = event.spellName
            })
            self:StartDeathCheck(event)
        elseif event.event == "SWING_DAMAGE" then
            self:logDmg(event.destName, {
                source = event.sourceName,
                sourceGUID = event.sourceGUID,
                amount = event.amount,
                spellName = "Автоатака"
            })
        elseif event.event == "UNIT_DIED" then
            self:ProcessPlayerDeath(log, event.destName, event.timestamp, event.destGUID)
        end
    end
end

function HalionTracker:ProcessPlayerDeath(log, playerName, timestamp, playerGUID)
    self:StopDeathCheck(playerGUID)
    local damageEvents = self.dmgEvents[playerName]

    if damageEvents then
        for i = #damageEvents, 1, -1 do
            local lastDamage = damageEvents[i]
            if spells[lastDamage.spellId] then
                RLHelperJournal.Log(log, "MECHANIC_DEATH", {
                    timestamp = timestamp, destGUID = playerGUID, destName = playerName,
                    sourceGUID = lastDamage.sourceGUID, sourceName = lastDamage.source,
                    spellId = lastDamage.spellId
                }, "TACTIC_VIOLATION")
                break
            end
        end
    end

    self.dmgEvents[playerName] = nil
end

HalionTracker.demoOrder = 9
function HalionTracker:RunDemo(demo)
    self:reset()
    -- Demo never starts DBM pulls or switches damage-meter segments.
    self.damageMetersReset, self.materialityPullStarted = true, true
    local p = demo.players
    local light = demo:Boss(LIGHT_HALION_ID, "Халион")
    local dark = demo:Boss(DARK_HALION_ID, "Халион")
    local orb = { guid = "demo-orb", name = "Темный шар" }
    demo:Event(self, "SPELL_AURA_APPLIED", dark, p.tank, pelena10)
    demo:Event(self, "SPELL_AURA_APPLIED", dark, dark, 74835)
    demo:Event(self, "SPELL_DAMAGE", p.hunter, light, 53209, { amount = 10000 })
    demo:Event(self, "SPELL_AURA_APPLIED", p.shaman, p.tank, HEROISM)
    demo:Event(self, "SPELL_DAMAGE", orb, p.mage, LEZVIA25HM, { amount = 26977 })
    demo:Event(self, "UNIT_DIED", nil, p.mage)
end


return HalionTracker
