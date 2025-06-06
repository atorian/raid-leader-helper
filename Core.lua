local TestAddon = LibStub("AceAddon-3.0"):NewAddon("TestAddon", "AceConsole-3.0", "AceEvent-3.0")

-- Utility functions
local function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end

-- Constants
TestAddon.PLAYER_FLAGS = 0x511
TestAddon.ENEMY_FLAGS = 0xa48
TestAddon.MAX_RAID_SIZE = 25 -- Максимальный размер боевого рейда
TestAddon.DIVINE_INTERVENTION = 19752 -- ID баффа Божественного вмешательства

-- Default settings
local defaults = {
    profile = {
        enabled = true,
        debug = false,
        minimap = {
            hide = false
        },
        combatHistory = {} -- Add combat history storage
    }
}

-- Combat history structures
TestAddon.combatHistory = {} -- Array for combat history
TestAddon.currentCombat = {
    startTime = nil,
    messages = List.new() -- List for current combat messages
}
TestAddon.viewingCurrentCombat = true -- Initialize to true by default

TestAddon.activeEnemies = {}
TestAddon.activePlayers = {}
TestAddon.enemyEvents = {} -- Structure to track enemies and their events

function TestAddon:Debug(...)
    if self.db.profile.debug then
        self:Print(...)
    end
end

function TestAddon:OnInitialize()
    self:Print("RL Быдло: Начало инициализации аддона")

    self.activeEnemies = self.activeEnemies or {}
    self.activePlayers = self.activePlayers or {}
    self.enemyEvents = self.enemyEvents or {}

    self.db = LibStub("AceDB-3.0"):New("TestAddonDB", defaults, true)

    -- Load combat history from DB
    if self.db.profile.combatHistory then
        for _, combat in ipairs(self.db.profile.combatHistory) do
            local messages = List.new()
            for _, msg in ipairs(combat.messages) do
                messages:push_back(msg)
            end
            table.insert(self.combatHistory, {
                startTime = combat.startTime,
                endTime = combat.endTime,
                messages = messages
            })
        end
    end

    self:RegisterChatCommand("rlh", "HandleSlashCommand")

    self:CreateMainFrame()

    self.mainFrame:Show()

    self:Print("RL Быдло: Аддон включен")
end

function TestAddon:OnEnable()
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
    self:RegisterEvent("PLAYER_REGEN_ENABLED")
end

local function isEnemy(flags)
    return bit.band(flags or 0, TestAddon.ENEMY_FLAGS) > 0
end

local function isPlayer(flags)
    return flags == TestAddon.PLAYER_FLAGS
end

local LADY_KONTROL = 71289

function TestAddon:trackCombatants(event)
    if not event.destName or event.spellId == LADY_KONTROL then
        return
    end

    if self.activeEnemies[event.sourceGUID] == 0 or self.activeEnemies[event.destGUID] == 0 then
        self:Debug("Enemy is alrady dead", event.timestamp, self.activeEnemies[event.sourceGUID])
        return
    end

    if isEnemy(event.sourceFlags) then
        self:Debug("ENEMY 1 From:", event.sourceName, "To", event.destName, event.sourceGUID,
            self.activeEnemies[event.sourceGUID], event.event, event.timestamp)
        self.activeEnemies[event.sourceGUID] = true
        self.enemyEvents[event.sourceGUID] = {
            name = event.sourceName,
            event = event.event,
            spellId = event.spellId
        }
        return
    end
    if isEnemy(event.destFlags) then
        self:Debug("ENEMY 2 From:", event.sourceName, "To", event.destName, event.destGUID,
            self.activeEnemies[event.destGUID], event.event, event.timestamp)
        self.activeEnemies[event.destGUID] = true
        self.enemyEvents[event.destGUID] = {
            name = event.destName,
            event = event.event,
            spellId = event.spellId
        }
        return
    end
    if isPlayer(event.sourceFlags) then
        self:Debug("PLAYER 1:", event.sourceName, event.event)
        self.activePlayers[event.sourceGUID] = self.activePlayers[event.sourceGUID] or false
        return
    end
    if isPlayer(event.destFlags) then
        self:Debug("PLAYER 2:", event.destName, event.destFlags)
        self.activePlayers[event.destGUID] = self.activePlayers[event.destGUID] or false
        return
    end
end

function TestAddon:printActiveEnemies()
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
        self:Print("Еще есть живые враги:", table.concat(enemyNames, ", "))
    else
        self:Print("Врагов нет")
    end
end

function TestAddon:PLAYER_REGEN_ENABLED()
    -- Бой окончен
    self:Print("Regen Enabled")
    self:printActiveEnemies()
    -- TODO: workaround Lady Deathwhisper
end

function TestAddon:PLAYER_REGEN_DISABLED()
    self.inCombat = true
    wipe(self.activeEnemies)
    self:DisplayCombat(self.currentCombat)
    self:Debug("Combat started - player entered combat")
end

function TestAddon:checkCombatEndConditions()
    -- Check if all enemies are dead (value is 0)
    local allEnemiesDead = true
    for _, value in pairs(self.activeEnemies) do
        if value ~= 0 then
            allEnemiesDead = false
            break
        end
    end

    if allEnemiesDead then
        self:EndCombat("all_enemies_dead")
        return true
    end

    local hasAlivePlayers = false
    local hasPlayersWithoutDI = false

    for guid, hasDI in pairs(self.activePlayers) do
        hasAlivePlayers = true
        if not hasDI then
            hasPlayersWithoutDI = true
            break
        end
    end

    if not hasAlivePlayers then
        self:EndCombat("all_players_dead")
        return true
    end

    -- All remaining players have Divine Intervention
    if not hasPlayersWithoutDI then
        self:EndCombat("all_players_divine_intervention")
        return true
    end
    -- self:Print("not a combat")
    return false
end

function affectingGroup(event)
    return bit.band(event.sourceFlags or 0, TestAddon.PLAYER_FLAGS) > 0 or
               bit.band(event.destFlags or 0, TestAddon.PLAYER_FLAGS) > 0
end

-- TODO: Case: после Халиона кто-то может сагрить Трэш и это ресетнет лог.
-- можно запоминать бои с боссами
--
function TestAddon:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
    local eventData = blizzardEvent(...)

    if not affectingGroup(eventData) then
        return
    end

    if eventData.event == "UNIT_DIED" or eventData.event == "PARTY_KILL" then

        self:Debug(eventData.event, eventData.destName, eventData.destGUID, self.activeEnemies[eventData.destGUID])

        if self.activeEnemies[eventData.destGUID] then
            self.activeEnemies[eventData.destGUID] = 0
        else
            self.activePlayers[eventData.destGUID] = 0
        end

        self:Debug(eventData.event, self.activeEnemies[eventData.destGUID])

        return self.inCombat and self:checkCombatEndConditions()
    end

    self:trackCombatants(eventData)

    -- Track Divine Intervention
    if eventData.event == "SPELL_AURA_APPLIED" and eventData.spellId == self.DIVINE_INTERVENTION then
        self.activePlayers[eventData.destGUID] = true
    elseif eventData.event == "SPELL_AURA_REMOVED" and eventData.spellId == self.DIVINE_INTERVENTION then
        self.activePlayers[eventData.destGUID] = false
    end

    -- TODO: inCombat логику проверить, чтобы правильно отключить бой
    return self.inCombat and self:checkCombatEndConditions()
end

function TestAddon:OnCombatLogEvent(message)
    if not self.currentCombat.startTime then
        self.currentCombat.startTime = time()
    end

    -- self:Print("RL Быдло: ", message)

    self.currentCombat.messages:push_back(message)
    self.mainFrame.logText:AddMessage(message)
end

function TestAddon:EndCombat(reason)
    self.inCombat = false

    self:Debug("Should save combat?", self.currentCombat.startTime, self.currentCombat.messages:length())

    -- Save current combat to history if it has messages
    if self.currentCombat.startTime and self.currentCombat.messages:length() > 0 then
        -- Convert List to array for storage
        local messages = {}
        for msg in self.currentCombat.messages:iter() do
            table.insert(messages, msg)
        end

        local combat = {
            startTime = self.currentCombat.startTime,
            endTime = time(),
            messages = messages
        }

        table.insert(self.combatHistory, combat)
        self:Debug("Combat Saved to history")
    end

    -- Reset current combat
    self.currentCombat = {
        startTime = nil,
        messages = List.new()
    }

    wipe(self.activePlayers)
    wipe(self.enemyEvents) -- Clear enemy events when combat ends
    self:Debug("Combat ended", reason)
    self:SendMessage("TestAddon_CombatEnded")
end

local function sendSync(prefix, msg)
    msg = msg or ""
    local zoneType = select(2, IsInInstance())
    if zoneType == "pvp" or zoneType == "arena" then
        TestAddon:Print("RL Быдло: Отправлено в BATTLEGROUND")
        SendAddonMessage(prefix, msg, "BATTLEGROUND")
    elseif GetRealNumRaidMembers() > 0 then
        TestAddon:Print("RL Быдло: Отправлено в RAID")
        SendAddonMessage(prefix, msg, "RAID")
    elseif GetRealNumPartyMembers() > 0 then
        TestAddon:Print("RL Быдло: Отправлено в PARTY")
        SendAddonMessage(prefix, msg, "PARTY")
    end
end

function TestAddon:MinimizeWindow()
    if not self.isMinimized then
        self.savedSize = {
            width = self.mainFrame:GetWidth(),
            height = self.mainFrame:GetHeight()
        }
    end

    self.mainFrame:SetSize(240, 150)
    self.isMinimized = true
end

function TestAddon:RestoreWindow()
    self.mainFrame:SetSize(self.savedSize.width, self.savedSize.height)
    self.isMinimized = false
end

function TestAddon:UpdateCombatDropdown()
    local dropdown = self.mainFrame.combatDropdown
    UIDropDownMenu_Initialize(dropdown, dropdown.initialize)
end

function TestAddon:DisplayCombat(combat)
    self.mainFrame.logText:Clear()
    if combat and combat.messages then
        if type(combat.messages) == "table" and combat.messages.iter then
            for message in combat.messages:iter() do
                self.mainFrame.logText:AddMessage(message)
            end
        else
            for _, message in ipairs(combat.messages) do
                self.mainFrame.logText:AddMessage(message)
            end
        end
    end
end

function TestAddon:CreateMainFrame()
    local frame = CreateFrame("Frame", "TestAddonMainFrame", UIParent)
    frame:SetSize(300, 600)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetMinResize(240, 100)
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
    title:SetText("RL Быдло")

    -- Close button
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)

    -- Button container
    local buttonContainer = CreateFrame("Frame", nil, frame)
    buttonContainer:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
    buttonContainer:SetPoint("TOPRIGHT", -15, -16)
    buttonContainer:SetHeight(25)

    -- Buttons
    local pull15Btn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    pull15Btn:SetSize(60, 25)
    pull15Btn:SetPoint("LEFT", buttonContainer, "LEFT", 0, 0)
    pull15Btn:SetText("Пул 15")
    pull15Btn:SetScript("OnClick", function()
        DBM:CreatePizzaTimer(15, "Pull", true)
        TestAddon:MinimizeWindow()
        TestAddon.mainFrame.logText:Clear()
    end)

    local pull75Btn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    pull75Btn:SetSize(60, 25)
    pull75Btn:SetPoint("LEFT", pull15Btn, "RIGHT", 5, 0)
    pull75Btn:SetText("Пул 70")
    pull75Btn:SetScript("OnClick", function()
        DBM:CreatePizzaTimer(70, "Pull", true)
        TestAddon:MinimizeWindow()
        TestAddon.mainFrame.logText:Clear()
    end)

    local resetBtn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    resetBtn:SetSize(60, 25)
    resetBtn:SetPoint("LEFT", pull75Btn, "RIGHT", 5, 0)
    resetBtn:SetText("Ресет")
    resetBtn:SetScript("OnClick", function()
        TestAddon.activeEnemies = {}
        TestAddon.currentCombat = {
            startTime = nil,
            messages = List.new()
        }
        TestAddon.mainFrame.logText:Clear()
        self:SendMessage("TestAddon_CombatEnded")
    end)

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
    logText:SetPoint("TOPLEFT", buttonContainer, "BOTTOMLEFT", 0, -8)
    logText:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -32, 8)
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
    frame:SetScript("OnSizeChanged", function(self, width, height)
        local availableHeight = height - buttonContainer:GetHeight() - 48
        logText:SetHeight(availableHeight)
    end)

    self.mainFrame = frame
    frame:Hide()
end

function TestAddon:ShowCombatHistory()
    if #self.combatHistory == 0 then
        self:Print("История боев пуста")
        return
    end

    self:Print("История боев:")
    for index, combat in ipairs(self.combatHistory) do
        local startTime = date("%H:%M:%S", combat.startTime)
        local endTime = date("%H:%M:%S", combat.endTime)
        self:Print(string.format("%d. Бой (%s - %s)", index, startTime, endTime))
    end
end

function TestAddon:ClearCombatHistory()
    self.combatHistory = {}
    self:Print("История боев очищена")
end

function TestAddon:ShowCombatByIndex(index)
    if index < 1 or index > #self.combatHistory then
        self:Print(
            "Неверный номер боя. Используйте /rlh history для просмотра списка боев")
        return
    end

    local combat = self.combatHistory[index]
    self:DisplayCombat(combat)
    self.mainFrame:Show()
end

function TestAddon:HandleSlashCommand(input)
    if input == "" then
        -- Toggle main window
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
    elseif input == "hist" then
        self:ShowCombatHistory()
    elseif input == "combat" then
        self:printActiveEnemies()
    elseif input == "clear" then
        self:ClearCombatHistory()
    elseif input:match("^b%s+(%d+)$") then
        local index = tonumber(input:match("^b%s+(%d+)$"))
        self:ShowCombatByIndex(index)
    end
end

return TestAddon
