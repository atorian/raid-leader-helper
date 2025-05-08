# WoW 3.3.5a Raid Leader Addon

This addon for World of Warcraft 3.3.5a assists Raid Leaders in identifying rule-breaking actions by players and simplifies applying GP penalties using the EPGP system.

## Requirements

- World of Warcraft 3.3.5a client
- EPGP addon installed and configured
- Lua 5.1 (compatible with WoW 3.3.5a)
- Basic knowledge of raid rules and EPGP system

## Tech Stack

- Lua: Core scripting language for WoW addons
- Ace3: Framework for addon development (modules: AceGUI, AceDB, AceEvent)
- WoW API: For accessing game events, player data, and EPGP integration

## Milestones

- Setup and Framework: Initialize addon with Ace3, create basic UI, and integrate with EPGP.
- Modular Rule System: Develop a system to add, load, and unload raid rule modules dynamically in-game.
- Rule Monitoring: Implement detection of rule-breaking actions based on loaded modules (e.g., incorrect positioning, failure to follow mechanics).
    - taunts
    - 
- Penalty System: Develop functionality to apply GP penalties via EPGP with customizable reasons tied to specific rule violations.
- Reporting UI and Testing: Create a user-friendly interface for Raid Leaders to manage modules, view violations, and apply penalties; test in raid environments and refine based on feedback