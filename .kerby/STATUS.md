# Project Status

> **Position only.** This file answers *where do things stand* — never *what
> happened*, *which version*, or *what a PR is doing*. Those have authorities
> already: the manifests, git, `.kerby/memory.log`, the tracker. Rewrite this from
> what they currently say, never from memory of what you set an hour ago.

---

## Current Position

| Field | Value |
|-------|-------|
| **Phase** | Implementation — fixing three portability defects in the shipped provenance guard |
| **Milestone** | Status-file accuracy — the guard behaves the same on every host it ships to |
| **Milestone Goal** | No fact that has an authority elsewhere is restated here; what stays is the judgment that has no other home |

---

## Next Up

| Priority | Task | Dependencies |
|----------|------|--------------|
| 1 | **Fresh-session `skill-evaluator` pass for #54, #56, #57.** All three are the higher-bar class in `skills/kerby/CLAUDE.md` § Gate tiers (safety / commit-discipline / new behavioral surface) and all three shipped without it. It cannot run in the session that authored the change — that is the point of the outer-bias check | a session other than the authoring one |
| 2 | Resolve the `prepare` ring-fence contradiction — `adopt-existing.md` creates tracked artifacts while its own ring-fence forbids committing them. Open P1 from #56, deliberately left as a scope decision | maintainer |
| 3 | Upgrade the installed kerby so a session governs by the rules this repo ships. Deferred in favour of a Claude Code plugin that auto-updates | plugin work |
| 4 | Work the logged P2/P3 debt (below) | none |

---

## Blockers

None.

---

## Logged debt

Non-blocking findings recorded rather than fixed, because P2/P3 never trigger a
re-review:

- **`quick-task.md` § 3a escalation dispositions** — four exits, two dispositions; one
  defect wearing two faces. Seven passes never converged, so it wants fresh eyes rather
  than an eighth patch.
- **Three remaining deferral-sink sites** — `vendor-adapters.md`'s cross-reference list,
  `working-patterns.md`'s ticket escape, and `debugging.md`'s sibling tickets each still
  name a sink instead of deferring to `guardrails.md` § Where a finding goes.
- **`planThreshold` runtime cap is unenforced** — the schema states the cap; nothing
  checks it at load.
- **`memory.log` has no `Evidence:` field** — a record can claim DONE without naming what
  proved it.
- **`check-skill-compat.py` has no test of any kind** — it is the HARD-always gate, and a
  guard with no test is an untested claim of safety.
- **`roadmap.md` calls `STATUS.md` ephemeral; `communication.md` calls it tracked shared
  state.** Pre-existing contradiction, unresolved.
- **`SKILL.md`** — one residual "never read" phrase contradicting the post-resolution
  inspection rule stated two paragraphs above it; the recursive-glob prohibition is
  explained twice.
- **Pin canonicalization** — the reconcile rewrites only when `version` or `path_or_url`
  differ, so a pin that is otherwise current but carries a non-null `sha256` or a stray
  `local_path` stays non-canonical.
- **`memory.log`** — one record written before #56 landed the format rules is missing its
  `[timestamp]` header and `Commit:` field. Append-only, so it needs a correction entry
  rather than an edit.
- **Four P2s from the final review round of the review-machinery series.** One is a
  disagreement worth the maintainer's eye: Codex holds that DELETING the flaky temp-file
  assertion lost real coverage and that isolating `TMPDIR` would have been better, because
  a broken `EXIT` trap could now leak a snapshot on every mark unnoticed. The other three:
  the read-once pin can still pass for an unrelated failure after its single read
  (reproduced) and should also assert the `DENIED` diagnostic; the signal comment's "both
  cost a re-review" is too strong; and the README row wrongly implies a missing sidecar
  always means the run never finished.
- **State-write ordering** — `context-management.md`'s shutdown path and
  `implementation-planning.md`'s validation step still write after their commit. Part of
  the same scope question as `prepare`'s ring-fence above.
- **`BOOTSTRAP.md` § 1b** — `rung:` is emitted with the grade, before investigation could
  change the approach, and nothing requires re-emitting it. Emitting at the decision point
  is what makes it bind, so moving it later has a real cost — a deliberate call, not a
  reflex fix.

---

## Notes for Human Review

- `protect-git` over-blocks a Bash call whose *heredoc text* merely contains a destructive
  git string. Safe direction, but not mentioned in `protect-git`'s own docs — an open
  documentation gap, not a record of past work.
- The installed kerby is older than what this repo ships, so a session here governs by
  rules the repo has already moved past. Open until the plugin work lands.
- **Settled: a clean local Codex review is sufficient to merge.** Portability defects the
  local venue cannot see are follow-up work, not a merge blocker. The standing cost is that
  a release can carry one until someone reads the merged PR's review comments.
