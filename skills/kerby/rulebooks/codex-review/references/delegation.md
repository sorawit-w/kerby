# Codex delegation (the rescue ladder)

When stuck — a retry budget exhausts, a debugging hypothesis cap hits, or two
consecutive fix attempts fail the same way — run `/codex:rescue` for an
independent diagnosis pass before escalating to the user. Prefer `--background`
for open-ended investigations (use `--effort high` for deep root-cause work) and
keep working meanwhile; check with `/codex:status` and fetch with `/codex:result`.
Codex advises; Claude decides — its diagnosis is a hypothesis to verify, not a fix
to apply blind. This is a rung before human escalation, not a replacement for it:
if the independent pass doesn't break the deadlock, escalate as usual.

## Bounded delegation — every headless Codex run (single source)

Applies to every headless Codex invocation this rulebook triggers — review,
scoped re-review, rescue.

- **Close stdin.** Headless `codex exec` / companion runs MUST redirect
  `< /dev/null` — an open empty stdin in a background shell deadlocks silently
  on `Reading additional input from stdin...`. Run backgrounded with output
  teed to a log, or the signals below don't exist.
- **Classify before waiting.** Log tail at a known block-point + flat CPU =
  deterministic hang → kill now, no grace. Alive and initialized but silent =
  stall → grace to the attempt's ceiling, then kill — never earlier, never past.
- **Wall-clock ceiling per attempt:** ~2× the observed-good duration (median of
  the numeric `dur=` fields in `$GIT_DIR/codex-review-audit.log`, ignoring `?`);
  no baseline → 15 min.
- **Restart keyed to cause:** known cause → fix it, retry once; unknown stall →
  at most one blind retry. Never loop identical restarts.
- **Delegation budget: at most 2 attempts per requested verdict** (a run that
  yields a *parseable* verdict never consumes it). Exhausted with no verdict →
  treat Codex as unable to produce a verdict and take the invoking workflow's
  fallback path (for the PR gate: `pr-workflow.md` step 4). "No verdict" means
  no parseable `CODEX_VERDICT` line — a missing line **and** a malformed one
  (present but not all four counts P0..P3) both count: each consumes a
  delegation attempt and, once the budget is spent, routes to the fallback.
  (A malformed line still costs no codex-mark *round* — that counter only
  advances on a well-formed verdict; the delegation budget and the round cap
  are separate.) A DENIED or HELD outcome IS a verdict; HELD escalates to the
  user, never to a fallback.

## The stop-time review gate — offer wording and cost caveat (single source)

The stop-time review gate (`/codex:setup --enable-review-gate`) stays off by
default — enable per-repo only if the prose review workflows are observed being
skipped. Cost caveat (state it whenever offering the gate, from any workflow in
this rulebook): the Stop hook spawns a Codex task on **every** turn end — the
"skip non-edit turns" logic is inside the Codex prompt (instant ALLOW), not the
hook — so even chat-only turns pay one Codex round trip; 15-min timeout. Good for
build-heavy repos that ship PRs, wasteful for mostly-conversational sessions.
