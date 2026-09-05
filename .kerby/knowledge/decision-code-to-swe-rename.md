---
title: Why the coding rulebook was renamed code → swe
type: decision
domain: [architecture, naming, migration]
related: [decision-engine-rulebook-split.md]
confidence: high
created: 2026-08-02
updated: 2026-09-05
---

## Context

Commit `f89bb3f` — "kerby v9.0.0 — rename the coding rulebook code → swe (+
engine-only root README) (#27)" — plus the "Migration residue" section in
`skills/kerby/SKILL.md` that still handles pre-v9 pins naming the builtin
`code`.

## Decision (human-confirmed 2026-08-02)

Renamed the builtin coding rulebook's id from `code` to `swe` at v9.0.0, with
a one-time pin-migration path kept in the engine (scheduled for removal at
v10) so a pre-v9 `.kerby/rulebooks.lock` pinning `code` still resolves.

## Rationale (human-confirmed)

> "Since we turned kerby into an engine that can support rulebooks, using
> `swe` makes more sense." — Kiang, 2026-08-02

- With the engine/rulebook split (see `decision-engine-rulebook-split.md`)
  already landed, `code` as an id read like it named *the whole system's*
  purpose rather than one domain among several planned ones (sales, support,
  compliance, editorial — see README "Rulebooks you could write").
- Renaming to `swe` (software engineering) frees `code` as an ordinary,
  unreserved id any future rulebook — builtin or external — could use.

## Revisit When

- Done at kerby 10.0.0: the residue was removed with the `codex-review`
  retirement (see `decision-remove-codex-review.md`); a stale `code` pin now
  fails closed like any other unknown builtin id
  instead of auto-migrating.
