# Lich King Shadow Trap Tracking Design

## Goal

Track who triggers Shadow Trap explosions in Icecrown Citadel and log one player per explosion.

## Scope

- WoW 3.3.5a only.
- Track only in Icecrown Citadel, using instance id `631`.
- Do not require boss id or current boss-combat name checks.
- Use `SPELL_DAMAGE`, an observed valid combat-log subevent for this addon.
- Use spell id `73529` (`Shadow Trap` / `Теневая ловушка`) for actual damage events, confirmed on `https://wotlk.ezhead.org/?spell=73529` and observed in local combat logs. Use its confirmed icon `spell_shadow_gathershadows`.
- Heroic Shadow Trap spell id `74282`, confirmed on `https://wotlk.ezhead.org/?spell=74282`, triggers `73529`, so tracking `73529` covers the actual logged damage for 10/25 heroic explosions.

## Design

Add a dedicated `modules/bosses/LichKingTracker.lua` module, because Shadow Trap is a Lich King boss mechanic and should not add more boss-specific behavior to the general `SpellTracker` module.

The module will receive combat events and use `zoneGateInstanceId = 631` so Core dispatches it only in Icecrown Citadel. It will check for `SPELL_DAMAGE` with spell id `73529` and a player destination.

Combat logs can contain multiple `73529` damage lines at the same timestamp when one Shadow Trap explosion hits several players. The tracker will keep the last logged Shadow Trap timestamp and log only the first player seen for each timestamp. Later `73529` events with the same timestamp will be ignored.

The log message will be:

`HH:MM:SS |cFFFFFFFFPlayer|r |TInterface\Icons\spell_shadow_gathershadows:24:24:0:0|t взорвал ловушку`

On `RLHelper_CombatEnded`, the module will clear the last logged timestamp. On `RLHelper_Demo`, it will log one representative Shadow Trap message with the same iconized format.

## Tests

Add `tests/LichKingTracker.test.lua` to cover:

- Logs the first player damaged by `73529` with the Shadow Trap icon.
- Ignores later `73529` damage events with the same timestamp.
- Logs another player when `73529` damage occurs at a different timestamp.
- Ignores non-player destinations.
- Ignores non-`SPELL_DAMAGE` events for Shadow Trap.
- Resets timestamp state on combat end/reset.
- Demo logs a representative iconized Shadow Trap message.

Update `RLHelper.toc` to load `modules\bosses\LichKingTracker.lua`.
