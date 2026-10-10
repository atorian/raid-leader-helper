local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local EPAwards = RLHelper:NewModule("EPAwards", "AceEvent-3.0")
local BossIds = RLHelperBossIds
local SAURFANG = BossIds.NPCS.DEATHBRINGER_SAURFANG
local PUTRICIDE = BossIds.NPCS.PROFESSOR_PUTRICIDE
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

local function oozeResult(snapshot, player)
    local total = player.oozeTotal
    if total == nil then
        -- Older saved fights contain per-spawn damage, but no gas target counts.
        total = 0
        for _, amount in pairs(player.oozeDamage or {}) do total = total + amount end
    end
    return total, math.max(0, snapshot.oozeCount * snapshot.oozeThreshold - 100000 * (player.gasTargets or 0))
end

local function qualifies(snapshot, player, offset)
    if snapshot.mode == "ooze" then
        local total, threshold = oozeResult(snapshot, player)
        return snapshot.oozeCount > 0 and snapshot.oozeThreshold > 0 and total >= threshold
    end
    return player.dps >= adjustedThreshold(player, offset) - 100
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
    if not profile.epAwards.dpsBosses then
        local thresholds = profile.epAwards.saurfangThresholds or {}
        for spec, value in pairs(DEFAULT_THRESHOLDS) do
            if thresholds[spec] == nil then thresholds[spec] = value end
        end
        profile.epAwards.dpsBosses = { [SAURFANG] = thresholds }
        profile.epAwards.saurfangThresholds = nil
    end
    profile.epAwards.dpsSource = profile.epAwards.dpsSource or "Details"
    return profile.epAwards
end

function EPAwards:IsOozeMode(boss)
    return boss == PUTRICIDE and self:GetSettings().putricideMode == "ooze"
end

function EPAwards:GetOozeThreshold()
    local value = self:GetSettings().putricideOozeDamage
    return value == nil and 100000 or value
end

function EPAwards:GetThreshold(spec, boss)
    local thresholds = self:GetSettings().dpsBosses[boss or SAURFANG]
    return thresholds and thresholds[spec]
end

function EPAwards:AddDPSBoss(boss)
    local encounter = BossIds.DPS_ENCOUNTER_BY_NPC[boss]
    if not encounter or encounter.id ~= boss then return false end
    local bosses = self:GetSettings().dpsBosses
    bosses[boss] = bosses[boss] or {}
    return true
end

function EPAwards:RemoveDPSBoss(boss)
    self:GetSettings().dpsBosses[boss] = nil
end

function EPAwards:GetDPSResults()
    local char = RLHelper.db.char
    char.dpsResults = char.dpsResults or {}
    if char.saurfangDPS then
        char.saurfangDPS.boss = SAURFANG
        char.dpsResults[SAURFANG] = char.dpsResults[SAURFANG] or char.saurfangDPS
        char.saurfangDPS = nil
    end
    return char.dpsResults
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
    local settings = self:GetSettings()
    settings.dpsSource = DPSMeters:ResolveSource(settings.dpsSource)
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
    if self.dpsWindow then self.dpsWindow:Hide() end
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
    local encounter = BossIds.DPS_ENCOUNTER_BY_NPC[npc]
    if encounter and encounter.instance == RLHelper.currentInstanceId and
        self:GetSettings().dpsBosses[encounter.id] then
        -- For shared encounters and bosses rescued/retreating, DBM confirms the victory.
        local N = BossIds.NPCS
        if encounter.id == N.GORMOK_THE_IMPALER then
            if npc == N.ICEHOWL then DPSMeters:BossKilled(npc) end
        elseif encounter.id ~= N.VIVIENNE_BLACKWHISPER and encounter.id ~= N.EYDIS_DARKBANE and
            encounter.id ~= N.PRINCE_VALANAR and encounter.id ~= N.HIGH_OVERLORD_SAURFANG and
            encounter.id ~= N.VALITHRIA_DREAMWALKER then
            DPSMeters:BossKilled(npc)
        end
    end
    for _, reward in ipairs(REWARDS) do
        if reward.bosses and reward.instance == RLHelper.currentInstanceId and reward.bosses[npc] then
            self:Suggest(reward.key)
        end
    end
end

function EPAwards:StartDPSMeter()
    local settings = self:GetSettings()
    settings.dpsSource = DPSMeters:ResolveSource(settings.dpsSource)
    DPSMeters:Start(settings.dpsSource, function(fight) self:DPSFightComplete(fight) end)
end

function EPAwards:SetDPSSource(source)
    if source ~= "Details" and source ~= "Skada" and source ~= "Recount" and source ~= "ErrorDPSCounter" then return end
    source = DPSMeters:ResolveSource(source)
    self:GetSettings().dpsSource = source
    if self.active then self:StartDPSMeter() end
end

-- Consume completed victories independently of the selected meter's data layout.
function EPAwards:DPSFightComplete(set)
    local encounter = BossIds.DPS_ENCOUNTER_BY_NPC[set.boss]
    if not self:IsFeatureEnabled() or set.source ~= self:GetSettings().dpsSource or
        not encounter or not self:GetSettings().dpsBosses[encounter.id] then return end
    local boss = encounter.id
    local saved = self:GetDPSResults()[boss]
    if saved and (saved.source or "Skada") == set.source and
        saved.starttime == set.starttime and saved.endtime == set.endtime then return end
    local snapshot = { boss = boss, source = set.source, starttime = set.starttime,
        endtime = set.endtime, players = {}, unknown = 0 }
    if self:IsOozeMode(boss) then
        snapshot.mode, snapshot.oozeThreshold, snapshot.oozes = "ooze", self:GetOozeThreshold(), {}
        for guid in pairs(set.oozeDamage or {}) do snapshot.oozes[#snapshot.oozes + 1] = guid end
        table.sort(snapshot.oozes)
        snapshot.oozeCount = #snapshot.oozes
    end
    for _, player in ipairs(set.players or {}) do
        local spec = SPEC_BY_ID[player.spec]
        local threshold = self:GetThreshold(player.spec, boss)
        if snapshot.mode == "ooze" then
            local damage, total = {}, 0
            for _, guid in ipairs(snapshot.oozes) do
                local amount = set.oozeDamage[guid][player.name] or 0
                damage[guid] = amount
                total = total + amount
            end
            snapshot.players[#snapshot.players + 1] = { name = player.name, class = player.class,
                spec = player.spec, oozeDamage = damage, oozeTotal = total,
                gasTargets = (set.gasTargets or {})[player.name] or 0 }
        elseif not spec or spec[2] ~= player.class or type(player.dps) ~= "number" then
            snapshot.unknown = snapshot.unknown + 1
        elseif threshold and threshold > 0 then
            snapshot.players[#snapshot.players + 1] = {
                name = player.name, class = player.class, spec = player.spec,
                dps = player.dps, threshold = threshold
            }
        end
    end
    table.sort(snapshot.players, function(a, b)
        return (snapshot.mode == "ooze" and a.oozeTotal or a.dps) > (snapshot.mode == "ooze" and b.oozeTotal or b.dps)
    end)
    self:GetDPSResults()[boss] = snapshot
    if self.dpsWindow and self.dpsWindow:IsShown() and self.dpsWindow.boss == boss then self:ShowDPSWindow(boss) end
end

function EPAwards:IndividualEPAward(_, name, reason, amount)
    local pending = self.pendingIndividual
    if pending and pending.name == name and pending.reason == reason and pending.amount == amount then
        pending.confirmed = true
    end
end

function EPAwards:AwardDPS(snapshot, selected, offset)
    if not self:IsFeatureEnabled() then return false, "Начисление GP и ЕП выключено в настройках." end
    if not snapshot or snapshot ~= self:GetDPSResults()[snapshot.boss] then
        return false, "Результат боя изменился. Откройте окно заново."
    end
    local encounter = BossIds.DPS_ENCOUNTER_BY_NPC[snapshot.boss]
    local amount = self:GetAmount("saurfang")
    local reason = "RLHelper: ДПС " .. (snapshot.boss == SAURFANG and "Саурфанг" or encounter.name)
    if amount <= 0 then return false, "Укажите сумму ЕП за ДПС в настройках." end
    local epgp = LibStub("AceAddon-3.0"):GetAddon("EPGP", true)
    if not epgp or type(epgp.IncEPBy) ~= "function" or type(epgp.GetEPGP) ~= "function" or
        type(epgp.RegisterCallback) ~= "function" then return false, "EPGP недоступен." end
    if not epgp:CanIncEPBy(reason, amount) then
        return false, "EPGP не готов к начислению: проверьте права и загрузку списка гильдии."
    end
    local recipients, mains = {}, {}
    for _, player in ipairs(snapshot.players) do
        if selected[player.name] and qualifies(snapshot, player, offset) then
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
        frame.dpsButton = makeButton(frame, "ДПС боссов", 155, function() self:ShowDPSWindow() end)
        frame.dpsButton:SetPoint("BOTTOMRIGHT", -14, 10)
        self.window = frame
    end
    if self.window:IsShown() then self.window:Hide() else self:RefreshWindow(); self.window:Show() end
end

function EPAwards:ShowDPSWindow(boss)
    if not self:IsFeatureEnabled() then return end
    if self.window then self.window:Hide() end
    local frame = self.dpsWindow
    if not frame then
        frame = makeWindow("ДПС боссов", 700, 514)
        frame.bossDropdown = CreateFrame("Frame", "RLHelperDPSAwardBossDropdown", frame, "UIDropDownMenuTemplate")
        frame.bossDropdown:SetPoint("TOPLEFT", -2, -30)
        UIDropDownMenu_SetWidth(frame.bossDropdown, 300)
        UIDropDownMenu_Initialize(frame.bossDropdown, function()
            local settings, results = self:GetSettings(), self:GetDPSResults()
            for _, encounter in ipairs(BossIds.DPS_ENCOUNTERS) do
                if settings.dpsBosses[encounter.id] or results[encounter.id] then
                    local info = UIDropDownMenu_CreateInfo()
                    info.text = encounter.raid .. ": " .. encounter.name
                    info.checked = frame.boss == encounter.id
                    info.func = function() self:ShowDPSWindow(encounter.id) end
                    UIDropDownMenu_AddButton(info)
                end
            end
        end)
        frame.info = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        frame.info:SetPoint("TOPLEFT", 14, -80)
        frame.info:SetWidth(670)
        frame.info:SetJustifyH("LEFT")
        for _, column in ipairs({ {14, "Имя игрока"}, {175, "Класс / спек"}, {390, "DPS"}, {480, "Планка"}, {580, "Выбран"} }) do
            local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
            label:SetPoint("TOPLEFT", column[1], -158)
            label:SetText(column[2])
            if column[1] == 390 then frame.valueHeader = label end
        end
        local scroll = CreateFrame("ScrollFrame", "RLHelperDPSScroll", frame, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 14, -182)
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
            local _, message = self:AwardDPS(frame.snapshot, frame.selected, frame.offset)
            frame.result:SetText(message)
            for _, row in ipairs(frame.rows) do
                if row.player then row.check:SetChecked(frame.selected[row.player.name] == true) end
            end
        end)
        frame.awardButton:SetPoint("BOTTOM", 0, 12)
        frame.minusButton = makeButton(frame, "-", 28, function() self:AdjustDPSThreshold(-500) end)
        frame.minusButton:SetPoint("TOPLEFT", 14, -120)
        frame.plusButton = makeButton(frame, "+", 28, function() self:AdjustDPSThreshold(500) end)
        frame.plusButton:SetPoint("LEFT", frame.minusButton, "RIGHT", 6, 0)
        frame.adjustment = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        frame.adjustment:SetPoint("LEFT", frame.plusButton, "RIGHT", 10, 0)
        self.dpsWindow = frame
    end
    local settings, results = self:GetSettings(), self:GetDPSResults()
    boss = boss or frame.boss
    if not boss or (not settings.dpsBosses[boss] and not results[boss]) then
        boss = nil
        for _, encounter in ipairs(BossIds.DPS_ENCOUNTERS) do
            if settings.dpsBosses[encounter.id] or results[encounter.id] then boss = encounter.id; break end
        end
    end
    frame.boss, frame.snapshot, frame.selected, frame.offset = boss, results[boss], {}, 0
    local encounter = BossIds.DPS_ENCOUNTER_BY_NPC[boss]
    UIDropDownMenu_SetText(frame.bossDropdown,
        encounter and (encounter.raid .. ": " .. encounter.name) or "Добавьте босса в настройках ЕПГП")
    self:RefreshDPSWindow()
    frame:Show()
end

function EPAwards:AdjustDPSThreshold(delta)
    local frame = self.dpsWindow
    frame.offset = frame.offset + delta
    self:RefreshDPSWindow()
end

function EPAwards:RefreshDPSWindow()
    local frame = self.dpsWindow
    local snapshot = frame.snapshot
    local oozeMode = snapshot and snapshot.mode == "ooze"
    frame.valueHeader:SetText(oozeMode and "Общий урон" or "DPS")
    if oozeMode then
        frame.minusButton:Hide(); frame.plusButton:Hide()
        frame.adjustment:SetText("Урон на призыв: " .. snapshot.oozeThreshold .. ". Цель газа: -100000.")
    else
        frame.minusButton:Show(); frame.plusButton:Show()
        frame.adjustment:SetText(string.format("Поправка к планкам: %+d DPS (шаг 500)", frame.offset))
    end
    frame.result:SetText("")
    for _, row in ipairs(frame.rows) do row:Hide(); row.player = nil end
    local count, previouslyAwarded = 0, 0
    if snapshot then
        for _, player in ipairs(snapshot.players) do
            local total, threshold
            if oozeMode then total, threshold = oozeResult(snapshot, player)
            else threshold = adjustedThreshold(player, frame.offset) end
            if qualifies(snapshot, player, frame.offset) then
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
                row.cells[2]:SetText(SPEC_BY_ID[player.spec] and SPEC_BY_ID[player.spec][3] or "Спек неизвестен")
                row.cells[3]:SetText(oozeMode and tostring(total) or string.format("%.1f", player.dps))
                row.cells[4]:SetText(tostring(threshold))
                if frame.selected[player.name] == nil then frame.selected[player.name] = true end
                row.check:SetChecked(frame.selected[player.name])
                row:Show()
            end
        end
        frame.info:SetText("Источник: " .. (snapshot.source or "Skada") .. ". Убийство: " .. date("%d.%m %H:%M", snapshot.endtime) .. ". По " .. self:GetAmount("saurfang") ..
            (oozeMode and (" ЕП. Слизней: " .. snapshot.oozeCount .. ". Общий урон по слизням, без допуска.") or
                " ЕП. Допуск: 100 DPS ниже планки.") .. "\nПодходят: " .. count ..
            (oozeMode and (snapshot.oozeCount == 0 and ". Нет данных по слизням." or ".") or
                (". Без данных о спеке/DPS: " .. snapshot.unknown .. ".")))
    else
        frame.info:SetText("Нет сохранённого результата. Источник: " .. self:GetSettings().dpsSource ..
            ". Нужны загруженный метр и победа над выбранным боссом с заданными планками.")
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
    panel:SetSize(410, 506 + #SPECS * 34)
    panel:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -22)
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", 0, 0)
    title:SetText("Начисление ЕП")
    local help = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    help:SetPoint("TOPLEFT", 0, -24)
    help:SetText("Галочка — показывать начисление и напоминание. 0 ЕП — отключить.")
    local fields = {}
    local function input(key, labelText, y, read, save, thresholdField)
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
        local function refresh()
            edit:SetText(tostring(read())); edit:SetCursorPosition(0)
            if thresholdField then
                if thresholdField() then edit:Show(); label:Show() else edit:Hide(); label:Hide() end
            end
        end
        local function commit()
            if thresholdField and not thresholdField() then return end
            save(edit:GetText())
            refresh()
        end
        edit:SetScript("OnEnterPressed", function() edit:ClearFocus() end)
        edit:SetScript("OnEditFocusLost", commit)
        edit:SetScript("OnEscapePressed", function() refresh(); edit:ClearFocus() end)
        refresh()
        table.insert(fields, refresh)
        return edit, label
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
    input("saurfang", "ДПС боссов (ЕП)", -234, function() return self:GetAmount("saurfang") end, function(value)
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
    local viewport = parent.GetParent and parent:GetParent()
    local sourceHelp = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    sourceHelp:SetPoint("TOPLEFT", 0, -298)
    sourceHelp:SetJustifyH("LEFT")
    sourceHelp:SetText(DPSMeters.requirements)
    panel.sourceHelp = sourceHelp
    local function refreshSource()
        -- Anchored option panels have no width until InterfaceOptions displays the category.
        local viewportWidth = viewport and viewport:GetWidth() or 0
        if viewportWidth <= 0 then viewportWidth = 375 end
        local availableWidth = viewportWidth - 16 - 10
        -- UIDropDownMenuTemplate contributes 50px beyond the configured text width.
        UIDropDownMenu_SetWidth(sourceDropdown, availableWidth - 134 - 50)
        sourceHelp:SetWidth(availableWidth)
        local source = self:GetSettings().dpsSource
        UIDropDownMenu_SetText(sourceDropdown, DPSMeters:GetSourceText(source))
    end
    UIDropDownMenu_Initialize(sourceDropdown, function()
        for _, source in ipairs(DPSMeters.sources) do
            local info = UIDropDownMenu_CreateInfo()
            local available, reason = DPSMeters:IsAvailable(source)
            info.text, info.value = DPSMeters:GetSourceText(source), source
            info.disabled = not available
            info.tooltipTitle, info.tooltipText = source, reason
            info.tooltipOnButton, info.tooltipWhileDisabled = true, true
            info.checked = self:GetSettings().dpsSource == source
            info.func = function() self:SetDPSSource(source); refreshSource() end
            UIDropDownMenu_AddButton(info)
        end
    end)
    refreshSource()
    table.insert(fields, refreshSource)
    local raids = { {BossIds.INSTANCES.ICECROWN_CITADEL, "ЦЛК"}, {BossIds.INSTANCES.RUBY_SANCTUM, "РС"},
        {BossIds.INSTANCES.TRIAL_OF_THE_CRUSADER, "ИВК"} }
    panel.boss = SAURFANG
    if not self:GetSettings().dpsBosses[panel.boss] then
        for _, encounter in ipairs(BossIds.DPS_ENCOUNTERS) do
            if self:GetSettings().dpsBosses[encounter.id] then panel.boss = encounter.id; break end
        end
    end
    panel.raid = BossIds.DPS_ENCOUNTER_BY_NPC[panel.boss].instance
    panel.thresholdInputs = {}
    local raidDropdown = CreateFrame("Frame", "RLHelperDPSRaidDropdown", panel, "UIDropDownMenuTemplate")
    raidDropdown:SetPoint("TOPLEFT", -16, -378)
    UIDropDownMenu_SetWidth(raidDropdown, 90)
    local bossDropdown = CreateFrame("Frame", "RLHelperDPSBossDropdown", panel, "UIDropDownMenuTemplate")
    bossDropdown:SetPoint("TOPLEFT", -16, -416)
    UIDropDownMenu_SetWidth(bossDropdown, 220)
    local add = makeButton(panel, "Добавить", 85, function()
        for _, edit in ipairs(panel.thresholdInputs) do edit:ClearFocus() end
        self:AddDPSBoss(panel.boss)
        panel.refresh()
    end)
    add:SetPoint("TOPLEFT", 247, -420)
    local remove = makeButton(panel, "Удалить", 85, function()
        for _, edit in ipairs(panel.thresholdInputs) do edit:ClearFocus() end
        self:RemoveDPSBoss(panel.boss)
        panel.refresh()
    end)
    remove:SetPoint("TOPLEFT", 247, -452)
    local function selectBoss(boss)
        for _, edit in ipairs(panel.thresholdInputs) do edit:ClearFocus() end
        panel.boss = boss
        panel.refresh()
    end
    UIDropDownMenu_Initialize(raidDropdown, function()
        for _, raid in ipairs(raids) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.checked = raid[2], panel.raid == raid[1]
            info.func = function()
                for _, encounter in ipairs(BossIds.DPS_ENCOUNTERS) do
                    if encounter.instance == raid[1] then
                        panel.raid = raid[1]
                        selectBoss(encounter.id)
                        break
                    end
                end
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    UIDropDownMenu_Initialize(bossDropdown, function()
        for _, encounter in ipairs(BossIds.DPS_ENCOUNTERS) do
            if encounter.instance == panel.raid then
                local info = UIDropDownMenu_CreateInfo()
                local added = self:GetSettings().dpsBosses[encounter.id] ~= nil
                info.text = encounter.name .. (added and " (добавлен)" or "")
                info.checked = panel.boss == encounter.id
                info.func = function() selectBoss(encounter.id) end
                UIDropDownMenu_AddButton(info)
            end
        end
    end)
    local thresholdsTitle = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    thresholdsTitle:SetPoint("TOPLEFT", 0, -488)
    thresholdsTitle:SetText("Планки ДПС по спекам")
    local thresholdsHelp = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    thresholdsHelp:SetPoint("TOPLEFT", 0, -512)
    thresholdsHelp:SetWidth(390)
    thresholdsHelp:SetJustifyH("LEFT")
    thresholdsHelp:SetText("Добавьте босса и заполните планки. Enter сохраняет значение.\nПусто или 0 — не учитывать спек. DPS — после победы.")
    local modeLabel = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalSmall")
    modeLabel:SetPoint("TOPLEFT", 0, -558)
    modeLabel:SetText("Условие награды")
    local modeDropdown = CreateFrame("Frame", "RLHelperPutricideModeDropdown", panel, "UIDropDownMenuTemplate")
    modeDropdown:SetPoint("TOPLEFT", 134, -552)
    UIDropDownMenu_SetWidth(modeDropdown, 200)
    local modeLabels = { boss = "ДПС по спекам", ooze = "Урон по слизням" }
    UIDropDownMenu_Initialize(modeDropdown, function()
        for _, mode in ipairs({ "boss", "ooze" }) do
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.checked = modeLabels[mode], (self:GetSettings().putricideMode or "boss") == mode
            info.func = function()
                for _, edit in ipairs(panel.thresholdInputs) do edit:ClearFocus() end
                self:GetSettings().putricideMode = mode
                panel.refresh()
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    local specRows = {}
    local function refreshBoss()
        for _, raid in ipairs(raids) do
            if raid[1] == panel.raid then UIDropDownMenu_SetText(raidDropdown, raid[2]) end
        end
        local encounter = BossIds.DPS_ENCOUNTER_BY_NPC[panel.boss]
        UIDropDownMenu_SetText(bossDropdown, encounter.name)
        local configured = self:GetSettings().dpsBosses[panel.boss] ~= nil
        if configured then add:Disable(); remove:Enable() else add:Enable(); remove:Disable() end
        local putricide = panel.boss == PUTRICIDE
        local oozeMode = self:IsOozeMode(panel.boss)
        if configured and putricide then modeLabel:Show(); modeDropdown:Show()
        else modeLabel:Hide(); modeDropdown:Hide() end
        UIDropDownMenu_SetText(modeDropdown, modeLabels[self:GetSettings().putricideMode or "boss"])
        thresholdsTitle:SetText(oozeMode and "Планка урона по слизням" or "Планки ДПС по спекам")
        thresholdsHelp:SetText(oozeMode and
            "Общий урон; планка умножается на число призывов.\nЦель газа: -100000. 0 — отключить награду." or
            "Добавьте босса и заполните планки. Enter сохраняет значение.\nПусто или 0 — не учитывать спек. DPS — после победы.")
        for index, row in ipairs(specRows) do
            local y = -552 - (index - 1) * 34 - (putricide and 76 or 0)
            row.label:ClearAllPoints(); row.label:SetPoint("TOPLEFT", 0, y)
            row.edit:ClearAllPoints(); row.edit:SetPoint("TOPLEFT", 150, y + 5)
        end
        local height = configured and (oozeMode and 648 or (564 + #SPECS * 34 + (putricide and 76 or 0))) or 550
        panel:SetHeight(height)
        if parent.SetHeight then parent:SetHeight(300 + height) end
    end
    table.insert(fields, refreshBoss)
    for index, spec in ipairs(SPECS) do
        local id = spec[1]
        local edit, label = input("Spec" .. id, spec[3], -552 - (index - 1) * 34,
            function() return self:GetThreshold(id, panel.boss) or "" end,
            function(value)
                local threshold = tonumber(value)
                local thresholds = self:GetSettings().dpsBosses[panel.boss]
                if not value:find("%S") or threshold == 0 then
                    thresholds[id] = 0
                elseif threshold and threshold > 0 and threshold <= 999999 and threshold == math.floor(threshold) then
                    thresholds[id] = threshold
                else RLHelper:Print("Планка DPS должна быть целым числом от 0 до 999999.") end
            end, function() return self:GetSettings().dpsBosses[panel.boss] and not self:IsOozeMode(panel.boss) end)
        panel.thresholdInputs[#panel.thresholdInputs + 1] = edit
        specRows[#specRows + 1] = { edit = edit, label = label }
    end
    local oozeEdit = input("PutricideOozeDamage", "Урон на слизня", -596,
        function() return self:GetOozeThreshold() end,
        function(value)
            local amount = tonumber(value)
            if amount and amount >= 0 and amount <= 999999 and amount == math.floor(amount) then
                self:GetSettings().putricideOozeDamage = amount
            else RLHelper:Print("Урон на слизня должен быть целым числом от 0 до 999999.") end
        end, function() return self:GetSettings().dpsBosses[panel.boss] and self:IsOozeMode(panel.boss) end)
    panel.thresholdInputs[#panel.thresholdInputs + 1] = oozeEdit
    panel.refresh = function() for _, refresh in ipairs(fields) do refresh() end end
    panel.refresh()
    panel:SetScript("OnShow", panel.refresh)
    self.options = panel
end

return EPAwards
