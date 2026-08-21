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

The shim execs `scripts/codex-run.py`, the mechanical form of the first three
bounds below; it bounds one attempt and reports why that attempt ended. The
bare/piped forms cannot be bounded at all: in `codex … | tee log &` the shell's
`$!` is **tee's** pid, so a timeout built on it kills `tee` and leaves the
runtime running — and macOS ships no `timeout(1)` to build one with. That
combination is how a 23.7-hour attempt reached this repo's own audit log.

The watchdog is python, not bash, because five review rounds of a pure-bash
predecessor found seven defects, all one shape: `ps`/`kill -0`/`kill`/`wait`
each have a third answer besides yes and no — *the query failed* — and every
guard that folded it into one of the other two produced an unbounded wait or a
signal aimed at a process the wrapper never started. `proc.wait(timeout=…)` on
the wrapper's own child has exactly two outcomes, both bounded by construction;
there is no third answer left to misfold. See `codex-run.py`'s module docstring
for the full account, and `README.md`'s Known ceilings for what python does
*not* fix.

- **Close stdin** (mechanical). An open empty stdin in a background shell
  deadlocks silently on `Reading additional input from stdin...`. The wrapper
  redirects to `/dev/null` structurally (`stdin=subprocess.DEVNULL`); a
  hand-rolled invocation must too.
- **Do not classify before waiting.** This rule used to split "deterministic
  hang" (kill now) from "stall" (wait for the ceiling). Drop that split: there is
  no sound way to tell them apart from outside. A model thinking and a model
  wedged look identical — the transcript is quiet in both. The documented
  block-point line is printed at *startup* on every redirected-stdin run and
  appears verbatim in this very file, so matching on it fires on healthy runs.
  A wrapper build that killed on line-plus-silence truncated a healthy 107 KB
  review at 38 seconds. Everything alive at the ceiling is a stall → killed,
  exit **4** — never earlier.
- **The wrapper returns no later than `ceiling + 15s` on every path it can
  control, unconditionally.** TERM is sent at the ceiling so the runtime can
  flush a partial transcript; a runtime ignoring it outlives the ceiling by at
  most the 5-second grace before SIGKILL. A process that does not die on
  SIGKILL (genuine uninterruptible I/O — a hung NFS/FUSE mount, a
  stopped-and-traced process) is bounded by nothing this wrapper, or any
  wrapper, can do: that case is **detected authoritatively** (`waitpid` on the
  wrapper's own child either succeeds or it doesn't — there is no third
  answer), reported as exit **6**, and the log lock is deliberately left in
  place so no retry can start beside it. Do not soften this to "never
  unboundedly" — that was the overclaim exit 6 exists to correct.
- **Wall-clock ceiling per attempt** (mechanical): ~2× the observed-good duration
  (median of the numeric `dur=` fields in `$GIT_DIR/codex-review-audit.log`,
  ignoring `?`); no baseline → 15 min. The wrapper computes this, clamps it to
  [5 min, 60 min] so neither one fast fluke nor an accumulation of hangs can
  disable the bound, and prints the value it used. `--ceiling` overrides.
- **Restart keyed to cause:** known cause → fix it, retry once; unknown stall →
  at most one blind retry. Never loop identical restarts. The wrapper's exit code
  says which applies — **4** (killed at the ceiling) is the blind-retry case,
  **5** means the runtime itself failed and names a cause in the transcript, so
  read it and fix before retrying, **7** means the review finished but its
  completion record could not be written (a filesystem problem, not a review
  problem — fix it and re-run; it costs no delegation attempt and logs none),
  and **6** means the process outlived SIGKILL:
  do **not** retry at all — a second attempt would run beside a still-alive
  process holding the transcript — investigate the reported pid, then clear the
  lock once it's confirmed dead.
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
