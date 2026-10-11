-- Journal exchange is deliberately limited to raids in the Ruby Sanctum (3.3.5a).
local Sync = {}
Sync.__index = Sync
Sync.PREFIX = "RLHRS1"
local Journal = RLHelperJournal
local fields = {
    "timestamp", "kind", "type", "subevent", "spellId", "amount", "missType",
    "extraSpellId", "extraSpellName", "pullId", "hidden", "identityTime",
    "auraSpellId", "auraName", "sourceIsTank", "targetIsTank", "targetIsBoss",
    "source.guid", "source.name", "source.class", "target.guid", "target.name", "target.class",
}
local kinds = {
    FIRST_DAMAGE = true, TAUNT = true, SPELL_USE = true, DISPEL = true, RESURRECT = true,
    FIRST_TWILIGHT_ENTRY = true, FIRST_LIGHT_DAMAGE = true, LIGHT_DAMAGE_WINDOW_CLOSED = true,
    MECHANIC_DEATH = true, MISDIRECTION_START = true, MISDIRECTION_DAMAGE = true, MISDIRECTION_SUMMARY = true,
}
local singletons = { FIRST_DAMAGE = true, FIRST_TWILIGHT_ENTRY = true }

local function encode(value)
    if value == nil then return "-" end
    if type(value) == "boolean" then return value and "b1" or "b0" end
    if type(value) == "number" then return "n" .. string.format("%.17g", value) end
    return "s" .. value:gsub("[^%w _%.%-]", function(char) return string.format("%%%02X", char:byte()) end)
end

local function decode(token)
    if token == "-" then return nil, true end
    if token == "b1" or token == "b0" then return token == "b1", true end
    if token:sub(1, 1) == "n" then
        local number = tonumber(token:sub(2))
        return number, number ~= nil and number == number and math.abs(number) < math.huge
    end
    if token:sub(1, 1) ~= "s" then return nil, false end
    local value = token:sub(2)
    if value:gsub("%%[A-Fa-f0-9][A-Fa-f0-9]", ""):find("[^%w _%.%-]") then return nil, false end
    return value:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end), true
end

local function entityId(entity)
    return entity and (entity.guid or entity.name) or ""
end

-- A fingerprint of the fact, independent of clocks, local counters and presentation.
-- Occurrences with this fingerprint are matched separately, across observers only.
function Sync.Hash(entry)
    local identity
    if singletons[entry.kind] then identity = entry.kind
    elseif entry.kind == "MECHANIC_DEATH" then identity = entry.kind .. ":" .. entityId(entry.target)
    else
        local parts = { entry.kind, entityId(entry.source), entityId(entry.target),
            entry.spellId or "", entry.extraSpellId or "", entry.missType or "", entry.subevent or "" }
        if entry.kind == "MISDIRECTION_DAMAGE" then parts[#parts + 1] = entry.amount or 0 end
        for i, value in ipairs(parts) do parts[i] = encode(value) end
        identity = table.concat(parts, "|")
    end
    local a, b = 5381, 52711
    for i = 1, #identity do
        a = (a * 33 + identity:byte(i)) % 4294967296
        b = (b * 33 + identity:byte(#identity - i + 1)) % 4294967296
    end
    return string.format("%08x%08x", a, b)
end

function Sync.New(addon)
    local self = setmetatable({ addon = addon, serial = 0, session = tostring(time()) }, Sync)
    self:Reset()
    return self
end

function Sync:Reset(keepOutgoing)
    if keepOutgoing and self.startedAt then
        self.previous = { combat = self.addon.currentCombat, startedAt = self.startedAt, endedAt = GetTime(),
            records = self.records, pullIds = self.pullIds, nextPullId = self.nextPullId }
    elseif not keepOutgoing then
        if self.timer then self.timer:Cancel() end
        self.timer, self.previous, self.queue = nil, nil, {}
    end
    self.startedAt = nil
    self.pending, self.records, self.pullIds = {}, {}, {}
    self.nextPullId = 1
end

function Sync:Enabled()
    return self.addon.currentInstanceId == 724 and GetNumRaidMembers() > 0 and self.addon.inCombat
end

function Sync:Observe(entry, observer, token, observedAt, context)
    context = context or self
    entry.hash = Sync.Hash(entry)
    local bucket = context.records[entry.hash] or {}
    context.records[entry.hash] = bucket
    observedAt = observedAt or GetTime()
    local pullKey = entry.pullId and (observer .. ":" .. entry.pullId)
    local pullId = pullKey and context.pullIds[pullKey]
    for _, record in ipairs(bucket) do
        local previous = record.entry
        local sameToken = token and record.observers[observer] == token
        local sameTime = math.abs((previous.identityTime or previous.timestamp) -
            (entry.identityTime or entry.timestamp)) <= 0.5
        local sameOccurrence = singletons[entry.kind] or sameToken or
            (not record.observers[observer] and (sameTime or math.abs(record.observedAt - observedAt) <= 1)) or
            (not token and previous.timestamp == entry.timestamp)
        if entry.kind == "MISDIRECTION_SUMMARY" then sameOccurrence = pullId == previous.pullId end
        if sameOccurrence then
            record.observers[observer] = token or true
            if pullKey then context.pullIds[pullKey], entry.pullId = previous.pullId, previous.pullId end
            local changed = false
            if entry.type == "TACTIC_VIOLATION" and previous.type ~= entry.type then
                previous.type, changed = entry.type, true
            end
            for _, key in ipairs({ "source", "target" }) do
                if previous[key] and entry[key] and not previous[key].class and entry[key].class then
                    previous[key].class, changed = entry[key].class, true
                end
            end
            if entry.kind == "MISDIRECTION_SUMMARY" and (entry.amount or 0) > (previous.amount or 0) then
                previous.amount, previous.text, changed = entry.amount, entry.text, true
            end
            return false, changed, record
        end
    end
    if pullKey then
        if not pullId then
            pullId, context.nextPullId = context.nextPullId, context.nextPullId + 1
            context.pullIds[pullKey] = pullId
        end
        entry.pullId = pullId
    end
    local record = { entry = entry, observedAt = observedAt, observers = { [observer] = token or true } }
    bucket[#bucket + 1] = record
    return true, false, record
end

local function serialize(entry, combat)
    local parts = { encode(combat.isBoss), encode(combat.firstEnemy), encode(combat.startTime) }
    for _, path in ipairs(fields) do
        local parent, child = path:match("^(%w+)%.(%w+)$")
        local value = entry[path]
        if parent then value = entry[parent] and entry[parent][child] end
        parts[#parts + 1] = encode(value)
    end
    return table.concat(parts, "|")
end

local function deserialize(payload)
    local tokens = {}
    for token in (payload .. "|"):gmatch("([^|]*)|") do tokens[#tokens + 1] = token end
    if #tokens ~= #fields + 3 then return end
    local values = {}
    for i, token in ipairs(tokens) do
        local value, valid = decode(token)
        if not valid then return end
        values[i] = value
    end
    local entry = {}
    for i, path in ipairs(fields) do
        local parent, child = path:match("^(%w+)%.(%w+)$")
        local value = values[i + 3]
        if parent and value ~= nil then
            entry[parent] = entry[parent] or {}
            entry[parent][child] = value
        elseif not parent then entry[path] = value end
    end
    if not kinds[entry.kind] or (entry.type ~= "INFO" and entry.type ~= "TACTIC_VIOLATION") or
        type(entry.timestamp) ~= "number" or (entry.identityTime ~= nil and type(entry.identityTime) ~= "number") or
        (entry.pullId ~= nil and (type(entry.pullId) ~= "number" or entry.pullId <= 0 or entry.pullId % 1 ~= 0)) or
        (entry.kind:sub(1, 12) == "MISDIRECTION" and not entry.pullId) then return end
    for _, key in ipairs({ "spellId", "amount", "extraSpellId", "auraSpellId" }) do
        if entry[key] ~= nil and type(entry[key]) ~= "number" then return end
    end
    for _, key in ipairs({ "subevent", "missType", "extraSpellName", "auraName" }) do
        if entry[key] ~= nil and type(entry[key]) ~= "string" then return end
    end
    for _, key in ipairs({ "hidden", "sourceIsTank", "targetIsTank", "targetIsBoss" }) do
        if entry[key] ~= nil and type(entry[key]) ~= "boolean" then return end
    end
    for _, key in ipairs({ "source", "target" }) do
        for _, value in pairs(entry[key] or {}) do if type(value) ~= "string" then return end end
    end
    if type(values[1]) ~= "boolean" or (values[2] ~= nil and type(values[2]) ~= "string") then return end
    if type(values[3]) ~= "number" then return end
    return Journal.Create(entry.kind, entry, entry.type, entry), values[1], values[2], values[3]
end

function Sync:Queue(entry, observedAt)
    if not self:Enabled() or not kinds[entry.kind] or type(SendAddonMessage) ~= "function" then return end
    self.startedAt = self.startedAt or GetTime()
    self.serial = self.serial + 1
    local payload = serialize(entry, self.addon.currentCombat)
    local count = math.ceil(#payload / 180)
    if count > 32 then return end
    local id = self.session .. "-" .. self.serial
    -- Damage details must not delay deaths, casts or Halion's mechanic records.
    local position = #self.queue + 1
    local bulk = entry.kind == "MISDIRECTION_DAMAGE"
    if not bulk then
        for index, packet in ipairs(self.queue) do
            if packet.bulk then position = index break end
        end
    end
    for index = 1, count do
        table.insert(self.queue, position + index - 1, { id = id, index = index, count = count, bulk = bulk,
            observedAt = observedAt or GetTime(), startedAt = self.startedAt, payload = payload:sub((index - 1) * 180 + 1, index * 180) })
    end
    if not self.timer then
        self.timer = (self.addon.C_Timer or C_Timer).NewTicker(0.4, function() self:Flush() end)
    end
end

function Sync:Flush()
    if self.addon.currentInstanceId ~= 724 or GetNumRaidMembers() == 0 then self:Reset() return end
    local now = GetTime()
    local packet = table.remove(self.queue, 1)
    while packet and packet.startedAt ~= self.startedAt and
        (not self.previous or packet.startedAt ~= self.previous.startedAt or now - self.previous.endedAt > 30) do
        packet = table.remove(self.queue, 1)
    end
    if packet then
        local header = string.format("%s:%d:%d:%.2f:%.2f:", packet.id, packet.index, packet.count,
            math.max(0, now - packet.observedAt), math.max(0, now - packet.startedAt))
        SendAddonMessage(Sync.PREFIX, header .. packet.payload, "RAID")
    end
    if #self.queue == 0 and self.timer then self.timer:Cancel() self.timer = nil end
end

function Sync:Receive(prefix, packet, channel, sender)
    if prefix ~= Sync.PREFIX or channel ~= "RAID" or self.addon.currentInstanceId ~= 724 or GetNumRaidMembers() == 0 or
        type(packet) ~= "string" or #packet > 240 or type(sender) ~= "string" or sender == UnitName("player") then return end
    local member = false
    for i = 1, GetNumRaidMembers() do
        if UnitName("raid" .. i) == sender then member = true break end
    end
    if not member then return end
    local id, index, count, age, combatAge, body = packet:match("^(%d+%-%d+):(%d+):(%d+):([%d.]+):([%d.]+):(.*)$")
    index, count, age, combatAge = tonumber(index), tonumber(count), tonumber(age), tonumber(combatAge)
    if not id or not age or not combatAge or count < 1 or count > 32 or index < 1 or index > count or #body > 180 then return end
    local now = GetTime()
    local key = sender .. ":" .. id
    local pendingCount = 0
    for pendingKey, pending in pairs(self.pending) do
        if now - pending.at > 30 then self.pending[pendingKey] = nil else pendingCount = pendingCount + 1 end
    end
    local pending = self.pending[key]
    if not pending then
        if pendingCount >= 64 then return end
        pending = { at = now, count = count, parts = {}, received = 0 }
        self.pending[key] = pending
    end
    if pending.count ~= count then self.pending[key] = nil return end
    if not pending.parts[index] then pending.parts[index], pending.received = body, pending.received + 1 end
    if pending.received ~= count then return end
    self.pending[key] = nil
    local entry, isBoss, firstEnemy, startTime = deserialize(table.concat(pending.parts))
    if not entry then return end
    local context, combat
    if self:Enabled() then
        self.startedAt = self.startedAt or now
        context, combat = self, self.addon.currentCombat
    end
    local previous = self.previous
    if previous and now - previous.endedAt <= 30 and
        (not combat or math.abs(previous.combat.startTime - startTime) < math.abs(combat.startTime - startTime)) then
        context, combat = previous, previous.combat
    end
    -- Per-combat wall time is only a coarse routing guard; it is never part of the hash.
    if not combat or math.abs(combat.startTime - startTime) > 10 or
        math.abs(now - context.startedAt - combatAge) > 10 or now - age < context.startedAt - 1 then return end
    if isBoss then combat.isBoss = true end
    combat.firstEnemy = combat.firstEnemy or firstEnemy
    self.addon:OnCombatLogEvent(entry, sender, id, now - age, combat, context)
end

_G.RLHelperJournalSync = Sync
return Sync
