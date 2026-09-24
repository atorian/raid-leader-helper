require('tests.mocks')
local addon = require('Core')
local Theme = addon.UITheme

describe('UI themes', function()
    local originalGlobals, originalAddon, namedFrames, dropdownItems, createdFrames
    local function newFrame(kind, name, parent, template)
        local frame = {
            name = name, parent = parent, template = template, points = {}, scripts = {},
            textures = {}, fonts = {}, enabled = true, visible = true,
            font = { 'Fonts\\FRIZQT__.TTF', 12, 'OUTLINE' }, color = { 1, 0.82, 0, 1 }
        }
        createdFrames[#createdFrames + 1] = frame
        local function refreshTexture(self, state)
            local texture = self.textures[state]
            if texture then
                texture.visible = (state == 'Normal' and self.enabled)
                    or (state == 'Disabled' and not self.enabled)
            end
        end
        function frame:SetPoint(...) self.points[#self.points + 1] = { ... } end
        function frame:ClearAllPoints() self.points = {} end
        function frame:SetSize(w, h) self.width, self.height = w, h end
        function frame:SetHeight(h) self.height = h end
        function frame:SetWidth(w) self.width = w end
        function frame:GetHeight() return self.height or 400 end
        function frame:GetWidth() return self.width or 400 end
        function frame:GetStringHeight()
            return self.text and self.text:find(':20:20:0:-1|t', 1, true) and 20 or 14
        end
        function frame:SetScrollChild(child) self.scrollChild = child end
        function frame:GetVerticalScroll() return self.verticalScroll or 0 end
        function frame:GetVerticalScrollRange()
            return math.max(0, (self.scrollChild and self.scrollChild.height or 0) - self:GetHeight())
        end
        function frame:SetVerticalScroll(value) self.verticalScroll = value end
        function frame:GetName() return self.name end
        function frame:SetText(text) self.text = text end
        function frame:GetText() return self.text or '' end
        function frame:SetFont(...) self.font = { ... } end
        function frame:GetFont() return unpack(self.font) end
        function frame:GetSpacing() return 0 end
        function frame:SetTextColor(...) self.color = { ... } end
        function frame:GetTextColor() return unpack(self.color) end
        function frame:SetTexture(...) self.texture = { ... } end
        function frame:GetTexture() return self.texture and self.texture[1] end
        function frame:SetBlendMode(mode) self.blendMode = mode end
        function frame:GetBlendMode() return self.blendMode or 'BLEND' end
        function frame:SetBackdrop(backdrop) self.backdrop = backdrop end
        function frame:SetScript(event, fn) self.scripts[event] = fn end
        function frame:GetScript(event) return self.scripts[event] end
        function frame:SetAttribute(key, value)
            assert.is_false(self.combatLocked or false, 'protected attribute mutation in combat')
            self.attributes = self.attributes or {}
            self.attributes[key] = value
        end
        function frame:RegisterForClicks(...) self.clicks = { ... } end
        function frame:GetEffectiveScale() return 1 end
        function frame:GetTop() return 400 end
        function frame:GetBottom() return 0 end
        function frame:GetLeft() return 10 end
        function frame:GetFrameLevel() return 3 end
        function frame:GetFrameStrata() return 'MEDIUM' end
        function frame:SetFrameLevel(level) self.level = level end
        function frame:IsVisible() return self.visible end
        function frame:Show() self.visible = true end
        function frame:Hide() self.visible = false end
        function frame:IsShown() return self.visible end
        function frame:Enable()
            self.enabled = true
            for state in pairs(self.textures) do refreshTexture(self, state) end
        end
        function frame:Disable()
            self.enabled = false
            for state in pairs(self.textures) do refreshTexture(self, state) end
        end
        function frame:SetChecked(value) self.checked = value end
        function frame:CreateFontString() return newFrame('FontString', nil, self) end
        function frame:CreateTexture() return newFrame('Texture', nil, self) end
        function frame:GetFontString()
            self.fontString = self.fontString or self:CreateFontString()
            return self.fontString
        end
        for _, state in ipairs({ 'Normal', 'Pushed', 'Highlight', 'Disabled' }) do
            frame['Get' .. state .. 'Texture'] = function(self) return self.textures[state] end
            frame['Set' .. state .. 'Texture'] = function(self, texture, blendMode)
                if type(texture) == 'string' then
                    local path = texture
                    texture = self:CreateTexture()
                    texture:SetTexture(path)
                    texture:SetBlendMode(blendMode or (state == 'Highlight' and 'ADD' or 'BLEND'))
                end
                -- Reassigning the same texture does not trigger a button-state change.
                if self.textures[state] ~= texture then
                    self.textures[state] = texture
                    refreshTexture(self, state)
                end
            end
            if state ~= 'Pushed' then
                frame.fonts[state] = 'original-' .. state
                frame['Get' .. state .. 'FontObject'] = function(self) return self.fonts[state] end
                frame['Set' .. state .. 'FontObject'] = function(self, font) self.fonts[state] = font end
            end
        end
        if template == 'UIPanelButtonTemplate' then
            for _, state in ipairs({ 'Normal', 'Pushed', 'Highlight', 'Disabled' }) do
                frame['Set' .. state .. 'Texture'](frame, 'original-' .. state)
            end
        end
        for _, method in ipairs({ 'SetAllPoints', 'SetFrameStrata', 'SetMovable', 'SetResizable',
            'SetMinResize', 'SetMaxResize', 'EnableMouse', 'RegisterForDrag', 'SetJustifyV', 'SetJustifyH',
            'SetFading', 'SetMaxLines', 'EnableMouseWheel', 'SetHyperlinksEnabled', 'SetIndentedWordWrap',
            'SetInsertMode', 'SetAutoFocus', 'ClearFocus', 'Clear', 'AddMessage' }) do
            frame[method] = function() end
        end
        function frame:StartMoving() self.moving = true end
        function frame:StopMovingOrSizing() self.moving = false end
        if name then
            namedFrames[name] = frame
            if kind == 'CheckButton' then
                local textName = name .. 'Text'
                originalGlobals[textName] = _G[textName] or false
                _G[textName] = frame:CreateFontString()
            end
        end
        return frame
    end

    before_each(function()
        namedFrames, dropdownItems, originalGlobals, originalAddon, createdFrames = {}, {}, {}, {}, {}
        for _, key in ipairs({ 'CreateFrame', 'UIParent', 'InterfaceOptions_AddCategory',
            'UIDropDownMenu_AddButton', 'UnitAffectingCombat', 'UnitIsPlayer', 'TargetUnit', 'RegisterStateDriver' }) do
            originalGlobals[key] = _G[key] or false
        end
        for _, key in ipairs({ 'db', 'mainFrame', 'themeButtons', 'journalView',
            'optionsPanel', 'displayedCombat', 'currentCombat', 'SendMessage' }) do
            originalAddon[key] = addon[key] or false
        end
        _G.CreateFrame = newFrame
        _G.UIParent = newFrame('Frame')
        _G.InterfaceOptions_AddCategory = function() end
        _G.UIDropDownMenu_AddButton = function(info) dropdownItems[#dropdownItems + 1] = info end
        addon.db = { profile = {}, char = {} }
        addon.themeButtons, addon.mainFrame = nil, nil
        addon.journalView = 'ALL'
        addon.currentCombat = { events = {}, messages = {} }
        addon.displayedCombat = addon.currentCombat
        addon.SendMessage = function() end
    end)

    after_each(function()
        for key, value in pairs(originalGlobals) do _G[key] = value or nil end
        for key, value in pairs(originalAddon) do addon[key] = value or nil end
    end)

    it('leaves existing profiles and the original UI unchanged by default', function()
        addon:CreateMainFrame()
        assert.are.equal('current', Theme.GetName(addon))
        assert.is_nil(addon.mainFrame.originalThemeFont)
        assert.has_no.errors(function() addon.mainFrame.scripts.OnSizeChanged() end)
        assert.are.same({ 'original-Normal' }, addon.mainFrame.raidCheckBtn.textures.Normal.texture)
        assert.is_nil(addon.mainFrame.title)
    end)

    it('switches repeatedly without changing the background, contents, visibility or handlers', function()
        addon:CreateMainFrame()
        local frame = addon.mainFrame
        local backdrop, log = frame.backdrop, frame.logText
        local button = frame.raidCheckBtn
        local normal, disabled = button.textures.Normal, button.textures.Disabled
        local click = button.scripts.OnClick
        for _ = 1, 3 do
            addon:SetTheme('minimal')
            assert.are.equal(backdrop, frame.backdrop)
            assert.are.equal(log, frame.logText)
            assert.are.equal(click, button.scripts.OnClick)
            assert.is_false(frame.cancelBtn.visible)
            assert.is_true(frame.journalFilterButtons.ALL.themeSelection.visible)
            assert.is_false(frame.journalFilterButtons.ERRORS.themeSelection.visible)
            assert.are.equal('GameFontHighlight', frame.journalFilterButtons.ALL.fonts.Disabled)
            assert.is_nil(frame.title)
            assert.are.equal(-2, frame.buttonContainer.points[1][5])
            addon:SetTheme('current')
            assert.are.equal(normal, button.textures.Normal)
            assert.are.equal(disabled, button.textures.Disabled)
            assert.are.equal('original-Normal', button.fonts.Normal)
            assert.is_false(frame.journalFilterButtons.ALL.themeSelection.visible)
            assert.is_nil(frame.title)
            assert.are.equal(-2, frame.buttonContainer.points[1][5])
            assert.are.equal('OUTLINE', log.font[3])
            assert.are.equal(backdrop, frame.backdrop)
        end
    end)

    it('changes texture contents without replacing button-owned objects or forcing their visibility', function()
        addon:CreateMainFrame()
        local saved = {}
        for button in pairs(addon.themeButtons) do
            saved[button] = {}
            for _, state in ipairs({ 'Normal', 'Pushed', 'Highlight', 'Disabled' }) do
                local texture = button['Get' .. state .. 'Texture'](button)
                saved[button][state] = {
                    object = texture, path = texture:GetTexture(), blend = texture:GetBlendMode(),
                    visible = texture.visible
                }
                button['Set' .. state .. 'Texture'] = function()
                    error('Theme must not replace a button-owned texture')
                end
                texture.Show = function() error('Button controls texture visibility') end
                texture.Hide = function() error('Button controls texture visibility') end
            end
        end
        for _, theme in ipairs({ 'minimal', 'current', 'minimal', 'current' }) do
            addon:SetTheme(theme)
            for button, states in pairs(saved) do
                for state, original in pairs(states) do
                    local texture = button['Get' .. state .. 'Texture'](button)
                    assert.are.equal(original.object, texture)
                    assert.are.equal(original.visible, texture.visible)
                    if theme == 'current' then
                        assert.are.equal(original.path, texture:GetTexture())
                        assert.are.equal(original.blend, texture:GetBlendMode())
                    else
                        assert.are.equal('number', type(texture:GetTexture()))
                        assert.are.equal('BLEND', texture:GetBlendMode())
                    end
                end
            end
        end
    end)

    it('handles a template without a disabled texture and clears its fill on restoration', function()
        addon:CreateMainFrame()
        local button = addon.mainFrame.raidCheckBtn
        button.textures.Disabled = nil
        addon:SetTheme('minimal')
        local texture = button:GetDisabledTexture()
        assert.is_not_nil(texture)
        button:Disable()
        assert.is_true(texture.visible)
        addon:SetTheme('current')
        assert.are.equal(texture, button:GetDisabledTexture())
        assert.is_nil(texture:GetTexture())
        addon:SetTheme('minimal')
        assert.are.equal(texture, button:GetDisabledTexture())
        assert.are.equal('number', type(texture:GetTexture()))
    end)

    it('shows action backgrounds immediately with a saved minimal theme and on reapplication', function()
        addon.db.profile.theme = 'minimal'
        addon:CreateMainFrame()
        for _ = 1, 3 do
            for _, button in ipairs(addon.mainFrame.pullButtons) do
                assert.is_true(button:GetNormalTexture().visible)
                assert.is_false(button:GetPushedTexture().visible)
                assert.is_false(button:GetDisabledTexture().visible)
                assert.is_false(button:GetHighlightTexture().visible)
            end
            Theme.Apply(addon)
        end
    end)

    it('restores visible action backgrounds on theme changes without clicking a button', function()
        addon:CreateMainFrame()
        for _, theme in ipairs({ 'minimal', 'current', 'minimal', 'current' }) do
            addon:SetTheme(theme)
            for _, button in ipairs(addon.mainFrame.pullButtons) do
                assert.is_true(button:GetNormalTexture().visible)
            end
            local selected = addon.mainFrame.journalFilterButtons.ALL
            assert.is_true(selected:GetDisabledTexture().visible)
            assert.is_false(selected:GetNormalTexture().visible)
        end
    end)

    it('never gives minimize or anchor buttons a background in any theme or state', function()
        addon.db.profile.theme = 'minimal'
        addon:CreateMainFrame()
        local controls = {}
        for _, frame in ipairs(createdFrames) do
            if frame.text == '_' or frame.text == 'A' then controls[#controls + 1] = frame end
        end
        assert.are.equal(2, #controls)
        for _, theme in ipairs({ 'minimal', 'current', 'minimal' }) do
            addon:SetTheme(theme)
            for _, button in ipairs(controls) do
                for _, state in ipairs({ 'Normal', 'Pushed', 'Highlight', 'Disabled' }) do
                    assert.are.same({ '' }, button['Get' .. state .. 'Texture'](button).texture)
                end
            end
        end
    end)

    it('moves the selected-filter marker when the journal view changes', function()
        addon.db.profile.theme = 'minimal'
        addon:CreateMainFrame()
        addon:SetJournalView('ERRORS')
        local buttons = addon.mainFrame.journalFilterButtons
        assert.is_false(buttons.ALL.themeSelection.visible)
        assert.is_true(buttons.ERRORS.themeSelection.visible)
        assert.is_false(buttons.ERRORS.enabled)
        assert.is_true(buttons.ALL.enabled)
    end)

    it('highlights every Errors entry only in All for live and saved V2 views', function()
        local Journal = require('lib.Journal')
        addon:CreateMainFrame()
        local frame = addon.mainFrame
        local event = { timestamp = 1000, sourceGUID = 'demo-hunter', sourceName = 'Стрелок',
            sourceClass = 'HUNTER', destName = 'Босс' }
        local ordinary = Journal.Create('FIRST_DAMAGE', event, 'INFO')
        local violation = Journal.Create('SHADOW_TRAP', event, 'TACTIC_VIOLATION', { text = 'Взорвал ловушку' })
        local summary = Journal.Create('MALLEABLE_GOO_SUMMARY', {}, 'INFO', { text = 'Вязкая гадость: всего 1' })
        addon:OnCombatLogEvent(ordinary)
        addon:OnCombatLogEvent(violation)
        addon:OnCombatLogEvent(summary)
        assert.are.equal(3, #frame.v2Items)
        assert.are.equal(21, frame.v2Items[1].height)
        assert.is_truthy(frame.v2Rows[1].text.text:find(':20:20:0:-1|t', 1, true))
        assert.is_false(frame.v2Rows[1].background.visible)
        assert.is_true(frame.v2Rows[2].background.visible)
        assert.is_false(frame.v2Rows[3].background.visible)
        assert.is_truthy(frame.v2Rows[2].text.text:find('|cFFABD473Стрелок|r', 1, true))
        assert.is_truthy(frame.v2Rows[2].text.text:find('|cFFFFFFFFВзорвал ловушку|r', 1, true))
        addon:SetJournalView('ERRORS')
        assert.are.equal(1, #frame.v2Items)
        assert.is_false(frame.v2Rows[1].background.visible)
        assert.is_nil(frame.v2Rows[1].text.text:find('|cFFFF0000', 1, true))
        assert.is_truthy(frame.v2Rows[1].text.text:find('|cFFFFFFFFВзорвал ловушку|r', 1, true))
        assert.is_truthy(frame.v2Rows[1].text.text:find('|cFFABD473Стрелок|r', 1, true))
        assert.is_false(frame.v2Rows[2].visible)
        addon:DisplayCombat(Journal.Copy(addon.currentCombat))
        assert.is_false(frame.v2Rows[1].background.visible)
        assert.is_nil(frame.v2Rows[1].text.text:find('|cFFFF0000', 1, true))
        addon:SetJournalView('ALL')
        assert.is_false(frame.v2Rows[1].background.visible)
        assert.is_true(frame.v2Rows[2].background.visible)
        addon:SetJournalView('MISDIRECTION')
        assert.are.equal(0, #frame.v2Items)
        assert.is_false(frame.v2Rows[1].visible)
        addon.currentCombat.droppedEvents = 2
        addon:DisplayCombat(addon.currentCombat)
        assert.are.equal(1, #frame.v2Items)
        assert.is_truthy(frame.v2Rows[1].text.text:find('пропущено событий 2', 1, true))
        assert.is_false(frame.v2Rows[1].background.visible)
    end)

    it('drags the main window from the scroll area and occupied journal rows', function()
        addon:CreateMainFrame()
        local frame = addon.mainFrame
        local Journal = require('lib.Journal')
        addon:OnCombatLogEvent(Journal.Create('FIRST_DAMAGE', { timestamp = 1000,
            sourceName = 'Бочок', destName = 'Профессор Мерзоцид' }))
        for _, region in ipairs({ frame.v2Scroll, frame.v2Content, frame.v2Rows[1] }) do
            region.scripts.OnDragStart(region)
            assert.is_true(frame.moving)
            region.scripts.OnDragStop(region)
            assert.is_false(frame.moving)
        end
    end)

    it('uses an independent secure target button and never calls TargetUnit directly', function()
        local Journal = require('lib.Journal')
        local inCombat = false
        _G.UnitAffectingCombat = function() return inCombat end
        _G.UnitIsPlayer = function(name) return name == 'Hunter' or name == 'Mage' end
        _G.TargetUnit = function() error('direct targeting is forbidden even outside combat') end
        _G.RegisterStateDriver = function(button, state, condition)
            button.driver = { state, condition }
        end
        addon:CreateMainFrame()
        local frame, row = addon.mainFrame, addon.mainFrame.v2Rows[1]
        local function show(kind, source, target)
            addon:DisplayCombat({ events = { Journal.Create(kind, {
                sourceName = source, destName = target,
                destClass = target == 'Mage' and 'MAGE' or nil,
            }) } })
            row.scripts.OnEnter(row)
        end
        inCombat = true
        show('SPELL_USE', 'Hunter', 'Boss')
        assert.is_nil(frame.v2TargetButton)
        inCombat = false
        row.scripts.OnEnter(row)
        local button = frame.v2TargetButton
        assert.are.equal('SecureActionButtonTemplate', button.template)
        assert.are.equal(UIParent, button.parent)
        assert.are.equal(UIParent, button.points[1][2])
        assert.are.same({ 'LeftButtonUp' }, button.clicks)
        assert.are.same({ 'visibility', '[combat] hide' }, button.driver)
        assert.are.equal('macro', button.attributes.type1)
        assert.are.equal('/targetexact [nocombat] Hunter', button.attributes.macrotext1)
        assert.is_nil(button.scripts.OnClick) -- Preserve Blizzard's inherited secure handler.
        assert.is_nil(row.scripts.OnMouseUp)
        assert.is_true(button.visible)
        button.scripts.OnDragStart(button)
        assert.is_nil(button.attributes.macrotext1)
        assert.is_true(frame.moving)
        button.scripts.OnDragStop(button)
        assert.is_false(frame.moving)
        assert.is_false(button.visible)
        show('SHADOW_TRAP', 'Boss', 'Mage')
        assert.are.equal('/targetexact [nocombat] Mage', button.attributes.macrotext1)
        button.scripts.OnMouseWheel(button, 1)
        assert.is_false(button.visible)
        row.scripts.OnEnter(row)
        button.combatLocked, inCombat = true, true
        local oldHide, oldShow = button.Hide, button.Show
        button.Hide = function() error('insecure hide in combat') end
        button.Show = function() error('insecure show in combat') end
        assert.has_no.errors(function()
            row.scripts.OnEnter(row)
            button.scripts.OnEnter(button)
            button.scripts.OnLeave(button)
            button.scripts.OnUpdate(button)
            button.scripts.OnDragStart(button)
            button.scripts.OnDragStop(button)
            addon:RefreshJournalRows(addon.displayedCombat)
            show('SPELL_USE', 'Hunter', nil)
        end)
        assert.are.equal('/targetexact [nocombat] Mage', button.attributes.macrotext1)
        button.combatLocked, inCombat = false, false
        button.Hide, button.Show = oldHide, oldShow
        for _, name in ipairs({ 'Boss', 'AbsentPlayer' }) do
            show('SPELL_USE', name, nil)
            assert.is_false(button.visible)
        end
        show('SPIRIT_SUMMARY', nil, nil)
        assert.is_false(button.visible)
        show('SPELL_USE', 'Hunter', nil)
        assert.is_true(button.visible)
        frame:Hide()
        button.scripts.OnUpdate(button)
        assert.is_false(button.visible)
    end)

    it('aligns controls and V2 text to the same side margins in both themes', function()
        addon:CreateMainFrame()
        local frame = addon.mainFrame
        local minimize
        for _, control in ipairs(createdFrames) do
            if control.text == '_' then minimize = control end
        end
        for _, theme in ipairs({ 'minimal', 'current', 'minimal' }) do
            addon:SetTheme(theme)
            assert.are.same({ 'TOPLEFT', frame, 'TOPLEFT', 2, -2 }, frame.buttonContainer.points[1])
            assert.are.same({ 'TOPRIGHT', frame, 'TOPRIGHT', -2, -2 }, minimize.points[1])
            assert.are.equal(0, frame.v2Rows[1].text.points[1][4])
            assert.are.equal(0, frame.v2Rows[1].text.points[2][4])
            assert.are.equal(-2, frame.logText.points[2][4])
        end
        addon.db.profile.gpAwardButtonsEnabled = true
        local gp = dofile('modules/ui/GPAwardButtons.lua')
        gp:attachToMainFrame()
        assert.are.same({ 'BOTTOMLEFT', frame, 'BOTTOMLEFT', 2, 2 }, gp.footerFrame.points[1])
        assert.are.same({ 'BOTTOMRIGHT', frame, 'BOTTOMRIGHT', -2, 2 }, gp.footerFrame.points[2])
        assert.are.equal(0, frame.logText.points[2][4])
    end)

    it('keeps compact single lines while giving wrapped V2 messages their measured height', function()
        local Journal = require('lib.Journal')
        addon:CreateMainFrame()
        local frame = addon.mainFrame
        addon:OnCombatLogEvent(Journal.Create('FIRST_DAMAGE', { timestamp = 1000,
            sourceName = 'Бочок', destName = 'Профессор Мерзоцид' }))
        assert.are.equal(21, frame.v2Items[1].height)
        frame.v2Measure.GetStringHeight = function() return 36 end
        addon:OnCombatLogEvent(Journal.Create('SPIRIT_SUMMARY', { timestamp = 1001 }, 'INFO',
            { text = 'Духов взорвали: всего 2 Целитель(1) Чародей(1)' }))
        assert.are.equal(37, frame.v2Items[2].height)
    end)

    it('matches demo error counts to red rows in All and removes backgrounds in Errors', function()
        addon:CreateMainFrame()
        addon:DemoJournal()
        local allErrors = 0
        for _, item in ipairs(addon.mainFrame.v2Items) do
            if item.highlighted then allErrors = allErrors + 1 end
        end
        assert.are.equal(25, allErrors)
        addon:SetJournalView('ERRORS')
        assert.are.equal(25, #addon.mainFrame.v2Items)
        for _, item in ipairs(addon.mainFrame.v2Items) do
            assert.is_false(item.highlighted)
        end
    end)

    it('appends live rows chronologically and scrolls to the latest after manual scrolling', function()
        local Journal = require('lib.Journal')
        addon:CreateMainFrame()
        local frame = addon.mainFrame
        frame.v2Scroll:SetHeight(100)
        for i = 1, 10 do
            addon:OnCombatLogEvent(Journal.Create('SHADOW_TRAP', { timestamp = i }, 'TACTIC_VIOLATION'))
        end
        for i, item in ipairs(frame.v2Items) do assert.are.equal(i, item.entry.timestamp) end
        assert.are.equal(110, frame.v2Scroll:GetVerticalScroll())
        frame.v2Scroll.scripts.OnMouseWheel(frame.v2Scroll, 1)
        assert.are.equal(50, frame.v2Scroll:GetVerticalScroll())
        addon:OnCombatLogEvent(Journal.Create('SHADOW_TRAP', { timestamp = 11 }, 'TACTIC_VIOLATION'))
        assert.are.equal(131, frame.v2Scroll:GetVerticalScroll())
        assert.are.equal(11, frame.v2Items[#frame.v2Items].entry.timestamp)
        addon:SetJournalView('ERRORS')
        assert.are.equal(131, frame.v2Scroll:GetVerticalScroll())
        addon:DisplayCombat(Journal.Copy(addon.currentCombat))
        assert.are.equal(131, frame.v2Scroll:GetVerticalScroll())
        assert.are.equal(1, frame.v2Items[1].entry.timestamp)
    end)

    it('keeps the newest thousand matching rows in chronological order', function()
        local Journal = require('lib.Journal')
        addon:CreateMainFrame()
        local frame = addon.mainFrame
        local combat = { events = {}, droppedEvents = 2 }
        for i = 1, 1005 do
            combat.events[#combat.events + 1] = Journal.Create('SHADOW_TRAP', { timestamp = i }, 'TACTIC_VIOLATION')
            combat.events[#combat.events + 1] = Journal.Create('SPELL_USE', { timestamp = i })
        end
        addon:SetJournalView('ERRORS')
        addon:DisplayCombat(combat)
        assert.are.equal(1001, #frame.v2Items)
        assert.are.equal(6, frame.v2Items[1].entry.timestamp)
        assert.are.equal(1005, frame.v2Items[1000].entry.timestamp)
        assert.is_truthy(frame.v2Items[1001].text:find('пропущено событий 2', 1, true))
        assert.are.equal(frame.v2Scroll:GetVerticalScrollRange(), frame.v2Scroll:GetVerticalScroll())
    end)

    it('keeps the demo pull detail tooltip on the V2 summary row', function()
        local previousTooltip = _G.GameTooltip
        local details = {}
        _G.GameTooltip = {
            SetOwner = function() end, AddLine = function() end, Show = function() end, Hide = function() end,
            AddDoubleLine = function(_, name, amount) details[#details + 1] = { name, amount } end,
        }
        addon:CreateMainFrame()
        addon:DemoJournal()
        local summary
        for _, row in ipairs(addon.mainFrame.v2Rows) do
            if row.entry and row.entry.kind == 'MISDIRECTION_SUMMARY' then summary = row; break end
        end
        assert.is_not_nil(summary)
        summary.scripts.OnEnter(summary)
        _G.GameTooltip = previousTooltip
        assert.are.same({ { 'Профессор Мерзоцид', '1500' } }, details)
    end)

    it('loads a saved theme and themes GP buttons created later, including disabled undo', function()
        addon.db.profile.theme = 'minimal'
        addon.db.profile.gpAwardButtonsEnabled = true
        addon:CreateMainFrame()
        assert.is_not_nil(addon.mainFrame.journalFilters)
        assert.are.equal('GameFontHighlight', addon.mainFrame.raidCheckBtn.fonts.Normal)
        local gp = dofile('modules/ui/GPAwardButtons.lua')
        gp:attachToMainFrame()
        assert.are.equal('GameFontHighlight', gp.buttons[1].fonts.Normal)
        assert.are.equal('GameFontDisable', gp.undoButton.fonts.Disabled)
        assert.is_false(gp.undoButton.enabled)
        addon:SetTheme('current')
        assert.are.equal('original-Normal', gp.buttons[1].fonts.Normal)
        addon.db.profile.gpAwardButtonsEnabled = false
        gp:refreshVisibility()
        addon:SetTheme('minimal')
        assert.is_false(gp.footerFrame.visible)
        addon.db.profile.gpAwardButtonsEnabled = true
        gp:refreshVisibility()
        assert.is_true(gp.footerFrame.visible)
        assert.are.equal('GameFontHighlight', gp.buttons[1].fonts.Normal)
        assert.is_false(gp.undoButton.enabled)
    end)

    it('offers two settings, applies and persists the choice, and restores it when reopening settings', function()
        addon:CreateMainFrame()
        addon:CreateOptionsPanel()
        local dropdown = namedFrames.RLHelperThemeDropdown
        addon.optionsPanel.scripts.OnShow()
        assert.are.equal('Текущая (по умолчанию)', dropdown.text)
        dropdown.initialize()
        assert.are.equal(2, #dropdownItems)
        assert.is_true(dropdownItems[1].checked)
        assert.is_false(dropdownItems[2].checked)
        dropdownItems[2].func()
        assert.are.equal('minimal', addon.db.profile.theme)
        assert.are.equal('Минимализм', dropdown.text)
        assert.are.equal('GameFontHighlight', addon.mainFrame.raidCheckBtn.fonts.Normal)
        dropdown.text = ''
        addon.optionsPanel.scripts.OnShow()
        assert.are.equal('Минимализм', dropdown.text)
        dropdownItems[1].func()
        assert.are.equal('current', addon.db.profile.theme)
        assert.are.equal('original-Normal', addon.mainFrame.raidCheckBtn.fonts.Normal)
    end)
end)
