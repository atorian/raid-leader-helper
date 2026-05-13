# Demo Coverage Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ensure `/rlh demo` emits representative persistent battle-log messages for every visible log feature currently implemented by combat trackers.

**Architecture:** Use the existing `RLHelper_Demo` message broadcast and per-module `demo()` methods. Add missing registrations and demo methods only where modules already emit visible log messages, and extend current demo methods with missing formatter outputs.

**Tech Stack:** Lua 5.1, AceEvent message registration, busted, luassert spies.

---

### Task 1: Add Failing Demo Coverage Tests

**Files:**
- Modify: `tests/PutricideTracker.test.lua`
- Modify: `tests/BloodPrincesTracker.test.lua`
- Modify: `tests/BloodQueenTracker.test.lua`
- Modify: `tests/TrialCrusaderTracker.test.lua`
- Modify: `tests/SpellTracker.test.lua`
- Modify: `tests/DeathwhisperTracker.test.lua`

- [ ] **Step 1: Add tests that call each affected module's `demo()`**

Each test should install a spy as `module.log`, call `module:demo()`, and assert representative messages. Tests for modules that do not have `demo()` yet should assert `assert.is_function(module.demo)` before calling it.

- [ ] **Step 2: Run affected tests to verify failures**

Run: `busted --verbose ./tests/PutricideTracker.test.lua ./tests/BloodPrincesTracker.test.lua ./tests/BloodQueenTracker.test.lua ./tests/TrialCrusaderTracker.test.lua ./tests/SpellTracker.test.lua ./tests/DeathwhisperTracker.test.lua`

Expected before implementation: failures for missing demo methods and missing representative messages in existing demos.

### Task 2: Implement Demo Coverage

**Files:**
- Modify: `modules/bosses/PutricideTracker.lua`
- Modify: `modules/bosses/BloodPrincesTracker.lua`
- Modify: `modules/bosses/BloodQueenTracker.lua`
- Modify: `modules/bosses/TrialCrusaderTracker.lua`
- Modify: `modules/SpellTracker.lua`
- Modify: `modules/bosses/DeathwhisperTracker.lua`

- [ ] **Step 1: Add missing registrations and demo methods**

Register `RLHelper_Demo` in Putricide, Blood Princes, Blood Queen, and Trial Crusader trackers, then add `demo()` methods that log the visible feature formatters.

- [ ] **Step 2: Extend existing demos**

Add missing visible log examples to `SpellTracker:demo()` and `DeathwhisperTracker:demo()`, including both successful and missed Deathwhisper cyclone formats.

- [ ] **Step 3: Run affected tests**

Run: `busted --verbose ./tests/PutricideTracker.test.lua ./tests/BloodPrincesTracker.test.lua ./tests/BloodQueenTracker.test.lua ./tests/TrialCrusaderTracker.test.lua ./tests/SpellTracker.test.lua ./tests/DeathwhisperTracker.test.lua`

Expected after implementation: affected tests pass with no failures or errors.

### Task 3: Verify Full Suite

**Files:**
- No further edits expected.

- [ ] **Step 1: Run full test suite**

Run: `busted --verbose ./tests/*.lua`

Expected: all tests pass with no failures or errors.
