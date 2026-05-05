# SpellTracker Dispel Tracking Design

## Goal

Add successful dispel tracking to `SpellTracker` so raid leaders can see who dispelled with curse, magic, or disease removal skills.

## Evidence From Logs

The addon-folder logs were checked with `head -n 2000 *.txt`. Successful dispels appear as `SPELL_DISPEL`, not `SPELL_AURA_DISPELLED`.

Example shape from the logs:

```text
SPELL_DISPEL,sourceGUID,sourceName,sourceFlags,destGUID,destName,destFlags,spellId,spellName,spellSchool,extraSpellId,extraSpellName,extraSpellSchool,auraType
```

Example lines include:

```text
SPELL_DISPEL,...,988,"Рассеивание заклинаний",0x2,74562,"Пылающий огонь",4,BUFF
SPELL_DISPEL,...,2782,"Снятие проклятия",0x40,74795,"Метка пожирания",32,BUFF
```

`SPELL_AURA_DISPELLED` is not used for this feature.

## Spell IDs

Spell IDs are checked against `https://wotlk.ezhead.org/`.

- Priest `527` - `Dispel Magic`, dispels magic.
- Priest `988` - `Dispel Magic`, dispels magic, rank used in current logs.
- Priest `528` - `Cure Disease`, dispels disease.
- Priest `552` - `Abolish Disease`, dispels disease and applies periodic disease removal.
- Priest `10872` - `Abolish Disease Effect`, periodic disease removal triggered by `552`.
- Priest `32375` - `Mass Dispel`, dispels magic.
- Priest `32592` - triggered `Mass Dispel`, dispels magic.
- Paladin `4987` - `Cleanse`, dispels poison, disease, and magic.
- Paladin `1152` - `Purify`, dispels disease and poison.
- Shaman `51886` - `Cleanse Spirit`, dispels poison, disease, and curse.
- Shaman `526` - `Cure Toxins`, dispels poison and disease.
- Mage `475` - `Remove Curse`, dispels curse.
- Druid `2782` - `Remove Curse`, dispels curse.

Because the real `SPELL_DISPEL` lines expose `auraType` as `BUFF` or `DEBUFF`, not as curse/magic/disease/poison, filtering will be by dispel spell ID. This means multi-purpose skills such as `Cleanse`, `Purify`, `Cleanse Spirit`, and `Cure Toxins` may also log poison removals when those spells successfully dispel poison.

## Behavior

`SpellTracker` should log successful `SPELL_DISPEL` events when `spellId` is in the dispel whitelist.

The log format should match existing `SpellTracker` spell entries:

```text
<time> |cFFFFFFFF<sourceName>|r |T<spellIcon>:24:24:0:0|t <destName>
```

This intentionally does not include `extraSpellName`, because the requested format is the normal SpellTracker format.

## Non-Goals

- Do not handle `SPELL_AURA_DISPELLED`.
- Do not handle `SPELL_DISPEL_FAILED`.
- Do not add counters or summary UI.
- Do not change existing taunt, battle resurrection, first-hit, or paladin utility tracking.

## Parser Change

`lib/blizzardEvent.lua` currently has branches for parser-only/unused dispel names. It should parse the real `SPELL_DISPEL` subevent instead, filling:

- `extraSpellId`
- `extraSpellName`
- `extraSpellSchool`
- `auraType`

## Tests

Tests should cover:

- `blizzardEvent` parses `SPELL_DISPEL` into `extraSpellId`, `extraSpellName`, `extraSpellSchool`, and `auraType`.
- `SpellTracker` logs a whitelisted successful dispel in the normal SpellTracker format.
- `SpellTracker` ignores non-whitelisted `SPELL_DISPEL` spell IDs.
- Existing SpellTracker tests continue to pass.

Verification command: `busted --verbose ./tests/*.lua`.
