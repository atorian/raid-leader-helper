local RLHelper = LibStub("AceAddon-3.0"):NewAddon("RLHelper", "AceConsole-3.0", "AceEvent-3.0", "LibCompat-1.0")
local callbacks = LibStub("CallbackHandler-1.0"):New(RLHelper)
local IsGroupInCombat, InCombatLockdown = RLHelper.IsGroupInCombat, InCombatLockdown
local GetUnitIdFromGUID = RLHelper.GetUnitIdFromGUID

local COMBAT_END_CHECK_INTERVAL = 1
local COMBAT_END_GRACE = 3
local ENEMY_ACTIVITY_TIMEOUT = 6
local IGOR_DEATH_COOLDOWN = 180
local MODULE_ZONE_ANY = 0
local ZONE_GATE_INSTANCE_ID_BY_INSTANCE_NAME = {
    ["Trial of the Crusader"] = 649,
    ["Trial of the Grand Crusader"] = 649,
    ["Испытание крестоносца"] = 649,
    ["Испытание великого крестоносца"] = 649,
    ["The Ruby Sanctum"] = 724,
    ["Ruby Sanctum"] = 724,
    ["Рубиновое святилище"] = 724,
    ["Icecrown Citadel"] = 631,
    ["Цитадель Ледяной Короны"] = 631
}
local DBM_PULL_BAR_NAMES = {
    "АТAKA!!",
    "Атака",
    "Pull in"
}

local IGOR_DEATH_PHRASES = {
    "Игорь осуждает смерть %s.",
    "Игорь делает вид, что так и было задумано.",
    "Игорь записал %s в список слабых.",
    "Игорь молча смотрит на тело %s.",
    "Игорь считает, что %s мог бы и пожить.",
    "Игорь тяжело вздыхает.",
    "Игорь говорит: минус мораль.",
    "Игорь делает пометку: %s умер не по плану.",
    "Игорь не одобряет происходящее.",
    "Игорь подозревает, что %s нажал не ту кнопку.",
    "Игорь просит больше так не делать.",
    "Игорь считает эту смерть обучающим моментом.",
    "Игорь смотрит на %s с разочарованием.",
    "Игорь говорит: зато красиво.",
    "Игорь добавляет смерть %s в отчет."
}

local IGNORED_COMBAT_ENEMIES = {
    ["World Invisible Trigger"] = true,
    ["Огрская пиньята"] = true,
    ["Робот \"Бей-Молоти\""] = true
}

-- Utility functions
local function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end

-- Group affiliation flags
RLHelper.GROUP_AFFILIATION_PLAYER = 0x1 -- Игрок
RLHelper.GROUP_AFFILIATION_PARTY = 0x2 -- Член группы
RLHelper.GROUP_AFFILIATION_RAID = 0x4 -- Член рейда
RLHelper.GROUP_AFFILIATION_ANY = 0x7 -- Принадлежность к любой группе (игрок/группа/рейд)

-- Enemy flags
RLHelper.ENEMY_FLAGS = 0xa48 -- Маска для проверки враждебных NPC (OUTSIDER | HOSTILE | NPC | NPC_TYPE)
RLHelper.CONTROLLED_FLAGS = 0x1248 -- Маска для проверки юнитов под контролем (OUTSIDER | CONTROLLED | NPC | NPC_TYPE)

-- Default settings
local defaults = {
    profile = {
        enabled = true,
        debug = false,
        pullCancelMessage = "ГАЛЯ, ОТМЕНА!",
        displayOnlyInGroup = false,
        bossOnlyHistory = false,
        igor = false,
        minimap = {
            hide = false
        },
        combatHistory = {}, -- Add combat history storage
        savedPosition = nil -- Add saved position storage
    }
}

-- Combat history structures
RLHelper.combatHistory = {} -- Array for combat history
RLHelper.currentCombat = {
    startTime = nil,
    messages = {},
    firstEnemy = nil, -- Name of the first enemy in combat
    isBoss = false
}
RLHelper.viewingCurrentCombat = true -- Initialize to true by default

RLHelper.activeEnemies = {}
RLHelper.activePlayers = {}
RLHelper.enemyEvents = {} -- Structure to track enemies and their events
RLHelper.lastCombatActivityAt = nil
RLHelper.combatEndRequestedAt = nil
RLHelper.combatTicker = nil
RLHelper.currentInstanceId = nil
RLHelper.lastIgorDeathMessageAt = nil

function RLHelper:Debug(...)
    if self.db and self.db.profile and self.db.profile.debug then
        self:Print(...)
    end
end

function RLHelper:isDebugging()
    return self.db and self.db.profile and self.db.profile.debug or false
end

function RLHelper:IsInGroup()
    if type(GetRealNumRaidMembers) == "function" and GetRealNumRaidMembers() > 0 then
        return true
    end

    if type(GetRealNumPartyMembers) == "function" and GetRealNumPartyMembers() > 0 then
        return true
    end

    if type(GetNumRaidMembers) == "function" and GetNumRaidMembers() > 0 then
        return true
    end

    return type(GetNumPartyMembers) == "function" and GetNumPartyMembers() > 0
end

function RLHelper:ShouldShowMainFrame()
    return not (self.db and self.db.profile and self.db.profile.displayOnlyInGroup) or self:IsInGroup()
end

function RLHelper:RefreshMainFrameVisibility()
    if not self.mainFrame or not (self.db and self.db.profile and self.db.profile.displayOnlyInGroup) then
        return
    end

    if self:IsInGroup() then
        self.mainFrame:Show()
    else
        self.mainFrame:Hide()
    end
end

function RLHelper:SetMainFrameVisible(visible)
    if not self.mainFrame then
        return
    end

    if visible then
        self.mainFrame:Show()
    else
        self.mainFrame:Hide()
    end
end

local function debugValue(value)
    if value == nil or value == "" then
        return "n/a"
    end

    return tostring(value)
end

local function getZoneGateInstanceIdByInstanceName(instanceName)
    if not instanceName then
        return nil
    end

    return ZONE_GATE_INSTANCE_ID_BY_INSTANCE_NAME[instanceName]
end

local function getCurrentMapAreaId()
    if type(GetCurrentMapAreaID) ~= "function" then
        return nil
    end

    if type(SetMapToCurrentZone) == "function" then
        SetMapToCurrentZone()
    end

    return GetCurrentMapAreaID()
end

function RLHelper:GetZoneDebugSnapshot()
    local instanceName, instanceType, difficultyIndex, difficultyName, maxPlayers, dynamicDifficulty, isDynamic,
        instanceMapId

    if type(GetInstanceInfo) == "function" then
        instanceName, instanceType, difficultyIndex, difficultyName, maxPlayers, dynamicDifficulty, isDynamic,
            instanceMapId = GetInstanceInfo()
    end

    local zone = {
        realZoneText = type(GetRealZoneText) == "function" and GetRealZoneText() or nil,
        zoneText = type(GetZoneText) == "function" and GetZoneText() or nil,
        subZoneText = type(GetSubZoneText) == "function" and GetSubZoneText() or nil,
        minimapZoneText = type(GetMinimapZoneText) == "function" and GetMinimapZoneText() or nil,
        instanceName = instanceName,
        instanceType = instanceType,
        difficultyIndex = difficultyIndex,
        difficultyName = difficultyName,
        dynamicDifficulty = dynamicDifficulty,
        isDynamic = isDynamic,
        instanceMapId = instanceMapId
    }
    zone.instanceMapId = getZoneGateInstanceIdByInstanceName(zone.instanceName) or zone.instanceMapId or
        getCurrentMapAreaId()

    return zone
end

function RLHelper:FormatModuleZoneGateDebug()
    if type(self.IterateModules) ~= "function" then
        return "модули недоступны"
    end

    local statuses = {}
    for _, module in self:IterateModules() do
        if module and module.receivesCombatEvents then
            local zoneGateInstanceId = module.zoneGateInstanceId or MODULE_ZONE_ANY
            local enabled = zoneGateInstanceId == MODULE_ZONE_ANY or zoneGateInstanceId == self.currentInstanceId
            table.insert(statuses, string.format("%s:%s gate=%s",
                module.name or "unnamed",
                enabled and "ON" or "OFF",
                zoneGateInstanceId == MODULE_ZONE_ANY and "any" or tostring(zoneGateInstanceId)))
        end
    end

    if #statuses == 0 then
        return "combat-модули не найдены"
    end

    table.sort(statuses)
    return table.concat(statuses, "; ")
end

function RLHelper:PrintZoneDebug(reason, force)
    if not force and not self:isDebugging() then
        return
    end

    local zone = self.currentZoneDebug or self:GetZoneDebugSnapshot()
    local logger = force and self.Print or self.Debug

    logger(self, string.format("Зона [%s]: name='%s', mapId=%s",
        debugValue(reason),
        debugValue(zone.instanceName or zone.realZoneText or zone.zoneText),
        debugValue(zone.instanceMapId)))
    logger(self, "Зональные combat-модули: " .. self:FormatModuleZoneGateDebug())
end

function RLHelper:OnInitialize()
    self:Debug("RL Быдло: Начало инициализации аддона")

    self.activeEnemies = self.activeEnemies or {}
    self.activePlayers = self.activePlayers or {}
    self.enemyEvents = self.enemyEvents or {}

    self.db = LibStub("AceDB-3.0"):New("RLHelperDB", defaults, true)

    -- Load combat history from DB
    if self.db.profile.combatHistory then
        for _, combat in ipairs(self.db.profile.combatHistory) do
            table.insert(self.combatHistory, {
                startTime = combat.startTime,
                endTime = combat.endTime,
                messages = combat.messages,
                firstEnemy = combat.firstEnemy,
                isBoss = combat.isBoss
            })
        end
    end

    self:RegisterChatCommand("rlh", "HandleSlashCommand")

    self:CreateMainFrame()
    self:CreateOptionsPanel()

    self.mainFrame:Show()
    self:RefreshMainFrameVisibility()

    self:Debug("RL Быдло: Аддон включен")
end

function RLHelper:OnEnable()
    self:MinimizeWindow()
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self:RegisterEvent("PARTY_MEMBERS_CHANGED")
    self:RegisterEvent("RAID_ROSTER_UPDATE")
    self:UpdateZoneContext()
    self:RefreshMainFrameVisibility()
end

local function isEnemy(flags)
    return bit.band(flags or 0, RLHelper.ENEMY_FLAGS) > 0
end

local function isPlayer(flags)
    return bit.band(flags or 0, RLHelper.GROUP_AFFILIATION_ANY) > 0
end

local function shouldIgnoreCombatEnemy(name)
    return IGNORED_COMBAT_ENEMIES[name] == true
end

local function isKnownBossUnit(guid, name)
    if type(UnitGUID) ~= "function" and type(UnitName) ~= "function" then
        return false
    end

    for i = 1, 5 do
        local unitId = "boss" .. i
        if type(UnitExists) ~= "function" or UnitExists(unitId) then
            local unitGuid = type(UnitGUID) == "function" and UnitGUID(unitId) or nil
            if guid and unitGuid and unitGuid ~= "0x0000000000000000" and unitGuid == guid then
                return true
            end

            local unitName = type(UnitName) == "function" and UnitName(unitId) or nil
            if name and unitName and unitName == name then
                return true
            end
        end
    end

    return false
end

local LADY_KONTROL = 71289

function RLHelper:GetCombatNow()
    if type(GetTime) == "function" then
        return GetTime()
    end

    return time()
end

function RLHelper:StopCombatTicker()
    if self.combatTicker and type(self.combatTicker.Cancel) == "function" then
        self.combatTicker:Cancel()
    end

    self.combatTicker = nil
end

function RLHelper:EnsureCombatTicker()
    if self.combatTicker then
        return
    end

    local timer = self.C_Timer or C_Timer
    if not timer or type(timer.NewTicker) ~= "function" then
        return
    end

    self.combatTicker = timer.NewTicker(COMBAT_END_CHECK_INTERVAL, function()
        self:EvaluateCombatEnd("ticker")
    end)
end

local function involvesEnemy(event)
    return isEnemy(event.sourceFlags) or isEnemy(event.destFlags)
end

function RLHelper:MarkEnemyInactive(guid)
    if not guid then
        return
    end

    self.activeEnemies[guid] = 0
end

function RLHelper:MarkEnemyActivity(guid, name, eventName, now)
    if not guid then
        return
    end

    self.activeEnemies[guid] = now
    self.enemyEvents[guid] = {
        name = name or "Unknown",
        event = eventName,
        seenAt = now
    }
end

function RLHelper:HasRecentEnemyActivity(now)
    for guid, seenAt in pairs(self.activeEnemies) do
        if seenAt ~= 0 then
            if now - seenAt <= ENEMY_ACTIVITY_TIMEOUT then
                return true
            end

            self.activeEnemies[guid] = 0
        end
    end

    return false
end

function RLHelper:IsCombatOngoing(now)
    if InCombatLockdown and InCombatLockdown() then
        return true
    end

    if IsGroupInCombat and IsGroupInCombat() then
        return true
    end

    return self:HasRecentEnemyActivity(now)
end

function RLHelper:StartCombat(reason)
    local now = self:GetCombatNow()
    self.lastCombatActivityAt = now
    self.combatEndRequestedAt = nil

    if self.inCombat then
        return
    end

    self.inCombat = true
    if not self.currentCombat.startTime then
        self.currentCombat.startTime = time()
    end

    self:EnsureCombatTicker()
    self:DisplayCombat(self.currentCombat)
    self:Debug("Combat started", reason)
end

function RLHelper:ResetCombatState()
    self:StopCombatTicker()
    self.inCombat = false
    self.lastCombatActivityAt = nil
    self.combatEndRequestedAt = nil

    self.currentCombat = {
        startTime = nil,
        messages = {},
        firstEnemy = nil,
        isBoss = false
    }

    wipe(self.activeEnemies)
    wipe(self.activePlayers)
    wipe(self.enemyEvents)
end

function RLHelper:FinishCombat(reason)
    self:Debug("Combat ended", reason)

    self:SendMessage("RLHelper_CombatEnding")

    local combat = nil
    if self.currentCombat.startTime and #self.currentCombat.messages > 0 then
        combat = {
            startTime = self.currentCombat.startTime,
            endTime = time(),
            messages = self.currentCombat.messages,
            firstEnemy = self.currentCombat.firstEnemy,
            isBoss = self.currentCombat.isBoss
        }
    end

    self:ResetCombatState()

    if combat and self:ShouldSaveCombatToHistory(combat) then
        self:SaveCombatToProfile(combat, self.db.profile)
        self:Debug("Combat Saved to history")
    end

    self:SendMessage("RLHelper_CombatEnded")
end

function RLHelper:trackCombatants(event)
    if event.spellId == LADY_KONTROL or not affectingGroup(event) or not involvesEnemy(event) then
        return false
    end

    local now = self:GetCombatNow()
    self.lastCombatActivityAt = now
    self.combatEndRequestedAt = nil

    if isPlayer(event.sourceFlags) and event.sourceGUID then
        self.activePlayers[event.sourceGUID] = true
    end
    if isPlayer(event.destFlags) and event.destGUID then
        self.activePlayers[event.destGUID] = true
    end

    if isEnemy(event.sourceFlags) then
        self:MarkEnemyActivity(event.sourceGUID, event.sourceName, event.event, now)
    end
    if isEnemy(event.destFlags) then
        self:MarkEnemyActivity(event.destGUID, event.destName, event.event, now)
    end

    if event.event == "UNIT_DIED" or event.event == "UNIT_DESTROYED" or event.event == "PARTY_KILL" then
        if isEnemy(event.destFlags) then
            self:MarkEnemyInactive(event.destGUID)
        end
    end

    self:StartCombat("combat_log")
    return true
end

function RLHelper:printActiveEnemies()
    local enemyNames = {}
    local count = 0
    for guid, v in pairs(self.activeEnemies) do
        if self.enemyEvents[guid] and v ~= 0 then
            table.insert(enemyNames,
                self.enemyEvents[guid].name .. " [" .. guid .. "] > " .. self.enemyEvents[guid].event)
            count = count + 1
            if count >= 3 then
                break
            end
        end
    end

    if count > 0 then
        self:Debug("Еще есть живые враги:", table.concat(enemyNames, ", "))
    else
        self:Debug("Врагов нет")
    end
end

function RLHelper:PLAYER_REGEN_ENABLED()
    self:Debug("Regen Enabled")
    self:printActiveEnemies()
    if not self.inCombat then
        return
    end

    self.combatEndRequestedAt = self:GetCombatNow()
    self:EnsureCombatTicker()
    self:EvaluateCombatEnd("PLAYER_REGEN_ENABLED")
end

function RLHelper:PLAYER_REGEN_DISABLED()
    self:StartCombat("PLAYER_REGEN_DISABLED")
end

function RLHelper:UpdateZoneContext(reason, silent)
    self.currentZoneDebug = self:GetZoneDebugSnapshot()

    if not self.currentZoneDebug.instanceMapId then
        self.currentInstanceId = MODULE_ZONE_ANY
        if not silent then
            self:PrintZoneDebug(reason or "UpdateZoneContext")
        end
        return self.currentInstanceId
    end

    self.currentInstanceId = self.currentZoneDebug.instanceMapId or MODULE_ZONE_ANY
    if not silent then
        self:PrintZoneDebug(reason or "UpdateZoneContext")
    end
    return self.currentInstanceId
end

function RLHelper:PLAYER_ENTERING_WORLD()
    self:UpdateZoneContext("PLAYER_ENTERING_WORLD")
end

function RLHelper:ZONE_CHANGED_NEW_AREA()
    self:UpdateZoneContext("ZONE_CHANGED_NEW_AREA")
end

function RLHelper:PARTY_MEMBERS_CHANGED()
    self:RefreshMainFrameVisibility()
end

function RLHelper:RAID_ROSTER_UPDATE()
    self:RefreshMainFrameVisibility()
end

function RLHelper:ShouldDispatchCombatEventToModule(module)
    if not module or not module.receivesCombatEvents then
        return false
    end

    if self.currentInstanceId == nil then
        self:UpdateZoneContext()
    end

    local zoneGateInstanceId = module.zoneGateInstanceId or MODULE_ZONE_ANY
    return zoneGateInstanceId == MODULE_ZONE_ANY or zoneGateInstanceId == self.currentInstanceId
end

function RLHelper:DispatchCombatEvent(eventData)
    if type(self.IterateModules) ~= "function" then
        return
    end

    for _, module in self:IterateModules() do
        if self:ShouldDispatchCombatEventToModule(module) and type(module.handleEvent) == "function" then
            module:handleEvent(eventData)
        end
    end
end

function RLHelper:IsGroupMemberDeath(event)
    if not event or event.event ~= "UNIT_DIED" then
        return false
    end

    local groupFlags = bit.bor and bit.bor(self.GROUP_AFFILIATION_PARTY, self.GROUP_AFFILIATION_RAID) or
        (self.GROUP_AFFILIATION_PARTY + self.GROUP_AFFILIATION_RAID)
    return bit.band(event.destFlags or 0, groupFlags) > 0
end

function RLHelper:FormatIgorDeathMessage(playerName)
    local phrase = IGOR_DEATH_PHRASES[math.random(#IGOR_DEATH_PHRASES)]
    if phrase:find("%%s") then
        return string.format(phrase, playerName or "кто-то")
    end

    return phrase
end

function RLHelper:MaybeSendIgorDeathMessage(event)
    if not self.db or not self.db.profile or not self.db.profile.igor then
        return false
    end

    if not self:IsGroupMemberDeath(event) then
        return false
    end

    local now = self:GetCombatNow()
    if self.lastIgorDeathMessageAt and now - self.lastIgorDeathMessageAt < IGOR_DEATH_COOLDOWN then
        return false
    end

    if type(SendChatMessage) ~= "function" then
        return false
    end

    SendChatMessage(self:FormatIgorDeathMessage(event.destName), "EMOTE")
    self.lastIgorDeathMessageAt = now
    return true
end

function affectingGroup(event)
    local sourceFlags = event.sourceFlags
    local destFlags = event.destFlags

    -- Игнорируем события, где источник или цель под контролем
    if bit.band(sourceFlags, RLHelper.CONTROLLED_FLAGS) == RLHelper.CONTROLLED_FLAGS or
        bit.band(destFlags, RLHelper.CONTROLLED_FLAGS) == RLHelper.CONTROLLED_FLAGS then
        return false
    end

    return isPlayer(sourceFlags) or isPlayer(destFlags)
end

function RLHelper:MarkBossCombat(event)
    if not self.currentCombat or self.currentCombat.isBoss or not affectingGroup(event) then
        return false
    end

    local bossName
    if isEnemy(event.sourceFlags) and isKnownBossUnit(event.sourceGUID, event.sourceName) then
        bossName = event.sourceName
    elseif isEnemy(event.destFlags) and isKnownBossUnit(event.destGUID, event.destName) then
        bossName = event.destName
    end

    if not bossName or shouldIgnoreCombatEnemy(bossName) then
        return false
    end

    self.currentCombat.isBoss = true
    self.currentCombat.firstEnemy = bossName
    return true
end

function RLHelper:ShouldSaveCombatToHistory(combat)
    if not self.db or not self.db.profile or not self.db.profile.bossOnlyHistory then
        return true
    end

    return combat and combat.isBoss == true
end

function RLHelper:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
    local eventData = blizzardEvent(...)
    self:MaybeSendIgorDeathMessage(eventData)
    self:DispatchCombatEvent(eventData)
    self:trackCombatants(eventData)
    self:MarkBossCombat(eventData)

    if self.currentCombat.firstEnemy or not affectingGroup(eventData) then
        return
    end

    -- Save first enemy name if not set yet
    if isEnemy(eventData.sourceFlags) and not shouldIgnoreCombatEnemy(eventData.sourceName) then
        if not self.currentCombat.firstEnemy then
            self.currentCombat.firstEnemy = eventData.sourceName
        end
    end
    if isEnemy(eventData.destFlags) and not shouldIgnoreCombatEnemy(eventData.destName) then

        if not self.currentCombat.firstEnemy then
            self.currentCombat.firstEnemy = eventData.destName
        end
    end
end

function RLHelper:OnCombatLogEvent(message)
    if not self.inCombat then
        self:StartCombat("message")
    end

    if not self.currentCombat.startTime then
        self.currentCombat.startTime = time()
    end

    table.insert(self.currentCombat.messages, message)
    if self.mainFrame and self.mainFrame.logText then
        self.mainFrame.logText:AddMessage(message)
    end
end

function RLHelper:SaveCombatToProfile(combat, profile)
    -- Добавляем бой в начало массива
    table.insert(self.combatHistory, 1, combat)

    -- Ограничиваем количество сохраненных боев до 50
    while #self.combatHistory > 50 do
        table.remove(self.combatHistory)
    end

    -- Сохраняем историю боев в профиль
    profile.combatHistory = {}
    for _, savedCombat in ipairs(self.combatHistory) do
        table.insert(profile.combatHistory, savedCombat)
    end
end

function RLHelper:EndCombat(reason)
    self:FinishCombat(reason)
end

function RLHelper:EvaluateCombatEnd(reason)
    if not self.inCombat then
        return false
    end

    local now = self:GetCombatNow()
    if self:IsCombatOngoing(now) then
        return false
    end

    if not self.combatEndRequestedAt then
        self.combatEndRequestedAt = now
    end

    local quietSince = self.combatEndRequestedAt
    if self.lastCombatActivityAt and self.lastCombatActivityAt > quietSince then
        quietSince = self.lastCombatActivityAt
    end

    if now - quietSince < COMBAT_END_GRACE then
        return false
    end

    self:FinishCombat(reason)
    return true
end

local function sendSync(prefix, msg)
    msg = msg or ""
    local zoneType = select(2, IsInInstance())
    if zoneType == "pvp" or zoneType == "arena" then
        RLHelper:Debug("RL Быдло: Отправлено в BATTLEGROUND")
        SendAddonMessage(prefix, msg, "BATTLEGROUND")
    elseif GetRealNumRaidMembers() > 0 then
        RLHelper:Debug("RL Быдло: Отправлено в RAID")
        SendAddonMessage(prefix, msg, "RAID")
    elseif GetRealNumPartyMembers() > 0 then
        RLHelper:Debug("RL Быдло: Отправлено в PARTY")
        SendAddonMessage(prefix, msg, "PARTY")
    end
end

function RLHelper:SaveAnchorPosition(silent)
    local point, _, relativePoint, x, y = self.mainFrame:GetPoint()
    local width = self.mainFrame:GetWidth()
    local height = self.mainFrame:GetHeight()
    self.db.profile.savedPosition = {
        point = point or "TOPLEFT",
        relativePoint = relativePoint or point or "TOPLEFT",
        x = x,
        y = y,
        width = width,
        height = height
    }
    if not silent then
        self:Print("Позиция и размер сохранены")
    end
end

function RLHelper:MinimizeWindow()
    self.mainFrame:ClearAllPoints()
    if self.db.profile.savedPosition then
        local savedPosition = self.db.profile.savedPosition
        local point = savedPosition.point or "TOPLEFT"
        local relativePoint = savedPosition.relativePoint or point
        self.mainFrame:SetSize(savedPosition.width, savedPosition.height)
        self.mainFrame:SetPoint(point, UIParent, relativePoint, savedPosition.x, savedPosition.y)
    else
        self.mainFrame:SetSize(400, 150)
        local screenWidth = GetScreenWidth()
        local screenHeight = GetScreenHeight()
        self.mainFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", screenWidth - 420, -20)
    end
end

function RLHelper:SetPullButtonsVisible(visible)
    local frame = self.mainFrame
    if not frame then
        return
    end

    for _, btn in ipairs(frame.pullButtons or {}) do
        if visible then
            btn:Show()
        else
            btn:Hide()
        end
    end

    if frame.cancelBtn then
        if visible then
            frame.cancelBtn:Hide()
        else
            frame.cancelBtn:Show()
        end
    end
end

function RLHelper:CancelPullResetTimer()
    local timer = self.pullResetTimer
    if timer and type(timer.Cancel) == "function" then
        timer:Cancel()
    end

    self.pullResetTimer = nil
end

function RLHelper:ResetPullControls()
    self:CancelPullResetTimer()
    self:SetPullButtonsVisible(true)
end

function RLHelper:CancelPullCountdown()
    self:CancelDBMPullCountdown()
    self:ResetPullControls()
end

function RLHelper:CancelDBMPullCountdown()
    local dbm = _G.DBM or DBM
    local cancelled = false

    if type(SendAddonMessage) == "function" then
        sendSync("DBMv4-PT", "0")
        for _, barName in ipairs(DBM_PULL_BAR_NAMES) do
            sendSync("DBMv4-Pizza", "0\t" .. barName)
        end
        cancelled = true
    end

    if dbm and type(dbm.Unschedule) == "function" then
        if type(SendChatMessage) == "function" then
            dbm:Unschedule(SendChatMessage)
            cancelled = true
        end

        if type(PlaySoundFile) == "function" then
            dbm:Unschedule(PlaySoundFile)
            cancelled = true
        end
    end

    if dbm and type(dbm.CreatePizzaTimer) == "function" then
        for _, barName in ipairs(DBM_PULL_BAR_NAMES) do
            dbm:CreatePizzaTimer(0, barName)
        end
        cancelled = true
    end

    if dbm and dbm.Bars and type(dbm.Bars.CancelBar) == "function" then
        for _, barName in ipairs(DBM_PULL_BAR_NAMES) do
            dbm.Bars:CancelBar(barName)
        end
        cancelled = true
    end

    local dummyMod
    if dbm and type(dbm.GetModByName) == "function" then
        dummyMod = dbm:GetModByName("PullTimerCountdownDummy")
    end

    if dummyMod then
        if dummyMod.text and type(dummyMod.text.Cancel) == "function" then
            dummyMod.text:Cancel()
            cancelled = true
        end

        if dummyMod.timer and type(dummyMod.timer.Stop) == "function" then
            dummyMod.timer:Stop()
            cancelled = true
        end

        if type(TimerTracker_OnEvent) == "function" and TimerTracker then
            TimerTracker_OnEvent(TimerTracker, "PLAYER_ENTERING_WORLD")
            cancelled = true
        end
    end

    if type(SendChatMessage) == "function" then
        local channel = (GetRealNumRaidMembers and GetRealNumRaidMembers() > 0) and "RAID_WARNING" or "PARTY"
        SendChatMessage(self.db and self.db.profile and self.db.profile.pullCancelMessage or "ГАЛЯ, ОТМЕНА!", channel)
        cancelled = true
    end

    return cancelled
end

function RLHelper:InvokeDBMPullCommand(duration)
    local pullValue = tonumber(duration) or 0
    local slashCmdList = _G.SlashCmdList or SlashCmdList
    local pullCommand = slashCmdList and slashCmdList["DEADLYBOSSMODSPULL"]

    if type(pullCommand) == "function" then
        local ok, err = pcall(pullCommand, tostring(pullValue))
        if not ok then
            self:Debug("DBM pull command failed:", err)
            return false
        end

        return true
    end

    return false
end

function RLHelper:StartPullCountdown(duration)
    self:BeginPullCountdown(duration)
    self:InvokeDBMPullCommand(duration)
    self:MinimizeWindow()

    if self.mainFrame and self.mainFrame.logText then
        self.mainFrame.logText:Clear()
    end
end

function RLHelper:BeginPullCountdown(duration)
    local timerApi = self.C_Timer or C_Timer
    self:CancelPullResetTimer()
    self:SetPullButtonsVisible(false)

    if not timerApi or type(timerApi.NewTimer) ~= "function" then
        return
    end

    local handle
    handle = timerApi.NewTimer(duration, function()
        if self.pullResetTimer ~= handle then
            return
        end

        self.pullResetTimer = nil
        self:SetPullButtonsVisible(true)
    end)
    self.pullResetTimer = handle
end

function RLHelper:UpdateCombatDropdown()
    self:Debug("Updating dropdown list")

    local list = {
        ["current"] = "Текущий бой"
    }

    for i, combat in ipairs(self.combatHistory) do
        local startTime = date("%H:%M:%S", combat.startTime)
        local endTime = date("%H:%M:%S", combat.endTime)
        local enemyInfo = combat.firstEnemy or ""
        list[tostring(i)] = string.format("%d. %s (%s - %s)", i, enemyInfo, startTime, endTime)
    end

    dropdown:SetList(list)
    self:Debug("Dropdown list updated with " .. #list .. " items")
end

function RLHelper:DisplayCombat(combat)
    if not self.mainFrame or not self.mainFrame.logText then
        return
    end

    self.mainFrame.logText:Clear()
    if combat and combat.messages then
        for _, message in ipairs(combat.messages) do
            self.mainFrame.logText:AddMessage(message)
        end
    end
end

function RLHelper:LayoutMainFrame()
    local frame = self.mainFrame
    if not frame or not frame.logText or not frame.buttonContainer then
        return
    end

    frame.logText:ClearAllPoints()
    frame.logText:SetPoint("TOPLEFT", frame.buttonContainer, "BOTTOMLEFT", 0, -8)

    if frame.bottomPanel then
        frame.logText:SetPoint("BOTTOMRIGHT", frame.bottomPanel, "TOPRIGHT", 0, 4)
    else
        frame.logText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 8)
    end
end

function RLHelper:SetMainFrameBottomPanel(panel)
    if not self.mainFrame then
        return
    end

    self.mainFrame.bottomPanel = panel
    self:LayoutMainFrame()
end

function RLHelper:CreateMainFrame()
    local frame = CreateFrame("Frame", "RLHelperMainFrame", UIParent)
    frame:SetSize(300, 600)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetMinResize(300, 100)
    frame:SetMaxResize(800, 1000)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

    frame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = {
            left = 11,
            right = 12,
            top = 12,
            bottom = 11
        }
    })

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOPLEFT", 15, 10)
    title:SetText("RL Пупсик")

    -- Close button
    -- local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    -- closeButton:SetPoint("TOPRIGHT", -5, -5)

    -- Minimize button
    local minimizeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    minimizeButton:SetSize(20, 25)
    minimizeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -14)
    minimizeButton:SetText("_")
    minimizeButton:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    minimizeButton:GetFontString():SetPoint("TOP", 0, -2)

    -- Remove button textures
    minimizeButton:SetNormalTexture("")
    minimizeButton:SetPushedTexture("")
    minimizeButton:SetHighlightTexture("")
    minimizeButton:SetDisabledTexture("")

    minimizeButton:SetScript("OnClick", function()
        RLHelper:MinimizeWindow()
    end)

    -- Anchor button
    local anchorButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    anchorButton:SetSize(20, 25)
    anchorButton:SetPoint("TOPRIGHT", minimizeButton, "TOPLEFT", 0, 0)
    anchorButton:SetText("A")
    anchorButton:GetFontString():SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    anchorButton:GetFontString():SetPoint("TOP", 0, -2)

    -- Remove button textures
    anchorButton:SetNormalTexture("")
    anchorButton:SetPushedTexture("")
    anchorButton:SetHighlightTexture("")
    anchorButton:SetDisabledTexture("")

    anchorButton:SetScript("OnClick", function()
        RLHelper:SaveAnchorPosition()
    end)

    -- Button container
    local buttonContainer = CreateFrame("Frame", nil, frame)
    buttonContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 12, -10)
    buttonContainer:SetPoint("TOPRIGHT", -10, -10)
    buttonContainer:SetHeight(25)

    -- Store buttons in frame for access
    frame.pullButtons = {}

    -- Buttons
    local pull15Btn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    pull15Btn:SetSize(60, 25)
    pull15Btn:SetPoint("LEFT", buttonContainer, "LEFT", 0, 0)
    pull15Btn:SetText("Пул 15")
    frame.pullButtons[1] = pull15Btn
    pull15Btn:SetScript("OnClick", function()
        RLHelper:StartPullCountdown(15)
    end)

    local pull75Btn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    pull75Btn:SetSize(60, 25)
    pull75Btn:SetPoint("LEFT", pull15Btn, "RIGHT", 4, 0)
    pull75Btn:SetText("Пул 70")
    frame.pullButtons[2] = pull75Btn
    pull75Btn:SetScript("OnClick", function()
        RLHelper:StartPullCountdown(70)
    end)

    -- Cancel button
    frame.cancelBtn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    frame.cancelBtn:SetSize(60, 25)
    frame.cancelBtn:SetPoint("LEFT", buttonContainer, "LEFT", 0, 0)
    frame.cancelBtn:SetText("Отмена")
    frame.cancelBtn:Hide() -- Initially hidden
    frame.cancelBtn:SetScript("OnClick", function()
        RLHelper:CancelPullCountdown()
    end)

    local resetBtn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    resetBtn:SetSize(25, 25)
    resetBtn:SetPoint("LEFT", pull75Btn, "RIGHT", 4, 0)
    resetBtn:SetText("C")
    resetBtn:SetScript("OnClick", function()
        RLHelper:ResetCombatState()
        RLHelper.mainFrame.logText:Clear()
        self:SendMessage("RLHelper_CombatEnded")
    end)

    -- Create dropdown
    local dropdown = CreateFrame("Frame", "RLHelperCombatDropdown", buttonContainer, "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", resetBtn, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(dropdown, 50)
    dropdown:Show()

    -- Function to initialize dropdown
    function dropdown.initialize(self, level)
        local info = UIDropDownMenu_CreateInfo()

        -- Current combat option
        info.text = "Текущий бой"
        info.value = "current"
        info.disabled = not RLHelper.currentCombat.startTime
        info.func = function()
            RLHelper:DisplayCombat(RLHelper.currentCombat)
            RLHelper.mainFrame:Show()
        end
        UIDropDownMenu_AddButton(info, level)

        for i, combat in ipairs(RLHelper.combatHistory) do
            local startTime = date("%H:%M:%S", combat.startTime)
            local endTime = date("%H:%M:%S", combat.endTime)
            local enemyInfo = combat.firstEnemy or ""
            info.text = string.format("%d. %s (%s - %s)", i, enemyInfo, startTime, endTime)
            info.value = tostring(i)
            info.disabled = nil
            info.func = function()
                RLHelper:ShowCombatByIndex(i)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end

    UIDropDownMenu_Initialize(dropdown, dropdown.initialize)
    UIDropDownMenu_SetText(dropdown, "Бои")

    -- Resize button
    local resizeButton = CreateFrame("Button", nil, frame)
    resizeButton:SetSize(16, 16)
    resizeButton:SetPoint("BOTTOMRIGHT", -5, 5)
    resizeButton:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeButton:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeButton:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeButton:SetScript("OnMouseDown", function()
        frame:StartSizing("BOTTOMRIGHT")
    end)
    resizeButton:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
    end)

    -- Log text
    local logText = CreateFrame("ScrollingMessageFrame", nil, frame)
    logText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    logText:SetJustifyV("TOP")
    logText:SetJustifyH("LEFT")
    logText:SetFading(false)
    logText:SetMaxLines(1000)
    logText:EnableMouseWheel(true)
    logText:SetHyperlinksEnabled(false)
    logText:SetIndentedWordWrap(true)
    logText:SetInsertMode("TOP")

    -- Mouse wheel handler
    logText:SetScript("OnMouseWheel", function(self, delta)
        for i = 1, math.abs(delta) do
            if delta > 0 then
                self:ScrollUp()
            else
                self:ScrollDown()
            end
        end
    end)

    -- Store references
    frame.buttonContainer = buttonContainer
    frame.logText = logText

    -- Size changed handler
    frame:SetScript("OnSizeChanged", function()
        RLHelper:LayoutMainFrame()
    end)

    self.mainFrame = frame
    self:LayoutMainFrame()
    self:SendMessage("RLHelper_MainFrameCreated", frame)
    frame:Hide()
end

function RLHelper:CreateOptionsPanel()
    if type(CreateFrame) ~= "function" or type(InterfaceOptions_AddCategory) ~= "function" then
        return
    end

    local panel = CreateFrame("Frame", "RLHelperOptionsPanel", UIParent)
    panel.name = "RL Helper"

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("RL Helper")

    local cancelLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    cancelLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -24)
    cancelLabel:SetText("Pull Cancel message text")

    local cancelEditBox = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
    cancelEditBox:SetSize(320, 24)
    cancelEditBox:SetPoint("TOPLEFT", cancelLabel, "BOTTOMLEFT", 8, -8)
    cancelEditBox:SetAutoFocus(false)
    cancelEditBox:SetScript("OnEnterPressed", function(self)
        RLHelper.db.profile.pullCancelMessage = self:GetText()
        self:ClearFocus()
    end)
    cancelEditBox:SetScript("OnEditFocusLost", function(self)
        RLHelper.db.profile.pullCancelMessage = self:GetText()
    end)

    local displayOnlyInGroup = CreateFrame("CheckButton", "RLHelperDisplayOnlyInGroupCheckButton", panel,
        "InterfaceOptionsCheckButtonTemplate")
    displayOnlyInGroup:SetPoint("TOPLEFT", cancelEditBox, "BOTTOMLEFT", -4, -18)
    _G[displayOnlyInGroup:GetName() .. "Text"]:SetText("Display only in Group")
    displayOnlyInGroup:SetScript("OnClick", function(self)
        RLHelper.db.profile.displayOnlyInGroup = self:GetChecked() and true or false
        RLHelper:RefreshMainFrameVisibility()
    end)

    local bossOnlyHistory = CreateFrame("CheckButton", "RLHelperBossOnlyHistoryCheckButton", panel,
        "InterfaceOptionsCheckButtonTemplate")
    bossOnlyHistory:SetPoint("TOPLEFT", displayOnlyInGroup, "BOTTOMLEFT", 0, -8)
    _G[bossOnlyHistory:GetName() .. "Text"]:SetText("Оставлять бои только с боссами")
    bossOnlyHistory:SetScript("OnClick", function(self)
        RLHelper.db.profile.bossOnlyHistory = self:GetChecked() and true or false
    end)

    local igor = CreateFrame("CheckButton", "RLHelperIgorCheckButton", panel, "InterfaceOptionsCheckButtonTemplate")
    igor:SetPoint("TOPLEFT", bossOnlyHistory, "BOTTOMLEFT", 0, -8)
    _G[igor:GetName() .. "Text"]:SetText("Игорь")
    igor:SetScript("OnClick", function(self)
        RLHelper.db.profile.igor = self:GetChecked() and true or false
    end)

    panel:SetScript("OnShow", function()
        cancelEditBox:SetText(RLHelper.db.profile.pullCancelMessage or "")
        displayOnlyInGroup:SetChecked(RLHelper.db.profile.displayOnlyInGroup)
        bossOnlyHistory:SetChecked(RLHelper.db.profile.bossOnlyHistory)
        igor:SetChecked(RLHelper.db.profile.igor)
    end)

    self.optionsPanel = panel
    InterfaceOptions_AddCategory(panel)
end

function RLHelper:OpenOptionsPanel()
    if not self.optionsPanel or type(InterfaceOptionsFrame_OpenToCategory) ~= "function" then
        return false
    end

    InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
    return true
end

function RLHelper:ClearCombatHistory()
    self.combatHistory = {}
    self.db.profile.combatHistory = {}
    self:Print("История боев очищена")
end

function RLHelper:ShowCombatByIndex(index)
    if index < 1 or index > #self.combatHistory then
        self:Print(
            "Неверный номер боя. Используйте /rlh history для просмотра списка боев")
        return
    end

    local combat = self.combatHistory[index]
    self:DisplayCombat(combat)
    self.mainFrame:Show()
end

function RLHelper:FindModuleByName(moduleName)
    if type(self.GetModule) == "function" then
        local ok, module = pcall(self.GetModule, self, moduleName, true)
        if ok and module then
            return module
        end
    end

    if type(self.IterateModules) ~= "function" then
        return nil
    end

    for _, module in self:IterateModules() do
        if module and module.name == moduleName then
            return module
        end
    end

    return nil
end

function RLHelper:TriggerDamageMeterReset()
    local halionTracker = self:FindModuleByName("HalionTracker")
    if not halionTracker or type(halionTracker.resetDamageMeters) ~= "function" then
        self:Debug("HalionTracker недоступен")
        return false
    end

    local ok = halionTracker:resetDamageMeters()
    if not ok then
        self:Debug("Не удалось переключить сегмент у meter addon")
        return false
    end

    self:Debug("Сброс сегментов урона запущен")
    return true
end

function RLHelper:HandleSlashCommand(input)
    if input == "" then
        if self.mainFrame:IsShown() then
            self:SetMainFrameVisible(false)
        else
            self:SetMainFrameVisible(true)
        end
    elseif input == "help" then
        print("RL Быдло команды:")
        print("/rlh - показать/скрыть окно")
        print("/rlh help - показать помощь")
        print("/rlh config|options - открыть настройки")
        print("/rlh debug - включить/выключить режим отладки")
        print("/rlh zone - вывести текущую зону и активность модулей")
        print("/rlh fill - включить/выключить режим отладки")
        print("/rlh hist - показать историю боев")
        print("/rlh clear - очистить историю боев")
        print("/rlh demo - show all messages")
        print("/rlh meters - вручную сбросить сегменты урона")
        print("/rlh b # - показать бой по номеру")
    elseif input == "fill" then
        for i = 1, 50 do
            self:OnCombatLogEvent(string.format(
                "Test message %d: |T%s:24:24:0:0|t |T%s:24:24:0:0|t |T%s:24:24:0:0|t |T%s:24:24:0:0|t |T%s:24:24:0:0|t",
                i, "Interface\\Icons\\INV_Misc_QuestionMark", "Interface\\Icons\\INV_Misc_QuestionMark",
                "Interface\\Icons\\INV_Misc_QuestionMark", "Interface\\Icons\\INV_Misc_QuestionMark",
                "Interface\\Icons\\INV_Misc_QuestionMark"))
        end
    elseif input == "debug" then
        self.db.profile.debug = not self.db.profile.debug
        print("Режим отладки: " .. (self.db.profile.debug and "включен" or "выключен"))
        if self.db.profile.debug then
            self:UpdateZoneContext("debug enabled")
        end
    elseif input == "config" or input == "options" then
        self:OpenOptionsPanel()
    elseif input == "zone" then
        self:UpdateZoneContext("slash zone", true)
        self:PrintZoneDebug("slash zone", true)
    elseif input == "clear" then
        self:ClearCombatHistory()
    elseif input == "demo" then
        self:SendMessage("RLHelper_Demo")
    elseif input == "meters" then
        self:TriggerDamageMeterReset()
    elseif input:match("^b%s+(%d+)$") then
        local index = tonumber(input:match("^b%s+(%d+)$"))
        self:ShowCombatByIndex(index)
    end
end

return RLHelper
