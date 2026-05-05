local CombatFilters = {}

local IGNORED_COMBAT_ENEMIES = {
    ["World Invisible Trigger"] = true,
    ["Огрская пиньята"] = true,
    ["Робот \"Бей-Молоти\""] = true
}

function CombatFilters:IsIgnoredCombatEnemy(name)
    return IGNORED_COMBAT_ENEMIES[name] == true
end

_G.RLHelperCombatFilters = CombatFilters

return CombatFilters
