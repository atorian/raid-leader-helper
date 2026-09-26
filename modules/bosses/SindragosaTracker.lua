local RLHelper = LibStub("AceAddon-3.0"):GetAddon("RLHelper")
local SindragosaTracker = RLHelper:NewModule("SindragosaTracker", "AceEvent-3.0")
SindragosaTracker.receivesCombatEvents = true
SindragosaTracker.zoneGateInstanceId = 631
SindragosaTracker.bossIds = { [36853] = "Синдрагоса" }

local INSTABILITY = 69766
local BACKLASH = { [71045] = true, [71046] = true } -- 10/25 heroic
local AIR_YELLS = {
    ["Здесь ваше вторжение и окончится! Никто не уцелеет."] = true,
    ["Your incursion ends here! None shall survive!"] = true,
    ["Rikk zilthuras rikk zila Aman adare tiriosh"] = true,
}

function SindragosaTracker:reset()
    self.stacks = {}
    self.airPhase = 0
    self.lastAirYell = nil
end

function SindragosaTracker:OnInitialize()
    self:reset()
    self.log = function(...) RLHelper:OnCombatLogEvent(...) end
end

function SindragosaTracker:OnEnable()
    self:RegisterMessage("RLHelper_CombatEnded", "reset")
    self:RegisterEvent("CHAT_MSG_MONSTER_YELL")
end

function SindragosaTracker:OnDisable()
    self:reset()
end

function SindragosaTracker:IsHeroic()
    local _, instanceType, difficulty, _, _, dynamicDifficulty, isDynamic = GetInstanceInfo()
    return instanceType == "raid" and (difficulty == 3 or difficulty == 4 or
        ((isDynamic == true or isDynamic == 1) and dynamicDifficulty == 1))
end

function SindragosaTracker:handleEvent(event)
    if not self:IsHeroic() then return end
    local context = self.context or RLHelper
    local now = event.timestamp or GetTime()
    if event.spellId == INSTABILITY and context:IsGroupMember(event.destGUID, event.destFlags) then
        if event.event == "SPELL_AURA_APPLIED" or event.event == "SPELL_AURA_APPLIED_DOSE" then
            self.stacks[event.destGUID] = { count = event.amount or 1 }
        elseif event.event == "SPELL_AURA_REMOVED" and self.stacks[event.destGUID] then
            -- Real 3.3.5a logs remove the aura before delivering Backlash damage.
            self.stacks[event.destGUID].removedAt = now
        end
    elseif BACKLASH[event.spellId] and
        (event.event == "SPELL_DAMAGE" or event.event == "SPELL_MISSED") then
        local stacks = self.stacks[event.sourceGUID]
        if not stacks then return end
        self.stacks[event.sourceGUID] = nil
        if stacks.removedAt and now - stacks.removedAt > 1 then return end
        -- One explosion can hit many targets, including absorbed/immune targets.
        local severity = stacks.count > 2 and "TACTIC_VIOLATION" or "INFO"
        RLHelperJournal.Log(self.log, "UNCHAINED_MAGIC_EXPLOSION", event, severity, {
            stacks = stacks.count,
            text = string.format("Взрыв Освобожденной магии: %s стаков", stacks.count),
        })
    elseif event.event == "UNIT_DIED" then
        self.stacks[event.destGUID] = nil
    end
end

local function markSkadaSegment(segment, name)
    if not segment then return end
    segment.mobname = name
    segment.gotboss = segment.gotboss or true
end

function SindragosaTracker:splitSkada(name)
    if type(Skada) ~= "table" then return end
    if Skada.current and type(Skada.NewSegment) == "function" then
        markSkadaSegment(Skada.current, Skada.current.mobname or "Синдрагоса")
        Skada:NewSegment()
    elseif not Skada.current and type(Skada.StartCombat) == "function" then
        Skada:StartCombat()
    else
        return
    end
    markSkadaSegment(Skada.current, name)
end

local function markDetailsSegment(details, name)
    local combat
    if type(details.GetCurrentCombat) == "function" then
        combat = details:GetCurrentCombat()
    elseif type(details.GetCombat) == "function" then
        combat = details:GetCombat("current")
    else
        combat = details.tabela_vigente
    end
    if type(combat) ~= "table" then return end
    combat.enemy = name or combat.enemy or "Синдрагоса"
    combat.is_boss = type(combat.is_boss) == "table" and combat.is_boss or {}
    combat.is_boss.name = combat.enemy
    combat.is_boss.encounter = combat.enemy
end

function SindragosaTracker:splitDetails(name)
    local details = _G._detalhes or _G.Details
    if type(details) ~= "table" or type(details.SairDoCombate) ~= "function" or
        type(details.EntrarEmCombate) ~= "function" then return end
    if details.in_combat then
        markDetailsSegment(details)
        details:SairDoCombate()
    end
    details:EntrarEmCombate()
    markDetailsSegment(details, name)
end

function SindragosaTracker:splitRecount()
    if type(Recount) == "table" and type(Recount.ResetFightData) == "function" then
        Recount:ResetFightData()
    end
end

function SindragosaTracker:CHAT_MSG_MONSTER_YELL(_, message)
    if not RLHelper.inCombat or RLHelper.currentInstanceId ~= self.zoneGateInstanceId then return end
    local airYell = false
    for yell in pairs(AIR_YELLS) do
        if message and message:find(yell, 1, true) then airYell = true; break end
    end
    if not airYell then return end
    local now = GetTime()
    if self.lastAirYell and now - self.lastAirYell < 5 then return end
    self.lastAirYell = now
    self.airPhase = self.airPhase + 1
    local name = string.format("Синдрагоса — глыбы %s", self.airPhase)
    for _, meter in ipairs({ "Skada", "Details", "Recount" }) do
        local ok, err = pcall(self["split" .. meter], self, name)
        if not ok then RLHelper:Debug("SindragosaTracker: %s: %s", meter, tostring(err)) end
    end
end

SindragosaTracker.demoOrder = 9
function SindragosaTracker:RunDemo(demo)
    self:reset()
    self.IsHeroic = function() return true end
    demo:Event(self, "SPELL_AURA_APPLIED", demo.players.mage, demo.players.mage, INSTABILITY)
    demo:Event(self, "SPELL_AURA_APPLIED_DOSE", demo.players.mage, demo.players.mage, INSTABILITY, { amount = 4 })
    demo:Event(self, "SPELL_AURA_REMOVED", demo.players.mage, demo.players.mage, INSTABILITY)
    demo:Event(self, "SPELL_DAMAGE", demo.players.mage, demo.players.priest, 71046, { amount = 8000 })
end

return SindragosaTracker
