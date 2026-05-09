local M = require('tests.mocks')
require('../lib/blizzardEvent')
require('../lib/CombatFilters')
require('../data/BossIds')
local RLHelper = require('../Core')
local Builder = require('../utils/CombatEventBuilder')

local function count(tbl)
    local total = 0
    for _ in pairs(tbl) do
        total = total + 1
    end
    return total
end

local function npcGuid(npcId, spawnId)
    return string.format("0xF13000%04X%06X", npcId, spawnId or npcId)
end

local function setBossModules(modules)
    RLHelper.IterateModules = function()
        return ipairs(modules)
    end
end

describe("Боевая система", function()
    local originalIterateModules

    before_each(function()
        originalIterateModules = RLHelper.IterateModules
        RLHelper:StopCombatTicker()
        RLHelper.inCombat = false
        RLHelper.lastCombatActivityAt = nil
        RLHelper.combatEndRequestedAt = nil
        RLHelper.combatEndRequiresRegen = false
        RLHelper.currentCombat = {
            startTime = nil,
            messages = {},
            firstEnemy = nil,
            isBoss = false
        }
        RLHelper.combatHistory = {}
        RLHelper.DisplayCombat = function()
        end
        RLHelper.mainFrame = {
            logText = {
                AddMessage = function()
                end,
                Clear = function()
                end
            }
        }

        wipe(RLHelper.activeEnemies)
        wipe(RLHelper.activePlayers)
        wipe(RLHelper.enemyEvents)

        RLHelper.db = {
            profile = {
                debug = false,
                combatHistory = {},
                bossOnlyHistory = false
            }
        }

        M:ClearUnitGUIDs()
        M.partySize = 0
        M.raidSize = 0
        M.UnitAffectingCombat1 = true
        M.UnitAffectingCombat2 = false
        M.UnitAffectingCombat3 = false
    end)

    after_each(function()
        RLHelper.IterateModules = originalIterateModules
    end)

    it("начинает бой когда игрок входит в бой", function()
        RLHelper:PLAYER_REGEN_DISABLED()

        assert.is_true(RLHelper.inCombat)
    end)

    it("начинает бой от боевого лога и отслеживает участников", function()
        M.UnitAffectingCombat1 = false

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Враг1"):ToPlayer("Игрок1"):Damage(100):Build())

        assert.is_true(RLHelper.inCombat)
        assert.are.equal(1, count(RLHelper.activeEnemies))
        assert.are.equal(1, count(RLHelper.activePlayers))
        assert.are.equal("Враг1", RLHelper.currentCombat.firstEnemy)
    end)

    it("запрещает прямое добавление сообщения до начала боя", function()
        assert.has.errors(function()
            RLHelper:OnCombatLogEvent("test message")
        end)

        assert.is_false(RLHelper.inCombat)
        assert.is_nil(RLHelper.currentCombat.startTime)
        assert.are.equal(0, #RLHelper.currentCombat.messages)
    end)

    it("переименовывает бой в имя босса по известному npc id без boss1", function()
        M.UnitAffectingCombat1 = false
        RLHelper.currentInstanceId = 631
        setBossModules({
            {
                name = "BloodQueenTracker",
                receivesCombatEvents = true,
                zoneGateInstanceId = 631,
                bossIds = {
                    [37955] = "Кровавая королева Лана'тель"
                }
            }
        })

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Адд"):ToPlayer("Игрок1"):Damage(100):Build())

        local bossEvent = { Builder:New():FromEnemy("Кровавая королева Лана'тель"):ToPlayer("Игрок1"):Damage(100):Build() }
        bossEvent[4] = npcGuid(37955)

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(unpack(bossEvent))

        assert.is_true(RLHelper.currentCombat.isBoss)
        assert.are.equal("Кровавая королева Лана'тель", RLHelper.currentCombat.firstEnemy)
    end)

    it("определяет босса по общему реестру npc id", function()
        M.UnitAffectingCombat1 = false
        RLHelper.currentInstanceId = 631
        setBossModules({})

        local bossEvent = { Builder:New():FromEnemy("Лорд Ребрад"):ToPlayer("Игрок1"):Damage(100):Build() }
        bossEvent[4] = npcGuid(36612)

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(unpack(bossEvent))

        assert.is_true(RLHelper.currentCombat.isBoss)
        assert.are.equal("Лорд Ребрад", RLHelper.currentCombat.firstEnemy)
    end)

    it("не помечает бой со Свалной как Валитрию от ауры на Валитрии", function()
        M.UnitAffectingCombat1 = false
        RLHelper.currentInstanceId = 631
        setBossModules({})

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Сестра Свална"):ToPlayer("Игрок1")
            :Damage(100):Build())

        local auraEvent = { Builder:New():FromPlayer("Игрок1"):ToEnemy("Валитрия Сноходица")
            :ApplyAura(48942, "Аура благочестия", "BUFF"):Build() }
        auraEvent[7] = npcGuid(36789)

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(unpack(auraEvent))

        assert.is_false(RLHelper.currentCombat.isBoss)
        assert.are.equal("Сестра Свална", RLHelper.currentCombat.firstEnemy)
    end)

    it("не помечает бой со Свалной как Валитрию через module bossIds", function()
        M.UnitAffectingCombat1 = false
        RLHelper.currentInstanceId = 631
        setBossModules({
            {
                name = "ValithriaTracker",
                receivesCombatEvents = true,
                zoneGateInstanceId = 631,
                bossIds = {
                    [36789] = "Валитрия Сноходица"
                }
            }
        })

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Сестра Свална"):ToPlayer("Игрок1")
            :Damage(100):Build())

        local auraEvent = { Builder:New():FromPlayer("Игрок1"):ToEnemy("Валитрия Сноходица")
            :ApplyAura(48942, "Аура благочестия", "BUFF"):Build() }
        auraEvent[7] = npcGuid(36789)

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(unpack(auraEvent))

        assert.is_false(RLHelper.currentCombat.isBoss)
        assert.are.equal("Сестра Свална", RLHelper.currentCombat.firstEnemy)
    end)

    it("помечает бой с Валитрией после первого исцеления Валитрии", function()
        M.UnitAffectingCombat1 = false
        RLHelper.currentInstanceId = 631
        setBossModules({})

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Сестра Свална"):ToPlayer("Игрок1")
            :Damage(100):Build())

        local healEvent = { Builder:New():FromPlayer("Игрок1"):ToEnemy("Валитрия Сноходица")
            :SpellHeal(54968, "Символ Света небес", 6038):Build() }
        healEvent[7] = npcGuid(36789)

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(unpack(healEvent))

        assert.is_true(RLHelper.currentCombat.isBoss)
        assert.are.equal("Валитрия Сноходица", RLHelper.currentCombat.firstEnemy)
    end)

    it("определяет босса по destGUID если босс является целью события", function()
        M.UnitAffectingCombat1 = false
        RLHelper.currentInstanceId = 724
        setBossModules({
            {
                name = "HalionTracker",
                receivesCombatEvents = true,
                zoneGateInstanceId = 724,
                bossIds = {
                    [39863] = "Халион"
                }
            }
        })

        local bossEvent = { Builder:New():FromPlayer("Игрок1"):ToEnemy("Халион"):SpellDamage(12345, "Удар", 100):Build() }
        bossEvent[7] = npcGuid(39863)

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(unpack(bossEvent))

        assert.is_true(RLHelper.currentCombat.isBoss)
        assert.are.equal("Халион", RLHelper.currentCombat.firstEnemy)
    end)

    it("не использует boss1 для определения боссового боя", function()
        M.UnitAffectingCombat1 = false
        RLHelper.currentInstanceId = 631
        M:SetUnitGUID("boss1", npcGuid(37955))
        M:SetUnitName("boss1", "Кровавая королева Лана'тель")
        setBossModules({
            {
                name = "BloodQueenTracker",
                receivesCombatEvents = true,
                zoneGateInstanceId = 631,
                bossIds = {
                    [37955] = "Кровавая королева Лана'тель"
                }
            }
        })

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Адд"):ToPlayer("Игрок1"):Damage(100):Build())

        assert.is_false(RLHelper.currentCombat.isBoss)
        assert.are.equal("Адд", RLHelper.currentCombat.firstEnemy)
    end)

    it("игнорирует World Invisible Trigger как название боя", function()
        M.UnitAffectingCombat1 = false

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("World Invisible Trigger"):ToPlayer("Игрок1")
            :Damage(100):Build())
        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Ануб'арак"):ToPlayer("Игрок1")
            :Damage(100):Build())

        assert.are.equal("Ануб'арак", RLHelper.currentCombat.firstEnemy)
    end)

    it("не отслеживает игнорируемых врагов как участников боя", function()
        M.UnitAffectingCombat1 = false

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("World Invisible Trigger"):ToPlayer("Игрок1")
            :Damage(100):Build())

        assert.is_false(RLHelper.inCombat)
        assert.are.equal(0, count(RLHelper.activeEnemies))
        assert.is_nil(RLHelper.currentCombat.firstEnemy)
    end)

    it("не завершает бой сразу по PLAYER_REGEN_ENABLED", function()
        RLHelper:PLAYER_REGEN_DISABLED()
        RLHelper:PLAYER_REGEN_ENABLED()

        assert.is_true(RLHelper.inCombat)
    end)

    it("не завершает бой пока группа еще в бою", function()
        RLHelper:PLAYER_REGEN_DISABLED()
        RLHelper:OnCombatLogEvent("test message")

        M.partySize = 1
        M.UnitAffectingCombat1 = false
        M.UnitAffectingCombat2 = true
        RLHelper.lastCombatActivityAt = RLHelper:GetCombatNow() - 10
        RLHelper.combatEndRequestedAt = RLHelper:GetCombatNow() - 5

        assert.is_false(RLHelper:EvaluateCombatEnd("test"))
        assert.is_true(RLHelper.inCombat)
        assert.are.equal(0, #RLHelper.combatHistory)
    end)

    it("завершает бой после тихого периода вне боя", function()
        RLHelper:PLAYER_REGEN_DISABLED()
        RLHelper:OnCombatLogEvent("test message")

        M.UnitAffectingCombat1 = false
        RLHelper.lastCombatActivityAt = RLHelper:GetCombatNow() - 10
        RLHelper.combatEndRequestedAt = RLHelper:GetCombatNow() - 5

        assert.is_true(RLHelper:EvaluateCombatEnd("test"))
        assert.is_false(RLHelper.inCombat)
        assert.are.equal(1, #RLHelper.combatHistory)
    end)

    it("не завершает бой по тикеру до PLAYER_REGEN_ENABLED", function()
        M.UnitAffectingCombat1 = false

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Враг1"):ToPlayer("Игрок1"):Damage(100):Build())
        RLHelper:PLAYER_REGEN_DISABLED()

        for guid in pairs(RLHelper.activeEnemies) do
            RLHelper.activeEnemies[guid] = RLHelper:GetCombatNow() - 10
        end
        RLHelper.lastCombatActivityAt = RLHelper:GetCombatNow() - 10
        RLHelper.combatEndRequestedAt = nil

        assert.is_false(RLHelper:EvaluateCombatEnd("ticker"))
        assert.is_true(RLHelper.inCombat)
        assert.is_nil(RLHelper.combatEndRequestedAt)
        assert.are.equal("Враг1", RLHelper.currentCombat.firstEnemy)
    end)

    it("завершает бой по таймауту если не было PLAYER_REGEN_DISABLED", function()
        M.UnitAffectingCombat1 = false

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Враг1"):ToPlayer("Игрок1"):Damage(100):Build())

        for guid in pairs(RLHelper.activeEnemies) do
            RLHelper.activeEnemies[guid] = RLHelper:GetCombatNow() - 10
        end
        RLHelper.lastCombatActivityAt = RLHelper:GetCombatNow() - 10
        RLHelper.combatEndRequestedAt = nil

        assert.is_false(RLHelper:EvaluateCombatEnd("ticker"))
        assert.is_not_nil(RLHelper.combatEndRequestedAt)
        RLHelper.combatEndRequestedAt = RLHelper:GetCombatNow() - 5

        assert.is_true(RLHelper:EvaluateCombatEnd("ticker"))
        assert.is_false(RLHelper.inCombat)
        assert.is_nil(RLHelper.currentCombat.firstEnemy)
    end)

    it("сбрасывает имя первого врага после таймаута боя", function()
        M.UnitAffectingCombat1 = false

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Король-лич"):ToPlayer("Игрок1"):Damage(100):Build())

        assert.are.equal("Король-лич", RLHelper.currentCombat.firstEnemy)

        for guid in pairs(RLHelper.activeEnemies) do
            RLHelper.activeEnemies[guid] = RLHelper:GetCombatNow() - 10
        end
        RLHelper.lastCombatActivityAt = RLHelper:GetCombatNow() - 10
        RLHelper.combatEndRequestedAt = RLHelper:GetCombatNow() - 5

        assert.is_true(RLHelper:EvaluateCombatEnd("test"))
        assert.is_false(RLHelper.inCombat)
        assert.is_nil(RLHelper.currentCombat.firstEnemy)
    end)

    it("тикер завершает бой и сбрасывает имя первого врага после PLAYER_REGEN_ENABLED", function()
        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Король-лич"):ToPlayer("Игрок1"):Damage(100):Build())
        RLHelper:PLAYER_REGEN_DISABLED()

        assert.are.equal("Король-лич", RLHelper.currentCombat.firstEnemy)

        M.UnitAffectingCombat1 = false
        RLHelper:PLAYER_REGEN_ENABLED()

        assert.is_true(RLHelper.inCombat)
        assert.is_not_nil(RLHelper.combatTicker)
        assert.is_not_nil(RLHelper.combatEndRequestedAt)

        for guid in pairs(RLHelper.activeEnemies) do
            RLHelper.activeEnemies[guid] = RLHelper:GetCombatNow() - 10
        end
        RLHelper.lastCombatActivityAt = RLHelper:GetCombatNow() - 10
        RLHelper.combatEndRequestedAt = RLHelper:GetCombatNow() - 5

        RLHelper.combatTicker.callback()

        assert.is_false(RLHelper.inCombat)
        assert.is_nil(RLHelper.currentCombat.firstEnemy)
    end)

    it("разрешает повторный запрос завершения после PLAYER_REGEN_ENABLED и новой активности", function()
        M.UnitAffectingCombat1 = false

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Враг1"):ToPlayer("Игрок1"):Damage(100):Build())
        RLHelper:PLAYER_REGEN_DISABLED()
        RLHelper:PLAYER_REGEN_ENABLED()

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Враг2"):ToPlayer("Игрок1"):Damage(100):Build())
        assert.is_nil(RLHelper.combatEndRequestedAt)

        for guid in pairs(RLHelper.activeEnemies) do
            RLHelper.activeEnemies[guid] = RLHelper:GetCombatNow() - 10
        end
        RLHelper.lastCombatActivityAt = RLHelper:GetCombatNow() - 10

        assert.is_false(RLHelper:EvaluateCombatEnd("ticker"))
        assert.is_not_nil(RLHelper.combatEndRequestedAt)
    end)

    it("не сохраняет обычный бой когда включена история только боссов", function()
        RLHelper.db.profile.bossOnlyHistory = true
        RLHelper:PLAYER_REGEN_DISABLED()
        RLHelper:OnCombatLogEvent("test message")

        M.UnitAffectingCombat1 = false
        RLHelper.lastCombatActivityAt = RLHelper:GetCombatNow() - 10
        RLHelper.combatEndRequestedAt = RLHelper:GetCombatNow() - 5

        assert.is_true(RLHelper:EvaluateCombatEnd("test"))
        assert.are.equal(0, #RLHelper.combatHistory)
        assert.are.equal(0, #RLHelper.db.profile.combatHistory)
    end)

    it("сохраняет боссовый бой когда включена история только боссов", function()
        RLHelper.db.profile.bossOnlyHistory = true
        M.UnitAffectingCombat1 = false
        RLHelper.currentInstanceId = 631
        setBossModules({
            {
                name = "BloodPrincesTracker",
                receivesCombatEvents = true,
                zoneGateInstanceId = 631,
                bossIds = {
                    [37970] = "Кровавый совет",
                    [37972] = "Кровавый совет",
                    [37973] = "Кровавый совет"
                }
            }
        })

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Адд"):ToPlayer("Игрок1"):Damage(100):Build())
        local bossEvent = { Builder:New():FromEnemy("Принц Валанар"):ToPlayer("Игрок1"):Damage(100):Build() }
        bossEvent[4] = npcGuid(37970)

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(unpack(bossEvent))
        RLHelper:OnCombatLogEvent("test message")

        for guid in pairs(RLHelper.activeEnemies) do
            RLHelper.activeEnemies[guid] = RLHelper:GetCombatNow() - 10
        end
        RLHelper.lastCombatActivityAt = RLHelper:GetCombatNow() - 10
        RLHelper.combatEndRequestedAt = RLHelper:GetCombatNow() - 5

        assert.is_true(RLHelper:EvaluateCombatEnd("test"))
        assert.are.equal(1, #RLHelper.combatHistory)
        assert.is_true(RLHelper.combatHistory[1].isBoss)
        assert.are.equal("Кровавый совет", RLHelper.combatHistory[1].firstEnemy)
        assert.are.equal("Кровавый совет", RLHelper.db.profile.combatHistory[1].firstEnemy)
    end)

    it("сохраняет boss-only бой с боссом из общего реестра", function()
        RLHelper.db.profile.bossOnlyHistory = true
        M.UnitAffectingCombat1 = false
        RLHelper.currentInstanceId = 603
        setBossModules({})

        local bossEvent = { Builder:New():FromEnemy("Йогг-Сарон"):ToPlayer("Игрок1"):Damage(100):Build() }
        bossEvent[4] = npcGuid(33288)

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(unpack(bossEvent))
        RLHelper:OnCombatLogEvent("test message")

        for guid in pairs(RLHelper.activeEnemies) do
            RLHelper.activeEnemies[guid] = RLHelper:GetCombatNow() - 10
        end
        RLHelper.lastCombatActivityAt = RLHelper:GetCombatNow() - 10
        RLHelper.combatEndRequestedAt = RLHelper:GetCombatNow() - 5

        assert.is_true(RLHelper:EvaluateCombatEnd("test"))
        assert.are.equal(1, #RLHelper.combatHistory)
        assert.is_true(RLHelper.combatHistory[1].isBoss)
        assert.are.equal("Йогг-Сарон", RLHelper.combatHistory[1].firstEnemy)
    end)

end)
