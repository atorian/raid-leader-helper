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
end)
