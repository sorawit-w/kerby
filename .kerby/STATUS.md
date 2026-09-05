# Project Status

> **Position only.** This file answers *where do things stand* — never *what
> happened*, *which version*, or *what a PR is doing*. Those have authorities
> already: the manifests, git, `.kerby/memory.log`, the tracker. Rewrite this from
> what they currently say, never from memory of what you set an hour ago.

---

## Current Position

| Field | Value |
|-------|-------|
| **Phase** | Release — retiring the `codex-review` builtin and the `code` → `swe` migration residue |
| **Milestone** | Three builtins; one PR-review path |
| **Milestone Goal** | No engine surface names a rulebook that does not ship, and the independent review lives where it converges — on the pull request |

---

## Next Up

| Priority | Task | Dependencies |
|----------|------|--------------|
| 1 | **Fresh-session `skill-evaluator` pass for #54, #56, #57.** All three are the higher-bar class in `skills/kerby/CLAUDE.md` § Gate tiers (safety / commit-discipline / new behavioral surface) and all three shipped without it. It cannot run in the session that authored the change — that is the point of the outer-bias check | a session other than the authoring one |
| 2 | Resolve the `prepare` ring-fence contradiction — `adopt-existing.md` creates tracked artifacts while its own ring-fence forbids committing them. Open P1 from #56, deliberately left as a scope decision | maintainer |
| 3 | Upgrade the installed kerby so a session governs by the rules this repo ships. Deferred in favour of a Claude Code plugin that auto-updates | plugin work |
| 4 | **Sibling-repo cleanup** — agent-skills, declair, dunkuri, konthai, oh-shift, piggy-hero each still select `codex-review` and register its gate hook: `kerby unload codex-review` then `kerby install` in each; konthai also drops the entry from its committed `.kerby/rulebooks.toml` | row 3 — the installed plugin must be on this release first |
| 5 | **laney follow-up** — seed `examples/swe`'s review phase with the `CODEX_VERDICT` grammar and P0/P1 triage from the retired rulebook (git history, not this tree) | laney |
| 6 | Work the logged P2/P3 debt (below) | none |

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
- **State-write ordering** — `context-management.md`'s shutdown path and
  `implementation-planning.md`'s validation step still write after their commit. Part of
  the same scope question as `prepare`'s ring-fence above.
- **`uninstall <id>` on an id the install no longer ships is undefined** — the scoped
  sweep derives signatures from that rulebook's manifest, which cannot resolve. `install`'s
  dead-script prune is the working path; the text should say so or define the case.
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
- **Settled: the independent review is the GitHub `@codex review` on the PR, and it is
  the only path.** The local loop was retired because it could not converge. The standing
  cost — a release carrying a defect the review finds — is now paid before merge, by
  addressing every comment against the current head.
