# Raid assignments and mechanic errors

## When to apply

When classifying newly recorded RLHelper journal events as information or tactical mistakes.

## Rule

Use the raid leader's current MAINTANK and MAINASSIST assignments as tank designations, cached by GUID with the group roster. The user explicitly treats both assignments as tanks. Refresh assignments on roster changes; remove stale assignments when members leave or roles change.

During combat:
- A taunt by an assigned tank is informational.
- A taunt by a known non-tank on a known boss is a violation, provided tank assignments exist.
- A taunt on an ordinary mob is informational even during a boss encounter.
- Righteous Defense (31789) cast on an assigned tank by another known non-tank is a violation. A cast by another assigned tank is informational: the off-tank may take the boss from the main tank.
- Hand of Protection (10278) on an assigned tank is a violation; on a non-tank it is informational.

Do not infer a tank from class or declare a taunt erroneous when assignments or boss identity are unknown. Keep the event in the journal regardless of classification.

## Reason

The same ability can be correct or erroneous depending on the player's assignment and the actual target. Encounter-wide boss status does not make every target a boss. Historical events must retain the assignments and assessment at the time they happened.

## Checklist

- Test both MAINTANK and MAINASSIST.
- Test boss targets and ordinary mobs in the same boss encounter.
- Test events inside and outside combat, including missing assignments.
- Persist source/target assignments and classification when recording events.
- For delayed logging, capture classification at the original event, before roles can change.
- Verify old history stays unchanged after a roster update.
