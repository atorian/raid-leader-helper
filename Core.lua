local RLHelper = LibStub("AceAddon-3.0"):NewAddon("RLHelper", "AceConsole-3.0", "AceEvent-3.0", "LibCompat-1.0")
local callbacks = LibStub("CallbackHandler-1.0"):New(RLHelper)
local IsGroupInCombat, InCombatLockdown = RLHelper.IsGroupInCombat, InCombatLockdown
local GetUnitIdFromGUID = RLHelper.GetUnitIdFromGUID

local COMBAT_END_CHECK_INTERVAL = 1
local COMBAT_END_GRACE = 3
local ENEMY_ACTIVITY_TIMEOUT = 6
local MODULE_ZONE_ANY = 0

local IGNORED_COMBAT_ENEMIES = {
    ["World Invisible Trigger"] = true
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
    firstEnemy = nil -- Name of the first enemy in combat
}
RLHelper.viewingCurrentCombat = true -- Initialize to true by default

RLHelper.activeEnemies = {}
RLHelper.activePlayers = {}
RLHelper.enemyEvents = {} -- Structure to track enemies and their events
RLHelper.lastCombatActivityAt = nil
RLHelper.combatEndRequestedAt = nil
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
                firstEnemy = combat.firstEnemy
            })
        end
    end

    self:RegisterChatCommand("rlh", "HandleSlashCommand")

    self:CreateMainFrame()

    self.mainFrame:Show()

    self:Debug("RL Быдло: Аддон включен")
end

function RLHelper:OnEnable()
    self:MinimizeWindow()
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self:RegisterEvent("PLAYER_ENTERING_WORLD")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
    self:RegisterEvent("ZONE_CHANGED_NEW_AREA")
    self:UpdateZoneContext()
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
        firstEnemy = nil
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
            firstEnemy = self.currentCombat.firstEnemy
        }
    end

    self:ResetCombatState()

    if combat then
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

function RLHelper:UpdateZoneContext()
    if type(GetInstanceInfo) ~= "function" then
        self.currentInstanceId = MODULE_ZONE_ANY
        return self.currentInstanceId
    end

    self.currentInstanceId = select(8, GetInstanceInfo()) or MODULE_ZONE_ANY
    return self.currentInstanceId
end

function RLHelper:PLAYER_ENTERING_WORLD()
    self:UpdateZoneContext()
end

function RLHelper:ZONE_CHANGED_NEW_AREA()
    self:UpdateZoneContext()
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
    local sourceFlags = event.sourceFlags
    local destFlags = event.destFlags

    -- Игнорируем события, где источник или цель под контролем
    if bit.band(sourceFlags, RLHelper.CONTROLLED_FLAGS) == RLHelper.CONTROLLED_FLAGS or
        bit.band(destFlags, RLHelper.CONTROLLED_FLAGS) == RLHelper.CONTROLLED_FLAGS then
        return false
    end

    return isPlayer(sourceFlags) or isPlayer(destFlags)
end

function RLHelper:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
    local eventData = blizzardEvent(...)
    self:DispatchCombatEvent(eventData)
    self:trackCombatants(eventData)

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

    -- Ограничиваем количество сохраненных боев до 10
    while #self.combatHistory > 10 do
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

function RLHelper:InvokeDBMPullCommand(duration)
    local pullValue = tonumber(duration) or 0
    local slashCmdList = _G.SlashCmdList or SlashCmdList
    local pullCommand = slashCmdList and slashCmdList["DEADLYBOSSMODSPULL"]

    if type(pullCommand) == "function" then
        pullCommand(tostring(pullValue))
        return true
    end

    return false
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
        RLHelper:InvokeDBMPullCommand(15)
        RLHelper:MinimizeWindow()
        RLHelper.mainFrame.logText:Clear()
        RLHelper:BeginPullCountdown(15)
    end)

    local pull75Btn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    pull75Btn:SetSize(60, 25)
    pull75Btn:SetPoint("LEFT", pull15Btn, "RIGHT", 4, 0)
    pull75Btn:SetText("Пул 70")
    frame.pullButtons[2] = pull75Btn
    pull75Btn:SetScript("OnClick", function()
        RLHelper:InvokeDBMPullCommand(70)
        RLHelper:MinimizeWindow()
        RLHelper.mainFrame.logText:Clear()
        RLHelper:BeginPullCountdown(70)
    end)

    -- Cancel button
    frame.cancelBtn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    frame.cancelBtn:SetSize(60, 25)
    frame.cancelBtn:SetPoint("LEFT", buttonContainer, "LEFT", 0, 0)
    frame.cancelBtn:SetText("Отмена")
    frame.cancelBtn:Hide() -- Initially hidden
    frame.cancelBtn:SetScript("OnClick", function()
        RLHelper:InvokeDBMPullCommand(0)
        RLHelper:ResetPullControls()
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

function RLHelper:HandleSlashCommand(input)
    if input == "" then
        if self.mainFrame:IsShown() then
            self.mainFrame:Hide()
        else
            self.mainFrame:Show()
        end
    elseif input == "help" then
        print("RL Быдло команды:")
        print("/rlh - показать/скрыть окно")
        print("/rlh help - показать помощь")
        print("/rlh debug - включить/выключить режим отладки")
        print("/rlh fill - включить/выключить режим отладки")
        print("/rlh hist - показать историю боев")
        print("/rlh clear - очистить историю боев")
        print("/rlh demo - show all messages")
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
    elseif input == "clear" then
        self:ClearCombatHistory()
    elseif input == "demo" then
        self:SendMessage("RLHelper_Demo")
    elseif input:match("^b%s+(%d+)$") then
        local index = tonumber(input:match("^b%s+(%d+)$"))
        self:ShowCombatByIndex(index)
    end
end

return RLHelper
