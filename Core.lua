local RLHelper = LibStub("AceAddon-3.0"):NewAddon("RLHelper", "AceConsole-3.0", "AceEvent-3.0", "LibCompat-1.0")
local callbacks = LibStub("CallbackHandler-1.0"):New(RLHelper)
local IsGroupInCombat, InCombatLockdown = RLHelper.IsGroupInCombat, InCombatLockdown
local GetUnitIdFromGUID = RLHelper.GetUnitIdFromGUID
local CombatFilters = RLHelperCombatFilters
local BossIds = RLHelperBossIds
local Journal = RLHelperJournal
local UITheme = {}
RLHelper.UITheme = UITheme

-- Keep theme initialization in Core so an existing client's cached TOC can load it.
do
    local Theme = UITheme
    local TEXTURE_STATES = { "Normal", "Pushed", "Highlight", "Disabled" }
    local FONT_STATES = { "Normal", "Highlight", "Disabled" }
    local BUTTON_COLORS = {
        Normal = { 0.17, 0.20, 0.23, 1 },
        Pushed = { 0.10, 0.12, 0.15, 1 },
        Highlight = { 0.75, 0.85, 0.92, 0.12 },
        Disabled = { 0.12, 0.14, 0.17, 1 }
    }

    function Theme.GetName(addon)
        local profile = addon.db and addon.db.profile
        return profile and profile.theme == "minimal" and "minimal" or "current"
    end

    function Theme.ApplyButton(addon, button, view)
        local minimal = Theme.GetName(addon) == "minimal"
        if not minimal and not button.originalThemeButton then return end
        if not button.originalThemeButton then
            local original = { textures = {}, fonts = {}, font = { button:GetFontString():GetFont() } }
            button.originalThemeButton = original
            for _, state in ipairs(TEXTURE_STATES) do
                local texture = button["Get" .. state .. "Texture"](button)
                original.textures[state] = texture and {
                    path = texture:GetTexture(), blend = texture:GetBlendMode()
                } or {}
            end
            for _, state in ipairs(FONT_STATES) do
                original.fonts[state] = button["Get" .. state .. "FontObject"](button)
            end
            if view then
                local marker = button:CreateTexture(nil, "OVERLAY")
                marker:SetPoint("BOTTOMLEFT", button, "BOTTOMLEFT", 0, 0)
                marker:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 0, 0)
                marker:SetHeight(2)
                marker:SetTexture(0.74, 0.85, 0.92, 1)
                button.themeSelection = marker
            end
        end

        local original = button.originalThemeButton
        -- Keep button-owned textures attached: swapping and reusing Texture objects
        -- can crash the old client. Let the button manage their state visibility.
        for _, state in ipairs(TEXTURE_STATES) do
            local texture = button["Get" .. state .. "Texture"](button)
            if not texture and minimal then
                button["Set" .. state .. "Texture"](button, "Interface\\Buttons\\WHITE8X8")
                texture = button["Get" .. state .. "Texture"](button)
            end
            if texture then
                local saved = original.textures[state]
                if minimal then
                    texture:SetTexture(unpack(BUTTON_COLORS[state]))
                    texture:SetBlendMode("BLEND")
                else
                    texture:SetTexture(saved.path)
                    texture:SetBlendMode(saved.blend or "BLEND")
                end
            end
        end
        for _, state in ipairs(FONT_STATES) do
            local font = original.fonts[state]
            if minimal then
                font = state == "Disabled" and not view and "GameFontDisable" or "GameFontHighlight"
            end
            button["Set" .. state .. "FontObject"](button, font)
        end
        if not minimal then button:GetFontString():SetFont(unpack(original.font)) end
        if button.themeSelection then
            if minimal and addon.journalView == view then button.themeSelection:Show()
            else button.themeSelection:Hide() end
        end
    end

    function Theme.RegisterButton(addon, button, view)
        addon.themeButtons = addon.themeButtons or {}
        addon.themeButtons[button] = view or false
        Theme.ApplyButton(addon, button, view)
    end

    function Theme.Apply(addon)
        local frame = addon.mainFrame
        if not frame then return end
        local minimal = Theme.GetName(addon) == "minimal"
        -- Leave the original UI untouched until the user first selects minimalism.
        if minimal or frame.originalThemeFont then
            if not frame.originalThemeFont then
                frame.originalThemeFont = { frame.logText:GetFont() }
            end
            frame.buttonContainer:ClearAllPoints()
            if minimal then
                frame.buttonContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
                frame.buttonContainer:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
                local font = frame.originalThemeFont
                frame.logText:SetFont(font[1], font[2], "")
            else
                frame.buttonContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
                frame.buttonContainer:SetPoint("TOPRIGHT", -2, -2)
                frame.logText:SetFont(unpack(frame.originalThemeFont))
            end
        end
        for button, view in pairs(addon.themeButtons or {}) do
            Theme.ApplyButton(addon, button, view or nil)
        end
        if frame.v2Rows then
            local font, size, flags = unpack(frame.originalThemeFont or { frame.logText:GetFont() })
            flags = minimal and "" or flags
            frame.v2Measure:SetFont(font, size, flags)
            for _, row in ipairs(frame.v2Rows) do row.text:SetFont(font, size, flags) end
            frame.v2Heights = setmetatable({}, { __mode = "k" })
        end
        addon:LayoutMainFrame()
        if frame.v2Scroll and addon.currentCombat and #(addon.currentCombat.events or {}) > 0 then
            addon:RefreshJournalRows(addon.displayedCombat or addon.currentCombat, true)
        end
    end
end

local COMBAT_END_CHECK_INTERVAL = 1
local COMBAT_END_GRACE = 3
local ENEMY_ACTIVITY_TIMEOUT = 6
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
    ["Цитадель Ледяной Короны"] = 631,
    ["Ulduar"] = 603,
    ["Ульдуар"] = 603
}
local DBM_PULL_BAR_NAMES = {
    "АТAKA!!",
    "Атака",
    "Pull in"
}

local DEFAULT_GP_AWARD_REASONS = {
    [100] = "Каспер",
    [200] = "Вомбат",
    [250] = "Бэтмен",
    [500] = "Капибара",
    [1000] = "Banana"
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
local COMBATLOG_OBJECT_TYPE_PLAYER_FLAG = COMBATLOG_OBJECT_TYPE_PLAYER or 0x00000400

-- Enemy flags
RLHelper.ENEMY_FLAGS = 0xa48 -- Маска для проверки враждебных NPC (OUTSIDER | HOSTILE | NPC | NPC_TYPE)

-- Default settings
local defaults = {
    profile = {
        enabled = true,
        debug = false,
        theme = "current",
        pullCancelMessage = "ГАЛЯ, ОТМЕНА!",
        discordLink = "",
        gpAwardButtonsEnabled = false,
        gpAwardReasons = DEFAULT_GP_AWARD_REASONS,
        displayOnlyInGroup = false,
        bossOnlyHistory = false,
        igor = false,
        halionBurstPull = false,
        halionBurstReset = true,
        halionPhaseTwoEntryTimer = false,
        minimap = {
            hide = false
        },
        savedPosition = nil -- Add saved position storage
    },
    char = {}
}

-- Combat history structures
RLHelper.combatHistory = {} -- Array for combat history
RLHelper.currentCombat = {
    startTime = nil,
    events = {},
    firstEnemy = nil, -- Name of the first enemy in combat
    isBoss = false
}
RLHelper.displayedCombat = RLHelper.currentCombat
RLHelper.viewingCurrentCombat = true -- Initialize to true by default

RLHelper.activeEnemies = {}
RLHelper.activePlayers = {}
RLHelper.groupMembers = {}
RLHelper.groupAssignments = {}
RLHelper.hasTankAssignments = false
RLHelper.enemyEvents = {} -- Structure to track enemies and their events
RLHelper.lastCombatActivityAt = nil
RLHelper.combatEndRequestedAt = nil
RLHelper.combatEndRequiresRegen = false
RLHelper.combatTicker = nil
RLHelper.currentInstanceId = nil

function RLHelper:Debug(...)
    if self.db and self.db.profile and self.db.profile.debug then
        self:Print(...)
    end
end

function RLHelper:isDebugging()
    return self.db and self.db.profile and self.db.profile.debug or false
end

local function trimText(value)
    if type(value) ~= "string" then
        return ""
    end

    return value:match("^%s*(.-)%s*$") or ""
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

-- Combat-log affiliation/reaction changes when the observer is mind-controlled.
-- Keep group identity separate from those flags and from per-combat state.
function RLHelper:RefreshGroupRoster()
    wipe(self.groupMembers)
    wipe(self.groupAssignments)
    self.hasTankAssignments = false
    local function addUnit(unit)
        if UnitExists(unit) then
            local guid = UnitGUID(unit)
            if guid then
                self.groupMembers[guid] = unit
            end
        end
    end

    addUnit("player")
    addUnit("pet")
    local raidSize = GetNumRaidMembers()
    local prefix = raidSize > 0 and "raid" or "party"
    local count = raidSize > 0 and raidSize or GetNumPartyMembers()
    for i = 1, count do
        addUnit(prefix .. i)
        addUnit(prefix .. "pet" .. i)
        if raidSize > 0 then
            local guid = UnitGUID("raid" .. i)
            local assignment = select(10, GetRaidRosterInfo(i))
            if self.groupMembers[guid] and (assignment == "MAINTANK" or assignment == "MAINASSIST") then
                self.groupAssignments[guid] = assignment
                self.hasTankAssignments = true
            end
        end
    end
end

function RLHelper:IsGroupMember(guid, flags)
    return self.groupMembers[guid] ~= nil or bit.band(flags or 0, self.GROUP_AFFILIATION_ANY) > 0
end

function RLHelper:IsAssignedTank(guid)
    local assignment = self.groupAssignments[guid]
    return assignment == "MAINTANK" or assignment == "MAINASSIST"
end

function RLHelper:ShouldShowMainFrame()
    return not (self.db and self.db.profile and self.db.profile.displayOnlyInGroup) or self:IsInGroup()
end

function RLHelper:IsHalionBurstPullEnabled()
    return self.db and self.db.profile and self.db.profile.halionBurstPull == true or false
end

function RLHelper:IsHalionBurstResetEnabled()
    return not (self.db and self.db.profile and self.db.profile.halionBurstReset == false)
end

function RLHelper:IsHalionPhaseTwoEntryTimerEnabled()
    return self.db and self.db.profile and self.db.profile.halionPhaseTwoEntryTimer == true or false
end

function RLHelper:GetDiscordLink()
    return trimText(self.db and self.db.profile and self.db.profile.discordLink)
end

function RLHelper:HasDiscordLink()
    return self:GetDiscordLink() ~= ""
end

function RLHelper:RefreshDiscordButton()
    if not self.mainFrame or not self.mainFrame.discordButton then
        return
    end

    if self:HasDiscordLink() then
        self.mainFrame.discordButton:Show()
    else
        self.mainFrame.discordButton:Hide()
    end
end

function RLHelper:SendDiscordLink()
    local link = self:GetDiscordLink()
    if link == "" or type(SendChatMessage) ~= "function" then
        return false
    end

    local isRaid = GetRealNumRaidMembers and GetRealNumRaidMembers() > 0
    local canAnnounce = (UnitIsGroupLeader and UnitIsGroupLeader("player")) or
        (UnitIsGroupAssistant and UnitIsGroupAssistant("player"))
    local channel = isRaid and (canAnnounce and "RAID_WARNING" or "RAID") or "PARTY"
    SendChatMessage(link, channel)
    return true
end

function RLHelper:RefreshGPAwardButtons()
    if type(self.GetModule) ~= "function" then
        return
    end

    local ok, module = pcall(self.GetModule, self, "GPAwardButtons", true)
    if ok and module and type(module.refreshVisibility) == "function" then
        module:refreshVisibility()
    end
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

    self:InitializeJournal()

    self:RegisterChatCommand("rlh", "HandleSlashCommand")

    self:CreateMainFrame()
    self:CreateOptionsPanel()
    self:CreateMinimapButton()

    self.mainFrame:Show()
    self:RefreshMainFrameVisibility()

    self:Debug("RL Быдло: Аддон включен")
end

function RLHelper:InitializeJournal()
    self.db.profile.journalV2 = nil
    self.db.profile.combatHistory = nil
    for _, profile in pairs(self.db.sv and self.db.sv.profiles or {}) do
        profile.journalV2 = nil
        profile.combatHistory = nil
    end
    self.db.char.combatHistory = nil
    for _, character in pairs(self.db.sv and self.db.sv.char or {}) do
        character.combatHistory = nil
    end
    self.journalView = "ALL"
    self.followNextCombat = false
    local store = self.db.char.combatHistoryV2
    if not store then
        store = { schemaVersion = 2, nextCombatId = 1, combats = {} }
        self.db.char.combatHistoryV2 = store
    end
    assert(store.schemaVersion == 2, "Unsupported combatHistoryV2 schema")
    self.combatHistory = Journal.Copy(store.combats)
    self.currentCombat = { events = {}, isBoss = false }
    self.displayedCombat = self.currentCombat
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
    self:RegisterEvent("UNIT_PET", "RefreshGroupRoster")
    self:RefreshGroupRoster()
    self:UpdateZoneContext()
    self:RefreshMainFrameVisibility()
end

local function isEnemy(flags, guid)
    return not RLHelper:IsGroupMember(guid, flags) and bit.band(flags or 0, RLHelper.ENEMY_FLAGS) > 0
end

local function isPlayerType(flags)
    return bit.band(flags or 0, COMBATLOG_OBJECT_TYPE_PLAYER_FLAG) > 0
end

local function isOutsidePlayer(flags, guid)
    return isPlayerType(flags) and not RLHelper:IsGroupMember(guid, flags)
end

local function shouldIgnoreCombatEnemy(name)
    return CombatFilters and CombatFilters:IsIgnoredCombatEnemy(name) or false
end

local function creatureIdFromGuid(guid)
    if type(RLHelper.GetCreatureId) == "function" then
        return RLHelper.GetCreatureId(guid)
    end

    return type(guid) == "string" and tonumber(guid:sub(9, 12), 16) or nil
end

local function bossNameFromModule(module, npcId)
    if type(module) ~= "table" or type(module.bossIds) ~= "table" or type(npcId) ~= "number" then
        return nil
    end

    return module.bossIds[npcId]
end

local function bossNameFromRegistry(instanceId, npcId)
    if type(BossIds) ~= "table" or type(BossIds.BY_INSTANCE) ~= "table" or type(npcId) ~= "number" then
        return nil
    end

    local instanceBossIds = BossIds.BY_INSTANCE[instanceId]
    if type(instanceBossIds) ~= "table" then
        return nil
    end

    return instanceBossIds[npcId]
end

local function isValithriaHealTrigger(event, npcId)
    local valithriaId = BossIds and BossIds.NPCS and BossIds.NPCS.VALITHRIA_DREAMWALKER
    if npcId ~= valithriaId then
        return true
    end

    return (event.event == "SPELL_HEAL" or event.event == "SPELL_PERIODIC_HEAL") and
        RLHelper:IsGroupMember(event.sourceGUID, event.sourceFlags) and
        (event.amount or 0) > 0
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

local function isTrackableEnemy(flags, name, guid)
    return isEnemy(flags, guid) and not shouldIgnoreCombatEnemy(name)
end

local function involvesTrackableEnemy(event)
    return isTrackableEnemy(event.sourceFlags, event.sourceName, event.sourceGUID) or
        isTrackableEnemy(event.destFlags, event.destName, event.destGUID)
end

local function isEnemyDeathEvent(event)
    return event.event == "UNIT_DIED" or event.event == "UNIT_DESTROYED" or event.event == "PARTY_KILL"
end

local function involvesOutsidePlayer(event)
    return isOutsidePlayer(event.sourceFlags, event.sourceGUID) or isOutsidePlayer(event.destFlags, event.destGUID)
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

function RLHelper:HasActiveEnemies()
    for _, seenAt in pairs(self.activeEnemies) do
        if seenAt ~= 0 then
            return true
        end
    end

    return false
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

function RLHelper:IsDisplayingCurrentCombat()
    return not self.displayedCombat or self.displayedCombat == self.currentCombat
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
    if self:IsDisplayingCurrentCombat() or self.followNextCombat then
        self:ShowCurrentCombat()
    end
    self:Debug("Combat started", reason)
end

function RLHelper:ResetCombatState()
    local wasDisplayingCurrentCombat = self:IsDisplayingCurrentCombat()
    self.followNextCombat = false

    self:StopCombatTicker()
    self.inCombat = false
    self.lastCombatActivityAt = nil
    self.combatEndRequestedAt = nil
    self.combatEndRequiresRegen = false

    self.currentCombat = {
        startTime = nil,
        events = {},
        firstEnemy = nil,
        isBoss = false
    }

    if wasDisplayingCurrentCombat then
        self.displayedCombat = self.currentCombat
    end

    wipe(self.activeEnemies)
    wipe(self.activePlayers)
    wipe(self.enemyEvents)
end

function RLHelper:FinishCombat(reason)
    self:Debug("Combat ended", reason)
    local wasDisplayingCurrentCombat = self:IsDisplayingCurrentCombat()

    self:SendMessage("RLHelper_CombatEnding")

    local combat = nil
    local records = self.currentCombat.events
    if self.currentCombat.startTime and #(records or {}) > 0 then
        combat = {
            startTime = self.currentCombat.startTime,
            endTime = time(),
            events = self.currentCombat.events,
            id = self.currentCombat.id,
            droppedEvents = self.currentCombat.droppedEvents,
            firstEnemy = self.currentCombat.firstEnemy,
            isBoss = self.currentCombat.isBoss
        }
    end

    self:ResetCombatState()

    if combat and self:ShouldSaveCombatToHistory(combat) then
        self:SaveCombatToProfile(combat)
        self:Debug("Combat Saved to history")
    end

    if combat and wasDisplayingCurrentCombat then
        self:DisplayCombat(combat)
        self.followNextCombat = true
    end

    self:SendMessage("RLHelper_CombatEnded")
end

function RLHelper:trackCombatants(event)
    if event.spellId == LADY_KONTROL or not affectingGroup(event) or not involvesTrackableEnemy(event) then
        return false
    end

    local now = self:GetCombatNow()
    self.lastCombatActivityAt = now
    self.combatEndRequestedAt = nil

    if RLHelper:IsGroupMember(event.sourceGUID, event.sourceFlags) and event.sourceGUID then
        self.activePlayers[event.sourceGUID] = true
    end
    if RLHelper:IsGroupMember(event.destGUID, event.destFlags) and event.destGUID then
        self.activePlayers[event.destGUID] = true
    end

    if isTrackableEnemy(event.sourceFlags, event.sourceName, event.sourceGUID) then
        self:MarkEnemyActivity(event.sourceGUID, event.sourceName, event.event, now)
    end
    if isTrackableEnemy(event.destFlags, event.destName, event.destGUID) then
        self:MarkEnemyActivity(event.destGUID, event.destName, event.event, now)
    end

    if isEnemyDeathEvent(event) then
        if isEnemy(event.destFlags, event.destGUID) then
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

    local now = self:GetCombatNow()
    self.combatEndRequestedAt = now
    self.combatEndRequiresRegen = false
    if not self:HasActiveEnemies() and not self.currentCombat.firstEnemy and not self:IsCombatOngoing(now) then
        self:ResetCombatState()
        return
    end

    if not self:HasActiveEnemies() and not self:IsCombatOngoing(now) then
        self:FinishCombat("PLAYER_REGEN_ENABLED")
        return
    end

    self:EnsureCombatTicker()
    self:EvaluateCombatEnd("PLAYER_REGEN_ENABLED")
end

function RLHelper:PLAYER_REGEN_DISABLED()
    self.combatEndRequiresRegen = true
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
    self:RefreshGroupRoster()
    self:UpdateZoneContext("PLAYER_ENTERING_WORLD")
end

function RLHelper:ZONE_CHANGED_NEW_AREA()
    self:UpdateZoneContext("ZONE_CHANGED_NEW_AREA")
end

function RLHelper:PARTY_MEMBERS_CHANGED()
    self:RefreshGroupRoster()
    self:RefreshMainFrameVisibility()
end

function RLHelper:RAID_ROSTER_UPDATE()
    self:RefreshGroupRoster()
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

function affectingGroup(event)
    return RLHelper:IsGroupMember(event.sourceGUID, event.sourceFlags) or
        RLHelper:IsGroupMember(event.destGUID, event.destFlags)
end

function RLHelper:IsBossGUID(guid)
    if self:IsGroupMember(guid) then return false end
    local npcId = creatureIdFromGuid(guid)
    if bossNameFromRegistry(self.currentInstanceId, npcId) then return true end
    if type(self.IterateModules) == "function" then
        for _, module in self:IterateModules() do
            if self:ShouldDispatchCombatEventToModule(module) and bossNameFromModule(module, npcId) then
                return true
            end
        end
    end
    return false
end

function RLHelper:GetKnownBossNameFromCombatEvent(event)
    local sourceNpcId = creatureIdFromGuid(event.sourceGUID)
    local destNpcId = creatureIdFromGuid(event.destGUID)

    local sourceRegistryBossName = bossNameFromRegistry(self.currentInstanceId, sourceNpcId)
    if sourceRegistryBossName and isValithriaHealTrigger(event, sourceNpcId) then
        return sourceRegistryBossName
    end

    local destRegistryBossName = bossNameFromRegistry(self.currentInstanceId, destNpcId)
    if destRegistryBossName and isValithriaHealTrigger(event, destNpcId) then
        return destRegistryBossName
    end

    if type(self.IterateModules) ~= "function" then
        return nil
    end

    for _, module in self:IterateModules() do
        if self:ShouldDispatchCombatEventToModule(module) then
            local sourceBossName = bossNameFromModule(module, sourceNpcId)
            if sourceBossName and isValithriaHealTrigger(event, sourceNpcId) then
                return sourceBossName
            end

            local destBossName = bossNameFromModule(module, destNpcId)
            if destBossName and isValithriaHealTrigger(event, destNpcId) then
                return destBossName
            end
        end
    end

    return nil
end

function RLHelper:MarkBossCombat(event)
    if not self.currentCombat or self.currentCombat.isBoss or not affectingGroup(event) then
        return false
    end

    local bossName = self:GetKnownBossNameFromCombatEvent(event)
    if not bossName then
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

    if involvesOutsidePlayer(eventData) then
        return
    end

    self:trackCombatants(eventData)
    self:MarkBossCombat(eventData)

    if not self.currentCombat.firstEnemy and affectingGroup(eventData) then
        -- Save first enemy name if not set yet
        if isEnemy(eventData.sourceFlags, eventData.sourceGUID) and not shouldIgnoreCombatEnemy(eventData.sourceName) then
            self.currentCombat.firstEnemy = eventData.sourceName
        elseif isEnemy(eventData.destFlags, eventData.destGUID) and not shouldIgnoreCombatEnemy(eventData.destName) then
            self.currentCombat.firstEnemy = eventData.destName
        end
    end

    self:DispatchCombatEvent(eventData)
end

function RLHelper:OnCombatLogEvent(message)
    assert(type(message) == "table" and message.kind and message.type, "Journal requires a structured event")
    local combat = self.currentCombat
    combat.events = combat.events or {}
    if #combat.events >= Journal.MAX_EVENTS then
        combat.droppedEvents = (combat.droppedEvents or 0) + 1
        if combat.droppedEvents == 1 and self.mainFrame and self.mainFrame.logText and self:IsDisplayingCurrentCombat() then
            self.mainFrame.logText:AddMessage("|cFFFF5555Достигнут лимит истории: дальнейшие события не сохраняются|r")
            self:RefreshJournalRows(combat)
        end
        return
    end
    local entry = Journal.Copy(message)
    entry.seq = #combat.events + 1
    table.insert(combat.events, entry)
    if self.mainFrame and self.mainFrame.logText and self:IsDisplayingCurrentCombat() and
        Journal.Visible(entry, self.journalView) then
        self.mainFrame.logText:AddMessage(self:FormatJournalEntry(entry))
        self:RefreshJournalRows(combat)
    end
end

function RLHelper:FormatJournalEntry(entry)
    local text = Journal.Format(entry, self.journalView == "ERRORS")
    if entry.kind == "MISDIRECTION_SUMMARY" then
        text = "|Hrlhpull:" .. entry.pullId .. "|h" .. text .. "|h"
    end
    return text
end

function RLHelper:SetJournalView(view)
    self.journalView = view
    for name, button in pairs(self.mainFrame and self.mainFrame.journalFilterButtons or {}) do
        if name == view then button:Disable() else button:Enable() end
        UITheme.ApplyButton(self, button, name)
    end
    self:DisplayCombat(self.displayedCombat or self.currentCombat)
end

function RLHelper:SaveCombatToProfile(combat)
    local store = self.db.char.combatHistoryV2
    if not combat.id then
        combat.id = store.nextCombatId
        store.nextCombatId = store.nextCombatId + 1
    end
    for _, saved in ipairs(store.combats) do
        if saved.id == combat.id then return end
    end
    table.insert(store.combats, 1, Journal.Copy(combat))
    while #store.combats > Journal.MAX_COMBATS do table.remove(store.combats) end
    self.combatHistory = Journal.Copy(store.combats)
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
        if self.combatEndRequiresRegen then
            return false
        end

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
    self:ShowCurrentCombat()
    self:BeginPullCountdown(duration)
    self:InvokeDBMPullCommand(duration)
    self:MinimizeWindow()

    if self.mainFrame and self.mainFrame.logText then
        self.mainFrame.logText:Clear()
    end
end

function RLHelper:StartDBMPullCommand(duration)
    return self:InvokeDBMPullCommand(duration)
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

local COMBAT_LIST_GRAY = "|cff808080"
local COMBAT_LIST_WHITE = "|cffffffff"
local COMBAT_LIST_YELLOW = "|cffffff00"
local COLOR_END = "|r"

local function getVisibleCharacterCount(text)
    local count = 0
    for i = 1, string.len(text) do
        local byte = string.byte(text, i)
        if byte < 128 or byte >= 192 then
            count = count + 1
        end
    end
    return count
end

local function getCombatListTextWidth(text)
    local plainText = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    return math.max(260, (getVisibleCharacterCount(plainText) * 7) + 16)
end

function RLHelper:FormatCombatListRow(index, combat, prefix, selected)
    local name = combat and combat.firstEnemy or "Бой"
    local startTime = combat and combat.startTime or 0
    if selected then
        return string.format("%s%s%02d. %s: %s%s",
            COMBAT_LIST_YELLOW,
            prefix or "",
            index,
            name,
            date("%H:%M", startTime),
            COLOR_END)
    end

    return string.format("%s%s%02d. %s%s%s%s: %s%s",
        COMBAT_LIST_GRAY,
        prefix or "",
        index,
        COLOR_END,
        COMBAT_LIST_WHITE,
        name,
        COLOR_END .. COMBAT_LIST_GRAY,
        date("%H:%M", startTime),
        COLOR_END)
end

function RLHelper:RefreshCombatListOverlay()
    local frame = self.mainFrame
    if not frame or not frame.combatListFrame then
        return
    end

    frame.combatListRows = frame.combatListRows or {}
    local selectedKind = self.selectedCombatKind or "current"
    local selectedIndex = self.selectedCombatIndex
    local rowIndex = 1
    local listWidth = 280

    local function setRow(text, onClick)
        local row = frame.combatListRows[rowIndex]
        if not row then
            row = CreateFrame("Button", nil, frame.combatListFrame)
            row:SetSize(260, 18)
            row:SetPoint("TOPLEFT", frame.combatListFrame, "TOPLEFT", 8, -8 - ((rowIndex - 1) * 18))
            row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            row.label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            row.label:SetPoint("LEFT", row, "LEFT", 0, 0)
            row.label:SetJustifyH("LEFT")
            frame.combatListRows[rowIndex] = row
        end

        row.label:SetText(text)
        row:SetScript("OnClick", onClick)
        row:Show()
        listWidth = math.max(listWidth, getCombatListTextWidth(text) + 16)
        rowIndex = rowIndex + 1
    end

    local currentPrefix = selectedKind == "current" and "> " or "  "
    local currentText = currentPrefix .. "Текущий"
    if selectedKind == "current" then
        currentText = COMBAT_LIST_YELLOW .. currentText .. COLOR_END
    end
    setRow(currentText, function()
        RLHelper:ShowCurrentCombat()
        RLHelper:HideCombatListOverlay()
    end)

    for i, combat in ipairs(self.combatHistory) do
        local selected = selectedKind == "history" and selectedIndex == i
        local prefix = selected and "> " or "  "
        setRow(self:FormatCombatListRow(i, combat, prefix, selected), function()
            RLHelper:ShowCombatByIndex(i)
            RLHelper:HideCombatListOverlay()
        end)
    end

    for i = rowIndex, #frame.combatListRows do
        frame.combatListRows[i]:Hide()
    end

    for i = 1, rowIndex - 1 do
        frame.combatListRows[i]:SetSize(listWidth - 16, 18)
    end

    frame.combatListFrame:SetSize(listWidth, 16 + ((rowIndex - 1) * 18))
end

function RLHelper:HideCombatListOverlay()
    local frame = self.mainFrame
    if not frame then
        return
    end

    if frame.combatListFrame then
        frame.combatListFrame:Hide()
    end

    if frame.combatListClickCatcher then
        frame.combatListClickCatcher:Hide()
    end
end

function RLHelper:ToggleCombatListOverlay()
    local frame = self.mainFrame
    if not frame or not frame.combatListFrame then
        return
    end

    if frame.combatListFrame.visible then
        self:HideCombatListOverlay()
        return
    end

    self:RefreshCombatListOverlay()
    if frame.combatListClickCatcher then
        frame.combatListClickCatcher:Show()
    end
    frame.combatListFrame:Show()
end

function RLHelper:UpdateCombatDropdown()
    self:RefreshCombatListOverlay()
end

function RLHelper:DisplayCombat(combat)
    self.displayedCombat = combat

    if not self.mainFrame or not self.mainFrame.logText then
        return
    end

    self.mainFrame.logText:Clear()
    if combat then
        for _, entry in ipairs(combat.events or {}) do
            if Journal.Visible(entry, self.journalView) then
                self.mainFrame.logText:AddMessage(self:FormatJournalEntry(entry))
            end
        end
        if combat.droppedEvents then
            self.mainFrame.logText:AddMessage("|cFFFF5555Лимит истории: пропущено событий " .. combat.droppedEvents .. "|r")
        end
    end

    self:RefreshJournalRows(combat)
    self:RefreshCombatListOverlay()
end

function RLHelper:ShowCurrentCombat()
    self.followNextCombat = false
    self.selectedCombatKind = "current"
    self.selectedCombatIndex = nil
    self:DisplayCombat(self.currentCombat)
end

function RLHelper:SetTheme(theme)
    self.db.profile.theme = theme == "minimal" and "minimal" or "current"
    UITheme.Apply(self)
end

-- Reuse visible V2 rows so a violation can have its own background.
function RLHelper:RenderJournalRows()
    local frame = self.mainFrame
    local scroll = frame and frame.v2Scroll
    if not scroll then return end
    if frame.v2TargetButton and not InCombatLockdown() then frame.v2TargetButton:Hide() end
    local offset = scroll:GetVerticalScroll()
    local bottom = offset + scroll:GetHeight()
    local visible = 0
    for _, item in ipairs(frame.v2Items or {}) do
        if item.top < bottom and item.top + item.height > offset then
            visible = visible + 1
            local row = frame.v2Rows[visible]
            if not row then break end
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", frame.v2Content, "TOPLEFT", 0, -item.top)
            row:SetPoint("TOPRIGHT", frame.v2Content, "TOPRIGHT", 0, -item.top)
            row:SetHeight(item.height)
            row.text:SetText(item.text)
            row.entry = item.entry
            if item.highlighted then row.background:Show()
            else row.background:Hide() end
            row:Show()
        end
    end
    for i = visible + 1, #frame.v2Rows do frame.v2Rows[i]:Hide() end
end

function RLHelper:RefreshJournalRows(combat, preservePosition)
    local frame = self.mainFrame
    local scroll = frame and frame.v2Scroll
    if not scroll then return end
    local width = math.max(scroll:GetWidth(), 1)
    local previousOffset = preservePosition and scroll:GetVerticalScroll() or 0
    local items, top = {}, 0
    frame.v2Measure:SetWidth(math.max(width, 1))
    local events = combat and combat.events or {}
    local first, count = 1, 0
    for i = #events, 1, -1 do
        if Journal.Visible(events[i], self.journalView) then
            count = count + 1
            if count == 1000 then first = i; break end
        end
    end
    for i = first, #events do
        local entry = events[i]
        if Journal.Visible(entry, self.journalView) then
            local cached = frame.v2Heights[entry]
            local highlighted = self.journalView == "ALL" and Journal.Visible(entry, "ERRORS")
            local text = Journal.Format(entry, highlighted or self.journalView == "ERRORS"):gsub(":24:24:0:%-2|t", ":20:20:0:-1|t")
            if not cached or cached.width ~= width or cached.text ~= text then
                frame.v2Measure:SetText(text)
                cached = { width = width, text = text,
                    height = math.max(21, frame.v2Measure:GetStringHeight() + 1) }
                frame.v2Heights[entry] = cached
            end
            items[#items + 1] = { entry = entry, text = text, top = top, height = cached.height,
                highlighted = highlighted }
            top = top + cached.height
        end
    end
    if combat and combat.droppedEvents then
        local warning = "|cFFFF5555Лимит истории: пропущено событий " .. combat.droppedEvents .. "|r"
        frame.v2Measure:SetText(warning)
        local height = math.max(21, frame.v2Measure:GetStringHeight() + 1)
        frame.v2WarningEntry = frame.v2WarningEntry or { type = "INFO" }
        items[#items + 1] = { entry = frame.v2WarningEntry, text = warning, top = top, height = height }
        top = top + height
    end
    frame.v2Items = items
    frame.v2Content:SetSize(width, math.max(top, scroll:GetHeight(), 1))
    local maximumOffset = math.max(top - scroll:GetHeight(), 0)
    scroll:SetVerticalScroll(preservePosition and math.min(previousOffset, maximumOffset) or maximumOffset)
    self:RenderJournalRows()
end

function RLHelper:CreateJournalRows(frame)
    local scroll = CreateFrame("ScrollFrame", nil, frame)
    scroll:SetAllPoints(frame.logText)
    scroll:EnableMouse(true)
    scroll:EnableMouseWheel(true)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(1, 1)
    content:EnableMouse(true)
    scroll:SetScrollChild(content)
    local function dragWindow(region)
        region:RegisterForDrag("LeftButton")
        region:SetScript("OnDragStart", function() frame:StartMoving() end)
        region:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)
    end
    dragWindow(scroll)
    dragWindow(content)
    frame.v2Scroll, frame.v2Content, frame.v2Rows = scroll, content, {}
    frame.v2Heights = setmetatable({}, { __mode = "k" })
    local measure = content:CreateFontString(nil, "ARTWORK")
    measure:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    frame.v2Measure = measure

    local function showTargetButton(row)
        if InCombatLockdown() then return end
        local actor = row.entry and Journal.Actor(row.entry)
        if not actor or not actor.name or not UnitIsPlayer(actor.name) then return end
        local button = frame.v2TargetButton
        if not button then
            -- Never parent or anchor a protected button to the live journal: doing
            -- so would also protect the window and prevent combat updates/dragging.
            button = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
            frame.v2TargetButton = button
            button:Hide()
            button:RegisterForClicks("LeftButtonUp")
            button:SetAttribute("type1", "macro")
            -- No out-of-combat 'show' state: an old target must not reappear.
            RegisterStateDriver(button, "visibility", "[combat] hide")
            button:SetScript("OnLeave", function(self)
                if not InCombatLockdown() then self:Hide() end
                if GameTooltip then GameTooltip:Hide() end
            end)
            button:SetScript("OnEnter", function(self)
                if self.row then self.row:GetScript("OnEnter")(self.row) end
            end)
            button:SetScript("OnUpdate", function(self)
                if not InCombatLockdown() and (not frame:IsShown() or not self.row:IsVisible()
                    or self.row.entry ~= self.entry) then self:Hide() end
            end)
            button:EnableMouseWheel(true)
            button:SetScript("OnMouseWheel", function(_, delta)
                scroll:GetScript("OnMouseWheel")(scroll, delta)
            end)
            button:RegisterForDrag("LeftButton")
            button:SetScript("OnDragStart", function(self)
                if InCombatLockdown() then return end
                self:SetAttribute("macrotext1", nil)
                frame:StartMoving()
            end)
            button:SetScript("OnDragStop", function(self)
                frame:StopMovingOrSizing()
                if not InCombatLockdown() then self:Hide() end
            end)
        end
        local scale = row:GetEffectiveScale() / UIParent:GetEffectiveScale()
        local top = math.min(row:GetTop(), scroll:GetTop())
        local bottom = math.max(row:GetBottom(), scroll:GetBottom())
        button:ClearAllPoints()
        button:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", row:GetLeft() * scale, top * scale)
        button:SetSize(row:GetWidth() * scale, math.max(1, top - bottom) * scale)
        button:SetFrameStrata(frame:GetFrameStrata())
        button:SetFrameLevel(row:GetFrameLevel() + 10)
        button.row, button.entry = row, row.entry
        -- The macro condition also covers combat starting before the state driver runs.
        button:SetAttribute("macrotext1", "/targetexact [nocombat] " .. actor.name)
        button:Show()
    end

    for i = 1, 40 do
        local row = CreateFrame("Frame", nil, content)
        row:EnableMouse(true)
        dragWindow(row)
        local background = row:CreateTexture(nil, "BACKGROUND")
        background:SetAllPoints(row)
        background:SetTexture(0.55, 0.07, 0.08, 0.55)
        background:Hide()
        row.background = background
        local label = row:CreateFontString(nil, "ARTWORK")
        label:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
        label:SetJustifyH("LEFT")
        label:SetJustifyV("TOP")
        label:SetPoint("TOPLEFT", row, "TOPLEFT", 0, -1)
        label:SetPoint("TOPRIGHT", row, "TOPRIGHT", 0, -1)
        row.text = label
        row:SetScript("OnEnter", function(self)
            showTargetButton(self)
            local entry = self.entry
            if not entry or entry.kind ~= "MISDIRECTION_SUMMARY" or not entry.pullId or not GameTooltip then return end
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:AddLine("Урон напула по целям")
            local combat = RLHelper.displayedCombat or RLHelper.currentCombat
            for _, detail in ipairs(Journal.PullTargets(combat, entry.pullId)) do
                GameTooltip:AddDoubleLine(detail.target.name or "?", tostring(detail.amount))
            end
            if combat.droppedEvents then GameTooltip:AddLine("Данные неполные: достигнут лимит истории") end
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
        row:Hide()
        frame.v2Rows[i] = row
    end
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local offset = self:GetVerticalScroll() - delta * 60
        self:SetVerticalScroll(math.max(0, math.min(offset, self:GetVerticalScrollRange())))
        RLHelper:RenderJournalRows()
    end)
    scroll:SetScript("OnVerticalScroll", function() RLHelper:RenderJournalRows() end)
    frame.logText:Hide()
end

function RLHelper:LayoutMainFrame()
    local frame = self.mainFrame
    if not frame or not frame.logText or not frame.buttonContainer then
        return
    end

    frame.logText:ClearAllPoints()
    frame.logText:SetPoint("TOPLEFT", frame.journalFilters or frame.buttonContainer, "BOTTOMLEFT", 0, -8)

    local rightInset = -2
    if frame.bottomPanel then
        frame.logText:SetPoint("BOTTOMRIGHT", frame.bottomPanel, "TOPRIGHT", 0, 4)
    else
        frame.logText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", rightInset, 8)
    end

    if frame.journalFilters then
        local _, fontSize = frame.logText:GetFont()
        -- Journal rows can contain 24-pixel spell icons.
        local rowHeight = math.max(fontSize, 24) + frame.logText:GetSpacing()
        if frame.logText:GetHeight() >= rowHeight * 5 then
            frame.journalFilters:Show()
        else
            frame.journalFilters:Hide()
            frame.logText:SetPoint("TOPLEFT", frame.buttonContainer, "BOTTOMLEFT", 0, -8)
        end
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
        tile = true,
        tileSize = 32
    })

    -- Close button
    -- local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    -- closeButton:SetPoint("TOPRIGHT", -5, -5)

    -- Minimize button
    local minimizeButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    minimizeButton:SetSize(20, 25)
    minimizeButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -2, -2)
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
    buttonContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 2, -2)
    buttonContainer:SetPoint("TOPRIGHT", -2, -2)
    buttonContainer:SetHeight(25)

    -- Store buttons in frame for access
    frame.pullButtons = {}

    -- Buttons
    frame.raidCheckBtn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    frame.raidCheckBtn:SetSize(32, 25)
    frame.raidCheckBtn:SetPoint("LEFT", buttonContainer, "LEFT", 0, 0)
    frame.raidCheckBtn:SetText("РЧ")
    frame.raidCheckBtn:SetScript("OnClick", function()
        if type(DoReadyCheck) == "function" then
            DoReadyCheck()
        else
            print("ReadyCheck недоступен")
        end
    end)
    frame.pullButtons[1] = frame.raidCheckBtn

    local pull15Btn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    pull15Btn:SetSize(60, 25)
    pull15Btn:SetPoint("LEFT", frame.raidCheckBtn, "RIGHT", 4, 0)
    pull15Btn:SetText("Пул 15")
    frame.pullButtons[2] = pull15Btn
    pull15Btn:SetScript("OnClick", function()
        RLHelper:StartPullCountdown(15)
    end)

    local pull75Btn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    pull75Btn:SetSize(60, 25)
    pull75Btn:SetPoint("LEFT", pull15Btn, "RIGHT", 4, 0)
    pull75Btn:SetText("Пул 70")
    frame.pullButtons[3] = pull75Btn
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

    frame.resetBtn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    frame.resetBtn:SetSize(25, 25)
    frame.resetBtn:SetPoint("LEFT", pull75Btn, "RIGHT", 33, 0)
    frame.resetBtn:SetText("C")
    frame.resetBtn:Hide()
    frame.resetBtn:SetScript("OnClick", function()
        RLHelper:ResetCombatState()
        RLHelper.mainFrame.logText:Clear()
        self:SendMessage("RLHelper_CombatEnded")
    end)

    frame.combatListButton = CreateFrame("Button", nil, buttonContainer)
    frame.combatListButton:SetSize(18, 18)
    frame.combatListButton:SetPoint("LEFT", pull75Btn, "RIGHT", 4, 0)
    frame.combatListButton:SetNormalTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Up")
    frame.combatListButton:SetPushedTexture("Interface\\Buttons\\UI-GuildButton-PublicNote-Down")
    frame.combatListButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    frame.combatListButton:SetScript("OnClick", function()
        RLHelper:ToggleCombatListOverlay()
    end)

    frame.discordButton = CreateFrame("Button", nil, buttonContainer)
    frame.discordButton:SetSize(18, 18)
    frame.discordButton:SetPoint("LEFT", frame.combatListButton, "RIGHT", 4, 0)
    frame.discordButton:SetNormalTexture("Interface\\FriendsFrame\\UI-Toast-ChatInviteIcon")
    frame.discordButton:SetPushedTexture("Interface\\FriendsFrame\\UI-Toast-ChatInviteIcon")
    frame.discordButton:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    frame.discordButton:SetScript("OnClick", function()
        RLHelper:SendDiscordLink()
    end)
    frame.discordButton:Hide()

    frame.combatListClickCatcher = CreateFrame("Button", nil, UIParent)
    frame.combatListClickCatcher:SetAllPoints(UIParent)
    frame.combatListClickCatcher:SetFrameStrata("DIALOG")
    frame.combatListClickCatcher:EnableMouse(true)
    frame.combatListClickCatcher:SetScript("OnClick", function()
        RLHelper:HideCombatListOverlay()
    end)
    frame.combatListClickCatcher:Hide()

    frame.combatListFrame = CreateFrame("Frame", nil, UIParent)
    frame.combatListFrame:SetPoint("TOPLEFT", frame.combatListButton, "BOTTOMLEFT", 0, -2)
    frame.combatListFrame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame.combatListFrame:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 16,
        insets = {
            left = 4,
            right = 4,
            top = 4,
            bottom = 4
        }
    })
    frame.combatListFrame:Hide()

    -- Resize button
    local resizeButton = CreateFrame("Button", nil, frame)
    resizeButton:SetSize(16, 16)
    resizeButton:SetPoint("BOTTOMRIGHT", 0, 0)
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
    logText:SetInsertMode("BOTTOM")

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
    self:CreateJournalRows(frame)

    do
        local filters = CreateFrame("Frame", nil, frame)
        filters:SetPoint("TOPLEFT", buttonContainer, "BOTTOMLEFT", 0, -4)
        filters:SetSize(260, 22)
        frame.journalFilters = filters
        frame.journalFilterButtons = {}
        local previous
        for _, choice in ipairs({ { "ALL", "Все" }, { "ERRORS", "Ошибки" }, { "MISDIRECTION", "Напулы" } }) do
            local view, label = choice[1], choice[2]
            local button = CreateFrame("Button", nil, filters, "UIPanelButtonTemplate")
            button:SetSize(80, 22)
            button:SetText(label)
            if previous then button:SetPoint("LEFT", previous, "RIGHT", 4, 0)
            else button:SetPoint("LEFT", filters, "LEFT", 0, 0) end
            button:SetScript("OnClick", function() RLHelper:SetJournalView(view) end)
            frame.journalFilterButtons[view] = button
            if view == self.journalView then button:Disable() end
            previous = button
        end
        logText:SetHyperlinksEnabled(true)
        logText:SetScript("OnHyperlinkEnter", function(_, link)
            local pullId = tonumber(link:match("^rlhpull:(%d+)$"))
            if not pullId or not GameTooltip then return end
            GameTooltip:SetOwner(logText, "ANCHOR_CURSOR")
            GameTooltip:AddLine("Урон напула по целям")
            local combat = RLHelper.displayedCombat or RLHelper.currentCombat
            for _, row in ipairs(Journal.PullTargets(combat, pullId)) do
                GameTooltip:AddDoubleLine(row.target.name or "?", tostring(row.amount))
            end
            if combat.droppedEvents then GameTooltip:AddLine("Данные неполные: достигнут лимит истории") end
            GameTooltip:Show()
        end)
        logText:SetScript("OnHyperlinkLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    end

    -- Size changed handler
    frame:SetScript("OnSizeChanged", function()
        RLHelper:LayoutMainFrame()
        if RLHelper.mainFrame and RLHelper.mainFrame.v2Scroll then
            RLHelper:RefreshJournalRows(RLHelper.displayedCombat or RLHelper.currentCombat, true)
        end
    end)

    self.mainFrame = frame
    for _, button in ipairs({ frame.raidCheckBtn, pull15Btn, pull75Btn, frame.cancelBtn,
        frame.resetBtn }) do
        UITheme.RegisterButton(self, button)
    end
    for view, button in pairs(frame.journalFilterButtons or {}) do
        UITheme.RegisterButton(self, button, view)
    end
    self:RefreshDiscordButton()
    UITheme.Apply(self)
    self:SendMessage("RLHelper_MainFrameCreated", frame)
    frame:Hide()
end

function RLHelper:CreateMinimapButton()
    local button = CreateFrame("Button", "RLHelperMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetPoint("CENTER", Minimap, "BOTTOMLEFT", 18, 18)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

    local icon = button:CreateTexture(nil, "BACKGROUND")
    icon:SetSize(20, 20)
    icon:SetPoint("TOPLEFT", 7, -5)
    icon:SetTexture("Interface\\Icons\\spell_magic_polymorphchicken")
    icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "LeftButton" then
            self:SetMainFrameVisible(not self.mainFrame:IsShown())
        elseif mouseButton == "RightButton" then
            self:OpenOptionsPanel()
        end
    end)
    button:SetScript("OnEnter", function(frame)
        GameTooltip:SetOwner(frame, "ANCHOR_LEFT")
        GameTooltip:AddLine("RLHelper")
        GameTooltip:AddLine("Левый клик — показать/скрыть окно", 1, 1, 1)
        GameTooltip:AddLine("Правый клик — настройки", 1, 1, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
    self.minimapButton = button
end

function RLHelper:CreateOptionsPanel()
    if type(CreateFrame) ~= "function" or type(InterfaceOptions_AddCategory) ~= "function" then
        return
    end

    local panel = CreateFrame("Frame", "RLHelperOptionsPanel", UIParent)
    panel.name = "RL Helper"

    local scrollFrame = CreateFrame("ScrollFrame", "RLHelperOptionsPanelScrollFrame", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", panel, "TOPLEFT", 8, -12)
    scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -30, 12)

    local content = CreateFrame("Frame", "RLHelperOptionsPanelContent", scrollFrame)
    content:SetSize(440, 710)
    if scrollFrame.SetScrollChild then
        scrollFrame:SetScrollChild(content)
    end

    local title = content:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", content, "TOPLEFT", 12, 0)
    title:SetText("RL Helper")

    local themeLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    themeLabel:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -24)
    themeLabel:SetText("Тема оформления")
    local themeDropdown = CreateFrame("Frame", "RLHelperThemeDropdown", content, "UIDropDownMenuTemplate")
    themeDropdown:SetPoint("TOPLEFT", themeLabel, "BOTTOMLEFT", -16, -4)
    UIDropDownMenu_SetWidth(themeDropdown, 200)
    local themeLabels = { current = "Текущая (по умолчанию)", minimal = "Минимализм" }
    UIDropDownMenu_Initialize(themeDropdown, function()
        for _, theme in ipairs({ "current", "minimal" }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text = themeLabels[theme]
            info.checked = UITheme.GetName(RLHelper) == theme
            info.func = function()
                RLHelper:SetTheme(theme)
                UIDropDownMenu_SetText(themeDropdown, themeLabels[theme])
            end
            UIDropDownMenu_AddButton(info)
        end
    end)

    local cancelLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    cancelLabel:SetPoint("TOPLEFT", themeDropdown, "BOTTOMLEFT", 16, -12)
    cancelLabel:SetText("Текст сообщения отмены пула")

    local cancelEditBox = CreateFrame("EditBox", "RLHelperPullCancelEditBox", content, "InputBoxTemplate")
    cancelEditBox:SetSize(320, 24)
    if cancelEditBox.SetWidth then
        cancelEditBox:SetWidth(320)
    end
    cancelEditBox:SetPoint("TOPLEFT", cancelLabel, "BOTTOMLEFT", 0, -8)
    cancelEditBox:SetAutoFocus(false)
    cancelEditBox:SetScript("OnEnterPressed", function(self)
        RLHelper.db.profile.pullCancelMessage = self:GetText()
        self:ClearFocus()
    end)
    cancelEditBox:SetScript("OnEditFocusLost", function(self)
        RLHelper.db.profile.pullCancelMessage = self:GetText()
    end)

    local discordLabel = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    discordLabel:SetPoint("TOPLEFT", cancelEditBox, "BOTTOMLEFT", 0, -10)
    discordLabel:SetText("Ссылка Discord")

    local discordEditBox = CreateFrame("EditBox", "RLHelperDiscordLinkEditBox", content, "InputBoxTemplate")
    discordEditBox:SetSize(320, 24)
    if discordEditBox.SetWidth then
        discordEditBox:SetWidth(320)
    end
    discordEditBox:SetPoint("TOPLEFT", discordLabel, "BOTTOMLEFT", 0, -8)
    discordEditBox:SetAutoFocus(false)
    discordEditBox:SetScript("OnEnterPressed", function(self)
        RLHelper.db.profile.discordLink = self:GetText()
        RLHelper:RefreshDiscordButton()
        self:ClearFocus()
    end)
    discordEditBox:SetScript("OnEditFocusLost", function(self)
        RLHelper.db.profile.discordLink = self:GetText()
        RLHelper:RefreshDiscordButton()
    end)

    local displayOnlyInGroup = CreateFrame("CheckButton", "RLHelperDisplayOnlyInGroupCheckButton", content,
        "InterfaceOptionsCheckButtonTemplate")
    displayOnlyInGroup:SetPoint("TOPLEFT", discordEditBox, "BOTTOMLEFT", -4, -18)
    _G[displayOnlyInGroup:GetName() .. "Text"]:SetText("Показывать только в группе")
    displayOnlyInGroup:SetScript("OnClick", function(self)
        RLHelper.db.profile.displayOnlyInGroup = self:GetChecked() and true or false
        RLHelper:RefreshMainFrameVisibility()
    end)

    local bossOnlyHistory = CreateFrame("CheckButton", "RLHelperBossOnlyHistoryCheckButton", content,
        "InterfaceOptionsCheckButtonTemplate")
    bossOnlyHistory:SetPoint("TOPLEFT", displayOnlyInGroup, "BOTTOMLEFT", 0, -8)
    _G[bossOnlyHistory:GetName() .. "Text"]:SetText("Оставлять бои только с боссами")
    bossOnlyHistory:SetScript("OnClick", function(self)
        RLHelper.db.profile.bossOnlyHistory = self:GetChecked() and true or false
    end)

    local igor = CreateFrame("CheckButton", "RLHelperIgorCheckButton", content, "InterfaceOptionsCheckButtonTemplate")
    igor:SetPoint("TOPLEFT", bossOnlyHistory, "BOTTOMLEFT", 0, -8)
    _G[igor:GetName() .. "Text"]:SetText("Игорь")
    igor:SetScript("OnClick", function(self)
        RLHelper.db.profile.igor = self:GetChecked() and true or false
    end)

    local halionBurstTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    halionBurstTitle:SetPoint("TOPLEFT", igor, "BOTTOMLEFT", 0, -16)
    halionBurstTitle:SetText("РС Бурст")

    local halionBurstReset = CreateFrame("CheckButton", "RLHelperHalionBurstResetCheckButton", content,
        "InterfaceOptionsCheckButtonTemplate")
    halionBurstReset:SetPoint("TOPLEFT", halionBurstTitle, "BOTTOMLEFT", 0, -8)
    _G[halionBurstReset:GetName() .. "Text"]:SetText("Сброс ДПС под Геру")
    halionBurstReset:SetScript("OnClick", function(self)
        RLHelper.db.profile.halionBurstReset = self:GetChecked() and true or false
    end)

    local halionBurst = CreateFrame("CheckButton", "RLHelperHalionBurstCheckButton", content,
        "InterfaceOptionsCheckButtonTemplate")
    halionBurst:SetPoint("TOPLEFT", halionBurstReset, "BOTTOMLEFT", 0, -8)
    _G[halionBurst:GetName() .. "Text"]:SetText("Отсчет на выход для Ретрика")
    halionBurst:SetScript("OnClick", function(self)
        RLHelper.db.profile.halionBurstPull = self:GetChecked() and true or false
    end)

    local halionPhaseTwoEntryTimer = CreateFrame("CheckButton", "RLHelperHalionPhaseTwoEntryTimerCheckButton", content,
        "InterfaceOptionsCheckButtonTemplate")
    halionPhaseTwoEntryTimer:SetPoint("TOPLEFT", halionBurst, "BOTTOMLEFT", 0, -8)
    _G[halionPhaseTwoEntryTimer:GetName() .. "Text"]:SetText("Отсчет на вход после 2го метеорита")
    halionPhaseTwoEntryTimer:SetScript("OnClick", function(self)
        RLHelper.db.profile.halionPhaseTwoEntryTimer = self:GetChecked() and true or false
    end)

    local gpAwardTitle = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    gpAwardTitle:SetPoint("TOPLEFT", halionPhaseTwoEntryTimer, "BOTTOMLEFT", 0, -16)
    gpAwardTitle:SetText("Начисление GP")

    local gpAwardButtonsEnabled = CreateFrame("CheckButton", "RLHelperGPAwardButtonsEnabledCheckButton", content,
        "InterfaceOptionsCheckButtonTemplate")
    gpAwardButtonsEnabled:SetPoint("TOPLEFT", gpAwardTitle, "BOTTOMLEFT", 0, -8)
    _G[gpAwardButtonsEnabled:GetName() .. "Text"]:SetText("Отображать кнопки начисления GP")
    gpAwardButtonsEnabled:SetScript("OnClick", function(self)
        RLHelper.db.profile.gpAwardButtonsEnabled = self:GetChecked() and true or false
        RLHelper:RefreshGPAwardButtons()
    end)

    local gpReasonEditBoxes = {}
    local gpReasonAnchor = gpAwardButtonsEnabled
    local isFirstGpReason = true
    for _, amount in ipairs({ 100, 200, 250, 500, 1000 }) do
        local label = content:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        label:SetPoint("TOPLEFT", gpReasonAnchor, "BOTTOMLEFT", isFirstGpReason and 4 or 0, -10)
        if label.SetWidth then
            label:SetWidth(70)
        end
        label:SetText(amount .. " GP")

        local editBox = CreateFrame("EditBox", "RLHelperGPAwardReason" .. amount .. "EditBox", content, "InputBoxTemplate")
        editBox:SetSize(260, 24)
        if editBox.SetWidth then
            editBox:SetWidth(260)
        end
        editBox:SetPoint("LEFT", label, "LEFT", 78, 0)
        editBox:SetAutoFocus(false)
        editBox:SetScript("OnEnterPressed", function(self)
            RLHelper.db.profile.gpAwardReasons = RLHelper.db.profile.gpAwardReasons or {}
            RLHelper.db.profile.gpAwardReasons[amount] = self:GetText()
            RLHelper:RefreshGPAwardButtons()
            self:ClearFocus()
        end)
        editBox:SetScript("OnEditFocusLost", function(self)
            RLHelper.db.profile.gpAwardReasons = RLHelper.db.profile.gpAwardReasons or {}
            RLHelper.db.profile.gpAwardReasons[amount] = self:GetText()
            RLHelper:RefreshGPAwardButtons()
        end)

        gpReasonEditBoxes[amount] = editBox
        gpReasonAnchor = label
        isFirstGpReason = false
    end

    panel:SetScript("OnShow", function()
        UIDropDownMenu_SetText(themeDropdown, themeLabels[UITheme.GetName(RLHelper)])
        cancelEditBox:SetText(RLHelper.db.profile.pullCancelMessage or "")
        discordEditBox:SetText(RLHelper.db.profile.discordLink or "")
        displayOnlyInGroup:SetChecked(RLHelper.db.profile.displayOnlyInGroup)
        bossOnlyHistory:SetChecked(RLHelper.db.profile.bossOnlyHistory)
        igor:SetChecked(RLHelper.db.profile.igor)
        halionBurst:SetChecked(RLHelper:IsHalionBurstPullEnabled())
        halionBurstReset:SetChecked(RLHelper:IsHalionBurstResetEnabled())
        halionPhaseTwoEntryTimer:SetChecked(RLHelper:IsHalionPhaseTwoEntryTimerEnabled())
        gpAwardButtonsEnabled:SetChecked(RLHelper.db.profile.gpAwardButtonsEnabled)
        RLHelper.db.profile.gpAwardReasons = RLHelper.db.profile.gpAwardReasons or {}
        for amount, editBox in pairs(gpReasonEditBoxes) do
            editBox:SetText(RLHelper.db.profile.gpAwardReasons[amount] or DEFAULT_GP_AWARD_REASONS[amount] or "")
        end
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
    self.db.char.combatHistoryV2.combats = {}
    self:Print("История боев очищена")
end

function RLHelper:ShowCombatByIndex(index)
    if index < 1 or index > #self.combatHistory then
        self:Print("Неверный номер боя")
        return
    end

    local combat = self.combatHistory[index]
    self.followNextCombat = false
    self.selectedCombatKind = "history"
    self.selectedCombatIndex = index
    self:DisplayCombat(combat)
    self:RefreshCombatListOverlay()
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
        print("/rlh clear - очистить историю боев")
        print("/rlh demo - показать демонстрационный бой")
    elseif input == "debug" then
        self.db.profile.debug = not self.db.profile.debug
        print("Режим отладки: " .. (self.db.profile.debug and "включен" or "выключен"))
        if self.db.profile.debug then
            self:UpdateZoneContext("debug enabled")
        end
    elseif input == "config" or input == "options" then
        self:OpenOptionsPanel()
    elseif input == "clear" then
        self:ClearCombatHistory()
    elseif input == "demo" then
        self:DemoJournal()
        self:SetMainFrameVisible(true)
    end
end

-- Demo inputs use isolated tracker instances; only their normal handlers produce journal records.
function RLHelper:DemoJournal()
    local players = {
        tank = { guid = "demo-warrior", name = "Бочок", class = "WARRIOR" },
        hunter = { guid = "demo-hunter", name = "Стрелок", class = "HUNTER" },
        priest = { guid = "demo-priest", name = "Целитель", class = "PRIEST" },
        mage = { guid = "demo-mage", name = "Чародей", class = "MAGE" },
        druid = { guid = "demo-druid", name = "Лист", class = "DRUID" },
        shaman = { guid = "demo-shaman", name = "Гром", class = "SHAMAN" },
    }
    local combat = { startTime = time(), events = {}, firstEnemy = "Демонстрация" }
    local modules = {}
    for name, module in pairs(self.modules or {}) do
        if type(module.RunDemo) == "function" then modules[#modules + 1] = { name = name, module = module } end
    end
    table.sort(modules, function(a, b)
        if a.module.demoOrder ~= b.module.demoOrder then return a.module.demoOrder < b.module.demoOrder end
        return a.name < b.name
    end)
    for _, item in ipairs(modules) do
        local context = setmetatable({
            players = players, currentCombat = {}, currentInstanceId = 631, inCombat = true,
            groupMembers = {}, groupAssignments = { [players.tank.guid] = "MAINTANK" }, hasTankAssignments = true,
        }, { __index = self })
        for _, player in pairs(players) do context.groupMembers[player.guid] = player end
        context.GetNumRaidMembers = function() return 1 end
        context.GetRaidRosterInfo = function() return players.priest.name, 0, 5, 80, "Жрец", "PRIEST" end
        function context:Boss(id, name)
            return { guid = string.format("0xF130%06X000001", id), name = name }
        end
        function context:Event(module, subevent, source, target, spellId, fields)
            local event = {
                timestamp = combat.startTime + #combat.events,
                event = subevent, spellId = spellId,
                sourceGUID = source and source.guid, sourceName = source and source.name,
                sourceClass = source and source.class, sourceFlags = source and source.class and 0x514 or 0xa48,
                destGUID = target and target.guid, destName = target and target.name,
                destClass = target and target.class, destFlags = target and target.class and 0x514 or 0xa48,
            }
            for key, value in pairs(fields or {}) do event[key] = value end
            module:handleEvent(event)
        end
        local instance = setmetatable({ context = context }, { __index = function(_, key)
            -- Inherit behavior only, never live state (tables, timers or pending casts).
            if type(item.module[key]) == "function" then return item.module[key] end
        end })
        instance.log = function(entry)
            local record = Journal.Copy(entry)
            record.timestamp = combat.startTime + #combat.events
            record.seq = #combat.events + 1
            combat.events[#combat.events + 1] = record
        end
        instance:RunDemo(context)
    end
    combat.endTime = time()
    combat.startTime = combat.endTime - #combat.events
    for i, entry in ipairs(combat.events) do entry.timestamp = combat.startTime + i end
    self.selectedCombatKind, self.selectedCombatIndex = "demo", nil
    self:DisplayCombat(combat)
    self:SetJournalView("ALL")
    return combat
end

return RLHelper
