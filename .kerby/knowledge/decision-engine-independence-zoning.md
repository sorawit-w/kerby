---
title: Why the engine stopped keying behavior on rulebook names
type: decision
domain: [architecture, engine, security]
related: [decision-engine-rulebook-split.md]
confidence: high
created: 2026-08-02
updated: 2026-08-02
---

## Context

Three consecutive commits — `94f91bf` (v9.4.0, "contract gains the optional
[identity] table — decoupling 1/3"), `be83802` (v9.5.0, "engine consumes
[identity]; behavior stops keying on `swe` — decoupling 2/3"), `98f427b`
(v9.5.1, "housekeeping for the decoupling 3/3") — plus root `CLAUDE.md`'s
"Engine independence" mention and `docs/rulebook-contract.md` § Engine
independence.

## Decision (human-confirmed 2026-08-02)

Introduced an optional `[identity]` table in the rulebook manifest contract
(load/reload confirmation strings, signature phrases for `status` scanning)
so the engine reads presentation behavior from a rulebook's own manifest
instead of special-casing the builtin `swe` rulebook's name in engine code
(`SKILL.md`, `resources/`).

## Rationale (human-confirmed)

- If the engine special-cased `swe`'s name to decide, e.g., which
  load-confirmation string to print verbatim, a same-named external `local`
  rulebook could either be silently treated as trusted-builtin-like, or the
  real builtin's confirmation logic could leak into a fork's context — a
  trust-boundary risk given kerby's local/remote rulebook trust model.
- Reading from `[identity]` instead lets the same confirmation/scan logic work
  for any rulebook (builtin or, for non-trust-granting fields, external)
  without the engine's *behavior* keying on that rulebook's name. The zoning
  rule (`docs/rulebook-contract.md` § Engine independence) still permits a
  builtin rulebook's name to appear in engine surfaces as a worked example or
  bundle contents — e.g. `swe` in SKILL.md's install-table example — it only
  forbids behavior branching on the name.

## Revisit When

- If a new engine surface (a new command, a new confirmation type) is added —
  check it consumes `[identity]`/`[detect]`/`[[check]]`/`[[command]]` fields
  rather than a hardcoded rulebook id, per the engine-independence zoning rule
  this decision established.
