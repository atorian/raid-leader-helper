-- Versioned, text-only account settings transfer. Never evaluates imported Lua.
local Transfer = {}
RLHelperSettingsTransfer = Transfer
local fields = {}
local function field(path, kind, limit)
    fields[#fields + 1] = { path = path, kind = kind, limit = limit }
end
for _, key in ipairs({ "enabled", "debug", "gpAwardButtonsEnabled", "displayOnlyInGroup",
    "bossOnlyHistory", "igor", "halionBurstPull", "halionBurstReset", "halionPhaseTwoEntryTimer" }) do
    field({key}, "boolean")
end
-- Keep the retired slot so RLH1/RLH2/RLH3 strings retain their field positions.
fields[4].obsolete = true
field({"theme"}, "theme")
field({"pullCancelMessage"}, "string")
field({"discordLink"}, "string")
field({"minimap", "hide"}, "boolean")
for _, amount in ipairs({100, 200, 250, 500, 1000}) do
    field({"gpAwardReasons", amount}, "string")
end
for _, key in ipairs({"point", "relativePoint"}) do field({"savedPosition", key}, "point") end
for _, key in ipairs({"x", "y"}) do field({"savedPosition", key}, "number", 100000) end
for _, key in ipairs({"width", "height"}) do field({"savedPosition", key}, "size", 100000) end
field({"epAwards", "rt"}, "time")
field({"epAwards", "dpsSource"}, "source")
for _, key in ipairs({"attendance", "icc", "rs", "toc", "saurfang"}) do
    field({"epAwards", "amounts", key}, "integer", 99999)
end
for _, key in ipairs({"attendance", "icc", "rs", "toc"}) do
    field({"epAwards", "reminders", key}, "boolean")
end
local specs = {71,72,73,250,251,252,65,66,70,253,254,255,259,260,261,
    256,257,258,262,263,264,62,63,64,265,266,267,102,103,104,105}
for _, spec in ipairs(specs) do
    field({"epAwards", "saurfangThresholds", spec}, "integer", 999999)
end
local points = {TOPLEFT=true, TOP=true, TOPRIGHT=true, LEFT=true, CENTER=true,
    RIGHT=true, BOTTOMLEFT=true, BOTTOM=true, BOTTOMRIGHT=true}
local function valid(value, descriptor)
    if value == nil then return true end
    local kind = descriptor.kind
    if kind == "boolean" then return type(value) == "boolean" end
    if kind == "number" or kind == "size" or kind == "integer" then
        return type(value) == "number" and value == value and math.abs(value) <= descriptor.limit
            and (kind ~= "size" or value > 0)
            and (kind ~= "integer" or (value >= 0 and value == math.floor(value)))
    end
    if type(value) ~= "string" or #value > 4096 or value:find("%c") then return false end
    if kind == "theme" then return value == "current" or value == "minimal" end
    if kind == "source" then return value == "Details" or value == "Skada" or value == "Recount" or value == "ErrorDPSCounter" end
    if kind == "point" then return points[value] == true end
    if kind == "time" then
        local h, m = value:match("^(%d%d):(%d%d)$")
        return h ~= nil and tonumber(h) < 24 and tonumber(m) < 60
    end
    return true
end
local function encode(value)
    if value == nil then return "-" end
    if type(value) == "boolean" then return value and "b1" or "b0" end
    if type(value) == "number" then return "n" .. string.format("%.17g", value) end
    return "s" .. value:gsub(".", function(c) return string.format("%02X", c:byte()) end)
end
function Transfer.Export(profile)
    local tokens = {"RLH1"}
    for _, descriptor in ipairs(fields) do
        local value
        local parent = profile
        for i = 1, #descriptor.path - 1 do parent = type(parent) == "table" and parent[descriptor.path[i]] or nil end
        if not descriptor.obsolete and type(parent) == "table" then value = parent[descriptor.path[#descriptor.path]] end
        if not valid(value, descriptor) then return nil, "Недопустимое значение настройки." end
        tokens[#tokens + 1] = encode(value)
    end
    local ep = profile.epAwards
    local putricide = ep and (ep.putricideMode ~= nil or ep.putricideOozeDamage ~= nil)
    local bosses = ep and ep.dpsBosses
    if putricide and not bosses then bosses = {} end
    if bosses then
        if type(bosses) ~= "table" then return nil, "Недопустимые настройки планок DPS." end
        tokens[1] = putricide and "RLH3" or "RLH2"
        local ids = {}
        for id, thresholds in pairs(bosses) do
            local encounter = RLHelperBossIds and RLHelperBossIds.DPS_ENCOUNTER_BY_NPC[id]
            if not encounter or encounter.id ~= id or type(thresholds) ~= "table" then
                return nil, "Недопустимые настройки планок DPS."
            end
            ids[#ids + 1] = id
        end
        table.sort(ids)
        tokens[#tokens + 1] = tostring(#ids)
        for _, id in ipairs(ids) do
            tokens[#tokens + 1] = tostring(id)
            for _, spec in ipairs(specs) do
                local value = bosses[id][spec]
                if not valid(value, {kind = "integer", limit = 999999}) then
                    return nil, "Недопустимое значение планки DPS."
                end
                tokens[#tokens + 1] = encode(value)
            end
        end
    end
    if putricide then
        if (ep.putricideMode ~= nil and ep.putricideMode ~= "boss" and ep.putricideMode ~= "ooze") or
            not valid(ep.putricideOozeDamage, {kind = "integer", limit = 999999}) then
            return nil, "Недопустимые настройки планки Мерзоцида."
        end
        tokens[#tokens + 1] = encode(ep.putricideMode)
        tokens[#tokens + 1] = encode(ep.putricideOozeDamage)
    end
    tokens[#tokens + 1] = "END"
    local text = table.concat(tokens, "|")
    if #text > 65536 then return nil, "Настройки слишком велики для переноса." end
    return text
end
function Transfer.Decode(text)
    local errorMessage = "Строка настроек повреждена или имеет неподдерживаемый формат."
    if type(text) ~= "string" or #text > 65536 then return nil, errorMessage end
    text = text:gsub("%s", "")
    local tokens = {}
    for token in (text .. "|"):gmatch("(.-)|") do tokens[#tokens + 1] = token end
    local putricide = tokens[1] == "RLH3"
    local extended = tokens[1] == "RLH2" or putricide
    if (tokens[1] ~= "RLH1" and not extended) or tokens[#tokens] ~= "END" or
        (not extended and #tokens ~= #fields + 2) or (extended and #tokens < #fields + 3) then
        return nil, errorMessage
    end
    local profile = {}
    for index, descriptor in ipairs(fields) do
        local token, value = tokens[index + 1]
        if token == "b1" then value = true
        elseif token == "b0" then value = false
        elseif token:match("^n[%-+%d.eE]+$") then
            value = tonumber(token:sub(2))
            if not value then return nil, errorMessage end
        elseif token:match("^s%x*$") and #token % 2 == 1 then
            value = token:sub(2):gsub("%x%x", function(hex) return string.char(tonumber(hex, 16)) end)
        elseif token ~= "-" then return nil, errorMessage end
        if not valid(value, descriptor) then return nil, errorMessage end
        if value ~= nil and not descriptor.obsolete then
            local parent = profile
            for i = 1, #descriptor.path - 1 do
                local key = descriptor.path[i]
                parent[key] = parent[key] or {}
                parent = parent[key]
            end
            parent[descriptor.path[#descriptor.path]] = value
        end
    end
    if extended then
        local cursor = #fields + 2
        local count = tonumber(tokens[cursor])
        local catalog = RLHelperBossIds and RLHelperBossIds.DPS_ENCOUNTERS
        if not catalog or not count or count < 0 or count > #catalog or count ~= math.floor(count) or
            #tokens ~= #fields + 3 + count * (#specs + 1) + (putricide and 2 or 0) then return nil, errorMessage end
        profile.epAwards = profile.epAwards or {}
        local bosses = {}
        profile.epAwards.dpsBosses = bosses
        for _ = 1, count do
            cursor = cursor + 1
            local id = tonumber(tokens[cursor])
            local encounter = RLHelperBossIds.DPS_ENCOUNTER_BY_NPC[id]
            if not encounter or encounter.id ~= id or bosses[id] then return nil, errorMessage end
            local thresholds = {}
            bosses[id] = thresholds
            for _, spec in ipairs(specs) do
                cursor = cursor + 1
                local token = tokens[cursor]
                if token ~= "-" then
                    local value = token:match("^n[%-+%d.eE]+$") and tonumber(token:sub(2))
                    if not value or not valid(value, {kind = "integer", limit = 999999}) then
                        return nil, errorMessage
                    end
                    thresholds[spec] = value
                end
            end
        end
        if putricide then
            local mode, damage = tokens[cursor + 1], tokens[cursor + 2]
            if mode == "s626F7373" then profile.epAwards.putricideMode = "boss"
            elseif mode == "s6F6F7A65" then profile.epAwards.putricideMode = "ooze"
            elseif mode ~= "-" then return nil, errorMessage end
            if damage ~= "-" then
                local value = damage:match("^n[%-+%d.eE]+$") and tonumber(damage:sub(2))
                if not value or not valid(value, {kind = "integer", limit = 999999}) then return nil, errorMessage end
                profile.epAwards.putricideOozeDamage = value
            end
        end
    end
    if profile.savedPosition then
        for _, key in ipairs({"point", "relativePoint", "x", "y", "width", "height"}) do
            if profile.savedPosition[key] == nil then return nil, errorMessage end
        end
    end
    if profile.epAwards then
        local ep = profile.epAwards
        ep.rt, ep.dpsSource = ep.rt or "19:00", ep.dpsSource or "Details"
        ep.amounts, ep.reminders = ep.amounts or {}, ep.reminders or {}
        if not ep.dpsBosses then ep.saurfangThresholds = ep.saurfangThresholds or {} end
    end
    return profile
end
function Transfer.Apply(profile, imported)
    -- Replace only supported settings; leave unrelated and character data untouched.
    for _, descriptor in ipairs(fields) do profile[descriptor.path[1]] = nil end
    for key, value in pairs(imported) do profile[key] = value end
end
return Transfer
