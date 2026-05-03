local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local TrialCrusaderTracker = RLHelper:NewModule("TrialCrusaderTracker", "AceEvent-3.0")
TrialCrusaderTracker.receivesCombatEvents = true
TrialCrusaderTracker.zoneGateInstanceId = 649 -- Trial of the Crusader / Trial of the Grand Crusader
TrialCrusaderTracker.bossIds = {
    [34796] = "Чудовища Нордскола", -- Gormok the Impaler
    [35144] = "Чудовища Нордскола", -- Acidmaw
    [34799] = "Чудовища Нордскола", -- Dreadscale
    [34797] = "Чудовища Нордскола", -- Icehowl
    [34780] = "Лорд Джараксус",
    [34467] = "Чемпионы фракций",
    [34448] = "Чемпионы фракций",
    [34475] = "Чемпионы фракций",
    [34453] = "Чемпионы фракций",
    [34454] = "Чемпионы фракций",
    [34472] = "Чемпионы фракций",
    [34466] = "Чемпионы фракций",
    [34447] = "Чемпионы фракций",
    [34473] = "Чемпионы фракций",
    [34441] = "Чемпионы фракций",
    [34474] = "Чемпионы фракций",
    [34450] = "Чемпионы фракций",
    [34461] = "Чемпионы фракций",
    [34458] = "Чемпионы фракций",
    [34463] = "Чемпионы фракций",
    [34444] = "Чемпионы фракций",
    [34471] = "Чемпионы фракций",
    [34445] = "Чемпионы фракций",
    [34460] = "Чемпионы фракций",
    [34451] = "Чемпионы фракций",
    [34497] = "Валь'киры-близнецы", -- Fjola Lightbane
    [34496] = "Валь'киры-близнецы", -- Eydis Darkbane
    [34564] = "Ануб'арак"
}

local ICEHOWL_TRAMPLE = 66734
local FACTION_CHAMPION_AUTOMARK_SECONDS = 180
local FACTION_CHAMPION_AUTOMARK_INTERVAL = 0.2
local FACTION_CHAMPION_AUTOMARK_UNITS = { "target", "mouseover" }
local trampleIcon = "Interface\\Icons\\Ability_Druid_DemoralizingRoar"

local RAID_MARKERS = {
    STAR = 1,
    CIRCLE = 2,
    DIAMOND = 3,
    TRIANGLE = 4,
    MOON = 5,
    CROSS = 7,
    SKULL = 8
}

local FIXED_MARKS = {
    HUNTER = RAID_MARKERS.SKULL,
    WARRIOR = RAID_MARKERS.CIRCLE,
    PRIEST = RAID_MARKERS.STAR,
    WARLOCK = RAID_MARKERS.MOON,
    DEATH_KNIGHT = RAID_MARKERS.TRIANGLE,
    ROGUE = RAID_MARKERS.CROSS
}

local DIAMOND_PRIORITY = {
    "ENHANCEMENT_SHAMAN",
    "RETRIBUTION_PALADIN",
    "BALANCE_DRUID"
}

local CHAMPION_ROLE_BY_NPC_ID = {
    [34467] = "HUNTER", -- Alyssia Moonstalker
    [34448] = "HUNTER", -- Ruj'kah

    [34475] = "WARRIOR", -- Shocuul
    [34453] = "WARRIOR", -- Narrhok Steelbreaker

    [34454] = "ROGUE", -- Maz'dinah
    [34472] = "ROGUE", -- Irieth Shadowstep

    [34466] = "PRIEST", -- Anthar Forgemender
    [34447] = "PRIEST", -- Caiphus the Stern
    [34473] = "PRIEST", -- Brienna Nightfell
    [34441] = "PRIEST", -- Vivienne Blackwhisper

    [34474] = "WARLOCK", -- Serissa Grimdabbler
    [34450] = "WARLOCK", -- Harkzog

    [34461] = "DEATH_KNIGHT", -- Tyrius Duskblade
    [34458] = "DEATH_KNIGHT", -- Gorgrim Shadowcleave

    [34463] = "ENHANCEMENT_SHAMAN", -- Shaabad
    [34444] = "ENHANCEMENT_SHAMAN", -- Broln Stouthorn

    [34471] = "RETRIBUTION_PALADIN", -- Baelnor Lightbearer
    [34445] = "RETRIBUTION_PALADIN", -- Malithas Brightblade

    [34460] = "BALANCE_DRUID", -- Kavina Grovesong
    [34451] = "BALANCE_DRUID" -- Birana Stormhoof
}

local FACTION_CHAMPION_START_FRAGMENTS = {
    "В следующем бою вы встретитесь с могучими рыцарями Серебряного Авангарда! Лишь победив их, вы заслужите достойную награду."
}

TrialCrusaderTracker.factionChampionStartFragments = FACTION_CHAMPION_START_FRAGMENTS

function TrialCrusaderTracker:OnInitialize()
    RLHelper:Debug("TrialCrusaderTracker: Инициализация")
    self.log = function(...)
        RLHelper:OnCombatLogEvent(...)
    end
    self:reset()
    self:RegisterMessage("RLHelper_CombatEnded", "reset")
    self:RegisterEvent("CHAT_MSG_MONSTER_YELL")
    self:RegisterEvent("CHAT_MSG_RAID_BOSS_EMOTE")
end

function TrialCrusaderTracker:OnEnable()
    RLHelper:Debug("TrialCrusaderTracker: Включен")
end

function TrialCrusaderTracker:reset()
    self:StopFactionChampionAutomark()
    self.championGuidsByRole = {}
    self.seenChampionGuids = {}
    self.markedRoles = {}
    self.diamondRole = nil
    self.allChampionMarksDone = false
end

local function formatIcehowlTrample(ts, playerName)
    return string.format("%s |cFFFFFFFF%s|r |T%s:24:24:0:0|t размазало об стену", date("%H:%M:%S", ts), playerName,
        trampleIcon)
end

local function formatBossMessageDebug(eventName, message, sender)
    return string.format("TrialCrusaderTracker %s sender='%s' text='%s'", eventName, tostring(sender or ""),
        tostring(message or ""))
end

local function creatureIdFromGuid(guid)
    if type(RLHelper.GetCreatureId) == "function" then
        return RLHelper.GetCreatureId(guid)
    end

    return type(guid) == "string" and tonumber(guid:sub(9, 12), 16) or nil
end

local function markUnit(unitId, marker)
    if type(SetRaidTarget) ~= "function" then
        return false
    end

    SetRaidTarget(unitId, marker)
    return true
end

local function unitIdFromGuid(guid)
    if type(RLHelper.GetUnitIdFromGUID) ~= "function" then
        return nil
    end

    return RLHelper.GetUnitIdFromGUID(guid)
end

local function isFactionChampionNpcId(npcId)
    if type(npcId) ~= "number" then
        return false
    end

    return (npcId >= 34441 and npcId <= 34458) or (npcId >= 34460 and npcId <= 34475)
end

local function championRoleFromGuid(guid)
    local npcId = creatureIdFromGuid(guid)
    if not isFactionChampionNpcId(npcId) then
        return nil
    end

    return CHAMPION_ROLE_BY_NPC_ID[npcId]
end

local function diamondPriorityIndex(role)
    for index, priorityRole in ipairs(DIAMOND_PRIORITY) do
        if priorityRole == role then
            return index
        end
    end

    return nil
end

function TrialCrusaderTracker:rememberFactionChampion(guid)
    if not guid then
        return false
    end

    local role = championRoleFromGuid(guid)
    if not role or self.seenChampionGuids[guid] then
        return false
    end

    if not self.championGuidsByRole[role] then
        self.championGuidsByRole[role] = guid
    end

    self.seenChampionGuids[guid] = true
    return true
end

function TrialCrusaderTracker:markFixedChampionUnit(role, unitId)
    local marker = FIXED_MARKS[role]
    if not marker or self.markedRoles[role] or not unitId then
        return false
    end

    if markUnit(unitId, marker) then
        self.markedRoles[role] = true
        return true
    end

    return false
end

function TrialCrusaderTracker:markFixedChampion(role)
    return self:markFixedChampionUnit(role, unitIdFromGuid(self.championGuidsByRole[role]))
end

function TrialCrusaderTracker:markDiamondChampion()
    local bestRole
    local bestIndex

    for role, guid in pairs(self.championGuidsByRole) do
        local index = diamondPriorityIndex(role)
        if index and unitIdFromGuid(guid) and (not bestIndex or index < bestIndex) then
            bestRole = role
            bestIndex = index
        end
    end

    if not bestRole or bestRole == self.diamondRole then
        return false
    end

    if markUnit(unitIdFromGuid(self.championGuidsByRole[bestRole]), RAID_MARKERS.DIAMOND) then
        self.diamondRole = bestRole
        return true
    end

    return false
end

local function getNow()
    if type(GetTime) == "function" then
        return GetTime()
    end

    return time()
end

function TrialCrusaderTracker:markFactionChampionUnit(unitId)
    if type(UnitGUID) ~= "function" then
        return false
    end

    local guid = UnitGUID(unitId)
    local role = championRoleFromGuid(guid)
    if not role then
        return false
    end

    self:rememberFactionChampion(guid)
    local fixedMarked = self:markFixedChampionUnit(role, unitId)
    local diamondMarked = self:markDiamondChampion()

    return fixedMarked or diamondMarked
end

function TrialCrusaderTracker:ScanFactionChampionAutomark()
    if not self.factionChampionAutomarkActiveUntil then
        return false
    end

    if self:AreChampionMarksDone() or getNow() > self.factionChampionAutomarkActiveUntil then
        self:StopFactionChampionAutomark()
        return false
    end

    local marked = false
    for _, unitId in ipairs(FACTION_CHAMPION_AUTOMARK_UNITS) do
        if self:markFactionChampionUnit(unitId) then
            marked = true
        end
    end

    if self:AreChampionMarksDone() then
        self:StopFactionChampionAutomark()
    end

    return marked
end

function TrialCrusaderTracker:StopFactionChampionAutomark()
    if self.factionChampionAutomarkTicker and type(self.factionChampionAutomarkTicker.Cancel) == "function" then
        self.factionChampionAutomarkTicker:Cancel()
    end

    self.factionChampionAutomarkTicker = nil
    self.factionChampionAutomarkActiveUntil = nil
end

function TrialCrusaderTracker:StartFactionChampionAutomark()
    if self:AreChampionMarksDone() then
        return false
    end

    self.factionChampionAutomarkActiveUntil = getNow() + FACTION_CHAMPION_AUTOMARK_SECONDS

    if not self.factionChampionAutomarkTicker then
        local timerApi = C_Timer
        if timerApi and type(timerApi.NewTicker) == "function" then
            self.factionChampionAutomarkTicker = timerApi.NewTicker(FACTION_CHAMPION_AUTOMARK_INTERVAL, function()
                self:ScanFactionChampionAutomark()
            end)
        end
    end

    self:ScanFactionChampionAutomark()
    return true
end

function TrialCrusaderTracker:AreChampionMarksDone()
    if self.allChampionMarksDone then
        return true
    end

    for role in pairs(FIXED_MARKS) do
        if not self.markedRoles[role] then
            return false
        end
    end

    if not self.diamondRole then
        return false
    end

    self.allChampionMarksDone = true
    return true
end

function TrialCrusaderTracker.debug(message)
    RLHelper:Debug(message)
end

function TrialCrusaderTracker:shouldStartFactionChampionAutomark(message)
    if type(message) ~= "string" then
        return false
    end

    for _, fragment in ipairs(self.factionChampionStartFragments or FACTION_CHAMPION_START_FRAGMENTS) do
        if fragment ~= "" and message:find(fragment, 1, true) then
            return true
        end
    end

    return false
end

function TrialCrusaderTracker:handleBossMessage(eventName, message, sender, canStartAutomark)
    self.debug(formatBossMessageDebug(eventName, message, sender))

    if canStartAutomark and self:shouldStartFactionChampionAutomark(message) then
        return self:StartFactionChampionAutomark()
    end

    return false
end

function TrialCrusaderTracker:CHAT_MSG_MONSTER_YELL(eventName, message, sender)
    return self:handleBossMessage(eventName, message, sender, true)
end

function TrialCrusaderTracker:CHAT_MSG_RAID_BOSS_EMOTE(eventName, message, sender)
    return self:handleBossMessage(eventName, message, sender, false)
end

function TrialCrusaderTracker:handleEvent(event)
    if event.event == "SPELL_DAMAGE" and event.spellId == ICEHOWL_TRAMPLE and event.destName then
        self.log(formatIcehowlTrample(event.timestamp, event.destName))
    end

    if self:AreChampionMarksDone() then
        return
    end

    local sourceRole = championRoleFromGuid(event.sourceGUID)
    local destRole = championRoleFromGuid(event.destGUID)
    if not sourceRole and not destRole then
        return
    end

    if sourceRole and self:rememberFactionChampion(event.sourceGUID) then
        self:markFixedChampion(sourceRole)
    end

    if destRole and self:rememberFactionChampion(event.destGUID) then
        self:markFixedChampion(destRole)
    end

    self:markDiamondChampion()
    self:AreChampionMarksDone()
end

return TrialCrusaderTracker
