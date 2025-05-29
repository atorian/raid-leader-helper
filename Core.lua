local TestAddon = LibStub("AceAddon-3.0"):NewAddon("TestAddon", "AceConsole-3.0", "AceEvent-3.0")
local List = List

-- Utility functions
local function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end

local function toString(val)
    if type(val) == "table" then
        local str = "{"
        for k, v in pairs(val) do
            str = str .. tostring(k) .. "=" .. toString(v) .. ","
        end
        return str .. "}"
    else
        return tostring(val)
    end
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
        }
    }
}

-- Frame pool management
local MAX_LOG_FRAMES = 30
local logFramePool = {}
local visibleLogFrames = {}

local function createLogFrame()
    local entryFrame = CreateFrame("Button")
    -- entryFrame:SetSize(400, 20)
    entryFrame:SetHeight(20)
    entryFrame:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")

    -- -- Add border and background
    -- entryFrame:SetBackdrop({
    --     bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
    --     edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    --     tile = true,
    --     tileSize = 32,
    --     edgeSize = 16,
    --     insets = {
    --         left = 4,
    --         right = 4,
    --         top = 4,
    --         bottom = 4
    --     }
    -- })
    -- entryFrame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
    -- entryFrame:SetBackdropColor(0, 0, 0, 0.5)

    -- Create and position the message text
    local messageText = entryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    messageText:SetPoint("LEFT", entryFrame, "LEFT", 4, 0)
    messageText:SetPoint("RIGHT", entryFrame, "RIGHT", -4, 0)
    messageText:SetJustifyH("LEFT")
    messageText:SetJustifyV("TOP")
    messageText:SetWordWrap(false)
    entryFrame.messageText = messageText

    return entryFrame
end

local function initializeLogFramePool()
    for i = 1, MAX_LOG_FRAMES do
        local frame = createLogFrame()
        frame:Hide()
        table.insert(logFramePool, frame)
    end
end

local function getLogFrame()
    local frame = table.remove(logFramePool)
    if frame then
        frame:Show()
        table.insert(visibleLogFrames, frame)
    end
    return frame
end

local function releaseLogFrame(frame)
    frame:Hide()
    frame:ClearAllPoints()
    frame.messageText:SetText("")

    -- Remove from visible frames
    for i, f in ipairs(visibleLogFrames) do
        if f == frame then
            table.remove(visibleLogFrames, i)
            break
        end
    end

    -- Add back to pool
    table.insert(logFramePool, frame)
end

local function releaseAllLogFrames()
    for _, frame in ipairs(visibleLogFrames) do
        releaseLogFrame(frame)
    end
end

-- Combat tracking
TestAddon.activeEnemies = {}
TestAddon.activePlayers = {} -- Now stores only players with Divine Intervention as guid = true

function TestAddon:OnInitialize()
    self:Print("RL Быдло: Начало инициализации аддона")

    -- Инициализируем таблицы для отслеживания
    self.activeEnemies = self.activeEnemies or {}
    self.activePlayers = self.activePlayers or {}

    self.db = LibStub("AceDB-3.0"):New("TestAddonDB", defaults, true)
    self.currentCombatLog = List.new()

    self:RegisterChatCommand("rlh", "HandleSlashCommand")

    initializeLogFramePool()

    self:CreateMainFrame()

    self.mainFrame:Show()

    self:Print("RL Быдло: Аддон включен")
end

function TestAddon:OnEnable()
    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
end

local function isPlayerTargeted(event)
    return bit.band(event.destFlags, COMBATLOG_OBJECT_TYPE_PLAYER) == COMBATLOG_OBJECT_TYPE_PLAYER
end

local function isEnemy(flags)
    return bit.band(flags or 0, TestAddon.ENEMY_FLAGS) == TestAddon.ENEMY_FLAGS
end

function TestAddon:trackCombatants(event)
    if isEnemy(event.sourceFlags) then
        self.activeEnemies[event.sourceGUID] = true
    else
        self.activePlayers[event.sourceGUID] = self.activePlayers[event.sourceGUID] or false
    end

    if isEnemy(event.destFlags) then
        self.activeEnemies[event.destGUID] = true
    else
        self.activePlayers[event.destGUID] = self.activePlayers[event.destGUID] or false
    end
end

function TestAddon:PLAYER_REGEN_DISABLED()
    self.inCombat = true
    if self.db.profile.debug then
        self:Print("Combat started - player entered combat")
    end
end

function TestAddon:checkCombatEndConditions()
    if not next(self.activeEnemies) then
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

    return false
end

-- TODO: Case: после Халиона кто-то может сагрить Трэш и это ресетнет лог.
-- можно запоминать бои с боссами
--
function TestAddon:COMBAT_LOG_EVENT_UNFILTERED(event, ...)

    local eventData = blizzardEvent(...)

    self:trackCombatants(eventData)

    if eventData.event == "UNIT_DIED" then
        if self.activeEnemies[eventData.sourceGUID] then
            self.activeEnemies[eventData.sourceGUID] = nil
        else
            self.activePlayers[eventData.sourceGUID] = nil
        end

        return self.inCombat and self:checkCombatEndConditions()
    end

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
    self:Print("RL Быдло: ", message)
    self.currentCombatLog:push_front(message)
    self.scrollBar:SetMinMaxValues(0, math.max(self.currentCombatLog:length() - 30, 30))
    self:UpdateModuleDisplays()
end

function TestAddon:EndCombat(reason)
    self.inCombat = false
    wipe(self.activeEnemies)
    wipe(self.activePlayers)
    self:Print("Combat ended", reason)
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
    if not self.mainFrame then
        return
    end

    -- Save current size if not already minimized
    if not self.isMinimized then
        self.savedSize = {
            width = self.mainFrame:GetWidth(),
            height = self.mainFrame:GetHeight()
        }
    end

    -- Set minimum size
    self.mainFrame:SetSize(240, 150)
    self.isMinimized = true
end

function TestAddon:RestoreWindow()
    if not self.mainFrame or not self.savedSize then
        return
    end

    self.mainFrame:SetSize(self.savedSize.width, self.savedSize.height)
    self.isMinimized = false
end

function TestAddon:CreateMainFrame()
    local frame = CreateFrame("Frame", "TestAddonMainFrame", UIParent)
    frame:SetSize(300, 600)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetMinResize(240, 150)
    frame:SetMaxResize(800, 1000)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

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
        TestAddon:UpdateModuleDisplays()
    end)

    -- Background
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

    -- Title
    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("BOTTOMLEFT", 15, 15)
    title:SetText("RL Быдло")

    -- Close button
    local closeButton = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    closeButton:SetPoint("TOPRIGHT", -5, -5)

    -- Создаем контейнер для кнопок
    local buttonContainer = CreateFrame("Frame", nil, frame)
    buttonContainer:SetPoint("TOPLEFT", frame, "TOPLEFT", 15, -15)
    buttonContainer:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -15, -15)
    buttonContainer:SetHeight(30)

    local pull15Btn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    pull15Btn:SetSize(60, 25)
    pull15Btn:SetPoint("TOPLEFT", buttonContainer, "TOPLEFT", 0, 0)
    pull15Btn:SetText("Пул 15")
    pull15Btn:SetScript("OnClick", function()
        DBM:CreatePizzaTimer(15, "Pull", true)
        TestAddon:MinimizeWindow()
        self.currentCombatLog = List:new()
        self:UpdateModuleDisplays()
    end)
    frame.pull15Btn = pull15Btn

    local pull75Btn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    pull75Btn:SetSize(60, 25)
    pull75Btn:SetPoint("LEFT", pull15Btn, "RIGHT", 5, 0)
    pull75Btn:SetText("Пул 70")
    pull75Btn:SetScript("OnClick", function()
        DBM:CreatePizzaTimer(70, "Pull", true)
        TestAddon:MinimizeWindow()
        self.currentCombatLog = List:new()
        self:UpdateModuleDisplays()
    end)
    frame.pull75Btn = pull75Btn

    local resetBtn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    resetBtn:SetSize(60, 25)
    resetBtn:SetPoint("LEFT", pull75Btn, "RIGHT", 5, 0)
    resetBtn:SetText("Ресет")
    resetBtn:SetScript("OnClick", function()
        if self.currentCombatLog then
            self.currentCombatLog = List:new()
            self:UpdateModuleDisplays()
        end
    end)
    frame.resetBtn = resetBtn

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", "TestAddonScrollFrame", frame)
    scrollFrame:SetPoint("TOP", buttonContainer, "BOTTOM", 0, -8)
    scrollFrame:SetPoint("BOTTOM", frame, "BOTTOM", 0, 8)
    scrollFrame:SetPoint("LEFT", frame, "LEFT", 12, 0)
    scrollFrame:SetPoint("RIGHT", frame, "RIGHT", -26, 0)
    scrollFrame:EnableMouseWheel(true)

    -- Create scroll bar using UIPanelScrollBarTemplate
    local scrollBar = CreateFrame("Slider", nil, scrollFrame, "UIPanelScrollBarTemplate")
    scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 0, -16)
    scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 0, 16)
    scrollBar:SetMinMaxValues(0, 30)
    scrollBar:SetValueStep(1)
    scrollBar:SetValue(0)
    scrollBar:SetWidth(16)
    scrollBar:SetScript("OnValueChanged", function(self, value)
        scrollFrame:SetVerticalScroll(value)
        TestAddon:UpdateModuleDisplays()
    end)

    self.scrollBar = scrollBar
    -- Add mouse wheel handling
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = scrollBar:GetValue()
        local step = scrollBar:GetValueStep()
        local newValue = current - delta * step
        scrollBar:SetValue(newValue)
    end)

    -- Scroll child
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetPoint("TOPLEFT", scrollFrame, "TOPLEFT", 0, 0)
    scrollChild:SetPoint("BOTTOMRIGHT", scrollFrame, "BOTTOMRIGHT", 0, 0)
    scrollFrame:SetScrollChild(scrollChild)

    frame.logScrollFrame = scrollFrame
    frame.logScrollChild = scrollChild
    frame.logScrollBar = scrollBar
    frame.buttonContainer = buttonContainer

    self.mainFrame = frame

    frame:SetScript("OnSizeChanged", function(self, width, height)
        TestAddon:UpdateModuleDisplays()
    end)

    frame:Hide()
end

function TestAddon:UpdateModuleDisplays()
    if not self.mainFrame or not self.currentCombatLog then
        self:Print("UpdateModuleDisplays: No mainFrame or currentCombatLog")
        return
    end

    local scrollChild = self.mainFrame.logScrollChild
    local scrollFrame = self.mainFrame.logScrollFrame
    local scrollBar = self.mainFrame.logScrollBar

    if not scrollChild or not scrollFrame or not scrollBar then
        self:Print("UpdateModuleDisplays: Missing required frames")
        return
    end

    local frameHeight = 22 -- Height of each log frame + spacing
    local maxVisibleFrames = 30 -- Always show all 30 frames

    local previousEntry
    local totalHeight = 0
    local frameCount = 0

    -- Calculate visible range
    local currentScroll = math.ceil(scrollFrame:GetVerticalScroll())
    TestAddon:Print("Current Scroll:", currentScroll)

    -- Get existing frames
    local existingFrames = {scrollChild:GetChildren()}
    local frameIndex = 1

    -- Display visible frames
    local index = 1
    for entry in self.currentCombatLog:iter() do
        if index >= currentScroll and frameCount < maxVisibleFrames then
            local frame
            if frameIndex <= #existingFrames then
                -- Reuse existing frame
                frame = existingFrames[frameIndex]
                frame.messageText:SetText(entry)
            else
                -- Create new frame if needed
                frame = getLogFrame()
                if frame then
                    frame:SetParent(scrollChild)
                    frame.messageText:SetText(entry)
                end
            end

            if frame then
                frame:SetWidth(scrollFrame:GetWidth() - 30) -- Account for scrollbar

                if previousEntry then
                    frame:SetPoint("TOPLEFT", previousEntry, "BOTTOMLEFT", 0, 0)
                    frame:SetPoint("TOPRIGHT", previousEntry, "BOTTOMRIGHT", 0, 0)
                else
                    frame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)
                    frame:SetPoint("TOPRIGHT", scrollChild, "TOPRIGHT", -30, 0)
                end

                frame:Show()
                previousEntry = frame
                frameCount = frameCount + 1
                totalHeight = totalHeight + frameHeight
                frameIndex = frameIndex + 1
            end
        end
        index = index + 1
    end

    -- Hide unused frames
    for i = frameIndex, #existingFrames do
        existingFrames[i]:Hide()
    end

    -- Set scroll child height
    scrollChild:SetHeight(math.max(totalHeight + 10, scrollFrame:GetHeight()))
    scrollChild:SetWidth(scrollFrame:GetWidth() - 30)

    -- Update scroll
    scrollFrame:UpdateScrollChildRect()
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
    elseif input == "fill" then
        for i = 1, 10 do
            self:OnCombatLogEvent(string.format(
                "Test message %d: |T%s:24:24:0:-2|t |T%s:24:24:0:-2|t |T%s:24:24:0:-2|t", i,
                "Interface\\Icons\\INV_Misc_QuestionMark", "Interface\\Icons\\INV_Misc_QuestionMark",
                "Interface\\Icons\\INV_Misc_QuestionMark"))
        end
    elseif input == "debug" then
        self.db.profile.debug = not self.db.profile.debug
        print("Режим отладки: " .. (self.db.profile.debug and "включен" or "выключен"))
    end
end

return TestAddon
