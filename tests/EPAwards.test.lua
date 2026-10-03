local mocks = require('tests.mocks')
require('Core')
require('data.BossIds')
local addon = LibStub('AceAddon-3.0'):GetAddon('RLHelper')
local meters = require('modules.DPSMeters')
local awards = require('modules.EPAwards')
addon.modules.EPAwards = nil

describe('EP awards', function()
    local original, now, epgp, calls, shown
    local function at(day, hour, minute)
        return os.time({ year = 2026, month = 9, day = day, hour = hour, min = minute, sec = 0 })
    end
    before_each(function()
        original = { db = addon.db, instance = addon.currentInstanceId, show = awards.ShowReminder,
            getAddon = mocks.GetAddon, time = time, date = date, leader = IsRaidLeader,
            raid = GetNumRaidMembers, createFrame = CreateFrame, categories = InterfaceOptions_AddCategory,
            skada = _G.Skada, main = addon.mainFrame, themeButtons = addon.themeButtons, print = addon.Print }
        now = at(27, 19, 0)
        _G.time = function(value) return value and os.time(value) or now end
        _G.date = function(format, value) return os.date(format, value or now) end
        _G.IsRaidLeader = function() return true end
        _G.GetNumRaidMembers = function() return 25 end
        addon.db = { profile = { gpAwardButtonsEnabled = true }, char = {} }
        local settings = awards:GetSettings()
        settings.amounts = { attendance = 1000, icc = 2000, rs = 1500 }
        shown, calls = {}, {}
        _G.Skada = nil
        meters:Stop()
        awards.active = nil
        awards.saurfangWindow = nil
        awards.individualCallbackSource, awards.pendingIndividual = nil, nil
        awards.popups, awards.window, awards.callbackSource, awards.pending = nil, nil, nil, nil
        awards:StartDPSMeter()
        awards.ShowReminder = function(_, key) table.insert(shown, key) end
        epgp = {
            CanIncEPBy = function() return true end,
            IsMemberInExtrasList = function(_, name) return name == 'Standby' end,
            RegisterCallback = function(target, event) assert.equals('MassEPAward', event); epgp.target = target end,
            IncMassEPBy = function(_, reason, amount)
                table.insert(calls, { reason, amount })
                epgp.target:MassEPAward('MassEPAward', { Main = true }, reason, amount,
                    { Standby = true }, reason .. ' - Standby', amount / 2)
            end
        }
        mocks.GetAddon = function(self, name, silent)
            if name == 'EPGP' then return epgp end
            return original.getAddon(self, name, silent)
        end
    end)
    after_each(function()
        meters:Stop()
        addon.db, addon.currentInstanceId = original.db, original.instance
        awards.ShowReminder = original.show
        mocks.GetAddon = original.getAddon
        _G.time, _G.date, _G.IsRaidLeader, _G.GetNumRaidMembers = original.time, original.date, original.leader, original.raid
        awards.window, awards.popups, awards.pending, awards.callbackSource = nil, nil, nil, nil
        addon.modules.EPAwards = nil
        _G.Skada = original.skada
        awards.active = nil
        awards.saurfangWindow = nil
        awards.individualCallbackSource, awards.pendingIndividual = nil, nil
        _G.CreateFrame, _G.InterfaceOptions_AddCategory = original.createFrame, original.categories
        addon.mainFrame, addon.themeButtons, addon.Print = original.main, original.themeButtons, original.print
        awards.options, awards.button, awards.clock = nil, nil, nil
    end)

    it('awards via EPGP including its standby handling, saving no recipients', function()
        assert.is_true(awards:Award('attendance'))
        assert.same({ { 'RLHelper: Приход вовремя', 1000 } }, calls)
        assert.same({ status = 'awarded', amount = 1000, reason = 'Приход вовремя', at = now }, awards:GetState().awards.attendance)
        assert.is_true(awards:Award('attendance'))
        assert.equals(2, #calls)
    end)
    it('allows the RL to delay the click and uses the current mass-award method', function()
        awards:CheckTime()
        now = at(27, 19, 4)
        assert.is_true(awards:Award('attendance'))
        assert.equals(now, awards:GetState().awards.attendance.at)
    end)
    it('keeps awards across midnight and reload, then resets at the next RT', function()
        awards:Award('icc')
        local saved = addon.db.char.epAwards
        awards.callbackSource = nil
        now = at(28, 0, 30)
        assert.equals(saved, awards:GetState())
        assert.equals('awarded', saved.awards.icc.status)
        now = at(28, 19, 0)
        assert.is_nil(awards:GetState().awards.icc)
        assert.is_true(awards:Award('icc'))
    end)
    it('does not clear current awards when RT settings change', function()
        awards:Award('icc')
        assert.is_true(awards:SetRT('20:00'))
        now = at(28, 19, 0)
        assert.equals('awarded', awards:GetState().awards.icc.status)
        now = at(28, 20, 0)
        assert.is_true(awards:Award('icc'))
    end)
    it('shows attendance only once at local RT, including across reload', function()
        now = at(27, 18, 59)
        awards:CheckTime()
        assert.equals(0, #shown)
        now = at(27, 19, 0)
        awards:CheckTime()
        awards:CheckTime()
        awards.popups = nil
        awards:CheckTime()
        assert.same({ 'attendance' }, shown)
    end)
    it('does not catch up a missed attendance reminder', function()
        now = at(27, 19, 2)
        awards:CheckTime()
        assert.equals(0, #shown)
    end)
    it('suppresses reminders already awarded manually', function()
        awards:Award('attendance')
        awards:CheckTime()
        awards:Award('icc')
        awards:Suggest('icc')
        assert.equals(0, #shown)
    end)
    it('respects disabled reminders and zero amounts', function()
        awards:GetSettings().reminders.attendance = false
        awards:CheckTime()
        awards:GetSettings().amounts.icc = 0
        awards:Suggest('icc')
        assert.equals(0, #shown)
        assert.is_false(awards:Award('icc'))
    end)
    it('requires leadership only for reminders and prevents guild-wide awards outside raids', function()
        _G.IsRaidLeader = function() return false end
        awards:CheckTime()
        assert.is_true(awards:Award('icc'))
        _G.IsRaidLeader = function() return true end
        _G.GetNumRaidMembers = function() return 0 end
        assert.is_false(awards:Award('icc'))
        assert.equals(1, #calls)
        assert.equals(0, #shown)
    end)
    it('does not mark success when EPGP is missing or disallows the operation', function()
        local saved = epgp
        epgp = nil
        assert.is_false(awards:Award('icc'))
        epgp = saved
        epgp.CanIncEPBy = function() return false end
        assert.is_false(awards:Award('icc'))
        assert.is_nil(awards:GetState().awards.icc)
    end)
    it('does not mark an empty mass award as successful', function()
        epgp.IncMassEPBy = function() end
        assert.is_false(awards:Award('icc'))
        assert.is_nil(awards:GetState().awards.icc)
    end)
    it('allows an explicit manual retry after an uncertain result', function()
        local massAward = epgp.IncMassEPBy
        epgp.IncMassEPBy = function() error('write failed') end
        assert.is_false(awards:Award('icc'))
        assert.equals('uncertain', awards:GetState().awards.icc.status)
        epgp.IncMassEPBy = massAward
        assert.is_true(awards:Award('icc'))
    end)
    it('ignores unrelated confirmation callbacks', function()
        epgp.IncMassEPBy = function(_, reason, amount)
            epgp.target:MassEPAward('MassEPAward', { Main = true }, 'other reason', amount)
        end
        assert.is_false(awards:Award('icc'))
    end)
    it('offers ICC only on the final boss death in the correct instance through Core', function()
        addon.modules.EPAwards = awards
        addon.currentInstanceId = 631
        local event = { event = 'UNIT_DIED', destGUID = '0xF130008EF5000001' }
        addon:DispatchCombatEvent(event)
        addon:DispatchCombatEvent(event)
        assert.same({ 'icc' }, shown)
    end)
    it('ignores wipes, spell damage, other bosses and other instances', function()
        addon.currentInstanceId = 724
        awards:handleEvent({ event = 'UNIT_DIED', destGUID = '0xF130008EF5000001' })
        awards:handleEvent({ event = 'SPELL_DAMAGE', destGUID = '0xF130009BB7000001' })
        awards:handleEvent({ event = 'UNIT_DIED', destGUID = '0x0000000000000001' })
        assert.equals(0, #shown)
    end)
    it('deduplicates both Halion death events', function()
        addon.currentInstanceId = 724
        awards:handleEvent({ event = 'UNIT_DIED', destGUID = '0xF130009BB7000001' })
        awards:handleEvent({ event = 'UNIT_DIED', destGUID = '0xF130009CCE000001' })
        assert.same({ 'rs' }, shown)
    end)
    local function installFrames()
        local frames = {}
        local function frame(kind, name, parent, template)
            local f = { kind = kind, name = name, parent = parent, template = template, scripts = {}, visible = true }
            frames[#frames + 1] = f
            function f:SetScript(event, fn) self.scripts[event] = fn end
            function f:SetText(value) self.text = value end
            function f:GetText() return self.text end
            function f:SetChecked(value) self.checked = value end
            function f:GetChecked() return self.checked end
            function f:CreateFontString() return frame('FontString', nil, self) end
            function f:SetAlpha(value) assert.equals('number', type(value)); self.alpha = value end
            function f:Show() self.visible = true end
            function f:Hide() self.visible = false end
            function f:IsShown() return self.visible end
            function f:Enable() self.enabled = true end
            function f:Disable() self.enabled = false end
            function f:StartMoving() self.moving = true end
            function f:StopMovingOrSizing() self.moving = false end
            function f:ClearFocus() if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end end
            for _, method in ipairs({ 'SetPoint', 'SetSize', 'SetWidth', 'SetFrameStrata', 'SetBackdrop',
                'SetHeight', 'ClearAllPoints', 'SetMovable', 'SetClampedToScreen', 'EnableMouse', 'RegisterForDrag', 'SetJustifyH',
                'SetScrollChild', 'SetVerticalScroll', 'SetNormalTexture', 'SetHighlightTexture', 'SetAutoFocus', 'SetTextInsets', 'SetCursorPosition' }) do
                f[method] = function() end
            end
            function f:SetPoint(...) self.point = { ... } end
            function f:SetWidth(value) self.width = value end
            function f:SetHeight(value) self.height = value end
            function f:SetBackdrop(value) self.backdrop = value end
            return f
        end
        _G.CreateFrame = frame
        _G.InterfaceOptions_AddCategory = function() end
        addon.Print = function() end
        return frames
    end

    it('selects a persistent DPS source in shared settings and labels an unavailable addon', function()
        local frames = installFrames()
        awards:CreateSettings({}, {})
        local dropdown
        for _, frame in ipairs(frames) do
            if frame.name == 'RLHelperDPSSourceDropdown' then dropdown = frame end
        end
        assert.equals('Skada', awards:GetSettings().dpsSource)
        assert.equals('Skada (не загружен)', dropdown.text)
        local addButton, choices = UIDropDownMenu_AddButton, {}
        _G.UIDropDownMenu_AddButton = function(info) choices[#choices + 1] = info end
        dropdown.initialize()
        _G.UIDropDownMenu_AddButton = addButton
        assert.equals(2, #choices)
        assert.equals('Skada', choices[1].value)
        assert.equals('Recount', choices[2].value)
        assert.is_true(choices[1].checked)
        choices[2].func()
        assert.equals('Recount', awards:GetSettings().dpsSource)
        awards.options.scripts.OnShow()
        assert.is_truthy(dropdown.text:find('Recount', 1, true))
        -- Saved selections survive creation of a fresh settings panel.
        local newFrames = installFrames()
        awards:CreateSettings({}, {})
        for _, frame in ipairs(newFrames) do
            if frame.name == 'RLHelperDPSSourceDropdown' then
                assert.is_truthy(frame.text:find('Recount', 1, true))
            end
        end
    end)

    it('creates the compact icon, movable reminder and shared manual award status', function()
        local frames = installFrames()
        awards.ShowReminder = original.show
        addon.mainFrame = { buttonContainer = {}, discordButton = {} }
        awards:AttachButton()
        assert.is_not_nil(awards.button.scripts.OnClick)
        awards:CheckTime()
        local popup = awards.popups.attendance
        assert.is_true(popup:IsShown())
        popup.scripts.OnDragStart(popup)
        assert.is_true(popup.moving)
        popup.scripts.OnDragStop(popup)
        assert.is_false(popup.moving)
        for _, f in ipairs(frames) do
            if f.parent == popup and f.template == 'UIPanelCloseButton' then f.scripts.OnClick(f) end
        end
        awards:CheckTime()
        assert.is_false(popup:IsShown())
        awards.button.scripts.OnClick()
        assert.is_true(awards.window:IsShown())
        local row = awards.window.rows.attendance
        assert.is_true(row.button.enabled)
        row.button.scripts.OnClick()
        assert.is_true(row.button.enabled)
        assert.equals('Начислить', row.button.text)
        assert.is_truthy(row.label.text:find('Последнее: 1000 ЕП в 19:00', 1, true))
        assert.equals(1, #calls)
        awards:Suggest('attendance')
        assert.is_false(popup:IsShown())
    end)

    it('shows saved settings immediately and validates time and amount input', function()
        local frames = installFrames()
        awards:CreateSettings({}, {})
        local edits = {}
        for _, f in ipairs(frames) do if f.kind == 'EditBox' then edits[#edits + 1] = f end end
        assert.equals('19:00', edits[1]:GetText())
        assert.equals('1000', edits[2]:GetText())
        edits[1]:SetText('25:90')
        edits[1].scripts.OnEnterPressed()
        assert.equals('19:00', edits[1]:GetText())
        edits[1]:SetText('20:30')
        edits[1].scripts.OnEnterPressed()
        assert.equals('20:30', awards:GetSettings().rt)
        for _, invalid in ipairs({ '-1', '0.5', '100000', 'abc' }) do
            edits[2]:SetText(invalid)
            edits[2].scripts.OnEnterPressed()
            assert.equals(1000, awards:GetAmount('attendance'))
        end
        edits[2]:SetText('2500')
        edits[2].scripts.OnEnterPressed()
        assert.equals(2500, awards:GetAmount('attendance'))
        edits[2]:SetText('999')
        edits[2].scripts.OnEscapePressed()
        assert.equals('2500', edits[2]:GetText())
        awards.options.scripts.OnShow()
        assert.equals('2500', edits[2]:GetText())
    end)

    it('hides stale reminders when the next raid day begins', function()
        installFrames()
        awards.ShowReminder = original.show
        awards:Suggest('rs')
        local popup = awards.popups.rs
        now = at(28, 19, 0)
        awards:GetState()
        assert.is_false(popup:IsShown())
        awards:Suggest('rs')
        assert.is_true(popup:IsShown())
    end)

    it('uses raid defaults while preserving explicit custom and zero values', function()
        awards:GetSettings().amounts = {}
        assert.equals(7000, awards:GetAmount('icc'))
        assert.equals(3000, awards:GetAmount('rs'))
        assert.equals(2000, awards:GetAmount('toc'))
        assert.equals(1000, awards:GetAmount('attendance'))
        awards:GetSettings().amounts.icc = 0
        awards:GetSettings().amounts.rs = 1234
        assert.equals(0, awards:GetAmount('icc'))
        assert.equals(1234, awards:GetAmount('rs'))
    end)

    it('recognizes all verified Anubarak IDs only in Trial of the Crusader', function()
        for _, id in ipairs({ 34564, 34566, 35615 }) do
            addon.db.char.epAwards = nil
            local event = { event = 'UNIT_DIED', destGUID = string.format('0xF130%06X000001', id) }
            addon.currentInstanceId = 631
            awards:handleEvent(event)
            assert.is_nil(awards:GetState().prompted.toc)
            addon.currentInstanceId = 649
            awards:handleEvent(event)
            awards:handleEvent(event)
            assert.is_true(awards:GetState().prompted.toc)
        end
        assert.same({ 'toc', 'toc', 'toc' }, shown)
    end)

    it('hides disabled rewards without gaps, removes settings and uses a borderless background', function()
        local frames = installFrames()
        awards:Award('icc')
        awards:GetSettings().reminders.icc = false
        awards:ToggleWindow()
        assert.is_false(awards.window.rows.icc.label:IsShown())
        assert.is_false(awards.window.rows.icc.button:IsShown())
        assert.equals(-102, awards.window.rows.rs.label.point[3])
        assert.equals(213, awards.window.height)
        assert.is_nil(awards.window.backdrop.edgeFile)
        for _, f in ipairs(frames) do assert.is_not.equal('Настройки', f.text) end
        for _, key in ipairs({ 'attendance', 'icc', 'rs', 'toc' }) do
            awards:GetSettings().reminders[key] = false
        end
        awards:RefreshWindow()
        assert.is_true(awards.window.empty:IsShown())
        assert.equals(145, awards.window.height)
    end)

    it('gives template inputs unique names and explicit widths in the shared settings section', function()
        local frames = installFrames()
        local parent, anchor = {}, {}
        awards:CreateSettings(parent, anchor)
        assert.equals(parent, awards.options.parent)
        assert.equals(anchor, awards.options.point[2])
        local names, count = {}, 0
        for _, f in ipairs(frames) do
            if f.kind == 'EditBox' then
                assert.is_not_nil(f.name)
                assert.is_nil(names[f.name])
                names[f.name] = true
                count = count + 1
                assert.equals(90, f.width)
            end
        end
        assert.equals(37, count)
    end)

    it('gives selected standby the full award regardless of EPGP percentage and restores EPGP', function()
        local originalExtras = epgp.IsMemberInExtrasList
        for _, percent in ipairs({ 0, 50, 100, 200 }) do
            addon.db.char.epAwards = nil
            local amounts = {}
            epgp.IncMassEPBy = function(self, reason, amount)
                -- Same amount-selection branch as the installed EPGP mass method.
                for _, name in ipairs({ 'Main', 'Standby' }) do
                    amounts[name] = self:IsMemberInExtrasList(name) and math.floor(percent * 0.01 * amount) or amount
                end
                self.target:MassEPAward('MassEPAward', { Main = true, Standby = true }, reason, amount)
            end
            assert.is_true(awards:Award('attendance'))
            assert.same({ Main = 1000, Standby = 1000 }, amounts)
            assert.equals(originalExtras, epgp.IsMemberInExtrasList)
            assert.is_true(epgp:IsMemberInExtrasList('Standby'))
        end
    end)

    it('restores EPGP standby behavior even if the mass award throws', function()
        local originalExtras = epgp.IsMemberInExtrasList
        epgp.IncMassEPBy = function() error('partial write') end
        assert.is_false(awards:Award('attendance'))
        assert.equals(originalExtras, epgp.IsMemberInExtrasList)
        assert.equals('uncertain', awards:GetState().awards.attendance.status)
    end)

    it('keeps every manual button enabled without leadership, outside raids and for zero amounts', function()
        installFrames()
        _G.IsRaidLeader = function() return false end
        _G.GetNumRaidMembers = function() return 0 end
        awards:GetSettings().amounts.icc = 0
        awards:ToggleWindow()
        for _, row in pairs(awards.window.rows) do assert.is_true(row.button.enabled) end
    end)

    it('keeps the previous success when a manual repeat has no recipients', function()
        awards:Award('icc')
        local previous = awards:GetState().awards.icc
        epgp.IncMassEPBy = function() end
        assert.is_false(awards:Award('icc'))
        assert.equals(previous, awards:GetState().awards.icc)
        awards:Suggest('icc')
        assert.equals(0, #shown)
    end)

    local function winningSet()
        local function player(name, spec, dps, class)
            return { name = name, spec = spec, class = class or 'WARRIOR', GetDPS = function() return dps end }
        end
        local set = { gotboss = 37813, success = true, starttime = now - 180, endtime = now,
            players = { player('Fury', 72, 10000), player('Arms', 71, 9900),
                player('Below', 72, 9899.9), player('NoThreshold', 73, 20000),
                player('Unknown', nil, 20000), player('Unholy', 252, 12000, 'DEATHKNIGHT') } }
        _G.Skada = { current = set }
        awards:GetSettings().saurfangThresholds = { [71] = 10000, [72] = 10000, [252] = 12500 }
        return set
    end
    local function individualEPGP()
        epgp.GetEPGP = function() return 1000, 100 end
        epgp.RegisterCallback = function(target, event, method)
            assert.equals('EPAward', event)
            epgp.target, epgp.method = target, method
        end
        epgp.IncEPBy = function(_, name, reason, amount)
            calls[#calls + 1] = { name, reason, amount }
            epgp.target[epgp.method](epgp.target, 'EPAward', name, reason, amount)
            return name
        end
    end

    it('snapshots configured specs from a completed victory and survives meter reset and changed settings', function()
        local set = winningSet()
        meters:SkadaSetComplete('Skada_SetComplete', set)
        local snapshot = addon.db.char.saurfangDPS
        assert.equals(4, #snapshot.players)
        assert.equals(1, snapshot.unknown)
        assert.equals('Unholy', snapshot.players[1].name)
        assert.equals(252, snapshot.players[1].spec)
        awards:GetSettings().saurfangThresholds[252] = 5000
        set.players[6].name = 'Changed'
        _G.Skada = nil
        assert.equals('Unholy', snapshot.players[1].name)
        assert.equals(12500, snapshot.players[1].threshold)
        now = at(28, 20, 0)
        awards:GetState()
        assert.equals(snapshot, addon.db.char.saurfangDPS)
    end)

    it('ignores live segments, wipes, unrelated bosses and additional phase segments', function()
        local set = winningSet()
        set.endtime = nil
        meters:SkadaSetComplete('COMBAT_BOSS_DEFEATED', set)
        assert.is_nil(addon.db.char.saurfangDPS)
        set.endtime, set.success = now, nil
        meters:SkadaSetComplete('Skada_SetComplete', set)
        assert.is_nil(addon.db.char.saurfangDPS)
        set.success, set.gotboss = true, 36597
        meters:SkadaSetComplete('Skada_SetComplete', set)
        assert.is_nil(addon.db.char.saurfangDPS)
        set.gotboss, Skada.current = 37813, {}
        meters:SkadaSetComplete('Skada_SetComplete', set)
        assert.is_nil(addon.db.char.saurfangDPS)
    end)

    it('accepts the actual death before Skada marks victory and a late bossmod victory after completion', function()
        local set = winningSet()
        set.success = nil
        addon.currentInstanceId = 631
        addon.modules.EPAwards = awards
        addon:DispatchCombatEvent({ event = 'UNIT_DIED', destGUID = '0xF1300093B5000001' })
        meters:SkadaSetComplete('Skada_SetComplete', set)
        assert.is_not_nil(addon.db.char.saurfangDPS)
        addon.db.char.saurfangDPS = nil
        Skada.current, Skada.last, set.success = nil, set, true
        meters:SkadaSetComplete('COMBAT_BOSS_DEFEATED', set)
        local saved = addon.db.char.saurfangDPS
        meters:SkadaSetComplete('COMBAT_BOSS_DEFEATED', set)
        assert.equals(saved, addon.db.char.saurfangDPS)
    end)

    it('registers the installed Skada completion callback and unregisters when disabled', function()
        installFrames()
        winningSet()
        local registered, unregistered
        Skada.RegisterCallback = function(target, event, method)
            registered = { target, event, method }
        end
        Skada.UnregisterCallback = function(target, event) unregistered = { target, event } end
        awards:OnEnable()
        assert.same({ meters, 'Skada_SetComplete', 'SkadaSetComplete' }, registered)
        awards:OnDisable()
        assert.same({ meters, 'Skada_SetComplete' }, unregistered)
    end)

    it('offers only players at or above threshold minus 100, checks them by default and awards selected players', function()
        local frames = installFrames()
        individualEPGP()
        meters:SkadaSetComplete('Skada_SetComplete', winningSet())
        awards:ToggleWindow()
        assert.is_true(awards.window:IsShown())
        awards.window.saurfangButton.scripts.OnClick()
        assert.is_false(awards.window:IsShown())
        local frame = awards.saurfangWindow
        assert.is_true(frame:IsShown())
        assert.equals(2, #frame.rows)
        assert.same({ Fury = true, Arms = true }, frame.selected)
        assert.equals('Fury', frame.rows[1].cells[1].text)
        assert.equals('Воин: Фури', frame.rows[1].cells[2].text)
        assert.equals('10000.0', frame.rows[1].cells[3].text)
        assert.equals('10000', frame.rows[1].cells[4].text)
        frame.rows[1].check:SetChecked(false)
        frame.rows[1].check.scripts.OnClick(frame.rows[1].check)
        awards:GetSettings().amounts.saurfang = 750
        frame.awardButton.scripts.OnClick()
        assert.same({ { 'Arms', 'RLHelper: ДПС Саурфанг', 750 } }, calls)
        assert.is_false(frame.rows[2].check:GetChecked())
        assert.equals(750, frame.rows[2].player.lastAward.amount)
        awards:ShowSaurfangWindow()
        assert.same({ Fury = true, Arms = true }, frame.selected)
        assert.is_truthy(frame.result.text:find('1', 1, true))
        for _, control in ipairs(frames) do
            if control.parent == frame and control.template == 'UIPanelCloseButton' then
                control.scripts.OnClick(control)
            end
        end
        assert.is_false(frame:IsShown())
        assert.is_false(awards.window:IsShown())
    end)

    it('shows empty results safely with no Skada, and never awards below the saved threshold', function()
        installFrames()
        individualEPGP()
        awards:ShowSaurfangWindow()
        assert.is_false(awards.saurfangWindow.awardButton.enabled)
        assert.is_false(awards:AwardSaurfang(nil, {}))
        meters:SkadaSetComplete('Skada_SetComplete', winningSet())
        assert.is_false(awards:AwardSaurfang(addon.db.char.saurfangDPS, { Below = true, Unholy = true }))
        assert.equals(0, #calls)
    end)

    it('validates every recipient before writing and retains confirmed partial awards', function()
        individualEPGP()
        meters:SkadaSetComplete('Skada_SetComplete', winningSet())
        local snapshot = addon.db.char.saurfangDPS
        local selected = { Fury = true, Arms = true }
        epgp.GetEPGP = function(_, name) if name == 'Fury' then return 1000, 100 end end
        assert.is_false(awards:AwardSaurfang(snapshot, selected))
        assert.equals(0, #calls)
        epgp.GetEPGP = function() return 1000, 100 end
        local inc = epgp.IncEPBy
        epgp.IncEPBy = function(self, name, reason, amount)
            if name == 'Arms' then error('write failed') end
            return inc(self, name, reason, amount)
        end
        assert.is_false(awards:AwardSaurfang(snapshot, selected))
        assert.is_false(selected.Fury)
        assert.is_true(selected.Arms)
        assert.equals(1, #calls)
        assert.is_nil(awards.pendingIndividual)
    end)

    it('requires EPGP confirmation, permissions, positive amounts and distinct mains', function()
        individualEPGP()
        meters:SkadaSetComplete('Skada_SetComplete', winningSet())
        local snapshot = addon.db.char.saurfangDPS
        local selected = { Fury = true, Arms = true }
        epgp.CanIncEPBy = function() return false end
        assert.is_false(awards:AwardSaurfang(snapshot, selected))
        epgp.CanIncEPBy = function() return true end
        awards:GetSettings().amounts.saurfang = 0
        assert.is_false(awards:AwardSaurfang(snapshot, selected))
        awards:GetSettings().amounts.saurfang = nil
        epgp.GetEPGP = function() return 1000, 100, 'Main' end
        assert.is_false(awards:AwardSaurfang(snapshot, selected))
        epgp.GetEPGP = function() return 1000, 100 end
        epgp.IncEPBy = function() return 'Fury' end
        assert.is_false(awards:AwardSaurfang(snapshot, selected))
        assert.is_true(selected.Fury)
        assert.equals(0, #calls)
    end)

    it('initializes and persists independent spec thresholds and the 500 EP default', function()
        local frames = installFrames()
        awards:CreateSettings({}, {})
        local inputs = {}
        for _, frame in ipairs(frames) do if frame.kind == 'EditBox' then inputs[frame.name] = frame end end
        assert.equals('500', inputs.RLHelperEPAwardsaurfangEditBox.text)
        local fury = inputs.RLHelperEPAwardSpec72EditBox
        local arms = inputs.RLHelperEPAwardSpec71EditBox
        assert.equals('21000', fury.text)
        fury:SetText('10000')
        fury.scripts.OnEnterPressed()
        assert.equals(10000, awards:GetSettings().saurfangThresholds[72])
        assert.equals('20000', arms.text)
        for _, invalid in ipairs({ '-1', '1.5', 'abc', '1000000' }) do
            fury:SetText(invalid)
            fury.scripts.OnEnterPressed()
            assert.equals('10000', fury.text)
        end
        awards.options.scripts.OnShow()
        assert.equals('10000', fury.text)
        fury:SetText('0')
        fury.scripts.OnEnterPressed()
        assert.equals(0, awards:GetThreshold(72))
    end)

    it('uses all screenshot defaults without overriding custom or disabled specs', function()
        local expected = { [71] = 20000, [72] = 21000, [63] = 21000, [62] = 21000,
            [252] = 19000, [251] = 20000, [260] = 20000, [259] = 18000,
            [265] = 18000, [266] = 17000, [267] = 17000, [258] = 18000,
            [70] = 20000, [262] = 18000, [263] = 18000 }
        for spec, threshold in pairs(expected) do assert.equals(threshold, awards:GetThreshold(spec)) end
        assert.is_nil(awards:GetThreshold(253))
        awards:GetSettings().saurfangThresholds[72] = 23000
        awards:GetSettings().saurfangThresholds[71] = 0
        assert.equals(23000, awards:GetThreshold(72))
        assert.equals(0, awards:GetThreshold(71))
        local set = winningSet()
        awards:GetSettings().saurfangThresholds = { [71] = 0 }
        meters:SkadaSetComplete('Skada_SetComplete', set)
        for _, player in ipairs(addon.db.char.saurfangDPS.players) do
            assert.is_not.equal(71, player.spec)
            assert.equals(expected[player.spec], player.threshold)
        end
    end)

    it('adjusts all award thresholds by 500 without changing settings or the snapshot', function()
        installFrames()
        individualEPGP()
        meters:SkadaSetComplete('Skada_SetComplete', winningSet())
        local snapshot = addon.db.char.saurfangDPS
        awards:ShowSaurfangWindow()
        local frame = awards.saurfangWindow
        frame.rows[1].check:SetChecked(false)
        frame.rows[1].check.scripts.OnClick(frame.rows[1].check)
        frame.minusButton.scripts.OnClick()
        assert.equals(-500, frame.offset)
        assert.same({ Fury = false, Arms = true, Below = true, Unholy = true }, frame.selected)
        assert.equals('12000', frame.rows[1].cells[4].text)
        assert.equals('9500', frame.rows[2].cells[4].text)
        assert.is_false(frame.rows[2].check:GetChecked())
        assert.equals(12500, snapshot.players[1].threshold)
        assert.equals(12500, awards:GetSettings().saurfangThresholds[252])
        frame.awardButton.scripts.OnClick()
        assert.same({ { 'Unholy', 'RLHelper: ДПС Саурфанг', 500 },
            { 'Arms', 'RLHelper: ДПС Саурфанг', 500 }, { 'Below', 'RLHelper: ДПС Саурфанг', 500 } }, calls)
        frame.plusButton.scripts.OnClick()
        assert.equals(0, frame.offset)
        assert.is_false(frame.rows[1].check:GetChecked())
        assert.is_false(frame.rows[2].check:GetChecked())
        awards:ShowSaurfangWindow()
        assert.equals(0, frame.offset)
        assert.same({ Fury = true, Arms = true }, frame.selected)
    end)

    it('excludes previously selected players when raised and clamps displayed thresholds at zero', function()
        installFrames()
        individualEPGP()
        meters:SkadaSetComplete('Skada_SetComplete', winningSet())
        awards:ShowSaurfangWindow()
        local frame = awards.saurfangWindow
        frame.plusButton.scripts.OnClick()
        assert.is_false(frame.awardButton.enabled)
        assert.is_false(awards:AwardSaurfang(frame.snapshot, frame.selected, frame.offset))
        assert.equals(0, #calls)
        for i = 1, 30 do frame.minusButton.scripts.OnClick() end
        assert.equals('0', frame.rows[1].cells[4].text)
        assert.equals('0', frame.rows[2].cells[4].text)
        assert.is_true(frame.awardButton.enabled)
    end)

    it('restores serialized DPS data after relog and awards later without Skada', function()
        installFrames()
        individualEPGP()
        meters:SkadaSetComplete('Skada_SetComplete', winningSet())
        -- SavedVariables retain plain data, not functions or the original table identities.
        local function serialize(value)
            if type(value) == 'table' then
                local fields = {}
                for key, item in pairs(value) do
                    fields[#fields + 1] = '[' .. serialize(key) .. ']=' .. serialize(item)
                end
                return '{' .. table.concat(fields, ',') .. '}'
            elseif type(value) == 'string' then
                return string.format('%q', value)
            end
            assert.is_true(type(value) == 'number' or type(value) == 'boolean')
            return tostring(value)
        end
        local saved = serialize(addon.db.char)
        local originalSnapshot = addon.db.char.saurfangDPS
        addon.db.char = assert(loadstring('return ' .. saved))()
        assert.is_not.equal(originalSnapshot, addon.db.char.saurfangDPS)
        assert.same(originalSnapshot, addon.db.char.saurfangDPS)
        _G.Skada = nil
        awards.active = nil
        awards.saurfangWindow = nil
        awards.individualCallbackSource, awards.pendingIndividual = nil, nil
        now = at(28, 20, 0)
        awards:GetState()
        awards:ShowSaurfangWindow()
        local frame = awards.saurfangWindow
        assert.same({ Fury = true, Arms = true }, frame.selected)
        assert.equals('10000.0', frame.rows[1].cells[3].text)
        assert.equals('10000', frame.rows[1].cells[4].text)
        frame.awardButton.scripts.OnClick()
        assert.same({ { 'Fury', 'RLHelper: ДПС Саурфанг', 500 },
            { 'Arms', 'RLHelper: ДПС Саурфанг', 500 } }, calls)
    end)

    it('disables all EP activity through the shared GP switch and resumes without reload', function()
        installFrames()
        individualEPGP()
        local set = winningSet()
        local registered, unregistered = 0, 0
        Skada.RegisterCallback = function() registered = registered + 1 end
        Skada.UnregisterCallback = function() unregistered = unregistered + 1 end
        addon.mainFrame = { buttonContainer = {}, discordButton = {} }
        addon.modules.EPAwards = awards
        awards:OnEnable()
        meters:SkadaSetComplete('Skada_SetComplete', set)
        local saved = addon.db.char.saurfangDPS
        awards:ToggleWindow()
        awards:ShowSaurfangWindow()
        awards.ShowReminder = original.show
        awards:ShowReminder('attendance')
        assert.is_true(awards.popups.attendance:IsShown())
        addon.db.profile.gpAwardButtonsEnabled = false
        addon:RefreshGPAwardButtons()
        assert.is_false(awards.button:IsShown())
        assert.is_false(awards.window:IsShown())
        assert.is_false(awards.saurfangWindow:IsShown())
        assert.is_false(awards.popups.attendance:IsShown())
        assert.is_nil(awards.clock.scripts.OnUpdate)
        assert.equals(1, unregistered)
        set.starttime = set.starttime + 1
        set.players[1].GetDPS = function() error('disabled DPS must not be read') end
        meters:SkadaSetComplete('COMBAT_BOSS_DEFEATED', set)
        awards:CheckTime()
        awards:Suggest('attendance')
        awards:ShowReminder('attendance')
        awards:ToggleWindow()
        awards:ShowSaurfangWindow()
        addon.currentInstanceId = 631
        addon:DispatchCombatEvent({ event = 'UNIT_DIED', destGUID = '0xF1300093B5000001' })
        assert.is_nil(meters.killed)
        assert.equals(saved, addon.db.char.saurfangDPS)
        assert.is_false(awards:Award('attendance'))
        assert.is_false(awards:AwardSaurfang(saved, { Fury = true }))
        assert.is_false(awards.window:IsShown())
        assert.is_false(awards.saurfangWindow:IsShown())
        assert.is_false(awards.popups.attendance:IsShown())
        assert.equals(0, #calls)
        addon.db.profile.gpAwardButtonsEnabled = true
        addon:RefreshGPAwardButtons()
        addon:RefreshGPAwardButtons()
        assert.equals(2, registered)
        assert.is_true(awards.button:IsShown())
        assert.is_not_nil(awards.clock.scripts.OnUpdate)
        awards:ShowSaurfangWindow()
        assert.is_true(awards.saurfangWindow:IsShown())
        assert.equals(saved, awards.saurfangWindow.snapshot)
    end)

    it('starts silently with the shared feature disabled', function()
        installFrames()
        addon.db.profile.gpAwardButtonsEnabled = false
        addon.mainFrame = { buttonContainer = {}, discordButton = {} }
        awards:OnEnable()
        awards:AttachButton()
        awards:CheckTime()
        assert.is_nil(awards.button)
        assert.is_nil(awards.clock)
        assert.is_nil(addon.db.char.epAwards)
        assert.equals(0, #shown)
    end)

end)
