# pr-check — report the PR-gate state

Read-only status report. Run each step, then render the report. Resolve every
rulebook path relative to this rulebook's root (the folder this command body was
loaded from). Write nothing; this command only inspects.

## 1. Codex preflight (on disk, never the skill list)

Locate the codex plugin on disk: find its `commands/` directory
(`find <plugin-root> -name '*.md' -path '*commands*'`) or its
`scripts/codex-companion.mjs`. Search the known plugin roots (the Claude Code
plugin cache and any configured plugin directories). Report one line:
`codex plugin: found at <path>` or `codex plugin: NOT FOUND on disk — the PR
workflow's step-4 fallback applies`. The session skill list is not evidence
either way — most codex commands are `disable-model-invocation` and never
appear there.

## 2. Gate state (current repo)

From the session's working directory:

- `git rev-parse --git-dir` and `git rev-parse HEAD` — if not a git repo, report
  that and stop.
- Marker: does `$GIT_DIR/codex-reviewed` exist, and does its content equal HEAD?
  Report `marker: fresh (HEAD reviewed)`, `marker: STALE (held <sha>, HEAD is
  <sha>)`, or `marker: none`.
- Rounds: read `$GIT_DIR/codex-review-rounds` (line 1 = branch, line 2 = count).
  Report `rounds: <n> of 3 on <branch>` or `rounds: 0 (fresh)`.
- Audit tail: last 3 lines of `$GIT_DIR/codex-review-audit.log`, or `audit log:
  empty`.
- Hook binding: is `hooks/codex-pr-gate.sh` (this rulebook's copy, resolved
  absolute) registered as a PreToolUse/Bash hook in the effective settings?
  Report `gate hook: bound` or `gate hook: NOT BOUND — run kerby install`
  (declared-hard enforcement is degraded to behavioral until bound).

## 3. Duplicate-rule check

Search the global `~/.claude/CLAUDE.md` and the current repo's `CLAUDE.md` for
duplicated codex workflow text (markers: `CODEX_VERDICT`, `Review loop
(bounded)`). For each hit, report the file and offer the menu: **remove the old
copy** (show the exact section, get per-file confirmation before any edit) /
**proceed anyway** (duplicates coexist; drifted copies are ambiguous — say so) /
**stop**. Never edit a CLAUDE.md without the user's explicit per-file yes.

## 4. Render

One compact report block with the four sections above, then a one-line verdict:
`pr-check: ready` (plugin found, marker fresh or no PR in flight, hook bound, no
duplicates) or `pr-check: attention — <the specific items>`.
