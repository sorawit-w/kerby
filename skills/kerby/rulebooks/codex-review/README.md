# codex-review — opt-in Codex workflows for kerby

Wires the Codex CLI (an independent model line) into three workflows, under one
stance: **Codex advises, Claude decides.**

| Workflow | Prose | Mechanics |
|---|---|---|
| PR gate — review before `gh pr create`; P0/P1 block; 3-round cap; PASS/DENIED/HELD | `references/pr-workflow.md` | `hooks/codex-pr-gate.sh` (PreToolUse/Bash) + `scripts/codex-mark.sh` (sole marker writer) |
| Plan review — adversarial pass on complex plans, dissent disclosed | `references/plan-review.md` | none (behavioral, `warn`) |
| Rescue delegation — independent diagnosis before human escalation | `references/delegation.md` | `scripts/codex-run.sh` (thin shim) → `scripts/codex-run.py` (bounds one headless attempt) |

Every headless Codex invocation — review, scoped re-review, rescue — runs through
`scripts/codex-run.sh`, a shim that execs `scripts/codex-run.py`. It closes
stdin, gives the runtime its own process group, kills it at a ceiling derived
from the observed-good `dur=` median, and reports how it ended (0 clean · 4
killed at the ceiling · 5 runtime error · 6 outlived SIGKILL, do not retry). It
bounds *one attempt* and never retries: the delegation budget and the verdict
grammar stay with the prose and `codex-mark.sh` respectively. Written in python
rather than bash — five review rounds of a bash predecessor found seven
defects, all one shape (see Known ceilings below); `codex-run.py`'s module
docstring carries the full rationale.

The root body (`references/stance.md`) is a thin eager index: stance, on-disk
preflight, when-to-read pointers. The heavy references load on demand.

## Opt-in and install

`codex-review` declares no `[detect]` markers — it never auto-selects. Opt a repo
in explicitly:

```
kerby load codex-review      # adds to the selection (pin persists)
kerby install                # register the gate hook (Phase 2)
```

Until `kerby install` binds the hook, `pr-create-gate` is declared `hard` but
effectively behavioral — `kerby status` shows the degrade. `kerby pr-check`
reports preflight, marker/rounds/audit state, hook binding, and duplicate rules.

**Duplicate rules:** if the global or repo CLAUDE.md still carries the old codex
sections, the stance's adoption check (and `pr-check`) surfaces a
remove/proceed/stop menu. While duplicates coexist there is no mechanical winner —
identical copies waste tokens; drifted copies are ambiguous (CLAUDE.md nominally
outranks loaded prose). Migration is move-not-copy: delete the old copy.

**Per-check opt-out (contract 2): none.** User config remaps severities at the
gate level only (`block_on`/`hold_on`) — it cannot disable one check. A repo that
wants the PR gate but not plan review relies on plan review's complexity
self-gating (~zero cost on simple plans). `hold_on = []` would demote ALL
warn-severity checks — blunt; not recommended.

## State files (per-clone, in `$GIT_DIR`, never committed)

| File | Written by | Meaning |
|---|---|---|
| `codex-reviewed` | `scripts/codex-mark.sh` ONLY | marker: the reviewed HEAD sha |
| `codex-review.log` | `scripts/codex-run.sh` (fresh inode per attempt) | evidence codex-mark verifies |
| `codex-review-rounds` | `scripts/codex-mark.sh` | branch + round counter (cap 3) |
| `codex-review-audit.log` | `scripts/codex-mark.sh` | append-only PASS history; its `dur=` median sets the watchdog ceiling |
| `codex-run-attempts.log` | `scripts/codex-run.sh` | append-only history of killed/failed attempts — deliberately NOT the audit log, so these can never skew the `dur=` median |

## Bypass

`CODEX_GATE_BYPASS=1` **directly prefixing** the gh invocation, user-authorized
only (manifest `override = "authorized-scoped"`). The prefix form is the only
honored one: an embedded token (PR-body text) authorizes nothing, and one
authorized invocation never authorizes a second one in the same command.
Marker-less use is sanctioned only inside the step-4 fallback ladder (GitHub-side
review replacing the local one, or the disclosed last-rung degradation) when
local Codex is genuinely missing — or present but unable to produce a verdict
within the delegation budget (`references/delegation.md` § Bounded delegation).

## Known ceilings (deliberate)

- **String-match gate, not a shell parser.** The matcher is a broad token
  sequence — `gh` … `pr` … `create`/`new` in order, any options in any form
  between, not crossing a `;`/`&`/`|` separator. This catches every gh
  invocation syntax by design (attached `-Rowner/repo`, `-R=owner/repo`, spaced
  `-R owner/repo`, `--repo=`, the `new` alias, arbitrary global flags) rather
  than enumerating option shapes — four review rounds each found a shape an
  enumerating regex missed, so the gate stopped enumerating. The trade is
  over-blocking in the safe direction: a `gh pr create`-shaped string inside
  quoted prose, or a `-C `/`-R`/`--repo`/`GH_REPO=` token anywhere in a compound
  command, triggers a (re)fusal — the gate already asks you to run the command
  standalone, so rerun it plain or bypass. Deliberate-only escape hatches it does
  **not** try to catch (shaped like intent, not accident): the raw REST path
  (`gh api repos/{o}/{r}/pulls -X POST …`), a user-defined `gh alias`, or a shell
  line-continuation split. These are the `CODEX_GATE_BYPASS` category by another
  name — an accepted ceiling, not a hole to plug.
- **codex-mark trusts the transcript.** Forging a log is deliberate deception,
  not drift; `$GIT_DIR/codex-review-audit.log` keeps history visible.
- **The ceiling is the only bound — no early kill.** codex-run cannot tell a
  wedged runtime from a thinking one, and does not pretend to: both go quiet.
  The block-point line Codex was once matched on is printed at *startup* on
  every redirected-stdin run and appears verbatim in `references/delegation.md`,
  so it fires on healthy transcripts. A build that killed on line-plus-silence
  truncated a healthy 107 KB review at 38s — that is worse than the unbounded
  wait it replaced. Cost of the honest version: a genuine wedge burns the full
  ceiling instead of ~6s. Exit code 3 is left unused rather than recycled.
- **The ceiling baseline only learns from PASSes.** `dur=` is written by
  codex-mark, and codex-mark only writes it on PASS — so a repo whose reviews
  keep coming back DENIED never updates its baseline, and the ceiling stays
  anchored to whatever the last clean runs happened to cost. Observed live while
  building this: a review finished at 628s against a 688s ceiling derived from
  much older, shorter runs. When a review is killed at the ceiling but the
  transcript looks healthy, pass `--ceiling` explicitly rather than assuming a
  wedge. (`codex-run-attempts.log` records the real elapsed time of every run,
  so the evidence for a better number is there; wiring it into the baseline is
  deliberately not done yet.)
- **codex-run.py (the watchdog behind the `codex-run.sh` shim) never asks the
  OS about the child — only `waitpid`, via `proc.wait()`, ever gets to
  conclude anything.** No `ps`, no `kill -0`, no `os.getpgid()`. Five bash
  review rounds produced seven defects, all one shape: `ps`/`kill -0` each have
  a third answer besides yes and no — *the query failed* — and folding it into
  either of the other two produced an unbounded wait or a signal aimed at a
  process the wrapper never started.
  **Pid recycling does not apply to the design's intended shape.** A pid is not
  reusable while the process is an unreaped zombie; a process-group id is not
  reusable while any member of it exists; `start_new_session=True` places the
  group in a session containing only the wrapper's own descendants, and
  `setpgid` can only join a group in the caller's *own* session, so a stranger
  cannot join it either. Every `os.killpg()` call is *meant* to run strictly
  before the one `proc.wait()` that reaps. **This claim is not "on every
  path," and an earlier version of this README overstated it that way** — the
  returncode-race residual below is exactly a path where the ordering can
  invert: a signal handler can observe `returncode is None` (so it looks
  unreaped) a few CPython bytecode instructions AFTER the kernel has actually
  reaped the child, meaning a `kill_ladder()` triggered from that handler
  could, in the narrow window this residual describes, signal an already-freed
  pid/pgid. The bash predecessor carried this risk on essentially every path,
  unconditionally; this design narrows it to one specific, documented, hard-
  to-hit gap rather than removing the premise entirely, which is a real
  improvement but not the absolute one earlier prose here claimed.
  **What genuinely remains, and is not solved by any language:** a process in
  an uninterruptible kernel wait does not die on `SIGKILL` — codex-run detects
  that authoritatively (see exit 6 below) rather than misreporting it, but
  detecting it is not preventing it. A group member that calls `setsid()`
  itself leaves the wrapper's session and escapes the `killpg` entirely — this,
  not pid recycling, is a real remaining orphan hazard. `proc.wait()` on the
  clean-exit path only proves the *leader* was reaped — `waitpid` cannot reap a
  grandchild (it isn't the wrapper's child, only a member of its process
  group), so a backgrounded descendant can outlive a successful exit,
  **undetected**: an earlier draft sent a courtesy `SIGTERM` to the group after
  every clean exit, on the theory that the leader is already dead so nothing
  else could be hit — but a review pointed out that once the group is fully
  empty (leader reaped, no surviving descendant either) its pgid number is
  freed for OS reuse, so a courtesy signal fired on SPECULATION risks hitting
  an unrelated, later process group. That is a *worse* instance of the exact
  hazard this file exists to eliminate than the straggler it was trying to
  catch, so it was removed — this case is accepted as an undetected gap, not
  patched with a guess. And a `SIGKILL` to the wrapper itself still strands the
  lock directory (the bash EXIT trap had the identical hole).
- **The same bug class reappeared one level up, in signal timing — and the
  first fix for it was itself incomplete.** A review found that a signal
  landing in the gap between "the child's fate is decided" and "the wrapper
  finishes acting on it" — after a successful reap but before the function
  returns, or literally mid-`kill_ladder()` — could re-run the kill ladder
  against a pid that might already belong to someone else, or escape a nested
  `except` uncaught and abandon a half-killed child. Fixed with
  `proc.returncode is None` as an "already reaped?" check before every
  `kill_ladder()` call reached from a signal handler, plus
  `signal.pthread_sigmask` blocking the three caught signals around the
  regions that must run as one unit — left unblocked around the main ceiling
  wait on purpose, so a long wait stays Ctrl-C-interruptible. Building the
  blocking half surfaced a THIRD, self-inflicted instance: blocking *before*
  calling `spawn()` made the forked child inherit the blocked mask for its
  *entire lifetime* (`fork()` copies the caller's mask), so a later `TERM`
  reached the child, raised no exception, and did **nothing** — only the
  unmaskable `KILL` still worked. Fixed by blocking *after* `spawn()` returns.
  **A second review round then found `proc.returncode is None` is not the
  race-free check the first fix claimed.** It is a fact about CPython's
  implementation, not a design choice: `Popen._wait()` calls `os.waitpid()` —
  which reaps the child — and only several bytecode instructions later
  assigns `self.returncode`. A signal in that gap sees `None` on an
  already-reaped, potentially recycled pid. Reproduced on the *first* attempt
  of a scripted adversarial probe. This is now an **accepted residual**, not
  claimed as closed: fully closing it means bypassing `Popen.wait()`'s
  internals for a hand-rolled `os.waitpid()` call under this file's own
  atomicity control — materially larger than a guard, and not undertaken
  here. A related but more tractable gap WAS closed this round: a signal
  landing between "we decided to call `kill_ladder()`" and that branch's own
  `block_signals()` line actually running escapes the branch entirely (Python
  doesn't let a sibling `except` catch an exception raised inside another
  except clause of the same `try`) — reaching, previously, an outer catch-all
  that assumed no child existed and orphaned it. The outer `except
  Interrupted:` now checks the same `proc.returncode is None` signal and runs
  `kill_ladder()` itself when reached this way, so these entry gaps end in a
  kill rather than an orphan; only the gap INSIDE `Popen._wait()`'s own
  internals remains truly unclosable. The mask-inheritance fix has its own
  dedicated dynamic pin
  (`codex-run.test.sh` T40) precisely because that class of bug — unlike the
  returncode race — *is* fully closable and was verified to be. Same
  reasoning applies to the lock: acquisition used to set `held = True`
  *before* calling `mkdir()`, leaving a gap where a signal could strand a
  flag with nothing on disk yet, or (rarer) delete a lock a *different*
  process created in that window; `Lock.acquire()` now blocks signals around
  the syscall itself — safe, because `mkdir()` forks nothing, so the
  mask-inheritance hazard that ruled this out for `spawn()` doesn't apply
  here. Pinned statically as T41 (the gap is too fast to time externally).
- **A killed run's exit status is not information — but the wrapper does wait
  to confirm the kill, then discards what it collected.** On the stall path
  (exit 4), `kill_ladder`'s final step is `proc.wait(timeout=REAP_SECONDS)` —
  that's what distinguishes a reaped stall from a proven survivor — but the
  collected status is meaningless for a killed process and isn't reported.
  On the survivor path (exit 6, below) there is no status to collect at all:
  the process is still running.
- **SURVIVOR (exit 6): the group did not die within grace+reap after
  SIGKILL.** Proven, not guessed — `waitpid` on the wrapper's own child times
  out, and that is authoritative in a way `ps` never was. Not reported as a
  stall: exit 4's contract is "at most one blind retry," and retrying beside a
  process that could not be killed is the exact hazard this whole rewrite
  exists to close — two Codex runs on one repo, interleaved git operations, a
  transcript being appended to by something no later attempt can see. The lock
  directory is deliberately **left in place** as a tombstone so the next
  attempt refuses rather than unlinking evidence the survivor is still
  writing to; the existing collision message already ends *"If nothing is
  running, remove that directory."* — on this path that sentence is doing real
  work. Exit is via `os._exit(6)`, not a normal return: an unreaped
  `subprocess.Popen` can emit an **unprefixed** `ResourceWarning` from
  `__del__` at interpreter shutdown, which would break the stderr-prefix
  contract on the one path where it matters most.
- **codex-run bounds one attempt, not the budget.** It never retries. The
  2-attempt delegation budget stays with the prose in
  `references/delegation.md`, because budget consumption is defined by verdict
  *parseability* — codex-mark's grammar, which must not be forked into a
  second script.
- **jq required for the gate hook.** Missing jq degrades to an announced ALLOW —
  the notice rides `additionalContext` JSON on stdout (the channel the agent
  reads on a PreToolUse exit 0; stderr there is invisible to the model). Install
  jq to restore enforcement.
- **Ambient GH_REPO is invisible.** An in-command `GH_REPO=other/repo gh pr
  create` is refused (wrong-repo), but an already-`export`ed `GH_REPO` can't be
  seen by a PreToolUse hook — same ambient-var blindness as swe's protect-git.
- **Plan review has no mechanical backstop.** The eager stance's trigger line is
  the only prompt; if rules seem to stop applying mid-session (compaction), run
  `kerby reload`.
- **`accepts = ["git_change"]`** scopes the subject model to the mechanical gate;
  the plan-review/delegation prose is behavioral and not subject-scoped.

## Provenance

Ported 2026-07-07 from the maintainer's global CLAUDE.md (v3) and
`~/.claude/hooks/{codex-pr-gate.sh,codex-mark.sh}` — the complete port: nothing
codex-coupled remains global after migration. Hook hardened over the global
original: whitespace-tolerant detection, per-invocation strip-then-residual
bypass, explicit no-jq degrade. codex-mark hardened: all four `CODEX_VERDICT`
counts required (fail-closed on a partial line).

`scripts/codex-run.sh` added 2026-08-03 (0.3.0) as a pure-bash watchdog — no
upstream original. Written against a reproduced failure: a 23.7-hour attempt
(`dur=85344s`) recorded in this repo's own audit log beside 2-minute reviews,
caused by an invocation shape that could not be bounded (`… | tee log &` makes
`$!` the *tee* pid) on a platform with no `timeout(1)`.

Rewritten 2026-08-04 (0.4.0): `codex-run.sh` became a thin shim; the watchdog
logic moved to `scripts/codex-run.py`. Five bash review rounds (P1 count 5 → 3 →
2 → 3, i.e. it got *worse* mid-series) converged on one root cause — the
shell's process-inspection primitives (`ps`, `kill -0`, `kill`, `wait`) each
have a third answer besides yes/no ("the query failed"), and every guard that
folded it into one of the other two produced an unbounded wait or a
misdirected signal. `subprocess.Popen.wait(timeout=…)` has no third answer.
Parity-checked against the retired bash implementation before deletion: of 39
assertions, 37 passed identically against both; the 2 that only the bash
version failed were exactly the round-4/5 findings the rewrite fixes (a
fabricated `rc=0` on stall, and bash's own unprefixed job-control notice
leaking onto stderr).
