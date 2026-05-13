# Putricide Choking Gas Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Track and summarize players affected by `Удушливый газ` / Choking Gas during Professor Putricide combat, including the Heroic 10 spell id and icon in immediate logs.

**Architecture:** Extend the existing `PutricideTracker`, which already owns Putricide-specific combat-log handling and combat-end summaries. Keep Choking Gas counts in a separate report table while reusing the same immediate log and summary style as Malleable Goo, with a small spell-id whitelist for Choking Gas mode variants.

**Tech Stack:** Lua 5.1, busted, luassert, WoW 3.3.5a combat-log events.

---

### Task 1: Add Choking Gas Tests

**Files:**
- Modify: `tests/PutricideTracker.test.lua`

- [ ] **Step 1: Add failing tests**

Add tests for immediate logging with icon, Heroic 10 spell id 72619, combat scoping, combat-end summary, empty summary, and reset behavior.

- [ ] **Step 2: Run tests to verify failure**

Run: `busted --verbose ./tests/PutricideTracker.test.lua`

Expected before implementation: Choking Gas tests fail because `PutricideTracker` does not log the icon and does not track spell id 72619.

### Task 2: Implement Choking Gas Tracking

**Files:**
- Modify: `modules/bosses/PutricideTracker.lua`

- [ ] **Step 1: Add Choking Gas spell ids, icon, state, formatting, summary, reset, and event handling**

Extend `PutricideTracker` with tracked spell ids `71278`, `72460`, `72619`, and `72620`; icon `Interface\\Icons\\Ability_Creature_Cursed_01`; a `chokingGasReport`; immediate log formatting; summary formatting; combat-end summary emission; and `SPELL_AURA_APPLIED` handling for all tracked Choking Gas ids.

- [ ] **Step 2: Run Putricide tests**

Run: `busted --verbose ./tests/PutricideTracker.test.lua`

Expected after implementation: all Putricide tracker tests pass.

### Task 3: Verify Full Suite

**Files:**
- No further edits expected.

- [ ] **Step 1: Run full test suite**

Run: `busted --verbose ./tests/*.lua`

Expected: all tests pass with no failures or errors.
