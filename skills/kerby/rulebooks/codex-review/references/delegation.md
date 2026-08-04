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

**Run it through `scripts/codex-run.sh`** — never bare, never piped to `tee`:

```
scripts/codex-run.sh [--ceiling <seconds>] [--log <path>] -- <runtime> [args...]
```

The script is the mechanical form of the first three bounds below; it bounds one
attempt and reports why that attempt ended. The bare/piped forms cannot be
bounded at all: in `codex … | tee log &` the shell's `$!` is **tee's** pid, so a
timeout built on it kills `tee` and leaves the runtime running — and macOS ships
no `timeout(1)` to build one with. That combination is how a 23.7-hour attempt
reached this repo's own audit log.

- **Close stdin** (mechanical). An open empty stdin in a background shell
  deadlocks silently on `Reading additional input from stdin...`. The wrapper
  redirects `< /dev/null`; a hand-rolled invocation must too.
- **Classify before waiting** (mechanical). Transcript parked at a known
  block-point *and* not growing = deterministic hang → killed now, exit **3**.
  Alive but silent = stall → grace to the ceiling, then killed, exit **4** —
  never earlier, never past. (The wrapper reads a frozen transcript mtime as its
  idle signal, not CPU: macOS `ps %cpu` is a decayed lifetime average, so "flat
  CPU" is not observable there. Same intent, honest instrument.)
- **Wall-clock ceiling per attempt** (mechanical): ~2× the observed-good duration
  (median of the numeric `dur=` fields in `$GIT_DIR/codex-review-audit.log`,
  ignoring `?`); no baseline → 15 min. The wrapper computes this, clamps it to
  [5 min, 60 min] so neither one fast fluke nor an accumulation of hangs can
  disable the bound, and prints the value it used. `--ceiling` overrides.
- **Restart keyed to cause:** known cause → fix it, retry once; unknown stall →
  at most one blind retry. Never loop identical restarts. The wrapper's exit code
  says which applies — **3** names the cause (fix it), **4** is the blind-retry
  case, **5** means the runtime itself failed (read the transcript first).
  Killed and failed attempts append a line to `$GIT_DIR/codex-run-attempts.log`;
  a run that hangs and never marks leaves no other trace.
- **Delegation budget: at most 2 attempts per requested verdict** (a run that
  yields a *parseable* verdict never consumes it). This one stays yours to
  count — `codex-run.sh` bounds a single attempt and never retries, because
  "parseable" is `codex-mark.sh`'s grammar (forking it into a second script is
  how two authorities drift apart) and "keyed to cause" is a judgment a wrapper
  could only ever discharge as the identical restart the rule forbids.
  Exhausted with no verdict →
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
