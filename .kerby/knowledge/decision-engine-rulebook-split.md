---
title: Why the engine was split from rulebook content
type: decision
domain: [architecture, engine]
related: [decision-code-to-swe-rename.md, decision-engine-independence-zoning.md]
confidence: high
created: 2026-08-02
updated: 2026-08-02
---

## Context

Commit history (`v6.0.0 — pluggable rulebooks (engine/rulebook split)`, `v7.0.0 —
plug-and-play rulebooks (self-containment, commands, multi-rulebook, remote
sources)`) shows kerby moved from a single hardcoded coding playbook (v1–v5) to
an engine that loads pluggable rulebook folders.

## Decision (human-confirmed 2026-08-02)

Split kerby into two parts: a domain-blind **engine** (loads, validates, pins
trust, registers hooks, renders verdicts) and **rulebooks** (self-contained
folders — manifest + prose + hooks + commands — carrying the actual domain
judgment). v7 made the split physical: rulebooks became self-contained folders
resolvable from their own root, supporting multiple rulebooks loaded at once
and remote sources.

## Rationale (human-confirmed)

- A single hardcoded corpus couldn't extend to non-coding domains (sales,
  support, compliance — see README "Rulebooks you could write").
- Self-containment (v7) appears to let a rulebook be copied, forked, or loaded
  from a different repo without engine changes.

## Revisit When

- If a future engine change needs to special-case a specific rulebook's
  content again — that would contradict this split and should surface as a
  finding, not a quiet exception (see `decision-engine-independence-zoning.md`).
