---
title: Why the codex-review rulebook was retired
type: decision
domain: [architecture, review, workflow]
related: [decision-engine-independence-zoning.md, decision-code-to-swe-rename.md]
confidence: high
created: 2026-09-05
updated: 2026-09-05
---

## Context

The `codex-review` builtin (shipped at 9.7.0, last touched at `3c9ef55`) wrapped a
local review-until-clean loop around Codex — run, mark, re-run, a three-round cap,
and a PreToolUse gate on `gh pr create`. Deleted at 10.0.0, together with the v9.0.0
`code` → `swe` migration residue that was scheduled for the same major.

## Decision (human-confirmed 2026-09-05)

Delete the rulebook, with no engine residue. The independent-model review stays as
the GitHub `@codex review` on the PR; if the review → fix → re-review sequence is
rebuilt, it is rebuilt as a laney workflow.

## Rationale (human-confirmed)

> "The review is necessary, but making it a hook may not be a good idea. This
> should be a part of the workflow instead of a kerby rulebook." — Kiang, 2026-09-05

- A model review is a sampler, not a proof, so "loop until clean" has no stable
  result. Audit log (`.git/codex-review-audit.log`, 2026-09-03 to 05): 19 PASSes,
  median 1 round, 7 hit the 3-round cap; 11 failed attempts, 7 of them stalls,
  about 76 minutes lost.
- The GitHub-side review found new defects after a clean local pass anyway (9.26.4
  records three), so the local loop duplicated it without replacing it.
- The wrapper needed six hardening PRs, mostly process-group kill semantics — the
  mechanism fought its environment.
- A capped sequence with a judge is a workflow. That is laney's shape
  (`examples/swe` phases review → fix → judge, max 3 loops), not a rulebook's:
  rulebooks hold judgment, sequences belong to the workflow engine.
- No engine residue: a stale `selected` entry takes the existing unknown-builtin
  HELD, and the fix is `kerby unload codex-review` then `kerby install`. All six
  affected repos are the maintainer's own; a migration path for them is code nobody
  else needs.

## Revisit When

- laney's `examples/swe` review phase is seeded with the `CODEX_VERDICT` grammar and
  P0/P1 triage from the retired `references/pr-workflow.md` and `scripts/codex-mark.sh`
  (`git show 3c9ef55:skills/kerby/rulebooks/codex-review/...`).
- A local review venue can prove convergence rather than sample it.
