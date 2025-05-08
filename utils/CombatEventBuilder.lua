local GUIDGenerator = {
    playerCounter = 0,
    npcCounter = 0,
    petCounter = 0
}

local BOSS_FLAGS = 0x60a48
local ENEMY_FLAGS = 0xa48
local PLAYER_FLAGS = 0x511

function GUIDGenerator:Reset()
    self.playerCounter = 0
    self.npcCounter = 0
    self.petCounter = 0
end

function GUIDGenerator:GeneratePlayerGUID()
    self.playerCounter = self.playerCounter + 1
    return string.format("0x%016d", self.playerCounter)
end

function GUIDGenerator:GenerateNPCGUID()
    self.npcCounter = self.npcCounter + 1
    return string.format("0xF13%013d", self.npcCounter)
end

function GUIDGenerator:GeneratePetGUID()
    self.petCounter = self.petCounter + 1
    return string.format("0xF14%013d", self.petCounter)
end

local CombatEventBuilder = {}
CombatEventBuilder.__index = CombatEventBuilder

function CombatEventBuilder:New()
    local instance = {
        timestamp = GetTime(),
        event = nil,
        source = {
            guid = "0x0000000000000000",
            name = "Unknown",
            flags = 0
        },
        target = {
            guid = "0x0000000000000000", 
            name = "Unknown",
            flags = 0
        },
        spell = {
            id = nil,
            name = nil,
            school = 0x1
        },
        amount = 0,
        type = "BUFF"
    }
    setmetatable(instance, CombatEventBuilder)
    return instance
end

function CombatEventBuilder:Reset()
    GUIDGenerator:Reset()
    return self
end

-- Методы для установки источника
function CombatEventBuilder:FromPlayer(name)
    self.source.guid = GUIDGenerator:GeneratePlayerGUID()
    self.source.name = name or UnitName("player")
    self.source.flags = PLAYER_FLAGS
    return self
end

function CombatEventBuilder:FromEnemy(name)
    self.source.guid = GUIDGenerator:GenerateNPCGUID()
    self.source.name = name
    self.source.flags = ENEMY_FLAGS
    return self
end

function CombatEventBuilder:FromPet(name)
    self.source.guid = GUIDGenerator:GeneratePetGUID()
    self.source.name = name
    self.source.flags = 0x1111 -- Pet flags
    return self
end

-- Методы для установки цели
function CombatEventBuilder:ToPlayer(name)
    self.target.guid = GUIDGenerator:GeneratePlayerGUID() 
    self.target.name = name or UnitName("player")
    self.target.flags = PLAYER_FLAGS
    return self
end

function CombatEventBuilder:ToEnemy(name)
    self.target.guid = GUIDGenerator:GenerateNPCGUID()
    self.target.name = name
    self.target.flags = ENEMY_FLAGS
    return self
end

function CombatEventBuilder:ToPet(name)
    self.target.guid = GUIDGenerator:GeneratePetGUID()
    self.target.name = name
    self.target.flags = 0x1111 -- Pet flags
    return self
end

-- Методы для установки типа события
function CombatEventBuilder:Damage(amount)
    self.event = "SWING_DAMAGE"
    self.amount = amount
    return self
end

function CombatEventBuilder:SpellDamage(spellId, spellName, amount)
    self.event = "SPELL_DAMAGE"
    self.spell.id = spellId
    self.spell.name = spellName
    self.amount = amount
    return self
end

function CombatEventBuilder:Death()
    self.event = "UNIT_DIED"
    return self
end

function CombatEventBuilder:ApplyAura(spellId, spellName, auraType)
    self.event = "SPELL_AURA_APPLIED"
    self.spell.id = spellId
    self.spell.name = spellName
    self.type = auraType or "BUFF"
    return self
end

function CombatEventBuilder:RemoveAura(spellId, spellName)
    self.event = "SPELL_AURA_REMOVED"
    self.spell.id = spellId
    self.spell.name = spellName
    return self
end

-- Построить и вернуть событие в формате COMBAT_LOG_EVENT_UNFILTERED
function CombatEventBuilder:Build()
    if self.event == "SWING_DAMAGE" then
        return "COMBAT_LOG_EVENT_UNFILTERED", self.timestamp, self.event,
            self.source.guid, self.source.name, self.source.flags,
            self.target.guid, self.target.name, self.target.flags,
            self.amount, -- amount
            0,          -- overkill
            1,          -- school (physical)
            0,          -- resisted
            0,          -- blocked
            0,          -- absorbed
            false,      -- critical
            false,      -- glancing
            false       -- crushing
    elseif self.event == "SPELL_DAMAGE" then
        return "COMBAT_LOG_EVENT_UNFILTERED", self.timestamp, self.event,
            self.source.guid, self.source.name, self.source.flags,
            self.target.guid, self.target.name, self.target.flags,
            self.spell.id, self.spell.name, self.spell.school,
            self.amount, -- amount
            0,          -- overkill
            self.spell.school, -- school
            0,          -- resisted
            0,          -- blocked
            0,          -- absorbed
            false,      -- critical
            false,      -- glancing
            false       -- crushing
    elseif self.event == "UNIT_DIED" then
        -- 4/22 20:33:49.642  UNIT_DIED,0x0000000000000000,nil,0x80000000,0x0000000000327B39,"Zippo",0x514
        return "COMBAT_LOG_EVENT_UNFILTERED", self.timestamp, self.event,
            "0x0000000000000000", nil, 0x80000000,
            self.target.guid, self.target.name, self.target.flags
    elseif self.event == "SPELL_AURA_APPLIED" or self.event == "SPELL_AURA_REMOVED" then
        return "COMBAT_LOG_EVENT_UNFILTERED", self.timestamp, self.event,
            self.source.guid, self.source.name, self.source.flags,
            self.target.guid, self.target.name, self.target.flags,
            self.spell.id, self.spell.name, self.spell.school,
            self.type,    -- auraType (BUFF/DEBUFF)
            1            -- amount (используется для стаков баффа)
    end
end

return CombatEventBuilder