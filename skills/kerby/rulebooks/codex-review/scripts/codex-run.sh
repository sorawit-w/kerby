#!/bin/bash
# codex-run.sh — runs ONE headless Codex attempt under a wall-clock bound.
#
# The mechanical form of references/delegation.md § Bounded delegation's first
# three bullets (close stdin / classify / ceiling). Everything else there stays
# prose: this script bounds ONE attempt and reports why it ended. It does not
# own the 2-attempt delegation budget, does not decide whether to retry, and
# never parses a verdict — that is codex-mark.sh's grammar and must not fork.
#
# Usage:
#   codex-run.sh [--ceiling <seconds>] [--log <path>] -- <command> [args...]
#     --ceiling  whole seconds; default = 2x the observed-good median (below)
#     --log      transcript path; default $GIT_DIR/codex-review.log
#     --         everything after it is an argv vector, run verbatim
#   Then, for a review, run codex-mark.sh to parse the verdict it left behind.
#
# The command is an argv VECTOR, never a pipeline and never eval'd. That is
# load-bearing, not style: with `codex ... | tee log &` the shell's $! is TEE's
# pid, so a timeout built on it kills tee and leaves codex running forever.
# That is the failure this script exists to end.
#
# Behavior (exit codes deliberately start at 3 — 0/1/2 are codex-mark's
# PASS/DENIED/HELD and must never be read across the two scripts):
#   0 — exited on its own, status 0, inside the ceiling. Run codex-mark next.
#   1 — precondition or usage error; nothing was spawned, no attempt consumed.
#   4 — STALL: still alive at the ceiling, killed. At most one blind retry, then
#       the pr-workflow.md step-4 fallback.
#   5 — exited on its own, non-zero. Read the log, fix, retry once.
#   (3 is deliberately unused — see "no early classification" below.)
#
# The script never inspects the child — no pid-recycle witness, no post-kill
# state probe. Four review rounds produced four defects in that machinery, each
# the same shape: `ps` has a third answer besides yes and no ("the query
# failed"), and folding it into either of the other two yielded an unbounded
# wait or a signal aimed at a process we never started. See § 5.
# Accepted consequence: at the ceiling this kills the recorded pid's group
# without re-confirming it is still ours. If the OS wrapped its entire pid space
# during the run, that signal could land on an unrelated process group. Every
# version of this script has carried that risk; the versions that tried to
# detect it carried it PLUS the defects above.
#
# Fail-closed: an unusable log path, an unresolvable runtime, or no git repo
# exits 1 WITHOUT spawning anything — a half-started attempt would leave a
# zero-byte log that codex-mark would then stat as evidence.
#
# No early hang classification — the ceiling is the only bound. delegation.md
# once split "deterministic hang" from "stall" and asked for an early kill on
# the former. There is no sound signal for it here: codex prints the documented
# block-point line ("Reading additional input from stdin...") at STARTUP on every
# redirected-stdin run, that same string appears verbatim in this rulebook's own
# prose (so any transcript quoting delegation.md matches it), and macOS `ps %cpu`
# is a decayed lifetime average that cannot say "idle right now". A first draft
# of this script shipped that classifier and killed a healthy 107 KB review at
# 38s. A bound that truncates good work is worse than the unbounded wait it
# replaced. The deadlock it aimed at is anyway unreachable through this wrapper,
# which always redirects < /dev/null; a wedge just costs the full ceiling.

set -u

fail() { echo "codex-run: $1" >&2; exit 1; }

ceiling=""
log=""
while [ $# -gt 0 ]; do
  case "$1" in
    --ceiling) shift; [ $# -gt 0 ] || fail "--ceiling needs a value in whole seconds, e.g. --ceiling 900"; ceiling="$1" ;;
    --log)     shift; [ $# -gt 0 ] || fail "--log needs a path"; log="$1" ;;
    --)        shift; break ;;
    *)         fail "unknown option '$1' — usage: codex-run.sh [--ceiling <seconds>] [--log <path>] -- <command> [args...]" ;;
  esac
  shift
done

[ $# -gt 0 ] || fail "no command after '--' — pass the runtime to run, e.g. -- codex exec \"<review brief>\""
# Validate BEFORE spawning. Length-check first so a 30-digit argument never
# reaches shell arithmetic: an overflowed value makes the ceiling comparison in
# the poll loop fail as a non-integer, and that failure is inside the muffled
# brace group — the loop would spin forever with the watchdog silently off.
# 10# strips leading zeros so "00" resolves to 0 and is rejected as the
# kill-immediately value it would otherwise be.
case "$ceiling" in
  '') ;;
  *[!0-9]*) fail "--ceiling takes whole seconds — pass a positive number like --ceiling 900" ;;
  *)
    [ "${#ceiling}" -le 6 ] || fail "--ceiling out of range (max 86400 seconds) — pass a smaller number like --ceiling 900"
    ceiling=$((10#$ceiling))
    { [ "$ceiling" -ge 1 ] && [ "$ceiling" -le 86400 ]; } \
      || fail "--ceiling must be between 1 and 86400 seconds — pass a value like --ceiling 900" ;;
esac

gitdir=$(git rev-parse --git-dir 2>/dev/null) || fail "not inside a git repo — run this from the repo whose branch is under review"
case "$gitdir" in /*) ;; *) gitdir="$PWD/$gitdir" ;; esac
[ -n "$log" ] || log="$gitdir/codex-review.log"
audit="$gitdir/codex-review-audit.log"
attempts="$gitdir/codex-run-attempts.log"

command -v "$1" >/dev/null 2>&1 \
  || fail "runtime '$1' not found on PATH — resolve the Codex runtime first (references/stance.md § Preflight, or run 'kerby pr-check')"

# 1. Fresh inode, before anything else. codex-mark derives the audit dur= field
# from this file's filesystem BIRTH time, and truncation does NOT reset birth —
# so a never-marked leftover makes the next attempt's dur= span since the FIRST
# one. That is how a 23.7-hour dur= lands in an audit log full of 2-minute
# reviews. Remove it; never pre-create it here — the child's redirect below is
# what stamps the run's start.
logdir=$(dirname "$log")
[ -d "$logdir" ] && [ -w "$logdir" ] || fail "cannot write the log directory $logdir — pass --log to a writable path"

# Claim the log before touching it. Two overlapping attempts on the default path
# silently destroy each other's evidence: the second unlinks the first's inode,
# the first keeps writing to a file with no name, and the survivor holds only
# half the story — while both report success. mkdir is the portable atomic
# test-and-set (no flock on macOS).
lockdir="$log.lock"
# `held` makes unlock both idempotent and ownership-checked: releasing twice
# must not remove a lock a DIFFERENT attempt acquired in between. The EXIT trap
# is armed BEFORE mkdir so a signal landing between acquisition and arming
# cannot strand the directory.
held=0
unlock() { [ "$held" -eq 1 ] && rmdir "$lockdir" 2>/dev/null; held=0; }
trap 'unlock' EXIT
mkdir "$lockdir" 2>/dev/null \
  || fail "another attempt already owns $log (lock: $lockdir) — wait for it to finish, or pass --log to a separate path. If nothing is running, remove that directory."
held=1

rm -f "$log" || fail "cannot remove the stale log at $log — remove it by hand, then re-run"
[ -e "$log" ] && fail "$log still exists after removal (a directory?) — clear that path, then re-run"

# 2. Ceiling = 2x the observed-good median. dur= only ever appears on codex-mark
# PASS lines, so the sample set is already "observed-good". `dur=?s` contains no
# digit, so delegation.md's "ignoring ?" rule needs no special case.
# MEDIAN, not mean: this repo's own audit log carries one 85344s entry that
# drags a mean to 4.8 hours and the median not at all.
if [ -z "$ceiling" ]; then
  durs=$(grep -oE 'dur=[0-9][0-9]*s' "$audit" 2>/dev/null | grep -oE '[0-9][0-9]*' | sort -n)
  n=$(printf '%s' "$durs" | grep -c '[0-9]')
  if [ "$n" -ge 3 ]; then
    # Upper median (element n/2+1): no averaging on the even case, and erring
    # generous is the safe direction for a threshold that kills things.
    ceiling=$(( $(printf '%s\n' "$durs" | sed -n "$((n / 2 + 1))p") * 2 ))
  else
    ceiling=900   # fewer than 3 samples is not a median — delegation.md's 15 min
  fi
  # Floor: one 20s fluke would set a 40s ceiling that kills every real review.
  # Cap: the median survives ONE outlier, but a log that accumulates several
  # would compute a 47-hour "ceiling" and the watchdog would stop being one.
  # Both bracket the 900s cold-start default.
  [ "$ceiling" -lt 300 ]  && ceiling=300
  [ "$ceiling" -gt 3600 ] && ceiling=3600
fi

# 3. Spawn in its own process group. codex spawns children; killing only the top
# pid orphans them. macOS has no setsid(1), so `set -m` is the portable way to
# get a new pgroup (verified: pgid == child pid). Monitor mode goes straight
# back off — it was needed only for the fork.
#
# The whole lifecycle runs inside a stderr-muffled brace group. NOT a subshell:
# class/rc must survive it. The shell writes its own job-control notice
# ("Terminated: 15") to stderr when it reaps a killed job, which would break
# this script's "every stderr line starts with codex-run:" contract. Rule: this
# block emits no messages of its own — all reporting happens after it.
child=0
# One kill ladder, used by both the ceiling and the signal trap. TERM first
# (the runtime may flush a partial transcript), KILL after a bounded grace.
# `kill -- -pid` needs the pgroup from `set -m`; a shell without job control
# leaves the child in OUR group, where -pid would kill us too — hence the
# bare-pid fallback.
kill_group() {
  [ "$child" -gt 0 ] || return 0
  kill -TERM -"$child" 2>/dev/null || kill -TERM "$child" 2>/dev/null
  # Grace is owed to the GROUP, not just its leader: a leader that exits first
  # while a descendant is still flushing must not cut the descendant's grace
  # short. `kill -0 -pid` succeeds while any member survives.
  i=0
  while [ "$i" -lt 5 ] \
    && { kill -0 -"$child" 2>/dev/null || kill -0 "$child" 2>/dev/null; }; do
    sleep 1; i=$((i + 1))
  done
  kill -KILL -"$child" 2>/dev/null || kill -KILL "$child" 2>/dev/null
}
# On our own death, take the child with us — through the SAME ladder. A single
# TERM followed by an immediate exit leaves a TERM-ignoring runtime orphaned,
# which is the exact outcome this wrapper exists to prevent.
# No unlock() here: `exit` runs the EXIT trap, which releases it. Calling it in
# both places opens a window where another attempt acquires the lock between the
# two calls and the second release deletes THEIRS.
trap 'kill_group; exit 130' HUP INT TERM
started=$(date +%s)
class=ok
rc=0
# Poll every second regardless of the ceiling. A coarser tick would only save
# noise-level CPU while making every fast run pay up to a full tick of dead
# latency before the wrapper notices the child already exited.
tick=1

{
  set -m
  # </dev/null is the whole point: an open empty stdin in a background shell
  # deadlocks silently on the block-point below. $! is the runtime's own pid
  # precisely because this is a vector, not a pipeline.
  "$@" >"$log" 2>&1 </dev/null &
  child=$!
  set +m

  # 4. Wait it out. Two exits only: the child finishes, or the ceiling fires.
  # A quiet transcript is NOT evidence of anything — a model thinking looks
  # exactly like a model wedged (see the header). Do not add a cleverer signal
  # here without one that can tell those two apart.
  while :; do
    kill -0 "$child" 2>/dev/null || break                         # exited on its own
    [ $(( $(date +%s) - started )) -ge "$ceiling" ] && { class=stall; break; }
    sleep "$tick"
  done

  # 5. Two paths, and NEITHER inspects the child.
  #
  # Earlier builds asked `ps` whether the pid had been recycled, then whether the
  # post-SIGKILL state was reapable. Four review rounds produced four defects in
  # that machinery, all the same shape: every reading of `ps` has a third answer
  # besides yes and no — "the query failed" — and every time that third answer
  # was folded into one of the other two, the result was either an unbounded
  # wait or a signal aimed at a process we did not start. Guard number five was
  # not going to be the one that held. The machinery is gone instead.
  #
  # What is left is true without any oracle:
  #   - loop exited because kill -0 failed  -> the child is gone -> wait() has
  #     its status in bash's job table and returns at once.
  #   - loop exited because the ceiling hit -> kill the group and LEAVE. A killed
  #     process's exit status is not information: we already know how it ended.
  #     Not waiting is what makes the wall-clock bound unconditional — there is
  #     no state a wedged process can be in that delays this script.
  if [ "$class" = stall ]; then
    kill_group
  else
    wait "$child"; rc=$?
  fi
} 2>/dev/null

elapsed=$(( $(date +%s) - started ))

# 6. Report. The killed log is deliberately LEFT IN PLACE: a run that emitted a
# CODEX_VERDICT before wedging did produce a verdict — per delegation.md it
# consumed no attempt, and codex-mark must still get to see it. Do not "tidy up"
# here. Killed and failed attempts also get an attempts-log line, kept OUT of
# codex-review-audit.log so these entries can never pollute the dur= median that
# sets the ceiling above; without it, a hang that never marks leaves no trace at
# all (the 85344s entry is only visible because it happened to end in PASS).
note() {
  printf '%s %s class=%s elapsed=%ss ceiling=%ss rc=%s\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$(git rev-parse --short HEAD 2>/dev/null || echo '-')" \
    "$1" "$elapsed" "$ceiling" "$rc" >> "$attempts"
}

case "$class" in
  stall)
    note stall
    echo "codex-run: STALL — still running at the ${ceiling}s ceiling, killed (ceiling ${ceiling}s). Transcript kept at $log. At most one blind retry, then take the step-4 fallback in references/pr-workflow.md." >&2
    exit 4 ;;
esac

if [ "$rc" -ne 0 ]; then
  note exit-"$rc"
  echo "codex-run: runtime exited $rc after ${elapsed}s (ceiling ${ceiling}s). Read $log for the cause, fix it, then retry once." >&2
  exit 5
fi

echo "codex-run: OK — ${elapsed}s (ceiling ${ceiling}s). Transcript at $log. NEXT: run scripts/codex-mark.sh now — it is the only thing that parses the verdict AND advances the 3-round cap. Reading the verdict by eye instead leaves the counter at zero and the cap never fires."
exit 0
