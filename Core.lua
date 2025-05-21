local TestAddon = LibStub("AceAddon-3.0"):NewAddon("TestAddon", "AceConsole-3.0", "AceEvent-3.0")

-- Utility functions
local function wipe(t)
    for k in pairs(t) do
        t[k] = nil
    end
    return t
end

local function count(tbl)
    local n = 0
    for _ in pairs(tbl or {}) do
        n = n + 1
    end
    return n
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
TestAddon.BOSS_FLAGS = 0x60a48
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
        penalties = {
            mistake = 200,
            wipe = 500,
            mainSpec = 500,
            offSpec = 250
        }
    }
}

function blizzardEvent(timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, ...)
    local args = {}
    args.timestamp = timestamp
    args.event = event
    args.sourceGUID = sourceGUID
    args.sourceName = sourceName
    args.sourceFlags = sourceFlags
    args.destGUID = destGUID
    args.destName = destName
    args.destFlags = destFlags

    if event == "SWING_DAMAGE" then
        args.amount, args.overkill, args.school, args.resisted, args.blocked, args.absorbed, args.critical, args.glancing, args.crushing =
            select(1, ...)
    elseif event == "SWING_MISSED" then
        args.spellName = ACTION_SWING
        args.missType = select(1, ...)
    elseif event:sub(1, 5) == "RANGE" then
        args.spellId, args.spellName, args.spellSchool = select(1, ...)
        if event == "RANGE_DAMAGE" then
            args.amount, args.overkill, args.school, args.resisted, args.blocked, args.absorbed, args.critical, args.glancing, args.crushing =
                select(4, ...)
        elseif event == "RANGE_MISSED" then
            args.missType = select(4, ...)
        end
    elseif event:sub(1, 5) == "SPELL" then
        args.spellId, args.spellName, args.spellSchool = select(1, ...)
        if event == "SPELL_DAMAGE" then
            args.amount, args.overkill, args.school, args.resisted, args.blocked, args.absorbed, args.critical, args.glancing, args.crushing =
                select(4, ...)
        elseif event == "SPELL_MISSED" then
            args.missType, args.amountMissed = select(4, ...)
        elseif event == "SPELL_HEAL" then
            args.amount, args.overheal, args.absorbed, args.critical = select(4, ...)
            args.school = args.spellSchool
        elseif event == "SPELL_ENERGIZE" then
            args.valueType = 2
            args.amount, args.powerType = select(4, ...)
        elseif event:sub(1, 14) == "SPELL_PERIODIC" then
            if event == "SPELL_PERIODIC_MISSED" then
                args.missType = select(4, ...)
            elseif event == "SPELL_PERIODIC_DAMAGE" then
                args.amount, args.overkill, args.school, args.resisted, args.blocked, args.absorbed, args.critical, args.glancing, args.crushing =
                    select(4, ...)
            elseif event == "SPELL_PERIODIC_HEAL" then
                args.amount, args.overheal, args.absorbed, args.critical = select(4, ...)
                args.school = args.spellSchool
            elseif event == "SPELL_PERIODIC_DRAIN" then
                args.amount, args.powerType, args.extraAmount = select(4, ...)
                args.valueType = 2
            elseif event == "SPELL_PERIODIC_LEECH" then
                args.amount, args.powerType, args.extraAmount = select(4, ...)
                args.valueType = 2
            elseif event == "SPELL_PERIODIC_ENERGIZE" then
                args.amount, args.powerType = select(4, ...)
                args.valueType = 2
            end
        elseif event == "SPELL_DRAIN" then
            args.amount, args.powerType, args.extraAmount = select(4, ...)
            args.valueType = 2
        elseif event == "SPELL_LEECH" then
            args.amount, args.powerType, args.extraAmount = select(4, ...)
            args.valueType = 2
        elseif event == "SPELL_INTERRUPT" then
            args.extraSpellId, args.extraSpellName, args.extraSpellSchool = select(4, ...)
        elseif event == "SPELL_EXTRA_ATTACKS" then
            args.amount = select(4, ...)
        elseif event == "SPELL_DISPEL_FAILED" then
            args.extraSpellId, args.extraSpellName, args.extraSpellSchool = select(4, ...)
        elseif event == "SPELL_AURA_DISPELLED" then
            args.extraSpellId, args.extraSpellName, args.extraSpellSchool = select(4, ...)
            args.auraType = select(7, ...)
        elseif event == "SPELL_AURA_STOLEN" then
            args.extraSpellId, args.extraSpellName, args.extraSpellSchool = select(4, ...)
            args.auraType = select(7, ...)
        elseif event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REMOVED" then
            args.auraType = select(4, ...)
        elseif event == "SPELL_AURA_APPLIED_DOSE" or event == "SPELL_AURA_REMOVED_DOSE" then
            args.auraType, args.amount = select(4, ...)
            args.sourceName = args.destName
            args.sourceGUID = args.destGUID
            args.sourceFlags = args.destFlags
        elseif event == "SPELL_CAST_FAILED" then
            args.missType = select(4, ...)
        end
    elseif event == "DAMAGE_SHIELD" then
        args.spellId, args.spellName, args.spellSchool = select(1, ...)
        args.amount, args.school, args.resisted, args.blocked, args.absorbed, args.critical, args.glancing, args.crushing =
            select(4, ...)
    elseif event == "DAMAGE_SHIELD_MISSED" then
        args.spellId, args.spellName, args.spellSchool = select(1, ...)
        args.missType = select(4, ...)
    elseif event == "ENCHANT_APPLIED" then
        args.spellName = select(1, ...)
        args.itemId, args.itemName = select(2, ...)
    elseif event == "ENCHANT_REMOVED" then
        args.spellName = select(1, ...)
        args.itemId, args.itemName = select(2, ...)
    elseif event == "UNIT_DIED" or event == "UNIT_DESTROYED" then
        args.sourceName = args.destName
        args.sourceGUID = args.destGUID
        args.sourceFlags = args.destFlags
    elseif event == "ENVIRONMENTAL_DAMAGE" then
        args.environmentalType = select(1, ...)
        args.amount, args.overkill, args.school, args.resisted, args.blocked, args.absorbed, args.critical, args.glancing, args.crushing =
            select(2, ...)
        args.spellName = _G["ACTION_" .. event .. "_" .. args.environmentalType]
        args.spellSchool = args.school
    elseif event == "DAMAGE_SPLIT" then
        args.spellId, args.spellName, args.spellSchool = select(1, ...)
        args.amount, args.school, args.resisted, args.blocked, args.absorbed, args.critical, args.glancing, args.crushing =
            select(4, ...)
    end
    return args
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

    self:RegisterChatCommand("rlh", "HandleSlashCommand")

    self:CreateMainFrame()

    self.mainFrame:Show()

    self:Print("RL Быдло: Аддон включен")
end

function TestAddon:OnEnable()

    self:RegisterEvent("COMBAT_LOG_EVENT_UNFILTERED")
    self:RegisterEvent("PLAYER_REGEN_DISABLED")
end

local function isPlayerTargeted(event)
    return bit.band(event.destFlags or 0, TestAddon.PLAYER_FLAGS) == TestAddon.PLAYER_FLAGS
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

function TestAddon:EndCombat(reason)
    self.inCombat = false
    wipe(self.activeEnemies)
    wipe(self.activePlayers)
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

function TestAddon:COMBAT_LOG_EVENT_UNFILTERED(event, ...)

    local eventData = blizzardEvent(...)

    -- if self.db.profile.debug then
    --     self:Print("RL Быдло: " .. eventData.event .. " - " .. eventData.sourceName .. " -> " .. eventData.destName, eventData.destFlags, eventData.destFlags == self.ENEMY_FLAGS)
    -- end

    self:trackCombatants(eventData)

    -- Track deaths
    if eventData.event == "UNIT_DIED" then
        if self.activeEnemies[eventData.sourceGUID] then
            self.activeEnemies[eventData.sourceGUID] = nil
        else
            self.activePlayers[eventData.sourceGUID] = nil
        end
    end

    -- Track Divine Intervention
    if eventData.event == "SPELL_AURA_APPLIED" and eventData.spellId == self.DIVINE_INTERVENTION then
        self.activePlayers[eventData.destGUID] = true
    elseif eventData.event == "SPELL_AURA_REMOVED" and eventData.spellId == self.DIVINE_INTERVENTION then
        self.activePlayers[eventData.destGUID] = false
    end

    if self:checkCombatEndConditions() then
        self:EndCombat("conditions_met")
    end
end

-- CombatLog class definition
local CombatLog = {}

function CombatLog:New()
    local instance = {
        entries = {},
        frames = {},
        startTime = GetTime(),
        entryCount = 0
    }
    setmetatable(instance, {
        __index = CombatLog
    })
    return instance
end

function CombatLog:AddEntry(player, message)
    self.entryCount = self.entryCount + 1
    local entryId = self.entryCount

    local entry = {
        id = entryId,
        player = player,
        message = message
    }

    table.insert(self.entries, entry)
end

function CombatLog:GetEntries()
    return self.entries
end

function CombatLog:Clear()
    for _, frame in ipairs(self.frames) do
        frame:Hide()
        frame:SetParent(nil)
    end

    wipe(self.entries)
    wipe(self.frames)
    self.startTime = GetTime()
    self.entryCount = 0
end

-- Make CombatLog available to TestAddon
TestAddon.CombatLog = CombatLog

function TestAddon:OnCombatLogEvent(player, message)
    if not self.inCombat then
        self.inCombat = true
        self.currentCombatLog = CombatLog:New()
    end

    self:Print("RL Быдло: " .. player .. ": " .. message)

    self.currentCombatLog:AddEntry(player, message)

    self:UpdateModuleDisplays()
end

local handlers = {}
local handlerI = 0
function TestAddon:withHandler(handler)
    handlerI = handlerI + 1
    handlers[handlerI] = handler
    self:Print("RL Быдло: добавлен обработчик #" .. handlerI)
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
    self.mainFrame:SetSize(270, 200)
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
    frame:SetSize(350, 600)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetMinResize(200, 150)
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
    buttonContainer:SetHeight(30) -- Увеличиваем высоту для двух строк кнопок

    -- Первая строка кнопок

    local pull15Btn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    pull15Btn:SetSize(60, 25)
    pull15Btn:SetPoint("TOPLEFT", buttonContainer, "TOPLEFT", 0, 0)
    pull15Btn:SetText("Пул 15")
    pull15Btn:SetScript("OnClick", function()
        DBM:CreatePizzaTimer(15, "Pull", true)
        TestAddon:MinimizeWindow()
    end)
    frame.pull15Btn = pull15Btn

    local pull75Btn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    pull75Btn:SetSize(60, 25)
    pull75Btn:SetPoint("LEFT", pull15Btn, "RIGHT", 5, 0)
    pull75Btn:SetText("Пул 70")
    pull75Btn:SetScript("OnClick", function()
        DBM:CreatePizzaTimer(70, "Pull", true)
        TestAddon:MinimizeWindow()
    end)
    frame.pull75Btn = pull75Btn

    local resetBtn = CreateFrame("Button", nil, buttonContainer, "UIPanelButtonTemplate")
    resetBtn:SetSize(60, 25)
    resetBtn:SetPoint("LEFT", pull75Btn, "RIGHT", 5, 0)
    resetBtn:SetText("Ресет")
    resetBtn:SetScript("OnClick", function()
        if self.currentCombatLog then
            self.currentCombatLog = CombatLog:New()
            self:UpdateModuleDisplays()
        end
    end)
    frame.resetBtn = resetBtn

    -- Scroll frame
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOP", buttonContainer, "BOTTOM", 0, -10)
    scrollFrame:SetPoint("BOTTOM", frame, "BOTTOM", 0, 10)
    scrollFrame:SetPoint("LEFT", frame, "LEFT", 12, 0)
    scrollFrame:SetPoint("RIGHT", frame, "RIGHT", -32, 0)
    scrollFrame:EnableMouseWheel(true)
    scrollFrame:SetScript("OnMouseWheel", function(self, delta)
        local current = self:GetVerticalScroll()
        local maxScroll = self:GetVerticalScrollRange()
        local step = 20
        local newScroll = current - delta * step

        -- Ограничиваем скролл границами
        newScroll = math.max(0, math.min(newScroll, maxScroll))
        self:SetVerticalScroll(newScroll)
    end)

    -- Scroll child
    local scrollChild = CreateFrame("Frame", nil, scrollFrame)
    scrollChild:SetHeight(1)
    scrollFrame:SetScrollChild(scrollChild)

    frame.logScrollFrame = scrollFrame
    frame.logScrollChild = scrollChild
    frame.buttonContainer = buttonContainer

    self.mainFrame = frame

    frame:SetScript("OnSizeChanged", function(self, width, height)
        if scrollChild then
            -- Принудительно обновляем размеры и позиции всех элементов
            self.logScrollFrame:SetWidth(width - 32)
            TestAddon:UpdateLogEntryLayout()
        end

        -- Проверяем видимость кнопок
        local buttons = {self.pull15Btn, self.pull75Btn, self.resetBtn}
        for _, button in ipairs(buttons) do
            if button then
                local buttonBottom = button:GetBottom()
                local frameBottom = self:GetBottom()
                if buttonBottom < frameBottom + 10 then
                    button:Hide()
                else
                    button:Show()
                end
            end
        end
    end)

    frame:Hide()
end

function TestAddon:UpdateLogEntryLayout()
    if not self.mainFrame then
        return
    end

    local scrollChild = self.mainFrame.logScrollChild
    if not scrollChild then
        return
    end

    local scrollFrame = self.mainFrame.logScrollFrame
    if not scrollFrame then
        return
    end

    local newWidth = scrollFrame:GetWidth()
    scrollChild:SetWidth(newWidth)

    local totalHeight = 0
    local previousEntry
    local children = {scrollChild:GetChildren()}

    -- Обновляем ширину и позиции всех элементов
    for _, entryFrame in ipairs(children) do
        if entryFrame.messageText then
            entryFrame:SetWidth(newWidth - 10)
            entryFrame.messageText:SetWidth(newWidth - 20)

            -- Переопределяем позицию фрейма
            if previousEntry then
                entryFrame:ClearAllPoints()
                entryFrame:SetPoint("TOPLEFT", previousEntry, "BOTTOMLEFT", 0, -2)
            else
                entryFrame:ClearAllPoints()
                entryFrame:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, -5)
            end

            totalHeight = totalHeight + entryFrame:GetHeight() + 2
            previousEntry = entryFrame
        end
    end

    -- Устанавливаем высоту контейнера
    scrollChild:SetHeight(math.max(totalHeight + 10, scrollFrame:GetHeight()))
end

function TestAddon:UpdateModuleDisplays()
    if not self.mainFrame then
        TestAddon:Print("ERROR: No mainFrame found")
        return
    end

    if not self.currentCombatLog then
        TestAddon:Print("ERROR: No currentCombatLog found")
        return
    end

    local scrollChild = self.mainFrame.logScrollChild
    if not scrollChild then
        TestAddon:Print("ERROR: No scrollChild found")
        return
    end

    local scrollFrame = self.mainFrame.logScrollFrame
    if not scrollFrame then
        TestAddon:Print("ERROR: No scrollFrame found")
        return
    end

    local children = {scrollChild:GetChildren()}
    for _, child in pairs(children) do
        child:Hide()
        child:SetParent(nil)
    end

    scrollChild:SetWidth(scrollFrame:GetWidth())

    local entries = self.currentCombatLog:GetEntries()
    local previousEntry
    local totalHeight = 0

    for i, entry in ipairs(entries) do
        local wrapperButton = self:CreateLogEntryFrame(entry)
        wrapperButton:SetParent(scrollChild)
        wrapperButton:SetWidth(scrollChild:GetWidth() - 10)

        if previousEntry then
            wrapperButton:SetPoint("TOPLEFT", previousEntry, "BOTTOMLEFT", 0, -2)
        else
            wrapperButton:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 5, -5)
        end

        wrapperButton:Show()
        previousEntry = wrapperButton
        totalHeight = totalHeight + wrapperButton:GetHeight() + 2
    end

    -- Устанавливаем высоту контейнера
    scrollChild:SetHeight(math.max(totalHeight + 10, scrollFrame:GetHeight()))

    -- Обновляем скролл
    scrollFrame:UpdateScrollChildRect()
    scrollFrame:SetVerticalScroll(0)
end

function TestAddon:CreateLogEntryFrame(entry)
    local entryFrame = CreateFrame("Button")
    entryFrame:SetSize(400, 20)
    entryFrame:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestLogTitleHighlight", "ADD")

    -- Create and position the message text
    local messageText = entryFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    messageText:SetPoint("LEFT", entryFrame, "LEFT", 5, 0)
    messageText:SetPoint("RIGHT", entryFrame, "RIGHT", -5, 0)
    messageText:SetJustifyH("LEFT")
    -- messageText:SetJustifyV("TOP")
    messageText:SetWordWrap(false)
    messageText:SetText(entry.message)

    -- Store references
    entryFrame.messageText = messageText
    entryFrame.playerName = entry.player

    return entryFrame
end

function TestAddon:OpenSettings()
    -- To be implemented
    -- print("Настройки временно недоступны")
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
        print("/rlh clear - очистить лог")
    elseif input == "debug" then
        self.db.profile.debug = not self.db.profile.debug
        print("Режим отладки: " .. (self.db.profile.debug and "включен" or "выключен"))
    elseif input == "clear" then
        if self.currentCombatLog then
            self.currentCombatLog:Clear()
            self:Print("Лог очищен")
        else
            self:Print("Нет активного лога")
        end
        self:UpdateModuleDisplays()
    end
end

function createRingBuffer(size)
    local buffer = {
        data = {},
        size = size or 5,
        index = 1,
        count = 0
    }

    function buffer:add(value)
        self.data[self.index] = value
        self.index = self.index % self.size + 1
        self.count = math.min(self.count + 1, self.size)
    end

    function buffer:getAll()
        local result = {}
        local start = (self.index - self.count - 1 + self.size) % self.size + 1
        for i = 1, self.count do
            local idx = (start + i - 1 - 1) % self.size + 1
            table.insert(result, self.data[idx])
        end
        return result
    end

    return buffer
end

return TestAddon
