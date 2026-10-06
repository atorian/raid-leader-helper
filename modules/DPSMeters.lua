local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local DPSMeters = RLHelper:NewModule("DPSMeters", "AceEvent-3.0")

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
                if self.source == "Recount" then self.killed = nil end
            end)
        end
        self.hookedRecount = recount
    end
end

function DPSMeters:BossKilled(boss)
    if self.source == "Skada" and Skada then
        self.killed = { boss = boss, set = Skada.current }
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
            starttime = Recount.InCombatT, specs = specs }
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
        endtime = finish, players = {} }
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
