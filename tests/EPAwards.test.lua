local mocks = require('tests.mocks')
require('Core')
require('data.BossIds')
local addon = LibStub('AceAddon-3.0'):GetAddon('RLHelper')
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
            main = addon.mainFrame, themeButtons = addon.themeButtons, print = addon.Print }
        now = at(27, 19, 0)
        _G.time = function(value) return value and os.time(value) or now end
        _G.date = function(format, value) return os.date(format, value or now) end
        _G.IsRaidLeader = function() return true end
        _G.GetNumRaidMembers = function() return 25 end
        addon.db = { profile = {}, char = {} }
        local settings = awards:GetSettings()
        settings.amounts = { attendance = 1000, icc = 2000, rs = 1500 }
        shown, calls = {}, {}
        awards.popups, awards.window, awards.callbackSource, awards.pending = nil, nil, nil, nil
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
        addon.db, addon.currentInstanceId = original.db, original.instance
        awards.ShowReminder = original.show
        mocks.GetAddon = original.getAddon
        _G.time, _G.date, _G.IsRaidLeader, _G.GetNumRaidMembers = original.time, original.date, original.leader, original.raid
        awards.window, awards.popups, awards.pending, awards.callbackSource = nil, nil, nil, nil
        addon.modules.EPAwards = nil
        _G.CreateFrame, _G.InterfaceOptions_AddCategory = original.createFrame, original.categories
        addon.mainFrame, addon.themeButtons, addon.Print = original.main, original.themeButtons, original.print
        awards.options, awards.button, awards.clock = nil, nil, nil
    end)

    it('awards via EPGP including its standby handling, saving no recipients', function()
        assert.is_true(awards:Award('attendance'))
        assert.same({ { 'RLHelper: Приход вовремя', 1000 } }, calls)
        assert.same({ status = 'awarded', amount = 1000, reason = 'Приход вовремя', at = now }, awards:GetState().awards.attendance)
        assert.is_false(awards:Award('attendance'))
        assert.equals(1, #calls)
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
        assert.is_false(awards:Award('icc'))
        now = at(28, 19, 0)
        assert.is_nil(awards:GetState().awards.icc)
        assert.is_true(awards:Award('icc'))
    end)
    it('does not clear current awards when RT settings change', function()
        awards:Award('icc')
        assert.is_true(awards:SetRT('20:00'))
        now = at(28, 19, 0)
        assert.is_false(awards:Award('icc'))
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
    it('requires a raid leader for reminders and awards', function()
        _G.IsRaidLeader = function() return false end
        awards:CheckTime()
        assert.is_false(awards:Award('icc'))
        _G.IsRaidLeader = function() return true end
        _G.GetNumRaidMembers = function() return 0 end
        assert.is_false(awards:Award('icc'))
        assert.equals(0, #calls)
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
    it('blocks retries after an exception that could follow partial awards', function()
        epgp.IncMassEPBy = function() error('write failed') end
        assert.is_false(awards:Award('icc'))
        assert.equals('uncertain', awards:GetState().awards.icc.status)
        assert.is_false(awards:Award('icc'))
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
                'SetNormalTexture', 'SetHighlightTexture', 'SetAutoFocus', 'SetTextInsets', 'SetCursorPosition' }) do
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
        assert.is_false(row.button.enabled)
        assert.equals('Начислено 19:00', row.button.text)
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
        assert.equals(177, awards.window.height)
        assert.is_nil(awards.window.backdrop.edgeFile)
        for _, f in ipairs(frames) do assert.is_not.equal('Настройки', f.text) end
        for _, key in ipairs({ 'attendance', 'icc', 'rs', 'toc' }) do
            awards:GetSettings().reminders[key] = false
        end
        awards:RefreshWindow()
        assert.is_true(awards.window.empty:IsShown())
        assert.equals(109, awards.window.height)
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
        assert.equals(5, count)
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

end)
