---
title: Why the read-only investigate route is a route, not a workflow file
type: decision
domain: [rulebook, swe, routing]
related: [decision-engine-rulebook-split.md, decision-code-to-swe-rename.md]
confidence: high
created: 2026-08-22
updated: 2026-09-02
---

## Context

Agents asked a read-only question — "look at this code and tell me why X" —
were running the test suite, editing docs, and appending to
`.kerby/memory.log`. The maintainer confirmed this was agent-chosen behavior,
and that a separate agent, asked afterwards, agreed the test run had not been
needed.

It was not improvisation. The rulebook instructed it, through four separate
paths that all pointed the same way:

- `BOOTSTRAP.md` § 3's routing table held seven rows and every one was a
  *change* task. An investigation matched none, so the nearest row won —
  "Documentation only" or "Config change, single-file edit" — and both point
  at `quick-task.md`.
- `workflows/quick-task.md` steps 3b–6 are unconditional: run the quality
  gate, commit, append the log, commit the log. No step asks whether anything
  changed.
- `references/communication.md` said to log "after every significant action",
  anchored to neither a commit nor a diff.
- § 2.5 forces a grade and a route on every task, with no exit for work that
  is not a task.

The vocabulary already existed — `references/audit.md` and
`workflows/adopt-existing.md` each carry a read-only contract. It had simply
never been applied to the ordinary "look at this code" request.

## Decision (human-confirmed 2026-08-22)

Add `investigate` as a **route value**, not a workflow file. Four edits, swe
only, shipped as swe 2.10.0 / kerby 9.22.0:

1. First value in the § 2.5 route enum — the line agents already emit, so the
   declaration costs no new forced artifact.
2. First row of the § 3 routing table, pointing at no workflow file.
3. A § 4 contract placed **first** in the section, so it scopes the
   change-shaped rules beneath it. Names the file:line citation — not a green
   suite — as what satisfies the Iron Law for an answer, and keeps an explicit
   carve-out for running a command to *observe*.
4. A first criterion in `quick-task.md`'s fit check: a change is actually
   being made.

Two anti-abuse guards, because the obvious failure is an agent declaring
`investigate` to duck commit discipline: the re-route clause ("`investigate`
is not a way to make a change without one") and the fit-check bullet, which
catches the mis-route where the old failure actually landed.

## Rejected, and why — this is the reusable part

| Considered | Rejected because |
|---|---|
| A fifth workflow file, `investigate.md` | Every rule costs recurring input tokens, and a fifth file must stay in sync with four others. A routing row plus one contract section covers it. |
| A third forced line (`mode: read-only`) | § 2.5 already forces two lines. `route: investigate` **is** the declaration; adding a third artifact to every task to serve one route does not pay. *(Still stands as written. swe 2.11.0 did add a third forced line, `plan:`, but it is emitted at the first edit rather than in § 2.5's block, and it serves every change route rather than one — the reasoning that rejected `mode: read-only` is what makes `investigate` one of the routes that waives it.)* |
| A `git status --short` conditional on the finish blocks in `feature.md` § 7 / `bugfix.md` § 6 | **The subtle one.** It looks like the general fix — "skip the write steps when nothing changed" — and it is wrong. After a clean task loop the tree **is** empty at § 7 and the session summary is still required, so the conditional would suppress exactly the entry whose ordering was fixed in `d0afdf7`. Scope the guard to `quick-task.md`, where the change is uncommitted by construction. |
| A parity guard for the new prose | `skills/kerby/CLAUDE.md` § "Guard a constant, not a sentence": a prose guard was written, defeated three times by ordinary authoring wording, and removed for converting *nobody checked* into *the check passed*. |
| Fixing it in `base` instead | The base floor's `iron-law-claims.md` ("identify the verification command … run it fresh") genuinely has no referent for an answer, and that ambiguity is still open. Deliberately left as separate work — see Open below. |
| Reflowing `assets/workflow-routing.svg` to six rows | The diagram's own title scopes it to "how kerby routes a task to a **workflow file**", and `investigate` reaches none. A caption was cheaper and stays true. |

## Consequences

- `investigate` reaches no workflow file at all. Anything that assumes every
  route has one will be wrong; § 3 still ends with "Read the workflow file
  now", which is unsatisfiable on this route. Left as-is: the table row says
  "No workflow" and eight test executors handled it without hunting for a
  file, so the cost of a clarifying clause did not clear the rule-cost gate.
  Revisit if it ever bites.
- The § 1b `rung:` and `skipped:` lines are waived here, and the rule now says
  to **omit** them rather than announce the waiver — the first evaluator round
  passed 41/41 and still caught executors writing a meta-paragraph explaining
  the omission, which is the closing fluff § 4 Output Discipline forbids.

## Open

- The `base` floor's Iron Law ambiguity is unaddressed. swe now defines what
  evidence means for an answer; every other rulebook inherits the vague
  version.
- Verified by an in-session split-role `skill-evaluator` pass (49/49 at
  `6aa18ff`) only. The maintainer chose the standard bar over the higher one
  (fresh-session pass), and waived the independent Codex review that
  `skills/kerby/CLAUDE.md` § Gate tiers marks HARD for rule-text changes. So
  the author-framing bias this repo normally removes was not removed here.
