-- Persisted journal records describe addon decisions, not combat-log subevents.
local Journal = {}
Journal.MAX_COMBATS = 30
Journal.MAX_EVENTS = 20000

function Journal.Log(addon, log, kind, event, legacyMessage, severity, fields)
    if addon.journalV2Enabled then
        log(Journal.Create(kind, event, severity, fields))
    else
        log(legacyMessage)
    end
end

function Journal.Copy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do copy[key] = Journal.Copy(child) end
    return copy
end

function Journal.Entity(guid, name)
    if not guid and not name then return nil end
    local entity = { guid = guid, name = name }
    -- Resolve class while the participant is available, never when reading history.
    if type(UnitGUID) == "function" and type(UnitClass) == "function" then
        local units = { "player", "target", "focus" }
        for i = 1, (GetNumRaidMembers and GetNumRaidMembers() or 0) do
            units[#units + 1] = "raid" .. i
        end
        for i = 1, (GetNumPartyMembers and GetNumPartyMembers() or 0) do
            units[#units + 1] = "party" .. i
        end
        for _, unit in ipairs(units) do
            if guid and UnitGUID(unit) == guid then
                local _, class = UnitClass(unit)
                entity.class = class
                break
            end
        end
    end
    return entity
end

function Journal.TauntType(guid)
    local hasAssignments, isMember = false, false
    if not guid or type(GetRaidRosterInfo) ~= "function" or type(UnitGUID) ~= "function" then
        return "INFO"
    end
    for i = 1, (GetNumRaidMembers and GetNumRaidMembers() or 0) do
        local _, _, _, _, _, _, _, _, _, role = GetRaidRosterInfo(i)
        local memberGUID = UnitGUID("raid" .. i)
        if memberGUID == guid then isMember = true end
        if role == "MAINTANK" then
            hasAssignments = true
            if memberGUID == guid then return "INFO" end
        end
    end
    return hasAssignments and isMember and "TACTIC_VIOLATION" or "INFO"
end

local descriptions = {
    FIRST_DAMAGE = "Первый урон",
    FIRST_HEAL = "Первый хил",
    TAUNT = "Провокация",
    SPELL_USE = "Применение способности",
    DISPEL = "Рассеивание",
    RESURRECT = "Боевое воскрешение",
    VORTEX_HIT = "Вихрь по хилеру",
    VORTEX_MISSED = "Вихрь не попал",
    BLOODBOLT_SPLASH = "Сплеш кровавой стрелы",
    MANA_BARRIER_REMOVED = "Леди: щит разбит",
    MIND_CONTROL = "Контроль разума",
    CYCLONE_APPLIED = "Циклон",
    CYCLONE_MISSED = "Циклон не сработал",
    SPIRIT_HIT = "Взорвал духа",
    SPIRIT_MISSED = "Дух промахнулся автоатакой",
    SPIRIT_SUMMARY = "Итог по духам",
    MALLEABLE_GOO = "Вязкая гадость",
    CHOKING_GAS = "Удушливый газ",
    MALLEABLE_GOO_SUMMARY = "Вязкая гадость: итог",
    CHOKING_GAS_SUMMARY = "Удушливый газ: итог",
    SHADOW_TRAP = "Взорвал ловушку",
    RAGING_SPIRIT = "Гневный дух",
    TRAMPLE_HIT = "Размазало об стену",
    FIRST_TWILIGHT_ENTRY = "Первый вход во тьму",
    FIRST_LIGHT_DAMAGE = "Первый урон по Халиону в свету",
    LIGHT_DAMAGE_WINDOW_CLOSED = "Окно первого урона в свету закрыто",
    MECHANIC_DEATH = "Смерть после попадания механики",
    MISDIRECTION_START = "Начало напула",
    MISDIRECTION_DAMAGE = "Урон напула",
    MISDIRECTION_SUMMARY = "Напул окончен, урон",
}

function Journal.Create(kind, event, severity, fields)
    event = event or {}
    local entry = {
        timestamp = event.timestamp or time(),
        type = severity or "INFO",
        kind = kind,
        source = Journal.Entity(event.sourceGUID, event.sourceName),
        target = Journal.Entity(event.destGUID, event.destName),
        spellId = event.spellId,
        amount = event.amount,
        missType = event.missType,
        extraSpellId = event.extraSpellId,
    }
    for key, value in pairs(fields or {}) do entry[key] = Journal.Copy(value) end
    if not entry.text then
        local parts = { descriptions[kind] or kind }
        if entry.source then parts[#parts + 1] = entry.source.name or "?" end
        if entry.target then parts[#parts + 1] = "→ " .. (entry.target.name or "?") end
        if entry.amount then parts[#parts + 1] = tostring(entry.amount) end
        if entry.missType then parts[#parts + 1] = entry.missType end
        entry.text = table.concat(parts, " ")
    end
    return entry
end

function Journal.Visible(entry, view)
    if view == "MISDIRECTION" then return entry.pullId ~= nil and not entry.hidden end
    if view == "DEATHS" then return entry.kind == "MECHANIC_DEATH" end
    return entry.kind ~= "MISDIRECTION_DAMAGE"
end

function Journal.Format(entry)
    local message = entry.text
    local icon = ""
    if entry.kind == "FIRST_DAMAGE" or entry.kind == "FIRST_HEAL" then
        message = string.format("|cFFFFFFFF%s|r %s по |cFFFFFFFF%s|r",
            entry.source and entry.source.name or "?", descriptions[entry.kind],
            entry.target and entry.target.name or "?")
    elseif entry.spellId and type(GetSpellInfo) == "function" then
        local _, _, texture = GetSpellInfo(entry.spellId)
        if texture then icon = "|T" .. texture .. ":18:18:0:-2|t " end
    end
    local text = date("%H:%M:%S", entry.timestamp) .. " " .. icon .. message
    if entry.type == "TACTIC_VIOLATION" then
        text = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
        return "|cFFFF0000[НАРУШЕНИЕ] " .. text .. "|r"
    end
    return text
end

function Journal.PullTargets(combat, pullId)
    local targets, order = {}, {}
    for _, entry in ipairs(combat.events or {}) do
        if entry.pullId == pullId and entry.kind == "MISDIRECTION_DAMAGE" and entry.target then
            local key = entry.target.guid or entry.target.name
            if key then
                if not targets[key] then
                    targets[key] = { target = entry.target, amount = 0 }
                    order[#order + 1] = targets[key]
                end
                targets[key].amount = targets[key].amount + (entry.amount or 0)
            end
        end
    end
    return order
end

_G.RLHelperJournal = Journal
return Journal
