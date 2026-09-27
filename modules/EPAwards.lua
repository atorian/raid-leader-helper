local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local EPAwards = RLHelper:NewModule("EPAwards", "AceEvent-3.0")
local BossIds = RLHelperBossIds
local REWARDS = {
    { key = "attendance", name = "Приход вовремя", defaultAmount = 1000, reason = "за приход" },
    { key = "icc", name = "ЦЛК", defaultAmount = 7000, reason = "за прохождение ЦЛК", instance = BossIds.INSTANCES.ICECROWN_CITADEL,
        bosses = { [BossIds.NPCS.THE_LICH_KING] = true } },
    { key = "rs", name = "РС", defaultAmount = 3000, reason = "за прохождение РС", instance = BossIds.INSTANCES.RUBY_SANCTUM,
        bosses = { [BossIds.NPCS.HALION] = true, [BossIds.NPCS.HALION_TWILIGHT] = true } },
    { key = "toc", name = "ИВК", defaultAmount = 2000, reason = "за прохождение ИВК",
        instance = BossIds.INSTANCES.TRIAL_OF_THE_CRUSADER,
        bosses = { [BossIds.NPCS.ANUBARAK] = true, [BossIds.NPCS.ANUBARAK_ALT_1] = true,
            [BossIds.NPCS.ANUBARAK_ALT_2] = true } }
}
EPAwards.receivesCombatEvents = true

local function getReward(key)
    for _, reward in ipairs(REWARDS) do
        if reward.key == key then return reward end
    end
end

function EPAwards:GetSettings()
    local profile = RLHelper.db.profile
    profile.epAwards = profile.epAwards or { rt = "19:00", amounts = {}, reminders = {} }
    return profile.epAwards
end

function EPAwards:SetRT(value)
    local h, m = value:match("^(%d%d):(%d%d)$")
    if not h or tonumber(h) >= 24 or tonumber(m) >= 60 then return false end
    self:GetSettings().rt = value
    local state = RLHelper.db.char.epAwards
    if state then
        local finish = date("*t", state.endsAt)
        finish.hour, finish.min, finish.sec, finish.isdst = tonumber(h), tonumber(m), 0, nil
        local nextRT = time(finish)
        if nextRT <= time() then
            nextRT = select(2, self:GetPeriod(time()))
        end
        state.endsAt = nextRT
    end
    return true
end

function EPAwards:GetAmount(key)
    local amount = self:GetSettings().amounts[key]
    if amount ~= nil then return amount end
    local reward = getReward(key)
    return reward and reward.defaultAmount or 0
end

function EPAwards:GetPeriod(now)
    local hour, minute = self:GetSettings().rt:match("^(%d%d):(%d%d)$")
    local day = date("*t", now)
    day.hour, day.min, day.sec, day.isdst = tonumber(hour), tonumber(minute), 0, nil
    local start = time(day)
    if start > now then
        day.day = day.day - 1
        start = time(day)
    end
    day = date("*t", start)
    day.day, day.isdst = day.day + 1, nil
    return start, time(day)
end

function EPAwards:GetState()
    local now = time()
    local state = RLHelper.db.char.epAwards
    -- Changing settings never clears awards from the current raid evening.
    if not state or now >= state.endsAt then
        local start, finish = self:GetPeriod(now)
        state = { startsAt = start, endsAt = finish, awards = {}, prompted = {} }
        RLHelper.db.char.epAwards = state
        for _, popup in pairs(self.popups or {}) do popup:Hide() end
    end
    return state
end

function EPAwards:IsRaidLeader()
    return GetNumRaidMembers() > 0 and IsRaidLeader()
end

function EPAwards:OnInitialize()
    self:RegisterMessage("RLHelper_MainFrameCreated", "AttachButton")
end

function EPAwards:OnEnable()
    self:AttachButton()
    if self.button then self.button:Show() end
    self.clock = self.clock or CreateFrame("Frame")
    local elapsed = 0
    self.clock:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed < 1 then return end
        elapsed = 0
        self:CheckTime()
    end)
end

function EPAwards:OnDisable()
    if self.clock then self.clock:SetScript("OnUpdate", nil) end
    if self.window then self.window:Hide() end
    for _, popup in pairs(self.popups or {}) do popup:Hide() end
    if self.button then self.button:Hide() end
end

function EPAwards:CheckTime()
    self:GetState()
    if self.window and self.window:IsShown() then self:RefreshWindow() end
    -- No catch-up reminders when logging in after RT.
    if date("%H:%M") == self:GetSettings().rt then self:Suggest("attendance") end
end

function EPAwards:Suggest(key)
    local state = self:GetState()
    if not self:IsRaidLeader() or self:GetAmount(key) <= 0 or
        self:GetSettings().reminders[key] == false or state.awards[key] or state.prompted[key] then return end
    state.prompted[key] = true
    self:ShowReminder(key)
end

function EPAwards:handleEvent(event)
    if event.event ~= "UNIT_DIED" or not event.destGUID then return end
    local npc = tonumber(event.destGUID:sub(9, 12), 16)
    for _, reward in ipairs(REWARDS) do
        if reward.bosses and reward.instance == RLHelper.currentInstanceId and reward.bosses[npc] then
            self:Suggest(reward.key)
        end
    end
end

function EPAwards:MassEPAward(_, names, reason, amount)
    local pending = self.pending
    if not pending or pending.reason ~= reason or pending.amount ~= amount or not next(names) then return end
    pending.record.status = "awarded"
    pending.record.at = time()
end

function EPAwards:Award(key)
    local reward = getReward(key)
    local state = self:GetState()
    local amount = self:GetAmount(key)
    if not reward or amount <= 0 then return false, "Укажите сумму ЕП в настройках." end
    if state.awards[key] then return false, "Это начисление уже выполнено или требует проверки в EPGP." end
    if not self:IsRaidLeader() then return false, "Начислять ЕП может лидер текущего рейда." end
    local epgp = LibStub("AceAddon-3.0"):GetAddon("EPGP", true)
    if not epgp or type(epgp.IncMassEPBy) ~= "function" or type(epgp.RegisterCallback) ~= "function" then
        return false, "EPGP недоступен."
    end
    local reason = "RLHelper: " .. reward.name
    if not epgp:CanIncEPBy(reason, amount) then
        return false, "EPGP не готов к начислению: проверьте права и загрузку списка гильдии."
    end
    if self.callbackSource ~= epgp then
        epgp.RegisterCallback(self, "MassEPAward")
        self.callbackSource = epgp
    end
    local record = { status = "pending", amount = amount, reason = reward.name, at = time() }
    state.awards[key] = record
    self.pending = { record = record, reason = reason, amount = amount }
    local ok = pcall(epgp.IncMassEPBy, epgp, reason, amount)
    self.pending = nil
    if not ok then
        -- An exception may follow partial writes. Never offer a blind retry.
        if record.status ~= "awarded" then record.status = "uncertain" end
        return false, "Ошибка EPGP. Проверьте журнал EPGP перед дальнейшими начислениями."
    end
    if record.status ~= "awarded" then
        -- Installed EPGP emits MassEPAward synchronously only for a nonempty award.
        state.awards[key] = nil
        return false, "EPGP не подтвердил начисление: нет подходящих получателей."
    end
    return true
end

function EPAwards:ClickAward(key)
    local ok, err = self:Award(key)
    if not ok then RLHelper:Print(err) end
    if self.popups and self.popups[key] and self:GetState().awards[key] then self.popups[key]:Hide() end
    if self.window then self:RefreshWindow() end
end

local function makeWindow(title, width, height)
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(width, height)
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    frame:SetFrameStrata("DIALOG")
    frame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        tile = true, tileSize = 32 })
    frame:SetMovable(true)
    frame:SetClampedToScreen(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    local heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    heading:SetPoint("TOPLEFT", 14, -14)
    heading:SetText(title)
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame:Hide()
    return frame
end

local function makeButton(parent, text, width, click)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(width, 24)
    button:SetText(text)
    button:SetScript("OnClick", click)
    RLHelper.UITheme.RegisterButton(RLHelper, button)
    return button
end

function EPAwards:ShowReminder(key)
    self.popups = self.popups or {}
    local popup = self.popups[key]
    if not popup then
        popup = makeWindow("Начисление ЕП", 370, 124)
        popup.message = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        popup.message:SetPoint("TOPLEFT", 14, -40)
        popup.message:SetWidth(340)
        popup.message:SetJustifyH("LEFT")
        local button = makeButton(popup, "Начислить", 110, function() self:ClickAward(key) end)
        button:SetPoint("BOTTOM", 0, 12)
        self.popups[key] = popup
    end
    popup.message:SetText("Время начислить " .. self:GetAmount(key) .. " ЕП " .. getReward(key).reason .. ".")
    popup:Show()
end

function EPAwards:RefreshWindow()
    local state = self:GetState()
    local visible = 0
    for _, reward in ipairs(REWARDS) do
        local row = self.window.rows[reward.key]
        if self:GetSettings().reminders[reward.key] == false then
            row.label:Hide()
            row.button:Hide()
        else
            row.label:Show()
            row.button:Show()
            row.label:ClearAllPoints()
            row.button:ClearAllPoints()
            row.label:SetPoint("TOPLEFT", 14, -68 - visible * 34)
            row.button:SetPoint("TOPRIGHT", -14, -61 - visible * 34)
            visible = visible + 1
        end
        local amount, award = self:GetAmount(reward.key), state.awards[reward.key]
        row.label:SetText(reward.name .. " — " .. (award and award.amount or amount) .. " ЕП")
        row.button:SetText(award and (award.status == "awarded" and "Начислено " .. date("%H:%M", award.at) or "Проверить EPGP") or "Начислить")
        if not award and amount > 0 and self:IsRaidLeader() then row.button:Enable() else row.button:Disable() end
        row.label:SetAlpha((amount > 0 or award) and 1 or 0.5)
    end
    self.window:SetHeight(75 + math.max(visible, 1) * 34)
    if visible == 0 then self.window.empty:Show() else self.window.empty:Hide() end
end

function EPAwards:ToggleWindow()
    if not self.window then
        local frame = makeWindow("Начисление ЕП", 430, 220)
        frame.rows = {}
        local help = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        help:SetPoint("TOPLEFT", 14, -38)
        help:SetText("Рейду и резерву EPGP. Отметки — до следующего РТ.")
        for _, reward in ipairs(REWARDS) do
            local key = reward.key
            local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
            label:SetWidth(230)
            label:SetJustifyH("LEFT")
            local button = makeButton(frame, "Начислить", 155, function() self:ClickAward(key) end)
            frame.rows[key] = { label = label, button = button }
        end
        frame.empty = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        frame.empty:SetPoint("TOPLEFT", 14, -68)
        frame.empty:SetText("Нет включённых начислений.")
        self.window = frame
    end
    if self.window:IsShown() then self.window:Hide() else self:RefreshWindow(); self.window:Show() end
end

function EPAwards:AttachButton()
    local main = RLHelper.mainFrame
    if self.button or not main then return end
    local button = CreateFrame("Button", nil, main.buttonContainer)
    button:SetSize(18, 18)
    button:SetPoint("LEFT", main.discordButton, "RIGHT", 4, 0)
    button:SetNormalTexture("Interface\\Icons\\INV_Misc_Coin_02")
    button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    button:SetScript("OnClick", function() self:ToggleWindow() end)
    button:SetScript("OnEnter", function()
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText("Начисление ЕП")
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
    self.button = button
end

function EPAwards:CreateSettings(parent, anchor)
    local panel = CreateFrame("Frame", "RLHelperEPAwardsSettings", parent)
    panel:SetSize(410, 270)
    panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -22)
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText("Начисление ЕП")
    local help = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 0, -24)
    help:SetText("Галочка — показывать начисление и напоминание. 0 ЕП — отключить.")
    local fields = {}
    local function input(key, labelText, y, read, save)
        local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
        label:SetPoint("TOPLEFT", 0, y)
        label:SetText(labelText)
        local edit = CreateFrame("EditBox", "RLHelperEPAward" .. key .. "EditBox", panel, "InputBoxTemplate")
        edit:SetSize(90, 24)
        edit:SetWidth(90)
        edit:SetPoint("TOPLEFT", 150, y + 5)
        edit:SetAutoFocus(false)
        edit:SetTextInsets(2, 4, 0, 0)
        local function refresh() edit:SetText(tostring(read())); edit:SetCursorPosition(0) end
        local function commit()
            save(edit:GetText())
            refresh()
        end
        edit:SetScript("OnEnterPressed", function() edit:ClearFocus() end)
        edit:SetScript("OnEditFocusLost", commit)
        edit:SetScript("OnEscapePressed", function() refresh(); edit:ClearFocus() end)
        refresh()
        table.insert(fields, refresh)
        return edit
    end
    input("rt", "Время РТ (местное)", -60, function() return self:GetSettings().rt end, function(value)
        if not self:SetRT(value) then
            RLHelper:Print("Введите время РТ в формате ЧЧ:ММ, например 19:00.")
        end
    end)
    for index, reward in ipairs(REWARDS) do
        local key = reward.key
        local edit = input(key, reward.name .. " (ЕП)", -98 - (index - 1) * 34,
            function() return self:GetAmount(key) end, function(value)
                local amount = tonumber(value)
                if amount and amount >= 0 and amount <= 99999 and amount == math.floor(amount) then
                    self:GetSettings().amounts[key] = amount
                    if self.popups and self.popups[key] then self.popups[key]:Hide() end
                else RLHelper:Print("Сумма ЕП должна быть целым числом от 0 до 99999.") end
            end)
        local check = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        check:SetPoint("LEFT", edit, "RIGHT", 8, 0)
        check:SetScript("OnClick", function()
            self:GetSettings().reminders[key] = check:GetChecked() and true or false
            if self.popups and self.popups[key] then self.popups[key]:Hide() end
            if self.window then self:RefreshWindow() end
        end)
        local function refresh() check:SetChecked(self:GetSettings().reminders[key] ~= false) end
        refresh()
        table.insert(fields, refresh)
    end
    panel:SetScript("OnShow", function() for _, refresh in ipairs(fields) do refresh() end end)
    self.options = panel
end

return EPAwards
