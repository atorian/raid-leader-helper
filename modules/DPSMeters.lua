local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local DPSMeters = RLHelper:NewModule("DPSMeters", "AceEvent-3.0")
local PUTRICIDE = RLHelperBossIds.NPCS.PROFESSOR_PUTRICIDE
-- Неустойчивый слизнюк and Облако газа, checked on wotlk.ezhead.org.
local OOZE_NPCS = { [37697] = true, [37562] = true }
-- Gas Cloud target debuffs, checked on wotlk.ezhead.org.
local GAS_BLOAT = { [70672] = true, [72455] = true, [72832] = true, [72833] = true }
local DAMAGE_EVENTS = { SWING_DAMAGE = true, RANGE_DAMAGE = true, SPELL_DAMAGE = true,
    SPELL_PERIODIC_DAMAGE = true, DAMAGE_SHIELD = true }

DPSMeters.receivesCombatEvents = true
DPSMeters.zoneGateInstanceId = RLHelperBossIds.INSTANCES.ICECROWN_CITADEL

local function isOoze(guid)
    return guid and OOZE_NPCS[tonumber(guid:sub(9, 12), 16)]
end

-- Meter totals merge enemies by name. Keep separate GUIDs for repeated ooze spawns.
function DPSMeters:handleEvent(event)
    if not self.complete or RLHelper.currentInstanceId ~= self.zoneGateInstanceId then return end
    local segment, number
    if self.source == "Skada" and Skada then segment = Skada.current
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
    if source == "Skada" then
        return Skada ~= nil and type(Skada.RegisterCallback) == "function"
    elseif source == "Recount" then
        return Recount ~= nil and type(Recount.LeaveCombat) == "function" and
            type(Recount.MergedPetDamageDPS) == "function" and Recount.db2 ~= nil
    end
    return false
end

function DPSMeters:Stop()
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
    self.source, self.complete = source, complete
    self:RegisterMessage("COMBAT_BOSS_DEFEATED", "SkadaSetComplete")
    if not self:IsAvailable(source) then return end
    if DBM and type(DBM.RegisterCallback) == "function" and type(DBM.UnregisterCallback) == "function" then
        self.dbmKill = self.dbmKill or function(_, mod)
            local npc = mod and (mod.creatureId or (mod.combatInfo and mod.combatInfo.mob))
            local encounter = RLHelperBossIds.DPS_ENCOUNTER_BY_NPC[npc]
            if encounter and encounter.instance == RLHelper.currentInstanceId then self:BossKilled(npc) end
        end
        self.dbm = DBM
        DBM:RegisterCallback("DBM_Kill", self.dbmKill)
    end
    if source == "Skada" then
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
    if self.source == "Skada" and Skada then
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

return DPSMeters
