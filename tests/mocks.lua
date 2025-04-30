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

-- Таблица для хранения GUID'ов юнитов
local unitGuids = {}

-- Функция для установки GUID'а определенному юниту
function M:SetUnitGUID(unitId, guid)
    unitGuids[unitId] = guid
end

-- Функция для очистки всех установленных GUID'ов
function M:ClearUnitGUIDs()
    wipe(unitGuids)
end

-- Мокк функции UnitGUID
UnitGUID = function(unitId)
    return unitGuids[unitId] or "0x0000000000000000"
end

-- Мокки для проверки состава группы/рейда
IsInRaid = function()
    return M.isInRaid or false
end

GetNumRaidMembers = function()
    return M.raidSize or 0
end

GetNumPartyMembers = function()
    return M.partySize or 0
end

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
            Print = function() end,
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
        Print = function() end,
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
        Print = function() end,
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

-- Мокк для проверки боевого состояния юнитов
UnitAffectingCombat = function(unitId)
    -- Проверяем самого игрока
    if unitId == "player" then
        return M.UnitAffectingCombat1 ~= false
    end
    
    -- Проверяем участников группы
    local partyIndex = unitId:match("party(%d+)")
    if partyIndex then
        local index = tonumber(partyIndex) + 1  -- +1 because player is index 1
        return M["UnitAffectingCombat" .. index] ~= false
    end
    
    -- Проверяем участников рейда
    local raidIndex = unitId:match("raid(%d+)")
    if raidIndex then
        return M["UnitAffectingCombat" .. raidIndex] ~= false
    end
    
    return true -- По умолчанию считаем что в бою
end

-- Мок для wipe - очистка таблицы
wipe = function(table)
    if type(table) == "table" then
        for k in pairs(table) do
            table[k] = nil
        end
    end
    return table
end

return M