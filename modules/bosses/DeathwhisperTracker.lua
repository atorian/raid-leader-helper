local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local DeathwhisperTracker = RLHelper:NewModule("DeathwhisperTracker", "AceEvent-3.0")
DeathwhisperTracker.bossIds = {
    [36855] = "Леди Смертный Шепот"
}
DeathwhisperTracker.receivesCombatEvents = true

local TRACKED_SPELLS = {
    [71426] = "spirit_summon" -- Призыв духа
}
local LADY_DEATHWHISPER_MANA_BARRIER = 70842
local LADY_DEATHWHISPER_DOMINATE_MIND = 71289
-- Vengeful Blast difficulty variants, verified against wotlk.ezhead.org.
local VENGEFUL_BLAST = { [71544] = true, [72010] = true, [72011] = true, [72012] = true }
local CYCLONE = 33786
local LADY_DEATHWHISPER = "Леди Смертный Шепот"

function DeathwhisperTracker:OnInitialize()
    RLHelper:Debug("DeathwhisperTracker: Инициализация")
    self.currentSpirits = {}
    self.explosions = {}
    self.report = {}
    self.log = function(...)
        RLHelper:OnCombatLogEvent(...)
    end
    self:RegisterMessage("RLHelper_CombatEnding", "summarizeCombat")
    self:RegisterMessage("RLHelper_CombatEnded", "reset")
end

function DeathwhisperTracker:OnEnable()
    RLHelper:Debug("DeathwhisperTracker: Включен")
end

local function isLadyDeathwhisperCombat(RLHelper)
    return RLHelper.currentCombat and RLHelper.currentCombat.firstEnemy == LADY_DEATHWHISPER
end

local function buildSpiritHitSummary(report)
    local names = {}
    local total = 0

    for name, count in pairs(report) do
        total = total + count
        table.insert(names, name)
    end

    if total == 0 then
        return nil
    end

    table.sort(names, function(a, b)
        if report[a] == report[b] then
            return a < b
        end

        return report[a] > report[b]
    end)

    local details = {}
    for _, name in ipairs(names) do
        table.insert(details, string.format("%s(%s)", name, report[name]))
    end

    return {
        total = total,
        details = table.concat(details, " ")
    }
end

-- function DeathwhisperTracker:ZONE_CHANGED_NEW_AREA()
-- local 
-- if 
-- end

-- function DeathwhisperTracker:PLAYER_ENTERING_WORLD()
--
-- end

function DeathwhisperTracker:reset()
    self.currentSpirits = {}
    self.explosions = {}
    self:sendSummaryToRaid()
    self.report = {}
end

function DeathwhisperTracker:summarizeCombat()
    local summary = buildSpiritHitSummary(self.report or {})
    if not summary then
        return
    end

    RLHelperJournal.Log(self.log, "SPIRIT_SUMMARY", nil, "INFO", {
        text = string.format("Духов взорвали: всего %s %s", summary.total, summary.details)
    })
end

function DeathwhisperTracker:sendSummaryToRaid()
    local summary = buildSpiritHitSummary(self.report or {})
    if not summary then
        return
    end

    SendChatMessage(string.format("Духов взорвали: всего %s %s", summary.total, summary.details), "RAID")
end

function DeathwhisperTracker:handleEvent(eventData)
    if eventData.event == "SPELL_CAST_SUCCESS" and eventData.spellId == LADY_DEATHWHISPER_DOMINATE_MIND and
        eventData.destName then
        RLHelperJournal.Log(self.log, "MIND_CONTROL", eventData)
        return
    end

    if isLadyDeathwhisperCombat(self.context or RLHelper) and eventData.spellId == CYCLONE and eventData.sourceName and eventData.destName then
        if eventData.event == "SPELL_AURA_APPLIED" then
            RLHelperJournal.Log(self.log, "CYCLONE_APPLIED", eventData)
            return
        end

        if eventData.event == "SPELL_MISSED" or eventData.event == "DAMAGE_SHIELD_MISSED" then
            RLHelperJournal.Log(self.log, "CYCLONE_MISSED", eventData)
            return
        end
    end

    if eventData.event == "SPELL_AURA_REMOVED" and eventData.spellId == LADY_DEATHWHISPER_MANA_BARRIER then
        RLHelperJournal.Log(self.log, "MANA_BARRIER_REMOVED", eventData)
        return
    end

    if eventData.event == "SPELL_SUMMON" and eventData.spellId == 71426 then
        self.currentSpirits[eventData.destGUID] = {
            name = eventData.destName,
            summonTime = eventData.timestamp
        }
        return
    end

    if VENGEFUL_BLAST[eventData.spellId] and
        (eventData.event == "SPELL_DAMAGE" or eventData.event == "SPELL_MISSED") then
        local explosion = self.explosions[eventData.sourceGUID]
        local isNew = not explosion
        if isNew then
            local spirit = self.currentSpirits[eventData.sourceGUID]
            local attack = spirit and spirit.lastAttack
            if not attack or not attack.destName then return end

            self.currentSpirits[eventData.sourceGUID] = nil
            self.report[attack.destName] = (self.report[attack.destName] or 0) + 1
            attack.timestamp = eventData.timestamp
            attack.missType = nil
            explosion = RLHelperJournal.Create("SPIRIT_HIT", attack, "TACTIC_VIOLATION", {
                updateKey = "spirit:" .. eventData.sourceGUID, raidDamage = 0,
            })
            self.explosions[eventData.sourceGUID] = explosion
        end

        local damage = 0
        local context = self.context or RLHelper
        if eventData.event == "SPELL_DAMAGE" and (eventData.amount or 0) > 0 and
            context:IsGroupMember(eventData.destGUID, eventData.destFlags) then
            local unit = context.groupMembers[eventData.destGUID]
            -- Roster identity survives mind control, which can change player type flags.
            local isPlayer = unit and (type(unit) ~= "string" or not unit:find("pet", 1, true))
            if not unit then
                isPlayer = bit.band(eventData.destFlags or 0, 0x400) > 0 or
                    (eventData.destGUID and eventData.destGUID:sub(1, 5) == "0x000")
            end
            if isPlayer then damage = eventData.amount end
        end
        if isNew or damage > 0 then
            explosion.raidDamage = explosion.raidDamage + damage
            self.log(explosion)
        end
        return
    end

    local spiritInfo = self.currentSpirits[eventData.sourceGUID]
    if not spiritInfo then return end
    if eventData.event == "SWING_DAMAGE" or eventData.event == "SWING_MISSED" then
        -- Keep the attack target: blast splash victims do not identify who triggered it.
        spiritInfo.lastAttack = RLHelperJournal.Copy(eventData)
        if eventData.event == "SWING_MISSED" then
            RLHelperJournal.Log(self.log, "SPIRIT_MISSED", eventData)
        end
    end
end

DeathwhisperTracker.demoOrder = 4
function DeathwhisperTracker:RunDemo(demo)
    self.currentSpirits, self.explosions, self.report = {}, {}, {}
    local p = demo.players
    local boss = demo:Boss(36855, LADY_DEATHWHISPER)
    demo.currentCombat.firstEnemy = LADY_DEATHWHISPER
    demo:Event(self, "SPELL_AURA_REMOVED", boss, boss, LADY_DEATHWHISPER_MANA_BARRIER)
    demo:Event(self, "SPELL_CAST_SUCCESS", boss, p.mage, LADY_DEATHWHISPER_DOMINATE_MIND)
    demo:Event(self, "SPELL_AURA_APPLIED", p.druid, p.mage, CYCLONE)
    demo:Event(self, "SPELL_MISSED", p.druid, p.mage, CYCLONE, { missType = "IMMUNE" })
    for i, target in ipairs({ p.mage, p.hunter }) do
        local spirit = { guid = "demo-spirit-" .. i, name = "Мстительный дух" }
        demo:Event(self, "SPELL_SUMMON", boss, spirit, 71426)
        demo:Event(self, i == 2 and "SWING_MISSED" or "SWING_DAMAGE", spirit, target, nil,
            i == 2 and { missType = "DODGE" } or { amount = 344 })
        if i == 1 then
            demo:Event(self, "SPELL_DAMAGE", spirit, target, 72012, { amount = 17608 })
            demo:Event(self, "SPELL_DAMAGE", spirit, p.priest, 72012, { amount = 12000 })
        end
    end
    self:summarizeCombat()
end


return DeathwhisperTracker
