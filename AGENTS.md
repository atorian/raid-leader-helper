# Project

WoW 3.3.5a only addon for Raid Leader support. 
Provides visual persistend battle log and quick actions.
Other versions of WOW are out of scope.

## Release Process

- To release, update `## Version` in `RLHelper.toc` first.
- Commit the version bump before creating the tag.
- Create the git tag on the version bump commit and push the commit and tag to GitHub.
- GitHub automation creates a draft release after the tag is pushed.
- Do not create GitHub releases unless explicitly requested.
- After publishing new git tag prepare release message in russian. It should inculde what changed since last published release:
    - Что нового 
    - Что исправлено

## Valid Data Source

When adding a SpellID or UnitID to addon, check if it point to right thing in https://wotlk.ezhead.org/. 

When adding combat log handling, use only subevents confirmed by real WoW 3.3.5a logs. Do not invent retail or parser-only event names.

Combat log `.txt` files in this addon can be very large. Do not inspect them with Read tool or by dumping broad search output into the model. Use targeted shell scripts (`python`, `bash`) or narrow command-line filters that aggregate and print only the relevant matches, counts, and short samples.

Observed valid combat log subevents from `head -n 2000 *.txt` in this addon folder:
- `DAMAGE_SHIELD`
- `DAMAGE_SHIELD_MISSED`
- `ENCHANT_APPLIED`
- `ENCHANT_REMOVED`
- `PARTY_KILL`
- `RANGE_DAMAGE`
- `SPELL_AURA_APPLIED`
- `SPELL_AURA_APPLIED_DOSE`
- `SPELL_AURA_REFRESH`
- `SPELL_AURA_REMOVED`
- `SPELL_CAST_FAILED`
- `SPELL_CAST_START`
- `SPELL_CAST_SUCCESS`
- `SPELL_CREATE`
- `SPELL_DAMAGE`
- `SPELL_DISPEL`
- `SPELL_ENERGIZE`
- `SPELL_EXTRA_ATTACKS`
- `SPELL_HEAL`
- `SPELL_INTERRUPT`
- `SPELL_MISSED`
- `SPELL_PERIODIC_DAMAGE`
- `SPELL_PERIODIC_ENERGIZE`
- `SPELL_PERIODIC_HEAL`
- `SPELL_PERIODIC_MISSED`
- `SPELL_RESURRECT`
- `SPELL_SUMMON`
- `SWING_DAMAGE`
- `SWING_MISSED`
- `UNIT_DIED`

For successful dispels in these logs, use `SPELL_DISPEL`. Example shape:
`SPELL_DISPEL,sourceGUID,sourceName,sourceFlags,destGUID,destName,destFlags,spellId,spellName,spellSchool,extraSpellId,extraSpellName,extraSpellSchool,auraType`.


## Solutions

Prefer Architecturally correct solutions, which keep modules cohesive and reduce coupling.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**  

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.
