require('tests.mocks')
local RLHelper = require("Core")
local IgorDeathTracker = require("../modules/IgorDeathTracker")

describe("IgorDeathTracker", function()
    local originalDb
    local originalSendChatMessage
    local originalGetCombatNow
    local originalRandom

    before_each(function()
        originalDb = RLHelper.db
        originalSendChatMessage = _G.SendChatMessage
        originalGetCombatNow = RLHelper.GetCombatNow
        originalRandom = math.random
        IgorDeathTracker.lastDeathMessageAt = nil
        RLHelper.db = {
            profile = {
                igor = true
            }
        }
        math.random = function()
            return 1
        end
    end)

    after_each(function()
        RLHelper.db = originalDb
        _G.SendChatMessage = originalSendChatMessage
        RLHelper.GetCombatNow = originalGetCombatNow
        math.random = originalRandom
        IgorDeathTracker.lastDeathMessageAt = nil
    end)

    it("receives combat events", function()
        assert.is_true(IgorDeathTracker.receivesCombatEvents)
    end)

    it("sends a random emote when a group member dies", function()
        local messages = {}
        _G.SendChatMessage = function(message, channel)
            table.insert(messages, { message = message, channel = channel })
        end
        RLHelper.GetCombatNow = function()
            return 100
        end

        local sent = IgorDeathTracker:handleEvent({
            event = "UNIT_DIED",
            destName = "Игрок",
            destFlags = 0x514
        })

        assert.is_true(sent)
        assert.are.same({ { message = "Игорь осуждает смерть Игрок.", channel = "EMOTE" } }, messages)
    end)

    it("sends a random emote when a party player dies", function()
        local messages = {}
        _G.SendChatMessage = function(message, channel)
            table.insert(messages, { message = message, channel = channel })
        end
        RLHelper.GetCombatNow = function()
            return 100
        end

        local sent = IgorDeathTracker:handleEvent({
            event = "UNIT_DIED",
            destName = "Игрок",
            destFlags = 0x512
        })

        assert.is_true(sent)
        assert.are.same({ { message = "Игорь осуждает смерть Игрок.", channel = "EMOTE" } }, messages)
    end)

    it("does not send more than once every fifteen seconds", function()
        local messages = {}
        _G.SendChatMessage = function(message, channel)
            table.insert(messages, { message = message, channel = channel })
        end
        local now = 100
        RLHelper.GetCombatNow = function()
            return now
        end
        local event = {
            event = "UNIT_DIED",
            destName = "Игрок",
            destFlags = 0x514
        }

        assert.is_true(IgorDeathTracker:handleEvent(event))
        now = 114
        assert.is_false(IgorDeathTracker:handleEvent(event))
        now = 116
        assert.is_true(IgorDeathTracker:handleEvent(event))

        assert.are.equal(2, #messages)
    end)

    it("ignores non-group deaths", function()
        local sentCount = 0
        _G.SendChatMessage = function()
            sentCount = sentCount + 1
        end

        local sent = IgorDeathTracker:handleEvent({
            event = "UNIT_DIED",
            destName = "Враг",
            destFlags = 0xa48
        })

        assert.is_false(sent)
        assert.are.equal(0, sentCount)
    end)

    it("ignores typed deaths outside the group", function()
        local sentCount = 0
        _G.SendChatMessage = function()
            sentCount = sentCount + 1
        end

        local deaths = {
            { destName = "Игрок", destFlags = 0x510 },
            { destName = "Волк", destFlags = 0x1010 },
            { destName = "Прислужник", destFlags = 0x2010 }
        }

        for _, event in ipairs(deaths) do
            event.event = "UNIT_DIED"
            assert.is_false(IgorDeathTracker:handleEvent(event))
        end
        assert.are.equal(0, sentCount)
    end)

    it("ignores group-affiliated non-player deaths", function()
        local sentCount = 0
        _G.SendChatMessage = function()
            sentCount = sentCount + 1
        end

        local sent = IgorDeathTracker:handleEvent({
            event = "UNIT_DIED",
            destName = "Тотем",
            destFlags = 0x114
        })

        assert.is_false(sent)
        assert.are.equal(0, sentCount)
    end)

    it("sends a pet emote when a group pet dies", function()
        local messages = {}
        _G.SendChatMessage = function(message, channel)
            table.insert(messages, { message = message, channel = channel })
        end
        RLHelper.GetCombatNow = function()
            return 100
        end

        local sent = IgorDeathTracker:handleEvent({
            event = "UNIT_DIED",
            destName = "Волк",
            destFlags = 0x1012
        })

        assert.is_true(sent)
        assert.are.same({ { message = "Игорь зажимает нос. Волк воняет.", channel = "EMOTE" } }, messages)
    end)

    it("sends a pet emote when a group guardian dies", function()
        local messages = {}
        _G.SendChatMessage = function(message, channel)
            table.insert(messages, { message = message, channel = channel })
        end
        RLHelper.GetCombatNow = function()
            return 100
        end

        local sent = IgorDeathTracker:handleEvent({
            event = "UNIT_DIED",
            destName = "Прислужник",
            destFlags = 0x2014
        })

        assert.is_true(sent)
        assert.are.same({ { message = "Игорь зажимает нос. Прислужник воняет.", channel = "EMOTE" } }, messages)
    end)

    it("shares cooldown between player and pet death emotes", function()
        local messages = {}
        _G.SendChatMessage = function(message, channel)
            table.insert(messages, { message = message, channel = channel })
        end
        local now = 100
        RLHelper.GetCombatNow = function()
            return now
        end

        assert.is_true(IgorDeathTracker:handleEvent({
            event = "UNIT_DIED",
            destName = "Игрок",
            destFlags = 0x514
        }))
        now = 114
        assert.is_false(IgorDeathTracker:handleEvent({
            event = "UNIT_DIED",
            destName = "Волк",
            destFlags = 0x1014
        }))
        now = 116
        assert.is_true(IgorDeathTracker:handleEvent({
            event = "UNIT_DIED",
            destName = "Волк",
            destFlags = 0x1014
        }))

        assert.are.equal(2, #messages)
    end)
end)
