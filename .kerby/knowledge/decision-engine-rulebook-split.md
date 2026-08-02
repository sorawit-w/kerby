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

Commit history shows two commit subjects labeled v6.0.0 (`b161c32`,
"pluggable rulebooks: engine/rulebook split") and v7.0.0 (`74509cb`,
"plug-and-play rulebooks: self-containment, commands, multi-rulebook, remote
sources") — these are version numbers named in the commit subject, not git
release tags (`git tag --list` is empty in this repo) — moving kerby to an
engine that loads pluggable rulebook folders. The "v1–v5 was a single
hardcoded coding playbook" framing comes from README.md's own "How it got
here" section, not from commit history in this repo's visible log — the
v1–v5 commits themselves aren't independently verified here.

## Decision (human-confirmed 2026-08-02)

Split kerby into two parts: an **engine** (loads, validates, pins trust,
registers hooks, renders verdicts) — designed to be domain-blind — and
**rulebooks** (self-contained folders — manifest, optionally prose / hooks /
commands too — carrying the actual domain judgment). v7 made the split
physical: rulebooks became self-contained folders resolvable from their own
root, supporting multiple rulebooks loaded at once and remote sources. Note:
v6/v7 established the *structural* split and the *intent* of domain-blindness;
the engine still special-cased the builtin `swe` rulebook's name in places
until the separate engine-independence-zoning decision (v9.4–v9.5) removed
that — see `decision-engine-independence-zoning.md`.

## Rationale (human-confirmed)

- A single hardcoded corpus couldn't extend to non-coding domains (sales,
  support, compliance — see README "Rulebooks you could write").
- Self-containment (v7) appears to let a rulebook be copied, forked, or loaded
  from a different repo without engine changes.

## Revisit When

- If a future engine change needs to special-case a specific rulebook's
  content again — that would contradict this split and should surface as a
  finding, not a quiet exception (see `decision-engine-independence-zoning.md`).
