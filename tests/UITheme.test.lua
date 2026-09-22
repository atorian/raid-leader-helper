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
        function frame:GetName() return self.name end
        function frame:SetText(text) self.text = text end
        function frame:GetText() return self.text or '' end
        function frame:SetFont(...) self.font = { ... } end
        function frame:GetFont() return unpack(self.font) end
        function frame:GetSpacing() return 0 end
        function frame:SetTextColor(...) self.color = { ... } end
        function frame:GetTextColor() return unpack(self.color) end
        function frame:SetTexture(...) self.texture = { ... } end
        function frame:SetBackdrop(backdrop) self.backdrop = backdrop end
        function frame:SetScript(event, fn) self.scripts[event] = fn end
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
            frame['Set' .. state .. 'Texture'] = function(self, texture)
                if type(texture) == 'string' then
                    local path = texture
                    texture = self:CreateTexture()
                    texture:SetTexture(path)
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
            'SetInsertMode', 'SetAutoFocus', 'SetScrollChild', 'ClearFocus', 'Clear', 'AddMessage' }) do
            frame[method] = function() end
        end
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
            'UIDropDownMenu_AddButton' }) do
            originalGlobals[key] = _G[key] or false
        end
        for _, key in ipairs({ 'db', 'mainFrame', 'themeButtons', 'journalV2Enabled', 'journalView',
            'optionsPanel', 'displayedCombat', 'currentCombat', 'SendMessage' }) do
            originalAddon[key] = addon[key] or false
        end
        _G.CreateFrame = newFrame
        _G.UIParent = newFrame('Frame')
        _G.InterfaceOptions_AddCategory = function() end
        _G.UIDropDownMenu_AddButton = function(info) dropdownItems[#dropdownItems + 1] = info end
        addon.db = { profile = {}, char = {} }
        addon.themeButtons, addon.mainFrame = nil, nil
        addon.journalV2Enabled, addon.journalView = true, 'ALL'
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

    it('loads a saved theme with V1 and themes GP buttons created later, including disabled undo', function()
        addon.journalV2Enabled = false
        addon.db.profile.theme = 'minimal'
        addon.db.profile.gpAwardButtonsEnabled = true
        addon:CreateMainFrame()
        assert.is_nil(addon.mainFrame.journalFilters)
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
