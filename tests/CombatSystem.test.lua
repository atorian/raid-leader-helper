local function record(text) return RLHelperJournal.Create('TEST', { timestamp = 1000 }, 'INFO', { text = text }) end
local M = require('tests.mocks')
require('../lib/blizzardEvent')
require('../lib/CombatFilters')
require('../data/BossIds')
local RLHelper = require('../Core')
local SpellTracker = require('../modules/SpellTracker')
local HalionTracker = require('../modules/bosses/HalionTracker')
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
    local originalSendMessage
    local displayedMessages
    local originalGroupMembers

    before_each(function()
        originalIterateModules = RLHelper.IterateModules
        originalSendMessage = RLHelper.SendMessage
        displayedMessages = {}
        originalGroupMembers = RLHelper.groupMembers
        RLHelper.groupMembers = {}
        RLHelper:StopCombatTicker()
        RLHelper.inCombat = false
        RLHelper.lastCombatActivityAt = nil
        RLHelper.combatEndRequestedAt = nil
        RLHelper.combatEndRequiresRegen = false
        RLHelper.currentCombat = {
            startTime = nil,
            events = {},
            firstEnemy = nil,
            isBoss = false
        }
        RLHelper.journalView = "ALL"
        RLHelper.followNextCombat = false
        RLHelper.displayedCombat = RLHelper.currentCombat
        RLHelper.combatHistory = {}
        RLHelper.DisplayCombat = function()
        end
        RLHelper.mainFrame = {
            logText = {
                AddMessage = function(_, message)
                    table.insert(displayedMessages, message)
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
            },
            char = {
                combatHistoryV2 = { schemaVersion = 2, nextCombatId = 1, combats = {} }
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
        RLHelper.SendMessage = originalSendMessage
        RLHelper.groupMembers = originalGroupMembers
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

    it("позволяет добавить сообщение до начала боя", function()
        RLHelper:OnCombatLogEvent(record("test message"))

        assert.is_false(RLHelper.inCombat)
        assert.is_nil(RLHelper.currentCombat.startTime)
        assert.are.equal("test message", RLHelper.currentCombat.events[1].text)
    end)

    it("renders structured records without changing their stored text", function()
        local entry = record("Tracked mechanic")
        RLHelper:OnCombatLogEvent(entry)
        assert.are.equal("Tracked mechanic", RLHelper.currentCombat.events[1].text)
        assert.are.same({ RLHelperJournal.Format(entry) }, displayedMessages)
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

    it("records a party druid Growl once in the journal", function()
        local oldLog = SpellTracker.log
        local oldAssignments, oldHasAssignments = RLHelper.groupAssignments, RLHelper.hasTankAssignments
        finally(function()
            SpellTracker.log = oldLog
            SpellTracker:reset()
            RLHelper.groupAssignments, RLHelper.hasTankAssignments = oldAssignments, oldHasAssignments
        end)
        M.partySize = 4
        M:SetUnitGUID("party1", "druid")
        RLHelper:RefreshGroupRoster()
        SpellTracker:reset()
        SpellTracker.log = function(message) RLHelper:OnCombatLogEvent(message) end
        setBossModules({ SpellTracker })

        for _, subevent in ipairs({ "SPELL_CAST_SUCCESS", "SPELL_AURA_APPLIED", "SPELL_AURA_REMOVED" }) do
            RLHelper:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", 100, subevent,
                "druid", "Медведь", 0x512, "mob", "Противник", 0xa48, 6795, "Рык", 1, "DEBUFF")
        end

        assert.are.equal(1, #RLHelper.currentCombat.events)
        local entry = RLHelper.currentCombat.events[1]
        assert.are.equal("TAUNT", entry.kind)
        assert.are.equal("INFO", entry.type)
        assert.are.equal(6795, entry.spellId)
        assert.are.equal("Медведь", entry.source.name)
        assert.are.equal("Противник", entry.target.name)
        assert.are.same({ RLHelperJournal.Format(entry) }, displayedMessages)
    end)

    it("сохраняет отслеживаемые бафы игроков до начала боя", function()
        M.UnitAffectingCombat1 = false
        SpellTracker:OnInitialize()
        SpellTracker:reset()
        setBossModules({ SpellTracker })

        assert.has_no.errors(function()
            RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromPlayer("Дк"):ToPlayer("Рога")
                :ApplyAura(49016, "Истерия", "BUFF"):Build())
        end)

        assert.is_false(RLHelper.inCombat)
        local entry = RLHelper.currentCombat.events[1]
        assert.are.equal('SPELL_USE', entry.kind)
        assert.are.equal(49016, entry.spellId)
        assert.are.equal('Дк', entry.source.name)
        assert.are.equal('Рога', entry.target.name)
    end)

    it("logs the first Twilight Shroud target through the Core dispatcher", function()
        RLHelper.currentInstanceId = 724
        HalionTracker:OnInitialize()
        HalionTracker:reset()
        setBossModules({ HalionTracker })

        assert.has_no.errors(function()
            RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Халион"):ToPlayer("Игрок1")
                :SpellDamage(75483, "Пелена Тени", 1000):Build())
            RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Халион"):ToPlayer("Игрок2")
                :SpellDamage(75483, "Пелена Тени", 1000):Build())
        end)

        local entry = RLHelper.currentCombat.events[1]
        assert.are.equal('FIRST_TWILIGHT_ENTRY', entry.kind)
        assert.are.equal('Игрок1', entry.target.name)
        assert.are.same({ RLHelperJournal.Format(entry) }, displayedMessages)
    end)

    it("не завершает бой сразу по PLAYER_REGEN_ENABLED", function()
        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Леди Смертный Шепот"):ToPlayer("Игрок1"):Damage(100):Build())
        RLHelper:PLAYER_REGEN_ENABLED()

        assert.is_true(RLHelper.inCombat)
    end)

    it("завершает бой по PLAYER_REGEN_ENABLED если живых врагов нет", function()
        RLHelper:PLAYER_REGEN_DISABLED()
        RLHelper.currentCombat.firstEnemy = "Враг1"
        RLHelper:OnCombatLogEvent(record("test message"))

        M.UnitAffectingCombat1 = false
        RLHelper:PLAYER_REGEN_ENABLED()

        assert.is_false(RLHelper.inCombat)
        assert.are.equal(1, #RLHelper.combatHistory)
    end)

    it("сбрасывает пустой бой от событий игроков без RLHelper_CombatEnded", function()
        local combatEndedMessages = 0
        RLHelper.SendMessage = function(_, message)
            if message == "RLHelper_CombatEnded" then
                combatEndedMessages = combatEndedMessages + 1
            end
        end

        RLHelper:PLAYER_REGEN_DISABLED()
        RLHelper.currentCombat.events = { record("player buff") }

        M.UnitAffectingCombat1 = false
        RLHelper:PLAYER_REGEN_ENABLED()

        assert.is_false(RLHelper.inCombat)
        assert.are.equal(0, combatEndedMessages)
        assert.are.equal(0, #RLHelper.combatHistory)
    end)

    it("не завершает бой по PLAYER_REGEN_ENABLED если группа еще в бою", function()
        RLHelper:PLAYER_REGEN_DISABLED()
        RLHelper:OnCombatLogEvent(record("test message"))

        M.partySize = 1
        M.UnitAffectingCombat1 = false
        M.UnitAffectingCombat2 = true
        RLHelper:PLAYER_REGEN_ENABLED()

        assert.is_true(RLHelper.inCombat)
        assert.are.equal(0, #RLHelper.combatHistory)
    end)

    it("не завершает бой пока группа еще в бою", function()
        RLHelper:PLAYER_REGEN_DISABLED()
        RLHelper:OnCombatLogEvent(record("test message"))

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
        RLHelper:OnCombatLogEvent(record("test message"))

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

    it("не обнуляет список врагов от смерти без участия группы", function()
        M.UnitAffectingCombat1 = false

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromEnemy("Саурфанг"):ToPlayer("Игрок1"):Damage(100):Build())
        RLHelper:OnCombatLogEvent(record("test message"))
        RLHelper.combatEndRequestedAt = RLHelper:GetCombatNow() - 5
        RLHelper.lastCombatActivityAt = RLHelper:GetCombatNow() - 5

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():ToEnemy("Саурфанг"):Death():Build())
        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(Builder:New():FromPlayer("Друид"):ToPlayer("Игрок1")
            :PeriodicHeal(48441, "Омоложение", 100):Build())

        assert.is_false(RLHelper:EvaluateCombatEnd("ticker"))
        assert.is_true(RLHelper.inCombat)
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
        RLHelper:OnCombatLogEvent(record("test message"))

        M.UnitAffectingCombat1 = false
        RLHelper.lastCombatActivityAt = RLHelper:GetCombatNow() - 10
        RLHelper.combatEndRequestedAt = RLHelper:GetCombatNow() - 5

        assert.is_true(RLHelper:EvaluateCombatEnd("test"))
        assert.are.equal(0, #RLHelper.combatHistory)
        assert.are.equal(0, #RLHelper.db.profile.combatHistory)
    end)

    it("сохраняет историю боев в хранилище текущего персонажа", function()
        RLHelper:PLAYER_REGEN_DISABLED()
        RLHelper:OnCombatLogEvent(record("test message"))

        M.UnitAffectingCombat1 = false
        RLHelper.lastCombatActivityAt = RLHelper:GetCombatNow() - 10
        RLHelper.combatEndRequestedAt = RLHelper:GetCombatNow() - 5

        assert.is_true(RLHelper:EvaluateCombatEnd("test"))
        assert.are.equal(1, #RLHelper.combatHistory)
        assert.are.equal(1, #RLHelper.db.char.combatHistoryV2.combats)
        assert.are.equal("test message", RLHelper.db.char.combatHistoryV2.combats[1].events[1].text)
        assert.are.equal(0, #RLHelper.db.profile.combatHistory)
    end)

    it("ограничивает историю текущего персонажа тридцатью боями", function()
        for i = 1, 31 do
            RLHelper:SaveCombatToProfile({
                startTime = i,
                endTime = i + 1,
                events = { record("combat " .. i) },
                firstEnemy = "Enemy " .. i,
                isBoss = false
            }, RLHelper.db.profile)
        end

        assert.are.equal(30, #RLHelper.combatHistory)
        assert.are.equal(30, #RLHelper.db.char.combatHistoryV2.combats)
        assert.are.equal("Enemy 31", RLHelper.combatHistory[1].firstEnemy)
        assert.are.equal("Enemy 2", RLHelper.combatHistory[30].firstEnemy)
    end)

    it("очищает историю только текущего персонажа", function()
        RLHelper.combatHistory = {
            {
                startTime = 1,
                endTime = 2,
                events = { record("combat") },
                firstEnemy = "Enemy",
                isBoss = false
            }
        }
        RLHelper.db.char.combatHistoryV2.combats = RLHelper.combatHistory
        RLHelper.db.profile.combatHistory = {
            {
                startTime = 10,
                endTime = 11,
                events = { record("old shared combat") },
                firstEnemy = "Old Enemy",
                isBoss = false
            }
        }

        RLHelper:ClearCombatHistory()

        assert.are.equal(0, #RLHelper.combatHistory)
        assert.are.equal(0, #RLHelper.db.char.combatHistoryV2.combats)
        assert.are.equal(1, #RLHelper.db.profile.combatHistory)
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
        RLHelper:OnCombatLogEvent(record("test message"))

        for guid in pairs(RLHelper.activeEnemies) do
            RLHelper.activeEnemies[guid] = RLHelper:GetCombatNow() - 10
        end
        RLHelper.lastCombatActivityAt = RLHelper:GetCombatNow() - 10
        RLHelper.combatEndRequestedAt = RLHelper:GetCombatNow() - 5

        assert.is_true(RLHelper:EvaluateCombatEnd("test"))
        assert.are.equal(1, #RLHelper.combatHistory)
        assert.is_true(RLHelper.combatHistory[1].isBoss)
        assert.are.equal("Кровавый совет", RLHelper.combatHistory[1].firstEnemy)
        assert.are.equal("Кровавый совет", RLHelper.db.char.combatHistoryV2.combats[1].firstEnemy)
    end)

    it("сохраняет boss-only бой с боссом из общего реестра", function()
        RLHelper.db.profile.bossOnlyHistory = true
        M.UnitAffectingCombat1 = false
        RLHelper.currentInstanceId = 603
        setBossModules({})

        local bossEvent = { Builder:New():FromEnemy("Йогг-Сарон"):ToPlayer("Игрок1"):Damage(100):Build() }
        bossEvent[4] = npcGuid(33288)

        RLHelper:COMBAT_LOG_EVENT_UNFILTERED(unpack(bossEvent))
        RLHelper:OnCombatLogEvent(record("test message"))

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


    describe("group identity during mind control", function()
        local observer = "0x00000000003F0563"
        local raider = "0x000000000036AE73"
        local lady = "0xF130008FF75CADA4"
        local spirit = "0xF13000954E5D128E"

        before_each(function()
            M.raidSize = 2
            M:SetUnitGUID("player", observer)
            M:SetUnitGUID("raid1", observer)
            M:SetUnitGUID("raid2", raider)
            RLHelper:RAID_ROSTER_UPDATE("RAID_ROSTER_UPDATE")
            RLHelper.currentInstanceId = 631
        end)

        after_each(function()
            M:ClearUnitGUIDs()
            M.raidSize = 0
            M.partySize = 0
        end)

        it("recognizes raid members and controlled players independently of their flags", function()
            assert.is_true(RLHelper:IsGroupMember(raider, 0x548))
            assert.is_true(RLHelper:IsGroupMember(observer, 0x801218))
            assert.is_true(affectingGroup({ sourceGUID = observer, sourceFlags = 0x1248 }))
            assert.is_true(affectingGroup({ destGUID = raider, destFlags = 0x548 }))
            assert.is_false(RLHelper:IsGroupMember("outsider", 0x548))
        end)

        it("rebuilds the roster when switching from raid to party and then solo", function()
            M.raidSize = 0
            M.partySize = 1
            M:SetUnitGUID("party1", "party-member")
            M:SetUnitGUID("partypet1", "party-pet")
            M:SetUnitGUID("pet", "own-pet")
            RLHelper:PARTY_MEMBERS_CHANGED("PARTY_MEMBERS_CHANGED")
            assert.is_false(RLHelper:IsGroupMember(raider, 0x548))
            assert.is_true(RLHelper:IsGroupMember("party-member", 0x548))
            assert.is_true(RLHelper:IsGroupMember("party-pet", 0x1148))
            assert.is_true(RLHelper:IsGroupMember("own-pet", 0x1148))

            M.partySize = 0
            RLHelper:PLAYER_ENTERING_WORLD("PLAYER_ENTERING_WORLD")
            assert.is_false(RLHelper:IsGroupMember("party-member", 0x548))
            assert.is_false(RLHelper:IsGroupMember("party-pet", 0x1148))
            assert.is_true(RLHelper:IsGroupMember(observer, 0x1218))
        end)

        it("refreshes pet GUIDs and retains group identity across combat resets", function()
            M:SetUnitGUID("raidpet2", "old-pet")
            RLHelper:RefreshGroupRoster("UNIT_PET", "raid2")
            assert.is_true(RLHelper:IsGroupMember("old-pet", 0x1148))
            M:SetUnitGUID("raidpet2", "new-pet")
            RLHelper:RefreshGroupRoster("UNIT_PET", "raid2")
            RLHelper:ResetCombatState()
            assert.is_false(RLHelper:IsGroupMember("old-pet", 0x1148))
            assert.is_true(RLHelper:IsGroupMember("new-pet", 0x1148))
            assert.is_true(RLHelper:IsGroupMember(raider, 0x548))
        end)

        it("dispatches raid mechanics in both directions but still rejects outside players", function()
            local handled = 0
            setBossModules({ { receivesCombatEvents = true, handleEvent = function()
                handled = handled + 1
            end } })
            for _, flags in ipairs({ 0x514, 0x548, 0x1248, 0x1218 }) do
                RLHelper:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", 100, "SWING_DAMAGE",
                    raider, "Storm", flags, lady, "Леди Смертный Шепот", 0xa18,
                    100, 0, 1, 0, 0, 0)
                RLHelper:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", 100, "SWING_DAMAGE",
                    lady, "Леди Смертный Шепот", 0xa18, raider, "Storm", flags,
                    100, 0, 1, 0, 0, 0)
            end
            assert.are.equal(8, handled)
            assert.is_true(RLHelper.activePlayers[raider])
            assert.is_nil(RLHelper.activeEnemies[raider])
            assert.are.equal("Леди Смертный Шепот", RLHelper.currentCombat.firstEnemy)
            assert.is_true(RLHelper.currentCombat.isBoss)

            RLHelper:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", 100, "SWING_DAMAGE",
                lady, "Леди Смертный Шепот", 0xa18, "outsider", "Чужой", 0x548,
                100, 0, 1, 0, 0, 0)
            assert.are.equal(8, handled)
        end)

        it("does not start an enemy encounter for damage between known controlled raiders", function()
            setBossModules({})
            RLHelper:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", 100, "SWING_DAMAGE",
                observer, "Бочок", 0x801218, raider, "Storm", 0x548,
                100, 0, 1, 0, 0, 0)
            assert.is_nil(RLHelper.currentCombat.firstEnemy)
            assert.is_false(RLHelper.inCombat)
            assert.are.equal(0, count(RLHelper.activeEnemies))
        end)

        it("keeps module-level mechanic filters independent of observer allegiance", function()
            local queen = require('../modules/bosses/BloodQueenTracker')
            local lich = require('../modules/bosses/LichKingTracker')
            local oldQueenLog, oldLichLog = queen.log, lich.log
            local oldTimestamp = lich.lastShadowTrapTimestamp
            finally(function()
                queen.log, lich.log = oldQueenLog, oldLichLog
                lich.lastShadowTrapTimestamp = oldTimestamp
            end)
            queen.log = function(message) RLHelper:OnCombatLogEvent(message) end
            lich.log = queen.log
            lich:reset()
            setBossModules({ queen, lich })
            RLHelper:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", 100, "SPELL_DAMAGE",
                raider, "Storm", 0x548, observer, "Бочок", 0x1218,
                71483, "Кровавый всплеск", 0x20, 1000, 0, 1, 0, 0, 0)
            RLHelper:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", 101, "SPELL_DAMAGE",
                "trap", "Ловушка", 0xa18, raider, "Storm", 0x548,
                73529, "Темная ловушка", 0x20, 1000, 0, 1, 0, 0, 0)
            assert.are.equal(2, #RLHelper.currentCombat.events)
        end)

        it("uses the roster for first damage without treating controlled group members as enemies", function()
            local oldLog = SpellTracker.log
            finally(function()
                SpellTracker.log = oldLog
                SpellTracker:reset()
            end)
            SpellTracker:reset()
            SpellTracker.log = function(message) RLHelper:OnCombatLogEvent(message) end
            setBossModules({ SpellTracker })
            RLHelper:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", 100, "SWING_DAMAGE",
                observer, "Бочок", 0x1218, raider, "Storm", 0x548,
                100, 0, 1, 0, 0, 0)
            assert.are.equal(0, #RLHelper.currentCombat.events)
            RLHelper:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", 101, "SWING_DAMAGE",
                raider, "Storm", 0x548, lady, "Леди Смертный Шепот", 0xa18,
                100, 0, 1, 0, 0, 0)
            assert.are.equal(1, #RLHelper.currentCombat.events)
            assert.are.equal("FIRST_DAMAGE", RLHelper.currentCombat.events[1].kind)
        end)

        it("identifies a controlled raid player's death as a player rather than a pet", function()
            local igor = require('../modules/IgorDeathTracker')
            local normal = igor:GetGroupDeathMessagePhrases({
                event = "UNIT_DIED", destGUID = raider, destName = "Storm", destFlags = 0x514
            })
            local controlled = igor:GetGroupDeathMessagePhrases({
                event = "UNIT_DIED", destGUID = raider, destName = "Storm", destFlags = 0x1248
            })
            assert.is_not_nil(normal)
            assert.are.equal(normal, controlled)
        end)

        do
            it("records the real spirit hit during observer control", function()
                local tracker = require('../modules/bosses/DeathwhisperTracker')
                local oldLog, oldSpirits, oldReport = tracker.log, tracker.currentSpirits, tracker.report
                finally(function()
                    tracker.log, tracker.currentSpirits, tracker.report = oldLog, oldSpirits, oldReport
                end)
                tracker.currentSpirits, tracker.report = {}, {}
                tracker.log = function(message) RLHelper:OnCombatLogEvent(message) end
                setBossModules({ tracker })

                -- WoWCombatLog3.txt: 20:34:32.185 summon, 20:34:36.022 hit under observer control.
                RLHelper:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", 100, "SPELL_SUMMON",
                    lady, "Леди Смертный Шепот", 0xa18, spirit, "Мстительный дух", 0xa18,
                    71426, "Призыв духа", 0x1)
                RLHelper:COMBAT_LOG_EVENT_UNFILTERED("COMBAT_LOG_EVENT_UNFILTERED", 104, "SWING_DAMAGE",
                    spirit, "Мстительный дух", 0xa18, raider, "Storm", 0x548,
                    224, 0, 1, 0, 0, 0)

                assert.are.equal(1, tracker.report.Storm)
                assert.is_nil(tracker.currentSpirits[spirit])
                assert.are.equal(1, #RLHelper.currentCombat.events)
                assert.are.equal("SPIRIT_HIT", RLHelper.currentCombat.events[1].kind)

            end)
        end
    end)
end)
