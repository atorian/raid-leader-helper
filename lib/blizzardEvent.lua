local function blizzardEvent(timestamp, event, sourceGUID, sourceName, sourceFlags, destGUID, destName, destFlags, ...)
    local args = {}
    args.timestamp = timestamp
    args.event = event
    args.sourceGUID = sourceGUID
    args.sourceName = sourceName
    args.sourceFlags = sourceFlags
    args.destGUID = destGUID
    args.destName = destName
    args.destFlags = destFlags

    if event == "SWING_DAMAGE" then
        args.amount, args.overkill, args.school, args.resisted, args.blocked, args.absorbed, args.critical, args.glancing, args.crushing =
            select(1, ...)
    elseif event == "SWING_MISSED" then
        args.spellName = ACTION_SWING
        args.missType = select(1, ...)
    elseif event:sub(1, 5) == "RANGE" then
        args.spellId, args.spellName, args.spellSchool = select(1, ...)
        if event == "RANGE_DAMAGE" then
            args.amount, args.overkill, args.school, args.resisted, args.blocked, args.absorbed, args.critical, args.glancing, args.crushing =
                select(4, ...)
        elseif event == "RANGE_MISSED" then
            args.missType = select(4, ...)
        end
    elseif event:sub(1, 5) == "SPELL" then
        args.spellId, args.spellName, args.spellSchool = select(1, ...)
        if event == "SPELL_DAMAGE" then
            args.amount, args.overkill, args.school, args.resisted, args.blocked, args.absorbed, args.critical, args.glancing, args.crushing =
                select(4, ...)
        elseif event == "SPELL_MISSED" then
            args.missType, args.amountMissed = select(4, ...)
        elseif event == "SPELL_HEAL" then
            args.amount, args.overheal, args.absorbed, args.critical = select(4, ...)
            args.school = args.spellSchool
        elseif event == "SPELL_ENERGIZE" then
            args.valueType = 2
            args.amount, args.powerType = select(4, ...)
        elseif event:sub(1, 14) == "SPELL_PERIODIC" then
            if event == "SPELL_PERIODIC_MISSED" then
                args.missType = select(4, ...)
            elseif event == "SPELL_PERIODIC_DAMAGE" then
                args.amount, args.overkill, args.school, args.resisted, args.blocked, args.absorbed, args.critical, args.glancing, args.crushing =
                    select(4, ...)
            elseif event == "SPELL_PERIODIC_HEAL" then
                args.amount, args.overheal, args.absorbed, args.critical = select(4, ...)
                args.school = args.spellSchool
            elseif event == "SPELL_PERIODIC_DRAIN" then
                args.amount, args.powerType, args.extraAmount = select(4, ...)
                args.valueType = 2
            elseif event == "SPELL_PERIODIC_LEECH" then
                args.amount, args.powerType, args.extraAmount = select(4, ...)
                args.valueType = 2
            elseif event == "SPELL_PERIODIC_ENERGIZE" then
                args.amount, args.powerType = select(4, ...)
                args.valueType = 2
            end
        elseif event == "SPELL_DRAIN" then
            args.amount, args.powerType, args.extraAmount = select(4, ...)
            args.valueType = 2
        elseif event == "SPELL_LEECH" then
            args.amount, args.powerType, args.extraAmount = select(4, ...)
            args.valueType = 2
        elseif event == "SPELL_INTERRUPT" then
            args.extraSpellId, args.extraSpellName, args.extraSpellSchool = select(4, ...)
        elseif event == "SPELL_EXTRA_ATTACKS" then
            args.amount = select(4, ...)
        elseif event == "SPELL_DISPEL_FAILED" then
            args.extraSpellId, args.extraSpellName, args.extraSpellSchool = select(4, ...)
        elseif event == "SPELL_AURA_DISPELLED" then
            args.extraSpellId, args.extraSpellName, args.extraSpellSchool = select(4, ...)
            args.auraType = select(7, ...)
        elseif event == "SPELL_AURA_STOLEN" then
            args.extraSpellId, args.extraSpellName, args.extraSpellSchool = select(4, ...)
            args.auraType = select(7, ...)
        elseif event == "SPELL_AURA_APPLIED" or event == "SPELL_AURA_REMOVED" then
            args.auraType = select(4, ...)
        elseif event == "SPELL_AURA_APPLIED_DOSE" or event == "SPELL_AURA_REMOVED_DOSE" then
            args.auraType, args.amount = select(4, ...)
            args.sourceName = args.destName
            args.sourceGUID = args.destGUID
            args.sourceFlags = args.destFlags
        elseif event == "SPELL_CAST_FAILED" then
            args.missType = select(4, ...)
        end
    elseif event == "DAMAGE_SHIELD" then
        args.spellId, args.spellName, args.spellSchool = select(1, ...)
        args.amount, args.school, args.resisted, args.blocked, args.absorbed, args.critical, args.glancing, args.crushing =
            select(4, ...)
    elseif event == "DAMAGE_SHIELD_MISSED" then
        args.spellId, args.spellName, args.spellSchool = select(1, ...)
        args.missType = select(4, ...)
    elseif event == "ENCHANT_APPLIED" then
        args.spellName = select(1, ...)
        args.itemId, args.itemName = select(2, ...)
    elseif event == "ENCHANT_REMOVED" then
        args.spellName = select(1, ...)
        args.itemId, args.itemName = select(2, ...)
    elseif event == "UNIT_DIED" or event == "UNIT_DESTROYED" then
        args.sourceName = args.destName
        args.sourceGUID = args.destGUID
        args.sourceFlags = args.destFlags
    elseif event == "ENVIRONMENTAL_DAMAGE" then
        args.environmentalType = select(1, ...)
        args.amount, args.overkill, args.school, args.resisted, args.blocked, args.absorbed, args.critical, args.glancing, args.crushing =
            select(2, ...)
        args.spellName = _G["ACTION_" .. event .. "_" .. args.environmentalType]
        args.spellSchool = args.school
    elseif event == "DAMAGE_SPLIT" then
        args.spellId, args.spellName, args.spellSchool = select(1, ...)
        args.amount, args.school, args.resisted, args.blocked, args.absorbed, args.critical, args.glancing, args.crushing =
            select(4, ...)
    end
    return args
end

_G.blizzardEvent = blizzardEvent

return blizzardEvent
