local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local DPSMeters = RLHelper:NewModule("DPSMeters", "AceEvent-3.0")
local PUTRICIDE = RLHelperBossIds.NPCS.PROFESSOR_PUTRICIDE
-- Неустойчивый слизнюк and Облако газа, checked on wotlk.ezhead.org.
local OOZE_NPCS = { [37697] = true, [37562] = true }
-- Gas Cloud target debuffs, checked on wotlk.ezhead.org.
local GAS_BLOAT = { [70672] = true, [72455] = true, [72832] = true, [72833] = true }
local DAMAGE_EVENTS = { SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true, DAMAGE_SHIELD = true }

-- Supported API baselines, verified against the upstream source snapshots.
-- Skada 1.8.73 r361 introduced actorPrototype:GetDPS (r360 has no method).
-- Recount r1127 is the verified 3.3.5a baseline (X-Curse-Packaged-Version).
-- Details-WotLK exposes its plugin API version independently of its build number.
DPSMeters.sources = { "Details", "Skada", "Recount" }
DPSMeters.requirements = "Поддерживаемые версии для WoW 3.3.5a:\nSkada: 1.8.73 (r361) и новее.\nRecount: r1127+ или v3.3 / v4.0.1.\nDetails: API 140 и новее."

local ErrorDPSCounter = {}
function ErrorDPSCounter:Report(action)
    RLHelper:Debug("ErrorDPSCounter: " .. action ..
        ": нет совместимого DPS-аддона (не установлен или неправильная версия). " .. DPSMeters.requirements)
end

local function metadata(source, key)
    return GetAddOnMetadata and GetAddOnMetadata(source, key)
end

DPSMeters.receivesCombatEvents = true
DPSMeters.zoneGateInstanceId = RLHelperBossIds.INSTANCES.ICECROWN_CITADEL

local function isOoze(guid)
    return guid and OOZE_NPCS[tonumber(guid:sub(9, 12), 16)]
end

-- Meter totals merge enemies by name. Keep separate GUIDs for repeated ooze spawns.
function DPSMeters:handleEvent(event)
    if self.source == "ErrorDPSCounter" then ErrorDPSCounter:Report(event.event); return end
    if not self.complete or RLHelper.currentInstanceId ~= self.zoneGateInstanceId then return end
    local segment, number
    if self.source == "Details" and Details then segment = Details:GetCurrentCombat()
    elseif self.source == "Skada" and Skada then segment = Skada.current
    elseif self.source == "Recount" and Recount and Recount.InCombat then
        segment, number = Recount.db2, Recount.db2.FightNum
    end
    if not segment then return end
    if self.oozeSegment ~= segment or self.oozeNumber ~= number then
        self.oozeSegment, self.oozeNumber = segment, number
        self.oozeDamage, self.gasTargets = {}, {}
        self.petOwners = self.petOwners or {}
    end
    for _, guid in pairs({ event.sourceGUID, event.destGUID }) do
        if isOoze(guid) then self.oozeDamage[guid] = self.oozeDamage[guid] or {} end
    end
    if event.event == "SPELL_AURA_APPLIED" and GAS_BLOAT[event.spellId] and event.destName and
        event.destGUID and event.destGUID:sub(1, 6) == "0x0000" then
        self.gasTargets[event.destName] = (self.gasTargets[event.destName] or 0) + 1
    end
    if event.event ~= "SPELL_SUMMON" and not (DAMAGE_EVENTS[event.event] and isOoze(event.destGUID)) then return end
    local owners = self.petOwners
    local sourceName = event.sourceGUID and owners[event.sourceGUID]
    if not sourceName and event.sourceGUID then
        if event.sourceGUID:sub(1, 6) == "0x0000" then sourceName = event.sourceName
        else
            for i = 1, GetNumRaidMembers() do
                if UnitGUID("raidpet" .. i) == event.sourceGUID then
                    sourceName = UnitName("raid" .. i)
                    owners[event.sourceGUID] = sourceName
                    break
                end
            end
        end
    end
    if event.event == "SPELL_SUMMON" and sourceName and event.destGUID then
        owners[event.destGUID] = sourceName
    end
    if DAMAGE_EVENTS[event.event] and isOoze(event.destGUID) and sourceName and event.amount then
        local damage = self.oozeDamage[event.destGUID]
        local amount = math.max(0, event.amount - math.max(0, event.overkill or 0))
        damage[sourceName] = (damage[sourceName] or 0) + amount
    end
end

-- Sources publish plain completed fights: source, boss, starttime, endtime,
-- players = { { name, class, spec, dps } }. Award rules belong to the consumer.
function DPSMeters:IsAvailable(source)
    local meter = _G[source]
    if not meter then return false, "не загружен" end
    local api, versionOK
    if source == "Details" then
        local combat = type(meter.GetCurrentCombat) == "function" and meter:GetCurrentCombat()
        api = type(meter.CreateEventListener) == "function" and type(meter.RegisterEvent) == "function" and
            type(meter.UnregisterEvent) == "function" and combat and
            type(combat.GetActorList) == "function" and type(combat.GetCombatTime) == "function" and
            type(combat.GetStartTime) == "function" and type(combat.GetEndTime) == "function"
        versionOK = (tonumber(meter.APIVersion) or 0) >= 140
    elseif source == "Skada" then
        local version = metadata(source, "Version") or meter.version or ""
        local major, minor, patch, revision = tostring(version):match("^(%d+)%.(%d+)%.(%d+)%.?(%d*)")
        major, minor, patch = tonumber(major), tonumber(minor), tonumber(patch)
        revision = tonumber(revision) or tonumber(metadata(source, "X-Revision")) or 0
        versionOK = major and (major > 1 or (major == 1 and
            (minor > 8 or (minor == 8 and (patch > 73 or (patch == 73 and revision >= 361))))))
        api = type(meter.RegisterCallback) == "function" and type(meter.UnregisterCallback) == "function" and
            meter.actorPrototype and type(meter.actorPrototype.GetDPS) == "function"
    elseif source == "Recount" then
        local version = metadata(source, "X-Curse-Packaged-Version") or metadata(source, "Version") or ""
        local revision = tonumber(tostring(version):match("^[rR](%d+)"))
        local major, minor, patch = tostring(version):match("^[vV]?(%d+)%.(%d+)%.?(%d*)")
        -- Historical release names and 30300 ports must still expose the collection API.
        major, minor, patch = tonumber(major), tonumber(minor), tonumber(patch)
        versionOK = (revision and revision >= 1127) or (major == 3 and minor == 3) or
            (major == 4 and minor == 0 and patch == 1 and tostring(metadata(source, "Interface")) == "30300")
        api = type(meter.LeaveCombat) == "function" and type(meter.MergedPetDamageDPS) == "function" and
            type(meter.db2) == "table" and type(meter.db2.combatants) == "table" and
            type(meter.db2.FightNum) == "number"
    end
    if not versionOK then return false, "неподходящая версия" end
    if not api then return false, "нет нужного API" end
    return true
end

function DPSMeters:ResolveSource(source)
    if self:IsAvailable(source) then return source end
    for _, candidate in ipairs(self.sources) do
        if self:IsAvailable(candidate) then return candidate end
    end
    return "ErrorDPSCounter"
end

function DPSMeters:GetSourceText(source)
    if source == "ErrorDPSCounter" then return "|cffff3333Нет источника DPS|r" end
    local available = self:IsAvailable(source)
    return available and source or ("|cffff3333" .. source .. "|r")
end

function DPSMeters:Stop()
    if self.source == "ErrorDPSCounter" then ErrorDPSCounter:Report("Stop") end
    if self.detailsListener then
        for _, event in ipairs({ "COMBAT_PLAYER_LEAVE", "COMBAT_PLAYER_ENTER", "DETAILS_DATA_RESET" }) do
            self.detailsListener:UnregisterEvent(event)
        end
        self.detailsListener = nil
    end
    if self.skada then
        self.skada.UnregisterCallback(self, "Skada_SetComplete")
        self.skada = nil
    end
    if self.dbm then
        self.dbm:UnregisterCallback("DBM_Kill", self.dbmKill)
        self.dbm = nil
    end
    self.source, self.complete, self.killed = nil, nil, nil
    self.oozeSegment, self.oozeNumber, self.oozeDamage, self.gasTargets, self.petOwners = nil, nil, nil, nil, nil
end

function DPSMeters:Start(source, complete)
    self:Stop()
    self.source, self.complete = self:ResolveSource(source), complete
    source = self.source
    if source == "ErrorDPSCounter" then ErrorDPSCounter:Report("Start"); return end
    self:RegisterMessage("COMBAT_BOSS_DEFEATED", "SkadaSetComplete")
    if DBM and type(DBM.RegisterCallback) == "function" and type(DBM.UnregisterCallback) == "function" then
        self.dbmKill = self.dbmKill or function(_, mod)
            local npc = mod and (mod.creatureId or (mod.combatInfo and mod.combatInfo.mob))
            local encounter = RLHelperBossIds.DPS_ENCOUNTER_BY_NPC[npc]
            if encounter and encounter.instance == RLHelper.currentInstanceId then self:BossKilled(npc) end
        end
        self.dbm = DBM
        DBM:RegisterCallback("DBM_Kill", self.dbmKill)
    end
    if source == "Details" then
        self.detailsListener = Details:CreateEventListener()
        self.detailsListener:RegisterEvent("COMBAT_PLAYER_LEAVE", function(_, combat) self:DetailsFightComplete(combat) end)
        for _, event in ipairs({ "COMBAT_PLAYER_ENTER", "DETAILS_DATA_RESET" }) do
            self.detailsListener:RegisterEvent(event, function()
                self.killed, self.oozeSegment, self.oozeDamage, self.gasTargets, self.petOwners = nil, nil, nil, nil, nil
            end)
        end
    elseif source == "Skada" then
        self.skada = Skada
        Skada.RegisterCallback(self, "Skada_SetComplete", "SkadaSetComplete")
    elseif self.hookedRecount ~= Recount then
        local recount = Recount
        -- Secure post-hooks leave Recount's own collection and segment handling intact.
        hooksecurefunc(recount, "LeaveCombat", function(_, finish) self:RecountFightComplete(recount, finish) end)
        if type(recount.ResetData) == "function" then
            hooksecurefunc(recount, "ResetData", function()
                if self.source == "Recount" then
                    self.killed, self.oozeSegment, self.oozeDamage, self.gasTargets, self.petOwners = nil, nil, nil, nil, nil
                end
            end)
        end
        self.hookedRecount = recount
    end
end

function DPSMeters:BossKilled(boss)
    if self.source == "ErrorDPSCounter" then ErrorDPSCounter:Report("BossKilled"); return end
    if self.source == "Details" and Details then
        local combat, specs = Details:GetCurrentCombat(), {}
        for i = 1, GetNumRaidMembers() do
            local unit = "raid" .. i
            local guid = UnitGUID(unit)
            if guid then
                local _, class = UnitClass(unit)
                specs[guid] = RLHelper.GetUnitSpec(unit, class)
            end
        end
        self.killed = { boss = boss, set = combat, specs = specs,
            oozeDamage = boss == PUTRICIDE and self.oozeSegment == combat and self.oozeDamage or nil,
            gasTargets = boss == PUTRICIDE and self.oozeSegment == combat and self.gasTargets or nil }
    elseif self.source == "Skada" and Skada then
        self.killed = { boss = boss, set = Skada.current,
            oozeDamage = boss == PUTRICIDE and self.oozeSegment == Skada.current and self.oozeDamage or nil,
            gasTargets = boss == PUTRICIDE and self.oozeSegment == Skada.current and self.gasTargets or nil }
    elseif self.source == "Recount" and self:IsAvailable("Recount") and Recount.InCombat then
        local specs = {}
        -- Freeze specs at the kill, before players can change talents after combat.
        for i = 1, GetNumRaidMembers() do
            local unit = "raid" .. i
            local guid = UnitGUID(unit)
            if guid then
                local _, class = UnitClass(unit)
                specs[guid] = RLHelper.GetUnitSpec(unit, class)
            end
        end
        self.killed = { boss = boss, db = Recount.db2, number = Recount.db2.FightNum,
            starttime = Recount.InCombatT, specs = specs,
            oozeDamage = boss == PUTRICIDE and self.oozeSegment == Recount.db2 and
                self.oozeNumber == Recount.db2.FightNum and self.oozeDamage or nil,
            gasTargets = boss == PUTRICIDE and self.oozeSegment == Recount.db2 and
                self.oozeNumber == Recount.db2.FightNum and self.gasTargets or nil }
    end
end

function DPSMeters:SkadaSetComplete(_, set)
    if self.source == "ErrorDPSCounter" then ErrorDPSCounter:Report("SkadaSetComplete"); return end
    local encounters = RLHelperBossIds.DPS_ENCOUNTER_BY_NPC
    local killedEncounter = self.killed and encounters[self.killed.boss]
    local setEncounter = set and encounters[set.gotboss]
    local confirmedKill = set and self.killed and self.killed.set == set and
        (self.killed.boss == set.gotboss or (killedEncounter and killedEncounter == setEncounter))
    if self.source ~= "Skada" or not self.complete or not Skada or not set or not set.endtime or
        not set.gotboss or (not set.success and not confirmedKill) then return end
    -- Skada also completes phase segments; consume only the whole fight.
    if set ~= Skada.current and set ~= Skada.last then return end
    -- Skada may identify a vehicle/add; DBM supplies the encounter's registered boss.
    local boss = set.gotboss
    if not setEncounter and killedEncounter and self.killed.set == set then boss = self.killed.boss end
    local fight = { source = "Skada", boss = boss, starttime = set.starttime,
        endtime = set.endtime, players = {} }
    if boss == PUTRICIDE then
        fight.oozeDamage = confirmedKill and self.killed.oozeDamage or
            (self.oozeSegment == set and self.oozeDamage or nil)
        fight.gasTargets = confirmedKill and self.killed.gasTargets or
            (self.oozeSegment == set and self.gasTargets or nil)
    end
    for _, player in ipairs(set.players or {}) do
        fight.players[#fight.players + 1] = { name = player.name, class = player.class, spec = player.spec,
            dps = type(player.GetDPS) == "function" and player:GetDPS() or nil }
    end
    self.killed = nil
    self.complete(fight)
end

function DPSMeters:RecountFightComplete(recount, finish)
    if self.source == "ErrorDPSCounter" then ErrorDPSCounter:Report("RecountFightComplete"); return end
    if self.source ~= "Recount" or not self.complete or recount ~= Recount then return end
    local killed = self.killed
    self.killed = nil
    -- LeaveCombat moves CurrentFightData to LastFightData and increments FightNum.
    -- A reset, discarded short fight or another segment cannot reuse the kill marker.
    if not killed or killed.db ~= recount.db2 or killed.starttime ~= recount.InCombatT or
        recount.db2.FightNum ~= killed.number + 1 or recount.InCombat then return end
    local fight = { source = "Recount", boss = killed.boss, starttime = killed.starttime,
        endtime = finish, players = {}, oozeDamage = killed.oozeDamage, gasTargets = killed.gasTargets }
    for name, player in pairs(recount.db2.combatants) do
        if (player.type == "Self" or player.type == "Grouped") and player.LastFightIn == killed.number and
            player.Fights and player.Fights.LastFightData then
            local _, dps = recount:MergedPetDamageDPS(player, "LastFightData")
            fight.players[#fight.players + 1] = { name = player.Name or name, class = player.enClass,
                spec = killed.specs[player.GUID], dps = dps }
        end
    end
    self.complete(fight)
end

function DPSMeters:DetailsFightComplete(combat)
    if self.source == "ErrorDPSCounter" then ErrorDPSCounter:Report("DetailsFightComplete"); return end
    if self.source ~= "Details" or not self.complete then return end
    local killed = self.killed
    self.killed = nil
    if not combat or not killed or killed.set ~= combat or not combat:GetEndTime() then return end
    local duration = combat:GetCombatTime()
    if duration <= 0 then return end
    -- Details uses GetTime() for segment bounds; persist epoch timestamps like the other sources.
    local finish = time() - (GetTime() - combat:GetEndTime())
    local fight = { source = "Details", boss = killed.boss, starttime = finish - duration,
        endtime = finish, players = {}, oozeDamage = killed.oozeDamage, gasTargets = killed.gasTargets }
    for _, player in ipairs(combat:GetActorList(1)) do
        -- Group actors already include their pets' damage in total.
        if player.grupo and not player.owner then
            fight.players[#fight.players + 1] = { name = player.nome, class = player.classe,
                spec = killed.specs[player.serial] or player.spec, dps = player.total / duration }
        end
    end
    self.complete(fight)
end

return DPSMeters
