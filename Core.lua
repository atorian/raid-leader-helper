local TestAddon = LibStub("AceAddon-3.0"):NewAddon("TestAddon", "AceConsole-3.0", "AceEvent-3.0")

-- Utility functions
local function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end

-- Constants
TestAddon.MAX_RAID_SIZE = 25 -- Максимальный размер боевого рейда
TestAddon.DIVINE_INTERVENTION = 19752 -- ID баффа Божественного вмешательства

-- Group affiliation flags
TestAddon.GROUP_AFFILIATION_PLAYER = 0x1 -- Игрок
TestAddon.GROUP_AFFILIATION_PARTY = 0x2 -- Член группы
TestAddon.GROUP_AFFILIATION_RAID = 0x4 -- Член рейда
TestAddon.GROUP_AFFILIATION_ANY = 0x7 -- Принадлежность к любой группе (игрок/группа/рейд)

-- Enemy flags
TestAddon.ENEMY_FLAG_OUTSIDER = 0x8 -- Не игрок
TestAddon.ENEMY_FLAG_HOSTILE = 0x40 -- Враждебный
TestAddon.ENEMY_FLAG_NPC = 0x200 -- NPC
TestAddon.ENEMY_FLAG_NPC_TYPE = 0x800 -- Тип NPC
TestAddon.ENEMY_FLAG_CONTROLLED = 0x1000 -- Под контролем
TestAddon.ENEMY_FLAGS = 0xa48 -- Маска для проверки враждебных NPC (OUTSIDER | HOSTILE | NPC | NPC_TYPE)
TestAddon.CONTROLLED_FLAGS = 0x1248 -- Маска для проверки юнитов под контролем (OUTSIDER | CONTROLLED | NPC | NPC_TYPE)

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
TestAddon.combatHistory = {} -- Array for combat history
TestAddon.currentCombat = {
    startTime = nil,
    messages = {},
    firstEnemy = nil -- Name of the first enemy in combat
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

function TestAddon:isDebugging()
    return self.db.profile.debug
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
    return bit.band(flags or 0, TestAddon.GROUP_AFFILIATION_ANY) > 0
end

local LADY_KONTROL = 71289

function TestAddon:trackCombatants(event)
    -- todo: Бафы которые были наложены другими игроками, в прошлом рейде, например,
    -- спадая участвуют в эвентах с именами тех игроков.
    if not event.destName or event.spellId == LADY_KONTROL then
        return
    end

    if self.activeEnemies[event.sourceGUID] == 0 or self.activeEnemies[event.destGUID] == 0 then
        return
    end

    if isEnemy(event.sourceFlags) then
        -- self:Debug("ENEMY 1 From:", event.sourceName, "To", event.destName, event.sourceGUID,
        --     self.activeEnemies[event.sourceGUID], event.event, event.timestamp)
        self.activeEnemies[event.sourceGUID] = true
        self.enemyEvents[event.sourceGUID] = {
            name = event.sourceName,
            event = event.event,
            spellId = event.spellId
        }
        -- Save first enemy name if not set yet
        if not self.currentCombat.firstEnemy then
            self.currentCombat.firstEnemy = event.sourceName
        end
    end
    if isEnemy(event.destFlags) then
        -- self:Debug("ENEMY 2 From:", event.sourceName, event.spellName, event.destName,
        --     self.activeEnemies[event.destGUID], event.event, event.timestamp)
        self.activeEnemies[event.destGUID] = true
        self.enemyEvents[event.destGUID] = {
            name = event.destName,
            event = event.event,
            spellId = event.spellId
        }
        -- Save first enemy name if not set yet
        if not self.currentCombat.firstEnemy then
            self.currentCombat.firstEnemy = event.destName
        end
    end
    if isPlayer(event.sourceFlags) then
        -- self:Debug("PLAYER 1:", event.sourceName, event.event)
        self.activePlayers[event.sourceGUID] = self.activePlayers[event.sourceGUID] or false
    end
    if isPlayer(event.destFlags) then
        -- self:Debug("PLAYER 2:", event.destName, event.destFlags)
        self.activePlayers[event.destGUID] = self.activePlayers[event.destGUID] or false
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
    self:Debug("Regen Enabled")
    self:printActiveEnemies()
    -- TODO: workaround Lady Deathwhisper
    self.inCombat = false

    -- self:Debug("Should save combat?", self.currentCombat.startTime, #self.currentCombat.messages)

    if self.currentCombat.startTime and #self.currentCombat.messages > 0 then
        local combat = {
            startTime = self.currentCombat.startTime,
            endTime = time(),
            messages = self.currentCombat.messages,
            firstEnemy = self.currentCombat.firstEnemy
        }

        self:SaveCombatToProfile(combat, self.db.profile)
        self:Debug("Combat Saved to history")
    end

    -- Reset current combat
    self.currentCombat = {
        startTime = nil,
        messages = {},
        firstEnemy = nil
    }

    wipe(self.activePlayers)
    wipe(self.enemyEvents)
    self:SendMessage("TestAddon_CombatEnded")
end

function TestAddon:PLAYER_REGEN_DISABLED()
    self.inCombat = true
    -- wipe(self.activeEnemies)
    self:DisplayCombat(self.currentCombat)
    self:Debug("Combat started - player entered combat")
end

function TestAddon:checkCombatEndConditions()
    -- Check if all enemies are dead (value is 0)
    -- local allEnemiesDead = true
    local active = false

    for _, value in pairs(self.activeEnemies) do
        if value == true then
            active = true
            break
        end
    end

    if not active then
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
    local sourceFlags = event.sourceFlags
    local destFlags = event.destFlags

    -- Игнорируем события, где источник или цель под контролем
    if bit.band(sourceFlags, TestAddon.CONTROLLED_FLAGS) == TestAddon.CONTROLLED_FLAGS or
        bit.band(destFlags, TestAddon.CONTROLLED_FLAGS) == TestAddon.CONTROLLED_FLAGS then
        return false
    end

    return isPlayer(sourceFlags) or isPlayer(destFlags)
end

function TestAddon:COMBAT_LOG_EVENT_UNFILTERED(event, ...)
    local eventData = blizzardEvent(...)

    if not affectingGroup(eventData) then
        return
    end

    if eventData.event == "UNIT_DIED" or eventData.event == "PARTY_KILL" then
        if self.activeEnemies[eventData.destGUID] then
            self.activeEnemies[eventData.destGUID] = 0
        else
            self.activePlayers[eventData.destGUID] = 0
        end
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

    table.insert(self.currentCombat.messages, message)
    self.mainFrame.logText:AddMessage(message)
end

function TestAddon:SaveCombatToProfile(combat, profile)
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

function TestAddon:EndCombat(reason)
    self:Debug("Combat ended", reason)
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

function TestAddon:SaveAnchorPosition()
    local point, _, _, x, y = self.mainFrame:GetPoint()
    local width = self.mainFrame:GetWidth()
    local height = self.mainFrame:GetHeight()
    self.db.profile.savedPosition = {
        x = x,
        y = y, -- Сохраняем Y как есть
        width = width,
        height = height
    }
    self:Print("Позиция и размер сохранены")
end

function TestAddon:MinimizeWindow()
    self.mainFrame:ClearAllPoints()
    if self.db.profile.savedPosition then
        self.mainFrame:SetSize(self.db.profile.savedPosition.width, self.db.profile.savedPosition.height)

        self.mainFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", self.db.profile.savedPosition.x,
            self.db.profile.savedPosition.y)
    else
        self.mainFrame:SetSize(400, 150)
        local screenWidth = GetScreenWidth()
        local screenHeight = GetScreenHeight()
        self.mainFrame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", screenWidth - 420, -20)
    end
end

function TestAddon:UpdateCombatDropdown()
    self:Print("Updating dropdown list")

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
    self:Print("Dropdown list updated with " .. #list .. " items")
end

function TestAddon:DisplayCombat(combat)
    self.mainFrame.logText:Clear()
    if combat and combat.messages then
        for _, message in ipairs(combat.messages) do
            self.mainFrame.logText:AddMessage(message)
        end
    end
end

function TestAddon:CreateMainFrame()
    local frame = CreateFrame("Frame", "TestAddonMainFrame", UIParent)
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
    title:SetText("RL Быдло")

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
        TestAddon:MinimizeWindow()
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
        TestAddon:SaveAnchorPosition()
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
        DBM:CreatePizzaTimer(15, "Pull", true)
        TestAddon:MinimizeWindow()
        TestAddon.mainFrame.logText:Clear()
        -- Hide pull buttons and show cancel button
        for _, btn in ipairs(frame.pullButtons) do
            btn:Hide()
        end
        frame.cancelBtn:Show()
    end)

    local pull75Btn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    pull75Btn:SetSize(60, 25)
    pull75Btn:SetPoint("LEFT", pull15Btn, "RIGHT", 4, 0)
    pull75Btn:SetText("Пул 70")
    frame.pullButtons[2] = pull75Btn
    pull75Btn:SetScript("OnClick", function()
        DBM:CreatePizzaTimer(70, "Pull", true)
        TestAddon:MinimizeWindow()
        TestAddon.mainFrame.logText:Clear()
        -- Hide pull buttons and show cancel button
        for _, btn in ipairs(frame.pullButtons) do
            btn:Hide()
        end
        frame.cancelBtn:Show()
    end)

    -- Cancel button
    frame.cancelBtn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    frame.cancelBtn:SetSize(60, 25)
    frame.cancelBtn:SetPoint("LEFT", buttonContainer, "LEFT", 0, 0)
    frame.cancelBtn:SetText("Отмена")
    frame.cancelBtn:Hide() -- Initially hidden
    frame.cancelBtn:SetScript("OnClick", function()
        DBM:CreatePizzaTimer(0, "Pull", true)
        DBM.Bars:CancelBar("Pull")
        for _, btn in ipairs(frame.pullButtons) do
            btn:Show()
        end
        frame.cancelBtn:Hide()
    end)

    local resetBtn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    resetBtn:SetSize(25, 25)
    resetBtn:SetPoint("LEFT", pull75Btn, "RIGHT", 4, 0)
    resetBtn:SetText("C")
    resetBtn:SetScript("OnClick", function()
        TestAddon.activeEnemies = {}
        TestAddon.currentCombat = {
            startTime = nil,
            messages = {}
        }
        TestAddon.mainFrame.logText:Clear()
        self:SendMessage("TestAddon_CombatEnded")
    end)

    -- Create dropdown
    local dropdown = CreateFrame("Frame", "TestAddonCombatDropdown", buttonContainer, "UIDropDownMenuTemplate")
    dropdown:SetPoint("LEFT", resetBtn, "RIGHT", -8, -2)
    UIDropDownMenu_SetWidth(dropdown, 50)
    dropdown:Show()

    -- Function to initialize dropdown
    function dropdown.initialize(self, level)
        local info = UIDropDownMenu_CreateInfo()

        -- Current combat option
        info.text = "Текущий бой"
        info.value = "current"
        info.disabled = not TestAddon.currentCombat.startTime
        info.func = function()
            TestAddon:DisplayCombat(TestAddon.currentCombat)
            TestAddon.mainFrame:Show()
        end
        UIDropDownMenu_AddButton(info, level)

        for i, combat in ipairs(TestAddon.combatHistory) do
            local startTime = date("%H:%M:%S", combat.startTime)
            local endTime = date("%H:%M:%S", combat.endTime)
            local enemyInfo = combat.firstEnemy or ""
            info.text = string.format("%d. %s (%s - %s)", i, enemyInfo, startTime, endTime)
            info.value = tostring(i)
            info.disabled = nil
            info.func = function()
                TestAddon:ShowCombatByIndex(i)
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

function TestAddon:ClearCombatHistory()
    self.combatHistory = {}
    self.db.profile.combatHistory = {}
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
        self:SendMessage("TestAddon_Demo")
    elseif input:match("^b%s+(%d+)$") then
        local index = tonumber(input:match("^b%s+(%d+)$"))
        self:ShowCombatByIndex(index)
    end
end

return TestAddon
