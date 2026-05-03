# Igor Module Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move Igor death-emote logic from `Core.lua` into `modules/IgorDeathTracker.lua` without changing behavior.

**Architecture:** Igor becomes a combat-event module with `receivesCombatEvents = true`, using the existing `Core.lua` dispatch path. `Core.lua` keeps configuration/UI only and no longer directly handles Igor deaths.

**Tech Stack:** Lua 5.1-style WoW 3.3.5a addon code, AceAddon module pattern, Busted tests, Makefile test target.

---

## File Structure

- Create `modules/IgorDeathTracker.lua`: owns Igor death classification, phrases, formatting, cooldown, and `handleEvent`.
- Modify `Core.lua`: remove Igor constants/helpers/functions and direct combat-log call.
- Modify `RLHelper.toc`: load `modules\IgorDeathTracker.lua` after `Core.lua`.
- Create `tests/IgorDeathTracker.test.lua`: relocated Igor tests.
- Modify `tests/Core.test.lua`: remove Igor death-emote test block.

### Task 1: Move Tests First

**Files:**
- Create: `tests/IgorDeathTracker.test.lua`
- Modify: `tests/Core.test.lua`

- [ ] **Step 1: Create module test file from existing Igor tests**

Use `require('tests.mocks')`, `spy = require("luassert.spy")`, and `IgorDeathTracker = require("../modules/IgorDeathTracker")`. Each test should call `IgorDeathTracker:handleEvent(event)` and assert the returned boolean.

- [ ] **Step 2: Remove the Igor describe block from Core tests**

Delete `describe("RLHelper Igor death emote", function()` from `tests/Core.test.lua` after equivalent tests exist in `tests/IgorDeathTracker.test.lua`.

- [ ] **Step 3: Run new test for RED**

Run: `busted --verbose ./tests/IgorDeathTracker.test.lua`

Expected: fails because `modules/IgorDeathTracker.lua` does not exist yet.

### Task 2: Extract Igor Module

**Files:**
- Create: `modules/IgorDeathTracker.lua`
- Modify: `Core.lua`
- Modify: `RLHelper.toc`

- [ ] **Step 1: Create `modules/IgorDeathTracker.lua`**

Move Igor constants, phrase lists, type helpers, death phrase classification, formatting, cooldown, and send logic into the new module. Implement `handleEvent(event)` as the public entrypoint.

- [ ] **Step 2: Remove Igor death handling from Core**

Remove Igor constants/helpers/functions from `Core.lua`. Remove `self:MaybeSendIgorDeathMessage(eventData)` from `COMBAT_LOG_EVENT_UNFILTERED`. Keep `db.profile.igor` and the options checkbox.

- [ ] **Step 3: Load module from TOC**

Add `modules\IgorDeathTracker.lua` after `Core.lua`.

- [ ] **Step 4: Run focused tests for GREEN**

Run: `busted --verbose ./tests/IgorDeathTracker.test.lua` and `busted --verbose ./tests/Core.test.lua`.

Expected: both pass.

### Task 3: Full Verification

**Files:**
- Verify all modified files.

- [ ] **Step 1: Run full test suite**

Run: `make test`

Expected: all tests pass.

- [ ] **Step 2: Review diff**

Run: `git diff -- Core.lua RLHelper.toc modules/IgorDeathTracker.lua tests/Core.test.lua tests/IgorDeathTracker.test.lua docs/superpowers/specs/2026-05-02-igor-module-extraction-design.md docs/superpowers/plans/2026-05-02-igor-module-extraction.md`

Expected: diff contains only Igor extraction plus spec/plan.

Do not commit unless the user explicitly asks for a commit.
