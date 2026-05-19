local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local GPAwardButtons = RLHelper:NewModule("GPAwardButtons", "AceEvent-3.0")

local BUTTONS = {
    { label = "100", amount = 100, reason = "Каспер" },
    { label = "200", amount = 200, reason = "Вомбат" },
    { label = "250", amount = 250, reason = "Бэтмен" },
    { label = "500", amount = 500, reason = "Капибара" },
    { label = "1к", amount = 1000, reason = "Banana" }
}

local MAX_UNDO_STACK_SIZE = 10

local function getTargetName()
    if type(UnitName) ~= "function" then
        return nil
    end

    return UnitName("target")
end

local function getEPGPSlashCommand()
    local slashCmdList = _G.SlashCmdList or SlashCmdList
    return slashCmdList and (slashCmdList["ACECONSOLE_EPGP"] or slashCmdList["EPGP"])
end

local function runGPCommand(targetName, reason, amount)
    local epgpSlash = getEPGPSlashCommand()
    if type(epgpSlash) ~= "function" then
        return false, "Slash-команда EPGP недоступна"
    end

    epgpSlash(string.format("gp %s %s %s", targetName, reason, amount))
    return true
end

function GPAwardButtons:OnInitialize()
    self:RegisterMessage("RLHelper_MainFrameCreated", "attachToMainFrame")
end

function GPAwardButtons:OnEnable()
    self:RegisterEvent("PLAYER_ENTERING_WORLD", "refreshVisibility")
    self:RegisterEvent("RAID_ROSTER_UPDATE", "refreshVisibility")
    self:RegisterEvent("PARTY_LEADER_CHANGED", "refreshVisibility")
    self:attachToMainFrame()
end

function GPAwardButtons:printError(message)
    RLHelper:Print("RL Быдло: " .. message)
end

function GPAwardButtons:refreshVisibility()
    if not self.footerFrame then
        return
    end

    self.footerFrame:Show()
    for _, button in ipairs(self.buttons or {}) do
        button:Show()
    end
    RLHelper:SetMainFrameBottomPanel(self.footerFrame)
end

function GPAwardButtons:RefreshUndoButtonState()
    if not self.undoButton then
        return
    end

    self.awardUndoStack = self.awardUndoStack or {}
    if #self.awardUndoStack > 0 then
        self.undoButton:Enable()
    else
        self.undoButton:Disable()
    end
end

function GPAwardButtons:PushUndoAward(targetName, reason, amount)
    self.awardUndoStack = self.awardUndoStack or {}
    table.insert(self.awardUndoStack, {
        targetName = targetName,
        reason = reason,
        amount = amount
    })

    while #self.awardUndoStack > MAX_UNDO_STACK_SIZE do
        table.remove(self.awardUndoStack, 1)
    end

    self:RefreshUndoButtonState()
end

function GPAwardButtons:AwardTargetGP(reason, amount)
    if type(UnitExists) ~= "function" or not UnitExists("target") then
        return false, "Нет выбранной цели"
    end

    if type(UnitIsPlayer) ~= "function" or not UnitIsPlayer("target") then
        return false, "Цель должна быть игроком"
    end

    local targetName = getTargetName()
    if type(targetName) ~= "string" or targetName == "" then
        return false, "Не удалось определить имя цели"
    end

    local ok, err = runGPCommand(targetName, reason, amount)
    if not ok then
        return false, err
    end

    self:PushUndoAward(targetName, reason, amount)
    return true, targetName
end

function GPAwardButtons:UndoLastGPAward()
    self.awardUndoStack = self.awardUndoStack or {}
    local award = self.awardUndoStack[#self.awardUndoStack]
    if not award then
        self:RefreshUndoButtonState()
        return false, "Нет начислений для отмены"
    end

    local ok, err = runGPCommand(award.targetName, award.reason, -award.amount)
    if not ok then
        return false, err
    end

    table.remove(self.awardUndoStack)
    self:RefreshUndoButtonState()
    return true, award.targetName
end

function GPAwardButtons:handleButtonClick(buttonInfo)
    local ok, result = self:AwardTargetGP(buttonInfo.reason, buttonInfo.amount)
    if not ok then
        self:printError(result)
    end
end

function GPAwardButtons:handleUndoButtonClick()
    local ok, result = self:UndoLastGPAward()
    if not ok then
        self:printError(result)
    end
end

function GPAwardButtons:createButton(parent, anchor, buttonInfo)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(40, 22)
    if anchor then
        button:SetPoint("LEFT", anchor, "RIGHT", 4, 0)
    else
        button:SetPoint("LEFT", parent, "LEFT", 0, 0)
    end
    button:SetText(buttonInfo.label)
    button:SetScript("OnClick", function()
        self:handleButtonClick(buttonInfo)
    end)

    return button
end

function GPAwardButtons:attachToMainFrame()
    if self.footerFrame or not RLHelper.mainFrame then
        return
    end

    local footer = CreateFrame("Frame", nil, RLHelper.mainFrame)
    footer:SetPoint("BOTTOMLEFT", RLHelper.mainFrame, "BOTTOMLEFT", 2, 2)
    footer:SetPoint("BOTTOMRIGHT", RLHelper.mainFrame, "BOTTOMRIGHT", 2, 2)
    footer:SetHeight(22)

    self.buttons = {}
    local anchor = nil
    for _, buttonInfo in ipairs(BUTTONS) do
        anchor = self:createButton(footer, anchor, buttonInfo)
        table.insert(self.buttons, anchor)
    end

    self.undoButton = self:createButton(footer, anchor, {
        label = "Отмена"
    })
    self.undoButton:SetSize(60, 22)
    self.undoButton:SetScript("OnClick", function()
        self:handleUndoButtonClick()
    end)

    self.footerFrame = footer
    RLHelper:SetMainFrameBottomPanel(footer)
    self:refreshVisibility()
    self:RefreshUndoButtonState()
end

return GPAwardButtons
