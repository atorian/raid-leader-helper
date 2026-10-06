local Transfer = require('lib.SettingsTransfer')
require('tests.mocks')
local addon = require('Core')

describe('Account settings transfer', function()
    local profile
    before_each(function()
        profile = {
            enabled = true, debug = false, theme = 'minimal', discordLink = 'https://discord.gg/test',
            pullCancelMessage = 'Галя, отмена! | 100% = "текст"', gpAwardButtonsEnabled = true,
            displayOnlyInGroup = false, bossOnlyHistory = true, igor = false,
            halionBurstPull = true, halionBurstReset = false, halionPhaseTwoEntryTimer = true,
            minimap = { hide = false }, gpAwardReasons = { [100] = 'Причина | ; %' },
            savedPosition = { point = 'TOPLEFT', relativePoint = 'CENTER', x = -213.25,
                y = 50.5, width = 520, height = 300 },
            epAwards = { rt = '20:30', dpsSource = 'Recount', amounts = {attendance = 0, icc = 7500},
                reminders = {attendance = false, icc = true}, saurfangThresholds = {[71] = 0, [72] = 22000} }
        }
    end)

    it('round trips all supported settings including false, zero, Cyrillic and punctuation', function()
        local text = assert(Transfer.Export(profile))
        assert.is_nil(text:find('[^%w|%.%+%-]'))
        assert.are.same(profile, Transfer.Decode(text))
        assert.are.same(profile, Transfer.Decode('  ' .. text:gsub('|', '|\n') .. '  '))
    end)

    it('omits personal data, obsolete settings and unknown fields', function()
        profile.combatHistory = { 'secret history' }
        profile.combatHistoryV2 = { combats = {} }
        profile.journalV2 = true
        profile.otherAddonData = 'personal'
        local decoded = assert(Transfer.Decode(assert(Transfer.Export(profile))))
        assert.is_nil(decoded.combatHistory)
        assert.is_nil(decoded.combatHistoryV2)
        assert.is_nil(decoded.journalV2)
        assert.is_nil(decoded.otherAddonData)
    end)

    it('replaces previous overrides and preserves character and unrelated data', function()
        local imported = assert(Transfer.Decode(assert(Transfer.Export(profile))))
        local target = { theme = 'current', gpAwardReasons = {[200] = 'old'},
            epAwards = {amounts = {rs = 9999}}, savedPosition = {x = 999}, unrelated = 'keep' }
        Transfer.Apply(target, imported)
        assert.are.equal('keep', target.unrelated)
        assert.is_nil(target.epAwards.amounts.rs)
        assert.is_nil(target.gpAwardReasons[200])
        target.unrelated = nil
        assert.are.same(profile, target)
    end)

    it('supports an unset position and EP defaults without carrying target overrides', function()
        profile.savedPosition, profile.epAwards = nil, nil
        local decoded = assert(Transfer.Decode(assert(Transfer.Export(profile))))
        assert.are.same(profile, decoded)
    end)

    it('rejects truncation, unknown versions, extra fields, invalid types and invalid values', function()
        local text = assert(Transfer.Export(profile))
        for _, bad in ipairs({ '', text:sub(1, -2), text:gsub('RLH1', 'RLH2'), text .. '|-',
            text:gsub('RLH1|b1', 'RLH1|s31'), text:gsub('n7500', 'n100000'),
            text:gsub('n22000', 'n1e999'), text:gsub('s32303A3330', 's32353A3330'),
            text:gsub('s6D696E696D616C', 's756E6B6E6F776E'),
            text:gsub('n520', '-'), text:gsub('n22000', 'n2.5') }) do
            local decoded, message = Transfer.Decode(bad)
            assert.is_nil(decoded)
            assert.is_string(message)
        end
        assert.is_nil(Transfer.Decode(string.rep('a', 65537)))
        assert.is_nil(Transfer.Decode('return os.execute("anything")'))
    end)

    it('does not change any saved settings or refresh the UI on invalid import', function()
        local previous = addon.db
        local character = {combatHistoryV2 = {combats = {'own raid'}}, epAwards = {awarded = true}}
        addon.db = { profile = profile, char = character }
        local ok, message = addon:ImportSettings('RLH1|broken')
        assert.is_false(ok)
        assert.is_string(message)
        assert.are.equal(profile, addon.db.profile)
        assert.are.equal(character, addon.db.char)
        addon.db = previous
    end)
    it('round trips every configured boss, empty configurations and per-spec disabled values', function()
        require('data.BossIds')
        profile.epAwards.saurfangThresholds = nil
        profile.epAwards.dpsBosses = {}
        for _, encounter in ipairs(RLHelperBossIds.DPS_ENCOUNTERS) do
            profile.epAwards.dpsBosses[encounter.id] = { [71] = 0, [72] = encounter.id }
        end
        local text = assert(Transfer.Export(profile))
        assert.equals('RLH2', text:sub(1, 4))
        assert.are.same(profile, Transfer.Decode(text))
        profile.epAwards.dpsBosses = {}
        assert.are.same(profile, Transfer.Decode(assert(Transfer.Export(profile))))
    end)

    it('round trips Putricide award mode and damage while retaining old transfer versions', function()
        require('data.BossIds')
        profile.epAwards.saurfangThresholds = nil
        profile.epAwards.dpsBosses = { [36678] = { [72] = 22000 } }
        local old = assert(Transfer.Export(profile))
        assert.equals('RLH2', old:sub(1, 4))
        profile.epAwards.putricideMode = 'ooze'
        profile.epAwards.putricideOozeDamage = 100000
        local text = assert(Transfer.Export(profile))
        assert.equals('RLH3', text:sub(1, 4))
        assert.same(profile, Transfer.Decode(text))
        assert.is_nil(Transfer.Decode(text:gsub('n100000', 'n9999999')))
        assert.is_nil(Transfer.Decode(text:gsub('n100000', 'n0.5')))
        assert.is_nil(Transfer.Decode(text:gsub('s6F6F7A65', 's626164')))
        profile.epAwards.putricideMode = 'boss'
        profile.epAwards.putricideOozeDamage = 0
        assert.same(profile, Transfer.Decode(assert(Transfer.Export(profile))))
        local decoded = assert(Transfer.Decode(old))
        assert.is_nil(decoded.epAwards.putricideMode)
        assert.is_nil(decoded.epAwards.putricideOozeDamage)
        profile.epAwards.putricideMode = 'bad'
        assert.is_nil(Transfer.Export(profile))
    end)

    it('rejects corrupt, duplicate or unsupported boss configurations atomically', function()
        require('data.BossIds')
        profile.epAwards.saurfangThresholds = nil
        profile.epAwards.dpsBosses = { [37813] = { [72] = 22000 }, [39863] = {} }
        local text = assert(Transfer.Export(profile))
        for _, bad in ipairs({ text:gsub('|37813|', '|99999|'), text:gsub('|39863|', '|37813|'),
            text:gsub('n22000', 'n1.5'), text:gsub('|2|37813|', '|3|37813|'), text .. '|-' }) do
            assert.is_nil(Transfer.Decode(bad))
        end
        profile.epAwards.dpsBosses[99999] = {}
        assert.is_nil(Transfer.Export(profile))
    end)

end)
