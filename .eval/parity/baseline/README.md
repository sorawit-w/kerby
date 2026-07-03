# Parity baseline — v5.8.0 behavior, pre-rulebook-split

Recorded 2026-07-03 at commit `fbf6085` (v5.8.0), branch point of
`feat/v6-pluggable-rulebooks`. This is the **Expected** side of the Iron Law
extension for the v6 engine/rulebook refactor: after Phase 3 (loader
integration), each scenario below is replayed and the Realized outcome is
recorded as-observed in `../realized/` — never edited to match. Judge
`match | mismatch` on **material intent**, not byte-exact output.

Scenarios:

- `scenario-1-load.md` — `kerby load` (no args): resolution order, what enters
  context, verbatim confirmation, readiness-nudge conditions.
- `scenario-2-status.md` — `kerby status`: detection method + verbatim reports.
- `scenario-3-gates.md` — mechanical gate outcomes: all hook test suites +
  repo check scripts, with counts.

Parity contract for v6 (from the handoff, § 9): `kerby load` with no args must
behave identically to v5.8.x — the `code` rulebook is the silent default; the
only permitted additive difference is the one-line D19 rulebook announcement.
