# Project Status

> **Position only.** This file answers *where do things stand* — never *what
> happened*, *which version*, or *what a PR is doing*. Those have authorities
> already: the manifests, git, `.kerby/memory.log`, the tracker. Rewrite this from
> what they currently say, never from memory of what you set an hour ago.

---

## Current Position

| Field | Value |
|-------|-------|
| **Phase** | Engine — the rules come back after a compaction (in review); next, the STATUS guard at commit time and the no-footprint rule |
| **Milestone** | Rules that survive a compaction, and a STATUS file that cannot state provenance |
| **Milestone Goal** | After a compaction the SessionStart hook re-supplies every pinned builtin's rules without the agent asking; a staged STATUS.md naming a version, SHA or PR number is refused at commit time; commit and PR text carries no tool footprint |

---

## Next Up

| Priority | Task | Dependencies |
|----------|------|--------------|
| 1 | **Ship the compaction re-injection PR** — Codex review on the pull request, address every comment against HEAD, squash-merge, then refresh the installed copy with `npx skills add sorawit-w/kerby` (the copy at `~/.agents/skills/kerby` is what every sibling repo's hooks run) | Codex review |
| 2 | **swe: the STATUS guard at commit time, and no footprint** — two new token shapes in the provenance guard (`#` + digits, `PR` + digits), a new block-severity `PreToolUse/Bash` enforcer that runs the guard on the staged STATUS.md, one commit-convention sentence that commit/PR text never names the tool, model or vendor; this repo's own STATUS.md rows that cite PR numbers are reworded in the same change | row 1 merged (same version surfaces) |
| 3 | **limeade alignment** — drop its AGENTS.md "Allowed" line for SHAs and PR numbers, import AGENTS.md from CLAUDE.md so it survives compaction, clean the two SHAs and two PR numbers its STATUS.md carries, drop the harness-attribution sentence from its Azure DevOps PR skill | row 1 merged and the install copy refreshed |
| 4 | **Fresh-session `skill-evaluator` pass for the protect-env scope change, the state-lands-inside-the-PR change, and the codex-mark transcript fix.** All three are the higher-bar class in `skills/kerby/CLAUDE.md` § Gate tiers (safety / commit-discipline / new behavioral surface) and all three shipped without it. It cannot run in the session that authored the change — that is the point of the outer-bias check | a session other than the authoring one |
| 5 | Resolve the `prepare` ring-fence contradiction — `adopt-existing.md` creates tracked artifacts while its own ring-fence forbids committing them. Open P1 from the state-lands-inside-the-PR change, deliberately left as a scope decision | maintainer |
| 6 | Keep the installed copy current — it is a plain copy fetched with `npx skills add sorawit-w/kerby`, not a link to this repo, so every merged release needs that command re-run before a session anywhere governs by it | none |
| 7 | **Sibling-repo cleanup** — agent-skills, declair, dunkuri, konthai, oh-shift, piggy-hero each still select `codex-review` and register its gate hook: `kerby unload codex-review` then `kerby install` in each; konthai also drops the entry from its committed `.kerby/rulebooks.toml` | row 6 — the installed copy must be on this release first |
| 8 | **laney follow-up** — seed `examples/swe`'s review phase with the `CODEX_VERDICT` grammar and P0/P1 triage from the retired rulebook (git history, not this tree) | laney |
| 9 | Work the logged P2/P3 debt (below) | none |

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
- **`memory.log`** — one record written before the state-lands-inside-the-PR change landed the format rules is missing its
  `[timestamp]` header and `Commit:` field. Append-only, so it needs a correction entry
  rather than an edit.
- **State-write ordering** — `context-management.md`'s shutdown path and
  `implementation-planning.md`'s validation step still write after their commit. Part of
  the same scope question as `prepare`'s ring-fence above.
- **`uninstall <id>` on an id the install no longer ships is undefined** — the scoped
  sweep derives signatures from that rulebook's manifest, which cannot resolve. `install`'s
  dead-script prune is the working path; the text should say so or define the case.
- **Install Phase 3 writes one git pre-commit file that runs one script** — a second check declaring `git_hook = "pre-commit"` cannot be chained yet, so the commit-time STATUS guard registers as a Claude Code hook only.
- **`BOOTSTRAP.md` § 1b** — `rung:` is emitted with the grade, before investigation could
  change the approach, and nothing requires re-emitting it. Emitting at the decision point
  is what makes it bind, so moving it later has a real cost — a deliberate call, not a
  reflex fix.

---

## Notes for Human Review

- `protect-git` over-blocks a Bash call whose *heredoc text* merely contains a destructive
  git string. Safe direction, but not mentioned in `protect-git`'s own docs — an open
  documentation gap, not a record of past work.
- The installed kerby is a copy, refreshed by hand (`npx skills add sorawit-w/kerby`); until it
  is refreshed after a merge, a session anywhere governs by the previous release.
- **Settled: the independent review is the GitHub `@codex review` on the PR, and it is
  the only path.** The local loop was retired because it could not converge. The standing
  cost — a release carrying a defect the review finds — is now paid before merge, by
  addressing every comment against the current head.
