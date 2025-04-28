local M = {}

-- Mock для AceEvent-3.0
local AceEvent = {
    RegisterEvent = function(self, eventName) end,
    UnregisterEvent = function(self, eventName) end,
    SendMessage = function(self, message, ...) end,
    RegisterMessage = function(self, message, ...) end,
}

-- Mock bit functions used by the addon
bit = {
    band = function(a, b) 
        -- Implementation of bitwise AND for older Lua versions
        local result = 0
        local bitval = 1
        while a > 0 and b > 0 do
            if a % 2 == 1 and b % 2 == 1 then
                result = result + bitval
            end
            bitval = bitval * 2
            a = math.floor(a/2)
            b = math.floor(b/2)
        end
        return result
    end
}

function M:GetAddon(name)
    local addon = {}
    function addon:NewModule(moduleName, mixins)
        return {
            name = moduleName,
            OnInitialize = function() end,
            OnEnable = function() end,
            RegisterEvent = AceEvent.RegisterEvent,
            UnregisterEvent = AceEvent.UnregisterEvent,
            SendMessage = AceEvent.SendMessage,
            RegisterMessage = AceEvent.RegisterMessage,
        }
    end
    return addon
end

function M:NewModule(name)
    local module = {
        name = name,
        OnInitialize = function() end,
        OnEnable = function() end,
        RegisterEvent = AceEvent.RegisterEvent,
        UnregisterEvent = AceEvent.UnregisterEvent,
        SendMessage = AceEvent.SendMessage,
        RegisterMessage = AceEvent.RegisterMessage,
    }
    
    return module
end

function M:NewAddon(name)
    local module = {
        name = name,
        OnInitialize = function() end,
        OnEnable = function() end,
        RegisterEvent = AceEvent.RegisterEvent,
        UnregisterEvent = AceEvent.UnregisterEvent,
        SendMessage = AceEvent.SendMessage,
        RegisterMessage = AceEvent.RegisterMessage,
    }
    
    return module
end

LibStub = function(name)
    return M
end

time = function() return 1234567890 end
Text = function(text) return text end
date = function(format, timestamp) 
    return "SOME DATE"
end

GetTime = function() return 1234567890 end
GetSpellTexture = function(spellName) return "texture_path" end

return M