# Display Only In Group Design

## Goal

Make `Display only in Group` control automatic visibility only. When enabled, RLHelper should hide itself after the player leaves a party or raid and show itself after the player joins a party or raid. Manual `/rlh` toggling should still work outside a group.

## Current Behavior

`SetMainFrameVisible(true)` checks `ShouldShowMainFrame()`, so `/rlh` cannot show the window outside a group when `displayOnlyInGroup` is enabled. `RefreshMainFrameVisibility()` only hides the frame when the player is outside a group; it does not show the frame again after joining a group.

## Desired Behavior

- If `displayOnlyInGroup` is enabled and the addon frame is visible, leaving a party or raid hides it.
- If `displayOnlyInGroup` is enabled and the player joins a party or raid, the addon frame is shown automatically.
- If `displayOnlyInGroup` is enabled and the player is outside a group, `/rlh` can still show the frame manually.
- If `displayOnlyInGroup` is disabled, group roster changes should not force-show or force-hide the frame.

## Implementation Shape

Keep `IsInGroup()` as the single source for group membership. Change `RefreshMainFrameVisibility()` so it only applies automatic group behavior when `displayOnlyInGroup` is enabled: show in group, hide outside group. Change `SetMainFrameVisible(true)` so manual show no longer calls `ShouldShowMainFrame()` as a blocker.

Keep existing calls to `RefreshMainFrameVisibility()` from initialization, enable, party roster changes, raid roster changes, and the settings checkbox click handler.

## Testing

Add focused tests in `tests/Core.test.lua` for:

- automatic hide outside a group when the option is enabled;
- automatic show after joining a party or raid when the option is enabled;
- `/rlh` or `SetMainFrameVisible(true)` can show the frame outside a group when the option is enabled;
- `RefreshMainFrameVisibility()` does not force visibility changes when the option is disabled.

Run the full Busted suite after implementation.
