local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local EPAwards = RLHelper:NewModule("EPAwards", "AceEvent-3.0")
local BossIds = RLHelperBossIds
local DPSMeters = RLHelper:GetModule("DPSMeters")
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
-- Spec identifiers shared by the DPS sources and the bundled LibCompat.
local SPECS = {
    {71, "WARRIOR", "Воин: Армс"}, {72, "WARRIOR", "Воин: Фури"}, {73, "WARRIOR", "Воин: Защита"},
    {250, "DEATHKNIGHT", "ДК: Кровь"}, {251, "DEATHKNIGHT", "ДК: Лёд"}, {252, "DEATHKNIGHT", "ДК: Нечестивость"},
    {65, "PALADIN", "Паладин: Свет"}, {66, "PALADIN", "Паладин: Защита"}, {70, "PALADIN", "Паладин: Воздаяние"},
    {253, "HUNTER", "Охотник: Звери"}, {254, "HUNTER", "Охотник: Стрельба"}, {255, "HUNTER", "Охотник: Выживание"},
    {259, "ROGUE", "Разбойник: Ликвидация"}, {260, "ROGUE", "Разбойник: Бой"}, {261, "ROGUE", "Разбойник: Скрытность"},
    {256, "PRIEST", "Жрец: Послушание"}, {257, "PRIEST", "Жрец: Свет"}, {258, "PRIEST", "Жрец: Тьма"},
    {262, "SHAMAN", "Шаман: Стихии"}, {263, "SHAMAN", "Шаман: Совершенств."}, {264, "SHAMAN", "Шаман: Исцеление"},
    {62, "MAGE", "Маг: Тайная магия"}, {63, "MAGE", "Маг: Огонь"}, {64, "MAGE", "Маг: Лёд"},
    {265, "WARLOCK", "Чернокнижник: Колд."}, {266, "WARLOCK", "Чернокнижник: Демон."}, {267, "WARLOCK", "Чернокнижник: Разруш."},
    {102, "DRUID", "Друид: Баланс"}, {103, "DRUID", "Друид: Кошка"}, {104, "DRUID", "Друид: Медведь"}, {105, "DRUID", "Друид: Исцеление"}
}
local DEFAULT_THRESHOLDS = {
    [71] = 20000, [72] = 21000, [63] = 21000, [62] = 21000,
    [252] = 19000, [251] = 20000, [260] = 20000, [259] = 18000,
    [265] = 18000, [266] = 17000, [267] = 17000, [258] = 18000,
    [70] = 20000, [262] = 18000, [263] = 18000
}

local function adjustedThreshold(player, offset)
    return math.max(0, player.threshold + (offset or 0))
end

local SPEC_BY_ID = {}
for _, spec in ipairs(SPECS) do SPEC_BY_ID[spec[1]] = spec end

EPAwards.receivesCombatEvents = true

local function getReward(key)
    for _, reward in ipairs(REWARDS) do
        if reward.key == key then return reward end
    end
end

function EPAwards:GetSettings()
    local profile = RLHelper.db.profile
    profile.epAwards = profile.epAwards or { rt = "19:00", amounts = {}, reminders = {} }
    profile.epAwards.saurfangThresholds = profile.epAwards.saurfangThresholds or {}
    profile.epAwards.dpsSource = profile.epAwards.dpsSource or "Skada"
    return profile.epAwards
end

function EPAwards:GetThreshold(spec)
    local threshold = self:GetSettings().saurfangThresholds[spec]
    if threshold ~= nil then return threshold end
    return DEFAULT_THRESHOLDS[spec]
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
    if key == "saurfang" then return 500 end
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

function EPAwards:IsFeatureEnabled()
    return RLHelper.db and RLHelper.db.profile.gpAwardButtonsEnabled == true
end

function EPAwards:OnEnable()
    self:RefreshEnabledState()
end

function EPAwards:RefreshEnabledState()
    if not self:IsFeatureEnabled() then self:OnDisable(); return end
    if self.active then return end
    self.active = true
    self:StartDPSMeter()
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
    self.active = false
    DPSMeters:Stop()
    if self.saurfangWindow then self.saurfangWindow:Hide() end
    if self.clock then self.clock:SetScript("OnUpdate", nil) end
    if self.window then self.window:Hide() end
    for _, popup in pairs(self.popups or {}) do popup:Hide() end
    if self.button then self.button:Hide() end
end

function EPAwards:CheckTime()
    if not self:IsFeatureEnabled() then return end
    self:GetState()
    if self.window and self.window:IsShown() then self:RefreshWindow() end
    -- No catch-up reminders when logging in after RT.
    if date("%H:%M") == self:GetSettings().rt then self:Suggest("attendance") end
end

function EPAwards:Suggest(key)
    if not self:IsFeatureEnabled() then return end
    local state = self:GetState()
    if not self:IsRaidLeader() or self:GetAmount(key) <= 0 or
        self:GetSettings().reminders[key] == false or state.awards[key] or state.prompted[key] then return end
    state.prompted[key] = true
    self:ShowReminder(key)
end

function EPAwards:handleEvent(event)
    if not self:IsFeatureEnabled() then return end
    if event.event ~= "UNIT_DIED" or not event.destGUID then return end
    local npc = tonumber(event.destGUID:sub(9, 12), 16)
    if npc == BossIds.NPCS.DEATHBRINGER_SAURFANG and
        RLHelper.currentInstanceId == BossIds.INSTANCES.ICECROWN_CITADEL then
        DPSMeters:BossKilled(npc)
    end
    for _, reward in ipairs(REWARDS) do
        if reward.bosses and reward.instance == RLHelper.currentInstanceId and reward.bosses[npc] then
            self:Suggest(reward.key)
        end
    end
end

function EPAwards:StartDPSMeter()
    DPSMeters:Start(self:GetSettings().dpsSource, function(fight) self:DPSFightComplete(fight) end)
end

function EPAwards:SetDPSSource(source)
    if source ~= "Skada" and source ~= "Recount" then return end
    self:GetSettings().dpsSource = source
    if self.active then self:StartDPSMeter() end
end

-- Consume completed victories independently of the selected meter's data layout.
function EPAwards:DPSFightComplete(set)
    if not self:IsFeatureEnabled() or set.source ~= self:GetSettings().dpsSource or
        set.boss ~= BossIds.NPCS.DEATHBRINGER_SAURFANG then return end
    local saved = RLHelper.db.char.saurfangDPS
    if saved and (saved.source or "Skada") == set.source and
        saved.starttime == set.starttime and saved.endtime == set.endtime then return end
    local snapshot = { source = set.source, starttime = set.starttime, endtime = set.endtime, players = {}, unknown = 0 }
    for _, player in ipairs(set.players or {}) do
        local spec = SPEC_BY_ID[player.spec]
        local threshold = self:GetThreshold(player.spec)
        if not spec or spec[2] ~= player.class or type(player.dps) ~= "number" then
            snapshot.unknown = snapshot.unknown + 1
        elseif threshold and threshold > 0 then
            snapshot.players[#snapshot.players + 1] = {
                name = player.name, class = player.class, spec = player.spec,
                dps = player.dps, threshold = threshold
            }
        end
    end
    table.sort(snapshot.players, function(a, b) return a.dps > b.dps end)
    RLHelper.db.char.saurfangDPS = snapshot
    if self.saurfangWindow and self.saurfangWindow:IsShown() then self:ShowSaurfangWindow() end
end

function EPAwards:IndividualEPAward(_, name, reason, amount)
    local pending = self.pendingIndividual
    if pending and pending.name == name and pending.reason == reason and pending.amount == amount then
        pending.confirmed = true
    end
end

function EPAwards:AwardSaurfang(snapshot, selected, offset)
    if not self:IsFeatureEnabled() then return false, "Начисление GP и ЕП выключено в настройках." end
    if not snapshot or snapshot ~= RLHelper.db.char.saurfangDPS then return false, "Результат боя изменился. Откройте окно заново." end
    local amount, reason = self:GetAmount("saurfang"), "RLHelper: ДПС Саурфанг"
    if amount <= 0 then return false, "Укажите сумму ЕП за ДПС Саурфанг в настройках." end
    local epgp = LibStub("AceAddon-3.0"):GetAddon("EPGP", true)
    if not epgp or type(epgp.IncEPBy) ~= "function" or type(epgp.GetEPGP) ~= "function" or
        type(epgp.RegisterCallback) ~= "function" then return false, "EPGP недоступен." end
    if not epgp:CanIncEPBy(reason, amount) then
        return false, "EPGP не готов к начислению: проверьте права и загрузку списка гильдии."
    end
    local recipients, mains = {}, {}
    for _, player in ipairs(snapshot.players) do
        if selected[player.name] and player.dps >= adjustedThreshold(player, offset) - 100 then
            local ep, _, main = epgp:GetEPGP(player.name)
            if not ep then return false, "Игрок не найден в EPGP: " .. player.name end
            main = main or player.name
            if mains[main] then return false, "Выбраны персонажи одного основного игрока: " .. main end
            mains[main] = true
            recipients[#recipients + 1] = player
        end
    end
    if #recipients == 0 then return false, "Выберите игроков для начисления." end
    if self.individualCallbackSource ~= epgp then
        epgp.RegisterCallback(self, "EPAward", "IndividualEPAward")
        self.individualCallbackSource = epgp
    end
    local awarded = 0
    for _, player in ipairs(recipients) do
        local pending = { name = player.name, reason = reason, amount = amount }
        self.pendingIndividual = pending
        local ok = pcall(epgp.IncEPBy, epgp, player.name, reason, amount)
        self.pendingIndividual = nil
        if pending.confirmed then
            player.lastAward = { amount = amount, at = time() }
            selected[player.name] = false
            awarded = awarded + 1
        end
        if not ok or not pending.confirmed then
            return false, "Начислено: " .. awarded .. ". Проверьте журнал EPGP для " .. player.name .. " перед повтором."
        end
    end
    return true, "Начислено по " .. amount .. " ЕП. Игроков: " .. awarded .. "."
end

function EPAwards:MassEPAward(_, names, reason, amount)
    local pending = self.pending
    if not pending or pending.reason ~= reason or pending.amount ~= amount or not next(names) then return end
    pending.record.status = "awarded"
    pending.record.at = time()
end

function EPAwards:Award(key)
    if not self:IsFeatureEnabled() then return false, "Начисление GP и ЕП выключено в настройках." end
    local reward = getReward(key)
    local state = self:GetState()
    local amount = self:GetAmount(key)
    if not reward or amount <= 0 then return false, "Укажите сумму ЕП в настройках." end
    if GetNumRaidMembers() == 0 then return false, "Для начисления ЕП нужно находиться в рейде." end
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
    local previousAward = state.awards[key]
    state.awards[key] = record
    self.pending = { record = record, reason = reason, amount = amount }
    -- Installed EPGP applies its standby percentage inside this synchronous method.
    -- Keep its award list and main/alt deduplication, but use the full award for everyone.
    local isExtra = epgp.IsMemberInExtrasList
    epgp.IsMemberInExtrasList = function() return false end
    local ok = pcall(epgp.IncMassEPBy, epgp, reason, amount)
    epgp.IsMemberInExtrasList = isExtra
    self.pending = nil
    if not ok then
        -- An exception may follow partial writes; show the uncertain result to the RL.
        if record.status ~= "awarded" then record.status = "uncertain" end
        return false, "Ошибка EPGP. Проверьте журнал EPGP перед дальнейшими начислениями."
    end
    if record.status ~= "awarded" then
        -- Installed EPGP emits MassEPAward synchronously only for a nonempty award.
        state.awards[key] = previousAward
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
    if not self:IsFeatureEnabled() then return end
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
        local text = reward.name .. " — " .. amount .. " ЕП"
        if award then
            local status = award.status == "awarded" and
                "Последнее: " .. award.amount .. " ЕП в " .. date("%H:%M", award.at) or "Проверьте результат в EPGP"
            text = text .. "\n|cffaaaaaa" .. status .. "|r"
        end
        row.label:SetText(text)
        row.button:SetText("Начислить")
        row.button:Enable()
    end
    self.window:SetHeight(111 + math.max(visible, 1) * 34)
    if visible == 0 then self.window.empty:Show() else self.window.empty:Hide() end
end

function EPAwards:ToggleWindow()
    if not self:IsFeatureEnabled() then return end
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
        frame.saurfangButton = makeButton(frame, "ДПС Саурфанг", 155, function() self:ShowSaurfangWindow() end)
        frame.saurfangButton:SetPoint("BOTTOMRIGHT", -14, 10)
        self.window = frame
    end
    if self.window:IsShown() then self.window:Hide() else self:RefreshWindow(); self.window:Show() end
end

function EPAwards:ShowSaurfangWindow()
    if not self:IsFeatureEnabled() then return end
    if self.window then self.window:Hide() end
    local frame = self.saurfangWindow
    if not frame then
        frame = makeWindow("ДПС Саурфанг", 700, 474)
        frame.info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        frame.info:SetPoint("TOPLEFT", 14, -40)
        frame.info:SetWidth(670)
        frame.info:SetJustifyH("LEFT")
        for _, column in ipairs({ {14, "Имя игрока"}, {175, "Класс / спек"}, {390, "DPS"}, {480, "Планка"}, {580, "Выбран"} }) do
            local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("TOPLEFT", column[1], -118)
            label:SetText(column[2])
        end
        local scroll = CreateFrame("ScrollFrame", "RLHelperSaurfangScroll", frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 14, -142)
        scroll:SetPoint("BOTTOMRIGHT", -34, 76)
        local content = CreateFrame("Frame", nil, scroll)
        content:SetSize(645, 1)
        scroll:SetScrollChild(content)
        frame.content, frame.scroll, frame.rows = content, scroll, {}
        frame.result = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        frame.result:SetPoint("BOTTOMLEFT", 14, 44)
        frame.result:SetWidth(670)
        frame.result:SetJustifyH("LEFT")
        frame.awardButton = makeButton(frame, "Начислить", 140, function()
            local _, message = self:AwardSaurfang(frame.snapshot, frame.selected, frame.offset)
            frame.result:SetText(message)
            for _, row in ipairs(frame.rows) do
                if row.player then row.check:SetChecked(frame.selected[row.player.name] == true) end
            end
        end)
        frame.awardButton:SetPoint("BOTTOM", 0, 12)
        frame.minusButton = makeButton(frame, "-", 28, function() self:AdjustSaurfangThreshold(-500) end)
        frame.minusButton:SetPoint("TOPLEFT", 14, -80)
        frame.plusButton = makeButton(frame, "+", 28, function() self:AdjustSaurfangThreshold(500) end)
        frame.plusButton:SetPoint("LEFT", frame.minusButton, "RIGHT", 6, 0)
        frame.adjustment = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        frame.adjustment:SetPoint("LEFT", frame.plusButton, "RIGHT", 10, 0)
        self.saurfangWindow = frame
    end
    frame.snapshot, frame.selected, frame.offset = RLHelper.db.char.saurfangDPS, {}, 0
    self:RefreshSaurfangWindow()
    frame:Show()
end

function EPAwards:AdjustSaurfangThreshold(delta)
    local frame = self.saurfangWindow
    frame.offset = frame.offset + delta
    self:RefreshSaurfangWindow()
end

function EPAwards:RefreshSaurfangWindow()
    local frame = self.saurfangWindow
    local snapshot = frame.snapshot
    frame.adjustment:SetText(string.format("Поправка к планкам: %+d DPS (шаг 500)", frame.offset))
    frame.result:SetText("")
    for _, row in ipairs(frame.rows) do row:Hide(); row.player = nil end
    local count, previouslyAwarded = 0, 0
    if snapshot then
        for _, player in ipairs(snapshot.players) do
            local threshold = adjustedThreshold(player, frame.offset)
            if player.dps >= threshold - 100 then
                count = count + 1
                if player.lastAward then previouslyAwarded = previouslyAwarded + 1 end
                local row = frame.rows[count]
                if not row then
                    row = CreateFrame("Frame", nil, frame.content)
                    row:SetSize(645, 26)
                    row:SetPoint("TOPLEFT", 0, -(count - 1) * 26)
                    row.cells = {}
                    for _, x in ipairs({0, 161, 376, 466}) do
                        local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                        label:SetPoint("LEFT", x, 0)
                        label:SetWidth(x == 161 and 205 or x == 0 and 155 or 85)
                        label:SetJustifyH("LEFT")
                        row.cells[#row.cells + 1] = label
                    end
                    row.check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
                    row.check:SetSize(24, 24)
                    row.check:SetPoint("LEFT", 580, 0)
                    row.check:SetScript("OnClick", function(check)
                        frame.selected[row.player.name] = check:GetChecked() and true or false
                    end)
                    frame.rows[count] = row
                end
                row.player = player
                row.cells[1]:SetText(player.name)
                row.cells[2]:SetText(SPEC_BY_ID[player.spec][3])
                row.cells[3]:SetText(string.format("%.1f", player.dps))
                row.cells[4]:SetText(tostring(threshold))
                if frame.selected[player.name] == nil then frame.selected[player.name] = true end
                row.check:SetChecked(frame.selected[player.name])
                row:Show()
            end
        end
        frame.info:SetText("Источник: " .. (snapshot.source or "Skada") .. ". Убийство: " .. date("%d.%m %H:%M", snapshot.endtime) .. ". По " .. self:GetAmount("saurfang") ..
            " ЕП. Допуск: 100 DPS ниже планки.\nПодходят: " .. count .. ". Без данных о спеке/DPS: " .. snapshot.unknown .. ".")
    else
        frame.info:SetText("Нет сохранённого результата. Источник: " .. self:GetSettings().dpsSource ..
            ". Нужны загруженный метр и убийство Саурфанга с заданными планками.")
    end
    if previouslyAwarded > 0 then
        frame.result:SetText("Ранее начислено игрокам из этого списка: " .. previouslyAwarded .. ".")
    end
    frame.content:SetHeight(math.max(1, count * 26))
    frame.scroll:SetVerticalScroll(0)
    if count > 0 then frame.awardButton:Enable() else frame.awardButton:Disable() end
end

function EPAwards:AttachButton()
    if not self:IsFeatureEnabled() then return end
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
    panel:SetSize(410, 398 + #SPECS * 34)
    panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -22)
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText("Начисление ЕП")
    local help = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 0, -24)
    help:SetText("Галочка — показывать начисление и напоминание. 0 ЕП — отключить.")
    local fields = {}
    local function input(key, labelText, y, read, save)
        local label = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
        label:SetWidth(145)
        label:SetJustifyH("LEFT")
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
    input("saurfang", "ДПС Саурфанг (ЕП)", -234, function() return self:GetAmount("saurfang") end, function(value)
        local amount = tonumber(value)
        if amount and amount >= 0 and amount <= 99999 and amount == math.floor(amount) then
            self:GetSettings().amounts.saurfang = amount
        else RLHelper:Print("Сумма ЕП должна быть целым числом от 0 до 99999.") end
    end)
    local sourceLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    sourceLabel:SetPoint("TOPLEFT", 0, -272)
    sourceLabel:SetText("Источник DPS")
    local sourceDropdown = CreateFrame("Frame", "RLHelperDPSSourceDropdown", panel, "UIDropDownMenuTemplate")
    sourceDropdown:SetPoint("TOPLEFT", 134, -262)
    UIDropDownMenu_SetWidth(sourceDropdown, 180)
    local function refreshSource()
        local source = self:GetSettings().dpsSource
        UIDropDownMenu_SetText(sourceDropdown, source .. (DPSMeters:IsAvailable(source) and "" or " (не загружен)"))
    end
    UIDropDownMenu_Initialize(sourceDropdown, function()
        for _, source in ipairs({ "Skada", "Recount" }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.value = source, source
            info.checked = self:GetSettings().dpsSource == source
            info.func = function() self:SetDPSSource(source); refreshSource() end
            UIDropDownMenu_AddButton(info)
        end
    end)
    refreshSource()
    table.insert(fields, refreshSource)
    local thresholdsTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    thresholdsTitle:SetPoint("TOPLEFT", 0, -328)
    thresholdsTitle:SetText("Планки ДПС — Саурфанг (по спекам)")
    local thresholdsHelp = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    thresholdsHelp:SetPoint("TOPLEFT", 0, -352)
    thresholdsHelp:SetText("Пусто или 0 — не учитывать. DPS — по выбранному метру после победы.")
    for index, spec in ipairs(SPECS) do
        local id = spec[1]
        input("Spec" .. id, spec[3], -386 - (index - 1) * 34,
            function() return self:GetThreshold(id) or "" end,
            function(value)
                local threshold = tonumber(value)
                if not value:find("%S") or threshold == 0 then
                    self:GetSettings().saurfangThresholds[id] = 0
                elseif threshold and threshold > 0 and threshold <= 999999 and threshold == math.floor(threshold) then
                    self:GetSettings().saurfangThresholds[id] = threshold
                else RLHelper:Print("Планка DPS должна быть целым числом от 0 до 999999.") end
            end)
    end
    panel:SetScript("OnShow", function() for _, refresh in ipairs(fields) do refresh() end end)
    self.options = panel
end

return EPAwards
