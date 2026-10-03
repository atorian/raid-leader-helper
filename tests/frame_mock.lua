local assert = require('luassert')

return function()
    local frames, namedFrames, texts, labelsByText, editBoxes, originalGlobals = {}, {}, {}, {}, {}, {}
    local function newFrame(kind, name, parent, template)
        local frame = {
            kind = kind, name = name, parent = parent, template = template, points = {}, scripts = {},
            textures = {}, fonts = {}, enabled = true, visible = true,
            font = { 'Fonts\\FRIZQT__.TTF', 12, 'OUTLINE' }, color = { 1, 0.82, 0, 1 }
        }
        frames[#frames + 1] = frame
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
        function frame:GetHeight()
            if self.kind == 'FontString' then return self.height or self:GetStringHeight() end
            return self.height or 400
        end
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
        function frame:SetText(text)
            self.text = text
            texts[#texts + 1] = text
            labelsByText[text] = self
        end
        function frame:GetText() return self.text or '' end
        function frame:SetTextInsets(...) self.textInsets = { ... } end
        function frame:SetCursorPosition(position) self.cursorPosition = position end
        function frame:SetFont(...) self.font = { ... } end
        function frame:GetFont() return unpack(self.font) end
        function frame:GetSpacing() return 0 end
        function frame:SetAlpha(alpha)
            assert.equals('number', type(alpha))
            self.alpha = alpha
        end
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
        function frame:GetChecked() return self.checked end
        function frame:ClearFocus() self.clearedFocus = true end
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
        for _, method in ipairs({ 'SetJustifyV', 'SetJustifyH',
            'SetFading', 'SetMaxLines', 'EnableMouseWheel', 'SetHyperlinksEnabled', 'SetIndentedWordWrap',
            'SetInsertMode', 'SetAutoFocus', 'SetClampedToScreen', 'Clear', 'AddMessage' }) do
            frame[method] = function() end
        end
        function frame:SetAllPoints(value) self.allPoints = value end
        function frame:SetFrameStrata(value) self.frameStrata = value end
        function frame:SetMovable(value) self.movable = value end
        function frame:SetResizable(value) self.resizable = value end
        function frame:SetMinResize(...) self.minResize = { ... } end
        function frame:SetMaxResize(...) self.maxResize = { ... } end
        function frame:EnableMouse(value) self.mouseEnabled = value end
        function frame:RegisterForDrag(...) self.dragButtons = {...} end
        function frame:StartMoving()
            self.moving = true
            self.moveStarts = (self.moveStarts or 0) + 1
        end
        function frame:StartSizing(point)
            self.sizing = point
            self.sizeStarts = (self.sizeStarts or 0) + 1
        end
        function frame:StopMovingOrSizing() self.moving, self.sizing = false, nil end
        if kind == 'EditBox' then editBoxes[#editBoxes + 1] = frame end
        if name then
            namedFrames[name] = frame
            if kind == 'CheckButton' then
                local textName = name .. 'Text'
                if originalGlobals[textName] == nil then originalGlobals[textName] = _G[textName] or false end
                _G[textName] = frame:CreateFontString()
            end
        end
        return frame
    end

    return {
        newFrame = newFrame, frames = frames, namedFrames = namedFrames,
        texts = texts, labelsByText = labelsByText, editBoxes = editBoxes,
        restoreGlobals = function()
            for key, value in pairs(originalGlobals) do _G[key] = value or nil end
        end
    }
end
