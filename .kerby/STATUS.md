# Project Status

> **Last updated:** 2026-08-25T18:30:00Z
> **Updated by:** ai

---

## Current Position

| Field | Value |
|-------|-------|
| **Phase** | In review — 9.25.1, a documentation correction (Copilot invokes kerby's hooks) |
| **Milestone** | Tiered hook opt-in — **complete** (9.23.0 → 9.25.0, three PRs, all merged) |
| **Milestone Goal** | Let a user decline individual hooks, and see what would be registered before deciding |
| **Working Branch** | feature/windows-hook-install (release `9.25.1`) — #61, #62, #63 merged; this branch is docs-only |

---

## Progress

| Status | Count | Tasks |
|--------|-------|-------|
| Done | 5 | #54 protect-env scope · #55 decision-ladder artifacts · #56 shared state + finish order · #57 locator + trust rules · #63 `kerby hooks` |
| In Review | 1 | 9.25.1 — Copilot invokes kerby's hooks through PowerShell (docs correction, this branch) |
| Blocked | 0 | — |
| Ready | 2 | Fresh-session `skill-evaluator` passes · logged P2/P3 debt |

---

## Recent Completions

| Task | Commit | Completed |
|------|--------|-----------|
| #54 — protect-env guards the file with no undo, not every `.env` | da830a4 | 2026-08-21 |
| #55 — the decision ladder becomes a forced artifact | 59286b7 | 2026-08-21 |
| #56 — state lands inside the PR that produced it | d0afdf7 | 2026-08-21 |
| #57 — the locator stops letting the workspace choose the gate | e38eff9 | 2026-08-21 |
| #58 — a killed review can no longer be marked clean | 3c9ef55 | 2026-08-21 |
| #63 — `kerby hooks`, a read-only view of what install would register | 450a627 | 2026-08-24 |
| 9.25.1 — Copilot/Windows hook claim corrected; engine change built then reverted | (pending) | 2026-08-25 |

---

## Next Up

| Priority | Task | Dependencies |
|----------|------|--------------|
| 1 | **Fresh-session `skill-evaluator` pass for #54, #56, #57.** All three are the higher-bar class in `skills/kerby/CLAUDE.md` § Gate tiers (safety / commit-discipline / new behavioral surface) and all three shipped without it. It cannot run in the session that authored the change — that is the point of the outer-bias check | a session other than the authoring one |
| 2 | Decide whether `STATUS.md` should stay tracked. #56 made it shared state, so a refresh costs a branch, a review and a PR. **Provisionally answered by practice:** rather than open a standalone status PR, this refresh rides along with the 9.25.1 documentation correction — which is what #56's own model prescribes. Keep it tracked and batch refreshes into real changes; revisit only if standalone state PRs become common | maintainer |
| 3 | Resolve the `prepare` ring-fence contradiction — `adopt-existing.md` creates tracked artifacts while its own ring-fence forbids committing them. Open P1 from #56, deliberately left as a scope decision | maintainer |
| 4 | Work the logged P2/P3 debt (below) | none |
| 5 | *(done — `gitleaks` is now on PATH at `/opt/homebrew/bin/gitleaks`, so the secret scan no longer runs on its narrow fallback regex)* | — |

---

## Blockers

None.

---

## Logged debt

Non-blocking findings from the four merged reviews, recorded rather than fixed because P2/P3 never trigger a re-review — plus one item this branch resolves:

- **`SKILL.md`** — one residual "never read" phrase contradicting the post-resolution
  inspection rule stated two paragraphs above it; the recursive-glob prohibition is
  explained twice.
- **Pin canonicalization** — the reconcile rewrites only when `version` or `path_or_url`
  differ, so a pin that is otherwise current but carries a non-null `sha256` or a stray
  `local_path` stays non-canonical.
- **`memory.log`** — one record written before #56 landed the format rules is missing its
  `[timestamp]` header and `Commit:` field. Append-only, so it needs a correction entry
  rather than an edit.
- **Four P2s logged from the final review round** (rulebook: P2/P3 never trigger a
  re-review). One is a disagreement worth the maintainer's eye: Codex holds that DELETING
  the flaky temp-file assertion lost real coverage and that isolating `TMPDIR` would have
  been better, because a broken `EXIT` trap could now leak a snapshot on every mark
  unnoticed. The other three: the read-once pin can still pass for an unrelated failure
  after its single read (reproduced) and should also assert the `DENIED` diagnostic; the
  signal comment's "both cost a re-review" is too strong (before either `.prev` move a
  re-mark suffices, and after the marker write the valid marker already passes the gate);
  and the new README row wrongly implies a missing sidecar always means the run never
  finished — `codex-run` can finish and still return 7 if the record cannot be written.
- **Review machinery, fixed on this branch** — `codex-mark` would parse a verdict out of a
  *killed* run's transcript. Found when a stalled review left six verdict lines quoted from
  earlier reviews, the last being another PR's clean `P0=0 P1=0`. Prior markers are
  unaffected: the hazard needs a run that did not finish. The audit log records verdict
  metadata and duration, **not** exit status — so their short durations support the
  inference that they did not hit the ceiling, they do not prove exit 0.
- **Four rounds, and rounds 2–4 each found a defect in the previous round's fix.** The
  chain: quoted-verdict hazard → in-band sentinel reproduced it → digest binding, but the
  new lock trap did not stop the script → traps that exit, but release was not one-shot and
  could delete a successor's lock. Every link was a *fix*, not the original bug. **Resolved
  by deleting the lock**, not by a fifth patch: reading the transcript once into a snapshot
  closes the window the lock existed for, and removes the entire class. Worth reading before
  adding machinery to this area.
- **State-write ordering** — `context-management.md`'s shutdown path and
  `implementation-planning.md`'s validation step still write after their commit. Part of
  the same scope question as item 3 above.
- **`BOOTSTRAP.md` § 1b** — `rung:` is emitted with the grade, before investigation could
  change the approach, and nothing requires re-emitting it. Emitting at the decision point
  is what makes it bind, so moving it later has a real cost — a deliberate call, not a
  reflex fix.

---

## Notes for Human Review

- The four PRs took **nine** Codex rounds between them (#54=3, #55=1, #56=3, #57=2 — only a parsed verdict consumes a round, so the no-verdict attempts cost nothing). #54 and #56 hit the three-round cap
  and were opened under an authorized `CODEX_GATE_BYPASS=1` with the open findings
  disclosed in the PR body; #55 and #57 passed cleanly and needed no bypass.
- Recurring pattern worth knowing: across the series, roughly half the findings in any
  round were defects introduced by the *previous* round's fix. Two shipped rules had to be
  reversed after review disproved their premise — `merge=union` on `memory.log` (it
  silently truncates records sharing a trailing line) and the enumerated install-path list
  (a project-local path is workspace content, so it reopened the hole it was meant to
  close).
- `protect-git` over-blocks a Bash call whose *heredoc text* merely contains a destructive
  git string. Safe direction, documented as a ceiling for the PR gate, but not mentioned in
  `protect-git`'s own docs.

---

## Session History

| Timestamp | Agent | Tasks Completed | Notes |
|-----------|-------|-----------------|-------|
| 2026-08-02T00:00:00Z | ai | Onboarding via `prepare` | Populated agent-context.yaml, CONTEXT.md, 3 draft knowledge entries |
| 2026-08-21T00:00:00Z | ai | #54, #55, #56, #57 authored, reviewed and merged | Release `9.20.0`; all four branches deleted; fresh-session evaluator still outstanding |
