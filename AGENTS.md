# Project

WoW 3.3.5a only addon for Raid Leader support. 
Provides visual persistend battle log and quick actions.
Other versions of WOW are out of scope.

## Branching

- Use Trunk Based Development: make changes directly on the `master` branch. Do not create or switch to feature branches unless explicitly requested.
- If work needs to diverge from `master` and is incomplete, keep it behind a feature flag so `master` remains releasable.

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


## Settings Window Geometry

Use the **visible settings area** as the width budget for every element and complete row, including labels, inputs, buttons, tables and their gaps. Do not prescribe separate maximum widths for individual widget types.

Standard WoW 3.3.5a geometry (UI coordinate units, before UI scaling):
- Entire `InterfaceOptionsFrame`: **648px wide**; this includes the category list on the left.
- Addon category panel (`InterfaceOptionsFramePanelContainer`): **413px wide** = 648 - 22 (outer left inset) - 175 (category list) - 16 (gap) - 22 (outer right inset).
- RLHelper scroll viewport: **375px wide** = 413 - 8 (left inset) - 30 (right inset including scrollbar clearance). This is the maximum visible content width, not the scroll child's nominal 440px width.
- Reserve 10px at the viewport's right edge: the complete row must end at or before **x = 365**, measured from the viewport's left edge. Subtract every ancestor's horizontal inset. For example, the current EP settings block begins at x = 16, leaving 359px visible or 349px with the right margin.

Before placing anything, compute `availableWidth = viewportWidth - ancestorInsets - rowX - rightMargin`. Include each element's actual rendered width, template borders, arrow, labels and gaps; do not compare only the width argument passed to a helper. Obtain the actual viewport's width with `scrollFrame:GetWidth()` when calculating layout in code. The non-scrolling «РС Бурст» category uses its own panel width and insets; the separate 700px award window is a different layout.

Verify complete rows in the client after layout changes. Lua mocks and the wider scroll child do not establish that controls are visible. If the client or another addon changes the window geometry, measure the live viewport rather than silently increasing this budget.

Source: [WoW 3.3.5a InterfaceOptionsFrame.xml](https://github.com/wowgaming/3.3.5-interface-files/blob/main/InterfaceOptionsFrame.xml) and the RLHelper scroll anchors in `Core.lua`.

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
