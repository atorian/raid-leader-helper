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
            skada = _G.Skada, main = addon.mainFrame, themeButtons = addon.themeButtons, print = addon.Print, metadata = GetAddOnMetadata }
        now = at(27, 19, 0)
        _G.time = function(value) return value and os.time(value) or now end
        _G.date = function(format, value) return os.date(format, value or now) end
        _G.IsRaidLeader = function() return true end
        _G.GetNumRaidMembers = function() return 25 end
        addon.db = { profile = { gpAwardButtonsEnabled = true }, char = {} }
        local settings = awards:GetSettings()
        settings.amounts = { attendance = 1000, icc = 2000, rs = 1500 }
        shown, calls = {}, {}
        _G.GetAddOnMetadata = function(name, key)
            return name == "Skada" and key == "Version" and "1.8.78" or nil
        end
        _G.Skada = { actorPrototype = { GetDPS = function() end },
            RegisterCallback = function() end, UnregisterCallback = function() end }
        meters:Stop()
        awards.active = nil
        awards.dpsWindow = nil
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
        _G.Skada, _G.GetAddOnMetadata = original.skada, original.metadata
        awards.active = nil
        awards.dpsWindow = nil
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

    it('shows incompatible sources in red and requirements below the selector', function()
        local frames = installFrames()
        awards:CreateSettings({}, {})
        local dropdown
        for _, frame in ipairs(frames) do
            if frame.name == 'RLHelperDPSSourceDropdown' then dropdown = frame end
        end
        assert.equals('Skada', awards:GetSettings().dpsSource)
        assert.equals('Skada', dropdown.text)
        local addButton, choices = UIDropDownMenu_AddButton, {}
        _G.UIDropDownMenu_AddButton = function(info) choices[#choices + 1] = info end
        dropdown.initialize()
        _G.UIDropDownMenu_AddButton = addButton
        assert.equals(3, #choices)
        assert.equals('Details', choices[1].value)
        assert.equals('Skada', choices[2].value)
        assert.equals('Recount', choices[3].value)
        assert.is_true(choices[2].checked)
        assert.is_true(choices[1].disabled)
        assert.equals('|cffff3333Details|r', choices[1].text)
        assert.is_false(choices[2].disabled)
        assert.is_truthy(awards.options.sourceHelp.text:find('Skada: 1.8.73 (r361)', 1, true))
        assert.is_truthy(awards.options.sourceHelp.text:find('Recount: r1127', 1, true))
        assert.is_true(16 + awards.options.sourceHelp.width <= 375 - 10)
        _G.Skada = nil
        awards:GetSettings().dpsSource = 'Skada'
        awards:OnEnable()
        assert.equals('ErrorDPSCounter', awards:GetSettings().dpsSource)
        awards.options.scripts.OnShow()
        assert.equals('|cffff3333Нет источника DPS|r', dropdown.text)
    end)

    it('sizes the source row and help from the live scroll viewport width', function()
        local frames = installFrames()
        local viewport = { GetWidth = function() return 345 end }
        awards:CreateSettings({ GetParent = function() return viewport end }, {})
        local dropdown
        for _, frame in ipairs(frames) do
            if frame.name == 'RLHelperDPSSourceDropdown' then dropdown = frame end
        end
        assert.equals(16 + 134 + dropdown.dropdownWidth + 50, 345 - 10)
        assert.equals(345 - 16 - 10, awards.options.sourceHelp.width)
    end)

    it('uses a visible width before the category opens and remeasures on show', function()
        local frames = installFrames()
        local width = 0
        local viewport = { GetWidth = function() return width end }
        awards:CreateSettings({ GetParent = function() return viewport end }, {})
        local dropdown
        for _, frame in ipairs(frames) do
            if frame.name == 'RLHelperDPSSourceDropdown' then dropdown = frame end
        end
        assert.equals(165, dropdown.dropdownWidth)
        assert.equals(349, awards.options.sourceHelp.width)
        width = 375
        awards.options.scripts.OnShow()
        assert.equals(165, dropdown.dropdownWidth)
        width = 345
        awards.options.scripts.OnShow()
        assert.equals(135, dropdown.dropdownWidth)
        assert.equals(319, awards.options.sourceHelp.width)
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
        assert.equals(38, count)
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
        _G.Skada = { current = set, actorPrototype = { GetDPS = function() end },
            RegisterCallback = function() end, UnregisterCallback = function() end }
        awards:GetSettings().dpsBosses[37813] = { [71] = 10000, [72] = 10000, [252] = 12500 }
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
        local snapshot = awards:GetDPSResults()[37813]
        assert.equals(4, #snapshot.players)
        assert.equals(1, snapshot.unknown)
        assert.equals('Unholy', snapshot.players[1].name)
        assert.equals(252, snapshot.players[1].spec)
        awards:GetSettings().dpsBosses[37813][252] = 5000
        set.players[6].name = 'Changed'
        _G.Skada = nil
        assert.equals('Unholy', snapshot.players[1].name)
        assert.equals(12500, snapshot.players[1].threshold)
        now = at(28, 20, 0)
        awards:GetState()
        assert.equals(snapshot, awards:GetDPSResults()[37813])
    end)

    it('ignores live segments, wipes, unrelated bosses and additional phase segments', function()
        local set = winningSet()
        set.endtime = nil
        meters:SkadaSetComplete('COMBAT_BOSS_DEFEATED', set)
        assert.is_nil(awards:GetDPSResults()[37813])
        set.endtime, set.success = now, nil
        meters:SkadaSetComplete('Skada_SetComplete', set)
        assert.is_nil(awards:GetDPSResults()[37813])
        set.success, set.gotboss = true, 36597
        meters:SkadaSetComplete('Skada_SetComplete', set)
        assert.is_nil(awards:GetDPSResults()[37813])
        set.gotboss, Skada.current = 37813, {}
        meters:SkadaSetComplete('Skada_SetComplete', set)
        assert.is_nil(awards:GetDPSResults()[37813])
    end)

    it('accepts the actual death before Skada marks victory and a late bossmod victory after completion', function()
        local set = winningSet()
        set.success = nil
        addon.currentInstanceId = 631
        addon.modules.EPAwards = awards
        addon:DispatchCombatEvent({ event = 'UNIT_DIED', destGUID = '0xF1300093B5000001' })
        meters:SkadaSetComplete('Skada_SetComplete', set)
        assert.is_not_nil(awards:GetDPSResults()[37813])
        awards:GetDPSResults()[37813] = nil
        Skada.current, Skada.last, set.success = nil, set, true
        meters:SkadaSetComplete('COMBAT_BOSS_DEFEATED', set)
        local saved = awards:GetDPSResults()[37813]
        meters:SkadaSetComplete('COMBAT_BOSS_DEFEATED', set)
        assert.equals(saved, awards:GetDPSResults()[37813])
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
        awards.window.dpsButton.scripts.OnClick()
        assert.is_false(awards.window:IsShown())
        local frame = awards.dpsWindow
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
        awards:ShowDPSWindow()
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
        awards:ShowDPSWindow()
        assert.is_false(awards.dpsWindow.awardButton.enabled)
        assert.is_false(awards:AwardDPS(nil, {}))
        meters:SkadaSetComplete('Skada_SetComplete', winningSet())
        assert.is_false(awards:AwardDPS(awards:GetDPSResults()[37813], { Below = true, Unholy = true }))
        assert.equals(0, #calls)
    end)

    it('validates every recipient before writing and retains confirmed partial awards', function()
        individualEPGP()
        meters:SkadaSetComplete('Skada_SetComplete', winningSet())
        local snapshot = awards:GetDPSResults()[37813]
        local selected = { Fury = true, Arms = true }
        epgp.GetEPGP = function(_, name) if name == 'Fury' then return 1000, 100 end end
        assert.is_false(awards:AwardDPS(snapshot, selected))
        assert.equals(0, #calls)
        epgp.GetEPGP = function() return 1000, 100 end
        local inc = epgp.IncEPBy
        epgp.IncEPBy = function(self, name, reason, amount)
            if name == 'Arms' then error('write failed') end
            return inc(self, name, reason, amount)
        end
        assert.is_false(awards:AwardDPS(snapshot, selected))
        assert.is_false(selected.Fury)
        assert.is_true(selected.Arms)
        assert.equals(1, #calls)
        assert.is_nil(awards.pendingIndividual)
    end)

    it('requires EPGP confirmation, permissions, positive amounts and distinct mains', function()
        individualEPGP()
        meters:SkadaSetComplete('Skada_SetComplete', winningSet())
        local snapshot = awards:GetDPSResults()[37813]
        local selected = { Fury = true, Arms = true }
        epgp.CanIncEPBy = function() return false end
        assert.is_false(awards:AwardDPS(snapshot, selected))
        epgp.CanIncEPBy = function() return true end
        awards:GetSettings().amounts.saurfang = 0
        assert.is_false(awards:AwardDPS(snapshot, selected))
        awards:GetSettings().amounts.saurfang = nil
        epgp.GetEPGP = function() return 1000, 100, 'Main' end
        assert.is_false(awards:AwardDPS(snapshot, selected))
        epgp.GetEPGP = function() return 1000, 100 end
        epgp.IncEPBy = function() return 'Fury' end
        assert.is_false(awards:AwardDPS(snapshot, selected))
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
        assert.equals(10000, awards:GetSettings().dpsBosses[37813][72])
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
        awards:GetSettings().dpsBosses[37813][72] = 23000
        awards:GetSettings().dpsBosses[37813][71] = 0
        assert.equals(23000, awards:GetThreshold(72))
        assert.equals(0, awards:GetThreshold(71))
        local set = winningSet()
        awards:GetSettings().dpsBosses[37813] = { [71] = 0 }
        meters:SkadaSetComplete('Skada_SetComplete', set)
        for _, player in ipairs(awards:GetDPSResults()[37813].players) do
            assert.is_not.equal(71, player.spec)
            assert.equals(expected[player.spec], player.threshold)
        end
    end)

    it('adjusts all award thresholds by 500 without changing settings or the snapshot', function()
        installFrames()
        individualEPGP()
        meters:SkadaSetComplete('Skada_SetComplete', winningSet())
        local snapshot = awards:GetDPSResults()[37813]
        awards:ShowDPSWindow()
        local frame = awards.dpsWindow
        frame.rows[1].check:SetChecked(false)
        frame.rows[1].check.scripts.OnClick(frame.rows[1].check)
        frame.minusButton.scripts.OnClick()
        assert.equals(-500, frame.offset)
        assert.same({ Fury = false, Arms = true, Below = true, Unholy = true }, frame.selected)
        assert.equals('12000', frame.rows[1].cells[4].text)
        assert.equals('9500', frame.rows[2].cells[4].text)
        assert.is_false(frame.rows[2].check:GetChecked())
        assert.equals(12500, snapshot.players[1].threshold)
        assert.equals(12500, awards:GetSettings().dpsBosses[37813][252])
        frame.awardButton.scripts.OnClick()
        assert.same({ { 'Unholy', 'RLHelper: ДПС Саурфанг', 500 },
            { 'Arms', 'RLHelper: ДПС Саурфанг', 500 }, { 'Below', 'RLHelper: ДПС Саурфанг', 500 } }, calls)
        frame.plusButton.scripts.OnClick()
        assert.equals(0, frame.offset)
        assert.is_false(frame.rows[1].check:GetChecked())
        assert.is_false(frame.rows[2].check:GetChecked())
        awards:ShowDPSWindow()
        assert.equals(0, frame.offset)
        assert.same({ Fury = true, Arms = true }, frame.selected)
    end)

    it('excludes previously selected players when raised and clamps displayed thresholds at zero', function()
        installFrames()
        individualEPGP()
        meters:SkadaSetComplete('Skada_SetComplete', winningSet())
        awards:ShowDPSWindow()
        local frame = awards.dpsWindow
        frame.plusButton.scripts.OnClick()
        assert.is_false(frame.awardButton.enabled)
        assert.is_false(awards:AwardDPS(frame.snapshot, frame.selected, frame.offset))
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
        local originalSnapshot = awards:GetDPSResults()[37813]
        addon.db.char = assert(loadstring('return ' .. saved))()
        assert.is_not.equal(originalSnapshot, awards:GetDPSResults()[37813])
        assert.same(originalSnapshot, awards:GetDPSResults()[37813])
        _G.Skada = nil
        awards.active = nil
        awards.dpsWindow = nil
        awards.individualCallbackSource, awards.pendingIndividual = nil, nil
        now = at(28, 20, 0)
        awards:GetState()
        awards:ShowDPSWindow()
        local frame = awards.dpsWindow
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
        local saved = awards:GetDPSResults()[37813]
        awards:ToggleWindow()
        awards:ShowDPSWindow()
        awards.ShowReminder = original.show
        awards:ShowReminder('attendance')
        assert.is_true(awards.popups.attendance:IsShown())
        addon.db.profile.gpAwardButtonsEnabled = false
        addon:RefreshGPAwardButtons()
        assert.is_false(awards.button:IsShown())
        assert.is_false(awards.window:IsShown())
        assert.is_false(awards.dpsWindow:IsShown())
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
        awards:ShowDPSWindow()
        addon.currentInstanceId = 631
        addon:DispatchCombatEvent({ event = 'UNIT_DIED', destGUID = '0xF1300093B5000001' })
        assert.is_nil(meters.killed)
        assert.equals(saved, awards:GetDPSResults()[37813])
        assert.is_false(awards:Award('attendance'))
        assert.is_false(awards:AwardDPS(saved, { Fury = true }))
        assert.is_false(awards.window:IsShown())
        assert.is_false(awards.dpsWindow:IsShown())
        assert.is_false(awards.popups.attendance:IsShown())
        assert.equals(0, #calls)
        addon.db.profile.gpAwardButtonsEnabled = true
        addon:RefreshGPAwardButtons()
        addon:RefreshGPAwardButtons()
        assert.equals(2, registered)
        assert.is_true(awards.button:IsShown())
        assert.is_not_nil(awards.clock.scripts.OnUpdate)
        awards:ShowDPSWindow()
        assert.is_true(awards.dpsWindow:IsShown())
        assert.equals(saved, awards.dpsWindow.snapshot)
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

    local function choices(dropdown)
        local originalAdd, result = UIDropDownMenu_AddButton, {}
        _G.UIDropDownMenu_AddButton = function(info) result[#result + 1] = info end
        dropdown.initialize()
        _G.UIDropDownMenu_AddButton = originalAdd
        return result
    end

    local function putricideFight()
        awards:AddDPSBoss(36678)
        local settings = awards:GetSettings()
        settings.putricideMode = 'ooze'
        settings.dpsBosses[36678] = { [72] = 999999 }
        local fight = { source = 'Skada', boss = 36678, starttime = now - 180, endtime = now,
            players = { { name = 'All', class = 'WARRIOR', spec = 72, dps = 1 },
                { name = 'Uneven', class = 'WARRIOR', spec = 72, dps = 9999999 },
                { name = 'Skipped', class = 'WARRIOR', spec = 72, dps = 9999999 },
                { name = 'NoSpec', class = 'HUNTER' } }, oozeDamage = {} }
        for i = 1, 4 do
            local npc = i % 2 == 0 and 37562 or 37697
            fight.oozeDamage[string.format('0xF130%06X%06X', npc, i)] = {
                All = 100000, Uneven = i == 4 and 99999 or 200000,
                Skipped = i == 4 and nil or 200000, NoSpec = 100000 }
        end
        fight.oozeDamage['0xF1300092BA000004'].Skipped = nil
        return fight
    end

    it('requires total ooze damage, regardless of its distribution, class, spec or boss DPS', function()
        installFrames()
        individualEPGP()
        awards:DPSFightComplete(putricideFight())
        local snapshot = awards:GetDPSResults()[36678]
        assert.equals('ooze', snapshot.mode)
        assert.equals(100000, snapshot.oozeThreshold)
        assert.equals(4, snapshot.oozeCount)
        local players = {}
        for _, player in ipairs(snapshot.players) do players[player.name] = player end
        assert.equals(400000, players.All.oozeTotal)
        assert.equals(699999, players.Uneven.oozeTotal)
        assert.equals(600000, players.Skipped.oozeTotal)
        awards:ShowDPSWindow(36678)
        assert.same({ All = true, NoSpec = true, Uneven = true, Skipped = true }, awards.dpsWindow.selected)
        assert.equals('Общий урон', awards.dpsWindow.valueHeader.text)
        assert.is_false(awards.dpsWindow.plusButton:IsShown())
        assert.is_true(awards:AwardDPS(snapshot, { All = true, NoSpec = true, Uneven = true, Skipped = true }, -999999))
        assert.equals(4, #calls)
        local names = {}
        for _, call in ipairs(calls) do names[call[1]] = call[3] end
        assert.same({ All = 500, NoSpec = 500, Uneven = 500, Skipped = 500 }, names)
    end)

    it('freezes the chosen ooze condition, threshold and per-spawn damage for later awards', function()
        installFrames()
        individualEPGP()
        local fight = putricideFight()
        awards:GetSettings().putricideOozeDamage = 120000
        awards:DPSFightComplete(fight)
        local snapshot = awards:GetDPSResults()[36678]
        assert.equals(120000, snapshot.oozeThreshold)
        awards:GetSettings().putricideMode = 'boss'
        awards:GetSettings().putricideOozeDamage = 1
        for _, damage in pairs(fight.oozeDamage) do damage.All = 999999 end
        local players = {}
        for _, player in ipairs(snapshot.players) do players[player.name] = player end
        assert.equals(400000, players.All.oozeTotal)
        _G.Skada = nil
        now = at(28, 20, 0)
        awards:GetState()
        awards:ShowDPSWindow(36678)
        assert.equals('Урон на призыв: 120000. Цель газа: -100000.', awards.dpsWindow.adjustment.text)
        assert.is_false(awards:AwardDPS(snapshot, { All = true }, -999999))
        assert.equals(0, #calls)
    end)

    it('reduces each player total threshold by 100000 per gas targeting and shows it in the row', function()
        installFrames()
        individualEPGP()
        local fight = putricideFight()
        fight.gasTargets = { All = 1, NoSpec = 1, Skipped = 2 }
        for _, damage in pairs(fight.oozeDamage) do
            damage.All, damage.NoSpec = 75000, 75000
        end
        fight.oozeDamage['0xF1300092BA000004'].NoSpec = 74999
        awards:DPSFightComplete(fight)
        local snapshot = awards:GetDPSResults()[36678]
        fight.gasTargets.All = 99
        awards:GetSettings().putricideOozeDamage = 999999
        _G.Skada = nil
        awards:ShowDPSWindow(36678)
        assert.same({ All = true, Uneven = true, Skipped = true }, awards.dpsWindow.selected)
        local rows = {}
        for _, row in ipairs(awards.dpsWindow.rows) do rows[row.player.name] = row end
        assert.equals('300000', rows.All.cells[3].text)
        assert.equals('300000', rows.All.cells[4].text)
        assert.equals('400000', rows.Uneven.cells[4].text)
        assert.equals('200000', rows.Skipped.cells[4].text)
        assert.equals(1, rows.All.player.gasTargets)
        assert.is_false(awards:AwardDPS(snapshot, { NoSpec = true }))
        assert.is_true(awards:AwardDPS(snapshot, { All = true }))
        assert.equals(1, #calls)
    end)

    it('clamps gas reductions at zero without enabling disabled or unobserved ooze awards', function()
        installFrames()
        individualEPGP()
        local fight = putricideFight()
        fight.gasTargets = { All = 5 }
        for _, damage in pairs(fight.oozeDamage) do damage.All = 0 end
        awards:DPSFightComplete(fight)
        awards:ShowDPSWindow(36678)
        local row
        for _, candidate in ipairs(awards.dpsWindow.rows) do
            if candidate.player.name == 'All' then row = candidate end
        end
        assert.equals('0', row.cells[4].text)
        assert.is_true(awards:AwardDPS(awards:GetDPSResults()[36678], { All = true }))
        for _, disabled in ipairs({ false, true }) do
            awards:GetDPSResults()[36678] = nil
            if disabled then awards:GetSettings().putricideOozeDamage = 0 else fight.oozeDamage = nil end
            awards:DPSFightComplete(fight)
            assert.is_false(awards:AwardDPS(awards:GetDPSResults()[36678], { All = true }))
        end
        assert.equals(1, #calls)
    end)

    it('shows total damage from saved per-ooze results that predate gas target tracking', function()
        installFrames()
        local snapshot = { boss = 36678, source = 'Skada', mode = 'ooze', oozeCount = 4,
            oozeThreshold = 100000, endtime = now, players = { { name = 'Old', class = 'HUNTER',
                oozeMin = 0, oozeDamage = { a = 400000, b = 0, c = 0, d = 0 } } } }
        awards:GetDPSResults()[36678] = snapshot
        awards:ShowDPSWindow(36678)
        assert.equals('400000', awards.dpsWindow.rows[1].cells[3].text)
        assert.equals('400000', awards.dpsWindow.rows[1].cells[4].text)
    end)

    it('never qualifies an ooze award with missing data or a disabled damage threshold', function()
        individualEPGP()
        for _, disabled in ipairs({ false, true }) do
            local fight = putricideFight()
            if disabled then awards:GetSettings().putricideOozeDamage = 0 else fight.oozeDamage = nil end
            awards:GetDPSResults()[36678] = nil
            awards:DPSFightComplete(fight)
            assert.is_false(awards:AwardDPS(awards:GetDPSResults()[36678], { All = true }))
        end
        assert.equals(0, #calls)
    end)

    it('uses the existing spec DPS rule when the RL selects boss mode', function()
        installFrames()
        individualEPGP()
        local fight = putricideFight()
        awards:GetSettings().putricideMode = 'boss'
        awards:GetSettings().dpsBosses[36678][72] = 10000
        awards:DPSFightComplete(fight)
        local snapshot = awards:GetDPSResults()[36678]
        assert.is_nil(snapshot.mode)
        awards:ShowDPSWindow(36678)
        assert.same({ Uneven = true, Skipped = true }, awards.dpsWindow.selected)
        assert.equals('DPS', awards.dpsWindow.valueHeader.text)
        assert.is_true(awards.dpsWindow.plusButton:IsShown())
        assert.is_true(awards:AwardDPS(snapshot, { All = true, NoSpec = true, Uneven = true }))
        assert.equals(1, #calls)
        assert.equals('Uneven', calls[1][1])
    end)

    it('edits one common ooze threshold and preserves boss spec thresholds when changing modes', function()
        local frames = installFrames()
        awards:AddDPSBoss(36678)
        awards:GetSettings().dpsBosses[36678][72] = 22222
        awards:CreateSettings({}, {})
        local named = {}
        for _, f in ipairs(frames) do if f.name then named[f.name] = f end end
        local mode, damage, fury = named.RLHelperPutricideModeDropdown,
            named.RLHelperEPAwardPutricideOozeDamageEditBox, named.RLHelperEPAwardSpec72EditBox
        assert.is_false(mode:IsShown())
        assert.is_false(damage:IsShown())
        for _, choice in ipairs(choices(named.RLHelperDPSBossDropdown)) do
            if choice.text:find('Мерзоцид', 1, true) then choice.func(); break end
        end
        assert.is_true(mode:IsShown())
        assert.is_true(fury:IsShown())
        assert.is_false(damage:IsShown())
        choices(mode)[2].func()
        assert.is_false(fury:IsShown())
        assert.is_true(damage:IsShown())
        assert.equals('100000', damage:GetText())
        assert.equals(22222, awards:GetThreshold(72, 36678))
        damage:SetText('125000'); damage.scripts.OnEnterPressed()
        for _, bad in ipairs({ '-1', '1.5', '1000000', 'abc' }) do
            damage:SetText(bad); damage.scripts.OnEnterPressed()
            assert.equals('125000', damage:GetText())
        end
        awards.options.scripts.OnShow()
        assert.equals('125000', damage:GetText())
        choices(mode)[1].func()
        assert.is_true(fury:IsShown())
        assert.is_false(damage:IsShown())
        assert.equals('22222', fury:GetText())
        assert.equals(125000, awards:GetOozeThreshold())
    end)

    it('migrates Saurfang thresholds and a saved award without changing custom or disabled specs', function()
        addon.db.profile.epAwards = { rt = '19:00', amounts = { saurfang = 750 }, reminders = {},
            saurfangThresholds = { [71] = 0, [72] = 12345 } }
        local snapshot = { players = { { name = 'Fury', threshold = 12000, lastAward = { amount = 500 } } } }
        addon.db.char.saurfangDPS = snapshot
        assert.equals(0, awards:GetThreshold(71))
        assert.equals(12345, awards:GetThreshold(72))
        assert.equals(21000, awards:GetThreshold(63))
        assert.equals(750, awards:GetAmount('saurfang'))
        assert.is_nil(awards:GetSettings().saurfangThresholds)
        assert.equals(snapshot, awards:GetDPSResults()[37813])
        assert.equals(37813, snapshot.boss)
        assert.equals(500, snapshot.players[1].lastAward.amount)
        assert.is_nil(addon.db.char.saurfangDPS)
    end)

    it('lists every encounter once and supports configuring every boss without a fixed slot limit', function()
        local counts, seen = {}, {}
        for _, encounter in ipairs(RLHelperBossIds.DPS_ENCOUNTERS) do
            counts[encounter.raid] = (counts[encounter.raid] or 0) + 1
            assert.is_nil(seen[encounter.name])
            seen[encounter.name] = true
            assert.is_true(awards:AddDPSBoss(encounter.id))
        end
        assert.same({ ['ЦЛК'] = 12, ['РС'] = 4, ['ИВК'] = 5 }, counts)
        local count = 0
        for _ in pairs(awards:GetSettings().dpsBosses) do count = count + 1 end
        assert.equals(21, count)
        assert.is_false(awards:AddDPSBoss(999999))
        assert.is_false(awards:AddDPSBoss(40142)) -- Alternate Halion NPC, same encounter.
    end)

    it('adds, edits and removes per-spec boss settings through the dropdowns and survives reopening', function()
        local frames = installFrames()
        awards:CreateSettings({}, {})
        local named, add, remove = {}
        for _, f in ipairs(frames) do
            if f.name then named[f.name] = f end
            if f.text == 'Добавить' then add = f end
            if f.text == 'Удалить' then remove = f end
        end
        local function choose(dropdown, label)
            for _, choice in ipairs(choices(dropdown)) do
                if choice.text:find(label, 1, true) then choice.func(); return end
            end
            error('Missing choice: ' .. label)
        end
        choose(named.RLHelperDPSRaidDropdown, 'РС')
        assert.equals(4, #choices(named.RLHelperDPSBossDropdown))
        choose(named.RLHelperDPSBossDropdown, 'Халион')
        local fury = named.RLHelperEPAwardSpec72EditBox
        assert.is_false(fury:IsShown())
        add.scripts.OnClick()
        assert.is_true(fury:IsShown())
        fury:SetText('25000')
        fury.scripts.OnEnterPressed()
        assert.equals(25000, awards:GetThreshold(72, 39863))
        for _, invalid in ipairs({ '-1', '1.5', '9999999', 'abc' }) do
            fury:SetText(invalid)
            fury.scripts.OnEnterPressed()
            assert.equals(25000, awards:GetThreshold(72, 39863))
        end
        choose(named.RLHelperDPSRaidDropdown, 'ЦЛК')
        choose(named.RLHelperDPSBossDropdown, 'Саурфанг')
        assert.equals('21000', fury:GetText())
        fury:SetText('23000') -- Commit the old boss before switching.
        choose(named.RLHelperDPSRaidDropdown, 'РС')
        choose(named.RLHelperDPSBossDropdown, 'Халион')
        assert.equals(23000, awards:GetThreshold(72, 37813))
        assert.equals('25000', fury:GetText())
        awards:CreateSettings({}, {})
        assert.equals(25000, awards:GetThreshold(72, 39863))
        -- Use the previous panel to remove Halion; recreating only changed self.options.
        remove.scripts.OnClick()
        assert.is_nil(awards:GetSettings().dpsBosses[39863])
        assert.is_false(fury:IsShown())
        awards:RemoveDPSBoss(37813)
        assert.same({}, awards:GetSettings().dpsBosses)
        assert.same({}, awards:GetSettings().dpsBosses) -- Do not recreate defaults after removal.
    end)

    it('saves independent winning results and awards selected players for the chosen boss', function()
        installFrames()
        individualEPGP()
        meters:SkadaSetComplete('Skada_SetComplete', winningSet())
        local saurfang = awards:GetDPSResults()[37813]
        awards:AddDPSBoss(39863)
        awards:GetSettings().dpsBosses[39863] = { [71] = 15000, [72] = 20000 }
        local fight = { source = 'Skada', boss = 40142, starttime = now - 250, endtime = now,
            players = { { name = 'Fury', class = 'WARRIOR', spec = 72, dps = 19900 },
                { name = 'Arms', class = 'WARRIOR', spec = 71, dps = 14899 } } }
        awards:DPSFightComplete(fight)
        local halion = awards:GetDPSResults()[39863]
        assert.equals(39863, halion.boss)
        assert.equals(20000, halion.players[1].threshold)
        assert.equals(saurfang, awards:GetDPSResults()[37813])
        awards:ShowDPSWindow(39863)
        local frame = awards.dpsWindow
        assert.same({ Fury = true }, frame.selected)
        frame.awardButton.scripts.OnClick()
        assert.same({ { 'Fury', 'RLHelper: ДПС Халион', 500 } }, calls)
        assert.equals(500, halion.players[1].lastAward.amount)
        assert.is_nil(saurfang.players[1].lastAward)
        frame.plusButton.scripts.OnClick()
        assert.equals(500, frame.offset)
        awards:ShowDPSWindow(37813)
        assert.equals(saurfang, frame.snapshot)
        assert.equals(0, frame.offset)
        assert.is_truthy(frame.bossDropdown.text:find('Саурфанг', 1, true))
        assert.equals(2, #choices(frame.bossDropdown))
        awards:RemoveDPSBoss(39863)
        awards:DPSFightComplete({ source = 'Skada', boss = 39863, starttime = now, endtime = now + 100 })
        assert.equals(halion, awards:GetDPSResults()[39863])
        awards:ShowDPSWindow(39863) -- Saved results remain available after removing settings.
        assert.equals(halion, frame.snapshot)
    end)

    it('keeps the DPS window usable after removing every configured boss', function()
        installFrames()
        awards:RemoveDPSBoss(37813)
        awards:ShowDPSWindow()
        assert.is_nil(awards.dpsWindow.snapshot)
        assert.is_nil(awards.dpsWindow.boss)
        assert.is_false(awards.dpsWindow.awardButton.enabled)
        assert.same({}, choices(awards.dpsWindow.bossDropdown))
    end)

    it('marks configured boss deaths only in their raid and ignores early beasts phases', function()
        local killed, before = {}, meters.BossKilled
        meters.BossKilled = function(_, npc) killed[#killed + 1] = npc end
        local ok, err = pcall(function()
            awards:AddDPSBoss(39863)
            awards:AddDPSBoss(34796)
            addon.currentInstanceId = 631
            awards:handleEvent({ event = 'UNIT_DIED', destGUID = string.format('0xF130%06X000001', 39863) })
            assert.equals(0, #killed)
            addon.currentInstanceId = 724
            awards:handleEvent({ event = 'UNIT_DIED', destGUID = string.format('0xF130%06X000001', 40142) })
            addon.currentInstanceId = 649
            for _, npc in ipairs({34796, 35144, 34799, 34797}) do
                awards:handleEvent({ event = 'UNIT_DIED', destGUID = string.format('0xF130%06X000001', npc) })
            end
            assert.same({40142, 34797}, killed)
        end)
        meters.BossKilled = before
        assert.is_true(ok, tostring(err))
    end)

end)
