local M = {}

-- Mock для AceEvent-3.0
local AceEvent = {
    RegisterEvent = function(self, eventName)
    end,
    UnregisterEvent = function(self, eventName)
    end,
    SendMessage = function(self, message, ...)
    end,
    RegisterMessage = function(self, message, ...)
    end
}

-- Mock bit functions used by the addon
bit = {
    band = function(a, b)
        if a == nil then
            return 0
        end
        -- Implementation of bitwise AND for older Lua versions
        local result = 0
        local bitval = 1
        while a > 0 and b > 0 do
            if a % 2 == 1 and b % 2 == 1 then
                result = result + bitval
            end
            bitval = bitval * 2
            a = math.floor(a / 2)
            b = math.floor(b / 2)
        end
        return result
    end
}

local function toString(val)
    if type(val) == "table" then
        local str = "{"
        for k, v in pairs(val) do
            str = str .. tostring(k) .. "=" .. toString(v) .. ","
        end
        return str .. "}"
    else
        return tostring(val)
    end
end

-- Таблица для хранения GUID'ов юнитов
local unitGuids = {}
local unitNames = {}
local raidRoster = {}
local glyphSockets = {}
local threatStates = {}
local addons = {}

-- Функция для установки GUID'а определенному юниту
function M:SetUnitGUID(unitId, guid)
    unitGuids[unitId] = guid
end

function M:SetUnitName(unitId, name)
    unitNames[unitId] = name
end

-- Функция для очистки всех установленных GUID'ов
function M:ClearUnitGUIDs()
    wipe(unitGuids)
    wipe(unitNames)
end

function M:SetRaidRosterInfo(index, name, subgroup, class, classFileName)
    raidRoster[index] = {
        name = name,
        subgroup = subgroup,
        class = class,
        classFileName = classFileName
    }
end

function M:ClearRaidRoster()
    wipe(raidRoster)
end

function M:SetGlyph(socketId, glyphSpellId)
    glyphSockets[socketId] = glyphSpellId
end

function M:ClearGlyphs()
    wipe(glyphSockets)
end

function M:SetThreatState(sourceUnit, mobUnit, isTanking, status)
    threatStates[sourceUnit .. "->" .. mobUnit] = {
        isTanking = isTanking,
        status = status
    }
end

function M:ClearThreatStates()
    wipe(threatStates)
end

-- Мокк функции UnitGUID
UnitGUID = function(unitId)
    return unitGuids[unitId] or "0x0000000000000000"
end

UnitExists = function(unitId)
    return unitGuids[unitId] ~= nil
end

UnitName = function(unitId)
    return unitNames[unitId]
end

GetNumGlyphSockets = function()
    return 6
end

GetGlyphSocketInfo = function(socketId)
    return true, 1, glyphSockets[socketId], "glyph_icon"
end

UnitDetailedThreatSituation = function(sourceUnit, mobUnit)
    local threat = threatStates[sourceUnit .. "->" .. mobUnit]
    if not threat then
        return nil
    end

    return threat.isTanking, threat.status
end

UnitThreatSituation = function(sourceUnit, mobUnit)
    local threat = threatStates[sourceUnit .. "->" .. mobUnit]
    return threat and threat.status or nil
end

-- Мокки для проверки состава группы/рейда
IsInRaid = function()
    return M.isInRaid or false
end

GetNumRaidMembers = function()
    return M.raidSize or 0
end

GetRaidRosterInfo = function(index)
    local member = raidRoster[index]
    if not member then
        return nil
    end

    return member.name, nil, member.subgroup, nil, member.class, member.classFileName
end

GetNumPartyMembers = function()
    return M.partySize or 0
end

local function isGroupInCombat()
    if UnitAffectingCombat("player") then
        return true
    end

    for i = 1, (M.partySize or 0) do
        if UnitAffectingCombat("party" .. i) then
            return true
        end
    end

    for i = 1, (M.raidSize or 0) do
        if UnitAffectingCombat("raid" .. i) then
            return true
        end
    end

    return false
end

C_Timer = {
    After = function(_, callback)
        local timer = {
            callback = callback,
            cancelled = false
        }

        function timer:Cancel()
            self.cancelled = true
        end

        return timer
    end,
    NewTimer = function(_, callback)
        local timer = {
            callback = callback,
            cancelled = false
        }

        function timer:Cancel()
            self.cancelled = true
        end

        return timer
    end,
    NewTicker = function(_, callback)
        local ticker = {
            callback = callback,
            cancelled = false
        }

        function ticker:Cancel()
            self.cancelled = true
        end

        return ticker
    end
}

function M:GetAddon(name)
    if addons[name] then
        return addons[name]
    end

    local addon = {
        Debug = function()
        end
    }
    function addon.GetUnitIdFromGUID(guid, filter)
        for unitId, unitGuid in pairs(unitGuids) do
            if unitGuid == guid then
                if filter ~= "player" or unitId == "player" then
                    return unitId
                end
            end
        end
    end
    addon.IsGroupInCombat = isGroupInCombat
    addon.C_Timer = C_Timer
    function addon:NewModule(moduleName, mixins)
        return {
            name = moduleName,
            OnInitialize = function()
            end,
            OnEnable = function()
            end,
            RegisterEvent = AceEvent.RegisterEvent,
            UnregisterEvent = AceEvent.UnregisterEvent,
            SendMessage = AceEvent.SendMessage,
            RegisterMessage = AceEvent.RegisterMessage,
            Print = function()
            end
        }
    end
    addons[name] = addon
    return addon
end

function M:NewModule(name)
    local module = {
        name = name,
        OnInitialize = function()
        end,
        OnEnable = function()
        end,
        RegisterEvent = AceEvent.RegisterEvent,
        UnregisterEvent = AceEvent.UnregisterEvent,
        SendMessage = AceEvent.SendMessage,
        RegisterMessage = AceEvent.RegisterMessage,
        Print = function(...)
            local str = ""
            for i, v in ipairs(...) do
                str = str .. tostring(v)
            end
            print(str)
        end,
        Debug = function()
        end

    }

    return module
end

function M:New(target)
    return {}
end

function M:NewAddon(name)
    local module = {
        name = name,
        OnInitialize = function()
        end,
        OnEnable = function()
        end,
        RegisterEvent = AceEvent.RegisterEvent,
        UnregisterEvent = AceEvent.UnregisterEvent,
        SendMessage = AceEvent.SendMessage,
        RegisterMessage = AceEvent.RegisterMessage,
        Print = function(...)
            local str = ""
            for i, v in ipairs(...) do
                str = str .. tostring(v)
            end
            print(str)
        end,
        Debug = function()
        end
    }

    module.IsGroupInCombat = isGroupInCombat
    module.C_Timer = C_Timer
    function module:NewModule(moduleName, mixins)
        return M:NewModule(moduleName, mixins)
    end
    addons[name] = module

    return module
end

LibStub = function(name)
    return M
end

time = function()
    return 1234567890
end
Text = function(text)
    return text
end
date = function(format, timestamp)
    return "SOME DATE"
end

GetTime = function()
    return 1234567890
end

GetSpellTexture = function(spellName)
    return "texture_path"
end

-- Мокк для проверки боевого состояния юнитов
UnitAffectingCombat = function(unitId)
    -- Проверяем самого игрока
    if unitId == "player" then
        return M.UnitAffectingCombat1 ~= false
    end

    -- Проверяем участников группы
    local partyIndex = unitId:match("party(%d+)")
    if partyIndex then
        local index = tonumber(partyIndex) + 1 -- +1 because player is index 1
        return M["UnitAffectingCombat" .. index] ~= false
    end

    -- Проверяем участников рейда
    local raidIndex = unitId:match("raid(%d+)")
    if raidIndex then
        return M["UnitAffectingCombat" .. raidIndex] ~= false
    end

    return true -- По умолчанию считаем что в бою
end

InCombatLockdown = function()
    return UnitAffectingCombat("player")
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
