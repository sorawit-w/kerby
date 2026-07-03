# Scenario 2 — `kerby status`, v5.8.0

Source of truth: `skills/kerby/SKILL.md` § `status` (lines 94–106 at `fbf6085`).

## Expected behavior

1. Scan recent conversation context for BOOTSTRAP signatures — distinctive
   phrases: `"Prime Directive"`, `"Clarity over cleverness. Safety over
   speed."`, `"implement → check → commit → log → repeat"`, or section tags
   `<prime_directive>`, `<hard_rules>`, `<reference_index>`.
2. If found:

   > **kerby: loaded.** Detected BOOTSTRAP markers in current context.

3. If not found:

   > **kerby: not loaded.** Invoke `kerby` with `args: load` to load them.

## What v6 must preserve (material intent)

- Loaded/not-loaded detection by context signature still works and the two
  verbatim reports remain the outer frame.

## Permitted additive difference (v6)

`status` grows the rulebook panel (D4): rulebook id/version/origin plus
per-check declared-vs-effective enforcement (degrades visible) and checks
skipped for unsatisfiable `needs`. The panel is additive — the loaded /
not-loaded verdict and its wording stay.
