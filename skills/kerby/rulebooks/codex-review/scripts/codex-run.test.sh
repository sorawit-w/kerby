#!/bin/bash
# Self-test for codex-run.sh (a thin shim) / codex-run.py (the watchdog): usage
# and precondition errors spawn nothing; a clean child exits 0; a crashing
# child exits 5; stdin is closed (the documented deadlock); a stall is killed
# at the ceiling (exit 4) and takes its whole process group with it; a
# quiet-but-healthy run is NOT killed early; the review log gets a FRESH inode
# per attempt (the birth-time contract codex-mark's dur= depends on); the
# ceiling is 2x the observed-good median, ignoring dur=?, clamped to
# [300,3600] with a 900s cold-start default; killed runs keep their log and
# leave an attempts-log trace; stderr stays prefixed on every call.
#
# No real Codex, no network: every child is a generated stub under $WORK.
#
# codex-run.py rewrote the bash predecessor after five review rounds found
# seven defects, all one shape: ps/kill -0/kill/wait each have a third answer
# ("the query failed") that every guard misfolded into an unbounded wait or a
# misdirected signal. proc.wait(timeout=) has no third answer, so this suite
# tests both the BEHAVIOUR (dynamic pins, same as the bash predecessor's) and
# the STRUCTURE (new static pins asserting the oracle machinery cannot exist
# in the file at all — see the "static analysis" section).
#
# NOT covered by assertion, and deliberately so — no env-var backdoor was
# added to force them, because a test-only hole in a wrapper whose job is
# bounding an untrusted runtime is a worse trade than an untested branch:
#   - exit 6 (SURVIVOR) needs a process that ignores SIGKILL — genuine
#     uninterruptible I/O, which cannot be created portably from a test.
#   - the EPERM-on-kill case needs a setuid credential change.
# Both are covered by review, not by this suite.
#
# Run from anywhere: bash codex-run.test.sh
# Exit 0 = all assertions pass; non-zero = a failure.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
RUN="$SCRIPT_DIR/codex-run.sh"
PY="$SCRIPT_DIR/codex-run.py"

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"
git init -q
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
GITDIR=$(git rev-parse --git-dir)
case "$GITDIR" in /*) ;; *) GITDIR="$WORK/$GITDIR" ;; esac
LOG="$GITDIR/codex-review.log"
AUDIT="$GITDIR/codex-review-audit.log"
ATTEMPTS="$GITDIR/codex-run-attempts.log"

# Every synchronous call goes through the shim ($RUN, unchanged filename) and
# is checked for the stderr-prefix contract inline — a stray unprefixed line
# (e.g. an uncaught traceback) fails immediately, at every call site, not just
# the one place the bash predecessor's job-control-notice bug happened to hit.
run() {
  bash "$RUN" "$@" >"$WORK/out.txt" 2>"$WORK/err.txt"; RC=$?
  local bad
  bad=$(grep -vc '^codex-run: ' "$WORK/err.txt" 2>/dev/null)
  [[ "${bad:-0}" -eq 0 ]] \
    || fail "run(): unprefixed stderr from '$*': $(grep -v '^codex-run: ' "$WORK/err.txt" | head -2)"
}
now() { date +%s; }
# Same GNU-then-BSD idiom the scripts use, so the tests observe exactly what
# codex-mark will compute.
mtime_of() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }
birth_of() { stat -c %W "$1" 2>/dev/null || stat -f %B "$1" 2>/dev/null; }
# The success/report line carries "(ceiling Ns)" — that string is how these
# tests observe the median computation without the script needing a dry-run flag.
ceiling_seen() { sed -n 's/.*(ceiling \([0-9][0-9]*\)s).*/\1/p' "$WORK/out.txt" "$WORK/err.txt" | tail -n1; }
seed_audit() { : > "$AUDIT"; for d in "$@"; do
  printf '2026-01-01T00:00:00Z deadbeef rounds=1 P0=0 P1=0 P2=0 P3=0 dur=%ss\n' "$d" >> "$AUDIT"
done; }

# --- Stubs. Quoted heredocs: nothing expands here, paths arrive as $1. ---
cat > "$WORK/fast.sh" <<'EOF'
#!/bin/bash
echo "review output..."
echo "CODEX_VERDICT: P0=0 P1=0 P2=0 P3=0"
EOF
cat > "$WORK/crash.sh" <<'EOF'
#!/bin/bash
echo "codex: boom" >&2
exit 9
EOF
cat > "$WORK/forever.sh" <<'EOF'
#!/bin/bash
sleep 300 &
echo $! > "$1"
echo "working..."
sleep 300
EOF
# Prints the old "block-point" line at startup and then works normally, quietly,
# for a while — exactly what real codex does on every redirected-stdin run.
cat > "$WORK/blocker.sh" <<'EOF'
#!/bin/bash
echo "Reading additional input from stdin..."
sleep 8
echo "...still working, and this must not have been killed"
EOF
cat > "$WORK/reader.sh" <<'EOF'
#!/bin/bash
cat > /dev/null
echo "stdin-eof"
EOF
# Ignores TERM. A single un-escalated TERM leaves this alive forever.
cat > "$WORK/stubborn.sh" <<'EOF'
#!/bin/bash
trap '' TERM
echo $$ > "$1"
echo "ignoring TERM"
sleep 300
EOF
chmod +x "$WORK"/*.sh

# --- Preconditions: nothing is spawned, no log is created (exit 1) ---

# 1. No `--` / no command.
rm -f "$LOG"
run
[[ "$RC" -eq 1 && ! -f "$LOG" ]] && pass "no command fails closed" || fail "no command: rc=$RC"

# 2. Unknown option.
run --nope -- "$WORK/fast.sh"
[[ "$RC" -eq 1 && ! -f "$LOG" ]] && pass "unknown option fails closed" || fail "unknown option: rc=$RC"

# 2b. Non-numeric ceiling.
run --ceiling abc -- "$WORK/fast.sh"
[[ "$RC" -eq 1 ]] && pass "non-numeric ceiling rejected" || fail "ceiling abc: rc=$RC"

# 3. Command not on PATH — must be caught BEFORE the log is created, or a
# typo'd runtime leaves a zero-byte log that codex-mark would then stat.
run -- "$WORK/does-not-exist.sh"
[[ "$RC" -eq 1 && ! -f "$LOG" ]] && pass "missing runtime fails closed, no log" || fail "missing runtime: rc=$RC log=$([ -f "$LOG" ] && echo yes || echo no)"

# T30 — -h/--help must be unknown options, not a help screen. argparse would
# install both silently and exit 2 (a code codex-mark owns) with an unprefixed
# usage block; this is the mechanical guard against a future "improvement"
# taking that shape.
run -h -- "$WORK/fast.sh"
[[ "$RC" -eq 1 ]] && grep -q "unknown option" "$WORK/err.txt" \
  && pass "-h is an unknown option, not help" || fail "-h: rc=$RC"
run --help -- "$WORK/fast.sh"
[[ "$RC" -eq 1 ]] && grep -q "unknown option" "$WORK/err.txt" \
  && pass "--help is an unknown option, not help" || fail "--help: rc=$RC"

# T36 — `--ceiling --` : the lone '--' is consumed AS THE CEILING VALUE (last
# wins, whatever token follows the flag), leaving no terminator for a command
# vector, so the very next token is read as an option and rejected. Same
# structural failure in both the bash predecessor and this port — verified by
# hand-tracing both parse loops token-by-token; the point of this pin is that
# a future edit to either can't silently swap which failure fires without
# changing rc.
run --ceiling -- "$WORK/fast.sh"
[[ "$RC" -eq 1 ]] && pass "--ceiling consumes '--' as its value, next token then rejected" || fail "--ceiling --: rc=$RC"

# --- Normal exits ---

# 4. Clean child -> exit 0, output captured.
t0=$(now); run -- "$WORK/fast.sh"; t1=$(now)
[[ "$RC" -eq 0 && $((t1 - t0)) -le 3 ]] && grep -q "CODEX_VERDICT" "$LOG" \
  && pass "clean child exits 0, log captured" || fail "clean child: rc=$RC elapsed=$((t1 - t0))"

# 5. Child exits non-zero -> exit 5 (NOT conflated with a timeout).
run -- "$WORK/crash.sh"
[[ "$RC" -eq 5 ]] && grep -q "$LOG" "$WORK/err.txt" \
  && pass "non-zero child exits 5, stderr names the log" || fail "crash: rc=$RC err=$(cat "$WORK/err.txt")"

# 6. REGRESSION PIN — stdin must be closed. reader.sh blocks on `cat` forever
# unless the child gets </dev/null. Without the redirect this runs to the
# ceiling and returns 4; the whole 23.7-hour class of failure starts here.
t0=$(now); run --ceiling 10 -- "$WORK/reader.sh"; t1=$(now)
[[ "$RC" -eq 0 && $((t1 - t0)) -le 3 ]] && grep -q "stdin-eof" "$LOG" \
  && pass "stdin closed (no deadlock)" || fail "stdin deadlock: rc=$RC elapsed=$((t1 - t0))"

# --- Kills ---

# 7. Stall -> killed at the ceiling, exit 4.
t0=$(now); run --ceiling 2 -- "$WORK/forever.sh" "$WORK/gchild"; t1=$(now)
[[ "$RC" -eq 4 && $((t1 - t0)) -lt 15 ]] \
  && pass "stall killed at ceiling (exit 4, $((t1 - t0))s)" || fail "stall: rc=$RC elapsed=$((t1 - t0))"

# 8. REGRESSION PIN — the whole process group dies, not just the top pid.
# forever.sh spawns a grandchild; killing only $child orphans it forever.
sleep 1
GC=$(cat "$WORK/gchild" 2>/dev/null || echo 0)
[[ "$GC" -gt 0 ]] && ! kill -0 "$GC" 2>/dev/null \
  && pass "grandchild reaped with the group" || fail "orphaned grandchild pid=$GC"

# 18. A killed run KEEPS its log — a run that emitted a verdict before wedging
# did produce one, and codex-mark must still get to parse it.
[[ -s "$LOG" ]] && pass "killed run keeps its log" || fail "killed run lost its log"

# 19. stderr hygiene, explicit re-check of the SAME call run()'s inline check
# already covered — belt and suspenders, since this is the exact path (a
# process-group kill) the bash predecessor's job-control notice used to leak on.
BAD=$(grep -v '^codex-run: ' "$WORK/err.txt" | wc -l | tr -d ' ')
[[ "$BAD" -eq 0 ]] && pass "stderr stays prefixed through a kill" || fail "leaked $BAD stderr line(s): $(grep -v '^codex-run: ' "$WORK/err.txt" | head -2)"

# 7b. The killed attempt left a trace — today a hang that never marks is
# invisible, because only codex-mark PASSes reach the audit log.
[[ -s "$ATTEMPTS" ]] && grep -q "stall" "$ATTEMPTS" \
  && pass "killed attempt logged to codex-run-attempts.log" || fail "no attempts-log entry"

# T31 — the stall's attempts-log line must show NO collected status (rc=-),
# never a fabricated rc=0. A stall is killed without waiting on the ceiling
# path itself (the ladder's own reap is what collects a status, and THAT
# status belongs to the kill, not to "how the runtime exited" — codex-run.py
# never conflates the two, and rc stays None -> '-' the whole way through the
# stall branch).
grep -q 'class=stall.*rc=-$' "$ATTEMPTS" \
  && pass "stall logs rc=- (no fabricated status)" || fail "stall rc field: $(grep 'class=stall' "$ATTEMPTS" | tail -1)"

# 9. REGRESSION PIN — a healthy run that prints the old "block-point" line at
# startup and then goes quiet must RUN TO COMPLETION. Real codex prints that
# line on every redirected-stdin run, and the string also appears verbatim in
# this rulebook's own delegation.md, so any transcript quoting it matches too.
# The first draft of this script treated line+silence as a hang and killed a
# healthy 107 KB review at 38s. A bound that truncates good work is worse than
# the unbounded wait it replaced.
t0=$(now); run --ceiling 60 -- "$WORK/blocker.sh"; t1=$(now)
[[ "$RC" -eq 0 ]] && grep -q "must not have been killed" "$LOG" \
  && pass "quiet-after-block-point run survives ($((t1 - t0))s)" || fail "false-positive kill: rc=$RC elapsed=$((t1 - t0))"

# --- The birth-time contract ---

# 10. REGRESSION PIN — fresh inode per attempt. codex-mark derives dur= from
# the log's filesystem BIRTH time, and truncation does NOT reset it. Replace
# the unlink with a truncating open and this asserts >= 3; pre-create the log
# and birth predates the run. Either way a stale leftover is how dur=85344s
# gets recorded. (codex-run.py uses O_EXCL, a kernel guarantee rather than a
# two-step check — see spawn()'s docstring.)
printf 'leftover from a never-marked attempt\n' > "$LOG"
sleep 3
run -- "$WORK/fast.sh"
b=$(birth_of "$LOG"); m=$(mtime_of "$LOG")
if [[ -z "$b" || "$b" == "0" ]]; then
  pass "birth time unavailable on this fs (dur would be '?')"
else
  [[ $((m - b)) -le 1 ]] && pass "fresh inode: mtime-birth=$((m - b))s" || fail "stale inode: mtime-birth=$((m - b))s"
fi
grep -q "leftover" "$LOG" && fail "stale log content survived" || pass "stale log removed"

# --- Ceiling computation ---

# 11. REGRESSION PIN — median ignores dur=?, and it is a MEDIAN. This repo's
# own audit log carries one 85344s entry: the median shrugs, a mean gives ~43k.
seed_audit '?' 200 300 400 85344
run -- "$WORK/fast.sh"
[[ "$(ceiling_seen)" == "800" ]] && pass "ceiling = 2x upper median, '?' ignored (800s)" || fail "median: ceiling=$(ceiling_seen) want 800"

# 12. Outlier cap — several hangs must not compute a 47-hour "ceiling" that
# disables the watchdog entirely.
seed_audit 85344 85344 85344
run -- "$WORK/fast.sh"
[[ "$(ceiling_seen)" == "3600" ]] && pass "ceiling capped at 3600s" || fail "cap: ceiling=$(ceiling_seen)"

# 13. Floor — one fast fluke must not set a ceiling that kills real reviews.
seed_audit 20 20 20
run -- "$WORK/fast.sh"
[[ "$(ceiling_seen)" == "300" ]] && pass "ceiling floored at 300s" || fail "floor: ceiling=$(ceiling_seen)"

# 14. Cold start: fewer than 3 numeric samples is not a median. Both the
# all-'?' log and no log at all fall back to delegation.md's 15 min.
seed_audit '?' '?' '?'
run -- "$WORK/fast.sh"
[[ "$(ceiling_seen)" == "900" ]] && pass "all-'?' audit -> 900s default" || fail "all-?: ceiling=$(ceiling_seen)"
rm -f "$AUDIT"
run -- "$WORK/fast.sh"
[[ "$(ceiling_seen)" == "900" ]] && pass "absent audit -> 900s default" || fail "absent audit: ceiling=$(ceiling_seen)"

# 15. Explicit override beats the computed baseline.
seed_audit 200 300 400
run --ceiling 7 -- "$WORK/fast.sh"
[[ "$(ceiling_seen)" == "7" ]] && pass "--ceiling overrides the median" || fail "override: ceiling=$(ceiling_seen)"

# --- Log routing ---

# 16. --log keeps rescue transcripts out of codex-review.log, where codex-mark
# would otherwise parse a rescue as a review verdict.
rm -f "$LOG"
run --log "$WORK/alt.log" -- "$WORK/fast.sh"
[[ "$RC" -eq 0 && -s "$WORK/alt.log" && ! -f "$LOG" ]] \
  && pass "--log routes away from codex-review.log" || fail "--log: rc=$RC review-log=$([ -f "$LOG" ] && echo created || echo absent)"

# 17. Outside a git repo there is no $GIT_DIR to default the log into.
NONREPO=$(mktemp -d)
( cd "$NONREPO" && bash "$RUN" -- "$WORK/fast.sh" >/dev/null 2>&1 ); RC=$?
rmdir "$NONREPO"
[[ "$RC" -eq 1 ]] && pass "not a git repo fails closed" || fail "non-repo: rc=$RC"

# --- Codex-review round 1 findings (P1/P2), pinned ---

# 21. Ceiling values that would silently DISABLE the watchdog. "00" is all
# digits and is not the string "0", so a naive guard lets it through and it
# means kill-immediately. An oversized value must be rejected by range, not
# silently wrap.
for BAD in 00 0 999999999999999999999999 -5 1.5; do
  run --ceiling "$BAD" -- "$WORK/fast.sh"
  [[ "$RC" -eq 1 ]] || fail "--ceiling $BAD accepted (rc=$RC)"
done
run --ceiling 86400 -- "$WORK/fast.sh"
[[ "$RC" -eq 0 ]] && pass "invalid ceilings rejected, in-range accepted" || fail "ceiling 86400 rejected: rc=$RC"

# 22. REGRESSION PIN — the signal handler must run the SAME kill ladder as the
# ceiling path. An earlier bash build fired one un-escalated TERM at the child
# and exited immediately, orphaning any runtime that ignores TERM — the
# precise outcome this wrapper exists to prevent. In codex-run.py there is
# literally one kill_ladder() function and one call site per path (ceiling,
# signal), which is what this pin has always been asserting.
rm -f "$LOG"
rm -f "$WORK/spid"
bash "$RUN" --ceiling 120 -- "$WORK/stubborn.sh" "$WORK/spid" >"$WORK/out.txt" 2>"$WORK/err.txt" &
WPID=$!
# The stub reports its own pid. pgrep -f would also match the WRAPPER's command
# line (it contains the stub path), and picking that pid makes this pin measure
# a process that always exits — i.e. pass no matter what the trap does.
until [[ -s "$WORK/spid" ]] || ! kill -0 "$WPID" 2>/dev/null; do sleep 1; done
CPID=$(cat "$WORK/spid" 2>/dev/null)
kill -TERM "$WPID" 2>/dev/null
wait "$WPID" 2>/dev/null; TRC=$?
sleep 1
if [[ -z "$CPID" ]]; then
  # Never let a missed pgrep read as success — that would make this pin vacuous
  # exactly when the child it is supposed to find is the thing at issue.
  fail "trap pin inconclusive: never observed the child pid"
elif kill -0 "$CPID" 2>/dev/null; then
  fail "trap orphaned the child (pid=$CPID still alive)"; kill -KILL "$CPID" 2>/dev/null
else
  pass "signal handler escalates to KILL, no orphan (wrapper rc=$TRC)"
fi

# 23. REGRESSION PIN — concurrent attempts on the shared default log used to
# destroy each other's evidence: the second unlinks the first's inode, the
# first keeps writing to an unnamed file, and BOTH reported success.
rm -f "$LOG"; rmdir "$LOG.lock" 2>/dev/null
bash "$RUN" --ceiling 30 -- "$WORK/forever.sh" "$WORK/gchild2" >/dev/null 2>&1 &
LPID=$!
until [[ -d "$LOG.lock" ]] || ! kill -0 "$LPID" 2>/dev/null; do sleep 1; done
run -- "$WORK/fast.sh"
[[ "$RC" -eq 1 ]] && grep -q "another attempt already owns" "$WORK/err.txt" \
  && pass "concurrent attempt refused (log ownership preserved)" || fail "concurrent: rc=$RC err=$(head -1 "$WORK/err.txt")"
kill -TERM "$LPID" 2>/dev/null; wait "$LPID" 2>/dev/null
rmdir "$LOG.lock" 2>/dev/null

# 24. The lock is released on every exit path, or the next attempt is wedged.
rm -f "$LOG"
run -- "$WORK/crash.sh"
[[ ! -d "$LOG.lock" ]] && pass "lock released after a failing run" || fail "lock leaked after failure"

# 25. Median needs >= 3 samples: one and two are not a median, and an odd
# non-uniform set must pick the true upper-median element.
seed_audit 200
run -- "$WORK/fast.sh"; ONE=$(ceiling_seen)
seed_audit 200 400
run -- "$WORK/fast.sh"; TWO=$(ceiling_seen)
seed_audit 100 900 200 800 250
run -- "$WORK/fast.sh"; ODD=$(ceiling_seen)
[[ "$ONE" == "900" && "$TWO" == "900" && "$ODD" == "500" ]] \
  && pass "1/2 samples -> default; odd non-uniform picks upper median (${ODD}s)" \
  || fail "sample counts: one=$ONE two=$TWO odd=$ODD (want 900/900/500)"

# --- Codex-review round 2 findings, pinned ---

# 26. Widened shadow — ps, pgrep, kill, and killall on PATH all fail. The
# watchdog must still hit the ceiling: codex-run.py asks the OS nothing about
# the child except through waitpid; it signals via os.killpg (a direct
# syscall from inside the process), never by shelling out to an external
# binary. Shadowing these must therefore have ZERO effect — this is a live
# behavioural guard against a future contributor reintroducing any shell-out
# for process inspection (the T33 static pin below is the structural half of
# the same guarantee).
mkdir -p "$WORK/fakebin"
for BIN in ps pgrep kill killall; do
  printf '#!/bin/bash\nexit 1\n' > "$WORK/fakebin/$BIN"; chmod +x "$WORK/fakebin/$BIN"
done
rm -f "$LOG"; rmdir "$LOG.lock" 2>/dev/null
t0=$(now)
PATH="$WORK/fakebin:$PATH" bash "$RUN" --ceiling 2 -- "$WORK/forever.sh" "$WORK/gchild3" \
  >"$WORK/out.txt" 2>"$WORK/err.txt" &
PPID_W=$!
until ! kill -0 "$PPID_W" 2>/dev/null || [[ $(( $(now) - t0 )) -gt 25 ]]; do sleep 1; done
if kill -0 "$PPID_W" 2>/dev/null; then
  fail "shadowed process tools caused an unbounded wait (wrapper still alive after $(( $(now) - t0 ))s)"
  kill -KILL "$PPID_W" 2>/dev/null
else
  wait "$PPID_W" 2>/dev/null; PRC=$?
  [[ "$PRC" -eq 4 ]] && pass "no dependence on ps/pgrep/kill/killall (exit 4)" || fail "shadowed tools: rc=$PRC"
fi
rm -rf "$WORK/fakebin"

# 27. REGRESSION PIN — the lock is released exactly ONCE on the signal path.
# unlock() used to run in both the signal trap and the EXIT trap; another
# attempt acquiring in between would have its lock deleted by the second call.
# codex-run.py has ONE release() call site (the try/finally in main()); the
# signal handler raises and lets that finally do the releasing.
rm -f "$LOG"; rmdir "$LOG.lock" 2>/dev/null
bash "$RUN" --ceiling 60 -- "$WORK/forever.sh" "$WORK/gchild4" >/dev/null 2>&1 &
SPID=$!
until [[ -d "$LOG.lock" ]] || ! kill -0 "$SPID" 2>/dev/null; do sleep 1; done
kill -TERM "$SPID" 2>/dev/null; wait "$SPID" 2>/dev/null
sleep 1
NOLOCK=0; [[ ! -d "$LOG.lock" ]] && NOLOCK=1
run -- "$WORK/fast.sh"
[[ "$NOLOCK" -eq 1 && "$RC" -eq 0 ]] \
  && pass "signal path releases the lock once; next attempt acquires" || fail "lock after signal: present=$((1-NOLOCK)) next-rc=$RC"

# --- The wall-clock bound, end to end ---

# 29. A TERM-ignoring child must not push the wrapper past ceiling + grace +
# reap. Expressed via the SAME constants codex-run.py uses (GRACE_SECONDS=5,
# REAP_SECONDS=10) rather than a bare magic number, so the assertion tracks
# the documented bound instead of a literal that happens to hold today.
GRACE_SECONDS=5; REAP_SECONDS=10; CEILING=3
BOUND=$((CEILING + GRACE_SECONDS + REAP_SECONDS + 2))   # +2s scheduling slack
rm -f "$LOG" "$WORK/spid2"; rmdir "$LOG.lock" 2>/dev/null
t0=$(now); run --ceiling "$CEILING" -- "$WORK/stubborn.sh" "$WORK/spid2"; t1=$(now)
[[ "$RC" -eq 4 && $((t1 - t0)) -lt "$BOUND" ]] \
  && pass "TERM-ignoring child bounded at ceiling+grace+reap ($((t1 - t0))s < ${BOUND}s)" \
  || fail "ladder unbounded: rc=$RC elapsed=$((t1 - t0))s bound=${BOUND}s"

# --- Codex-review round 6 findings (the python rewrite's own first live
# review — one P0, five P1, three P2, one P3), pinned ---

# T37 — REGRESSION PIN. A signal arriving MID-kill_ladder() (during the 5s
# TERM->KILL grace) used to raise Interrupted from inside the caller's
# `except subprocess.TimeoutExpired:` clause, where the sibling
# `except Interrupted:` could NOT catch it (it belongs to the same try, not a
# nesting one) — it escaped uncaught, leaving the child half-killed and the
# lock released. Reproduced by the reviewer: wrapper returned 130, the
# TERM-ignoring child stayed alive, lock absent. block_signals() during
# kill_ladder() makes this window zero-width: the external TERM below is sent
# ~2s after the ceiling fires, landing inside the 5s grace sleep with margin
# on both sides, so timing precision isn't load-bearing for the test.
GRACE_SECONDS=5; CEILING=2
rm -f "$LOG" "$WORK/spid3"; rmdir "$LOG.lock" 2>/dev/null
bash "$RUN" --ceiling "$CEILING" -- "$WORK/stubborn.sh" "$WORK/spid3" \
  >"$WORK/out.txt" 2>"$WORK/err.txt" &
MPID=$!
until [[ -s "$WORK/spid3" ]] || ! kill -0 "$MPID" 2>/dev/null; do sleep 1; done
CPID3=$(cat "$WORK/spid3" 2>/dev/null)
sleep "$((CEILING + 2))"          # land inside the grace window, not at its edges
kill -TERM "$MPID" 2>/dev/null
wait "$MPID" 2>/dev/null
sleep 1
if [[ -z "$CPID3" ]]; then
  fail "mid-ladder pin inconclusive: never observed the child pid"
elif kill -0 "$CPID3" 2>/dev/null; then
  fail "signal mid-kill_ladder orphaned the child (pid=$CPID3 still alive)"
  kill -KILL "$CPID3" 2>/dev/null
elif [[ -d "$LOG.lock" ]]; then
  fail "signal mid-kill_ladder left the lock stranded"
  rmdir "$LOG.lock" 2>/dev/null
else
  pass "signal mid-kill_ladder still completes the ladder, lock released"
fi

# T40 — REGRESSION PIN, found and fixed while building the T38 pin above, not
# by the review itself: block_signals() called BEFORE spawn() means fork()
# copies the CALLER's mask into the child, so the spawned process (and
# everything it backgrounds) would inherit HUP/INT/TERM as blocked for its
# ENTIRE lifetime — only the unmaskable SIGKILL could ever reach it. Verified
# directly against a bare Popen(): os.killpg(..., SIGTERM) reached the child,
# raised no exception, and had NO EFFECT — the child never saw the signal it
# had just received. That would have silently defeated "TERM first, so the
# runtime can flush a partial transcript" everywhere, not just here.
#
# kill_ladder() sleeps the FULL grace period UNCONDITIONALLY regardless of
# whether TERM already worked (deliberate — grace is owed to the group, see
# kill_ladder's own docstring), so the wrapper's total elapsed time can't
# distinguish "TERM worked" from "TERM was swallowed": both take ~5s by
# design. The only way to observe the difference is to watch the CHILD's own
# liveness from OUTSIDE the wrapper, mid-grace, before the wrapper's fixed
# sleep even completes.
GRACE_SECONDS=5; CEILING=2
rm -f "$LOG" "$WORK/gchild6"; rmdir "$LOG.lock" 2>/dev/null
bash "$RUN" --ceiling "$CEILING" -- "$WORK/forever.sh" "$WORK/gchild6" >/dev/null 2>&1 &
TPID=$!
until [[ -s "$WORK/gchild6" ]] || ! kill -0 "$TPID" 2>/dev/null; do sleep 1; done
TGC=$(cat "$WORK/gchild6" 2>/dev/null || echo 0)
# Poll shortly after the ceiling fires but well inside the grace window (the
# wrapper is still asleep in kill_ladder's fixed sleep at this point).
sleep "$((CEILING + 2))"
if [[ "$TGC" -eq 0 ]]; then
  fail "T40 inconclusive: never observed the descendant pid"
elif kill -0 "$TGC" 2>/dev/null; then
  fail "descendant still alive mid-grace — TERM had no effect (only KILL will finish it)"
else
  pass "TERM alone kills a normal child during the grace window (not blocked-then-KILLed)"
fi
kill -KILL "$TGC" 2>/dev/null
wait "$TPID" 2>/dev/null

# T38 — REGRESSION PIN. `proc.wait()` on the clean-exit path only proves the
# LEADER was reaped, not the whole process group — waitpid cannot reap a
# grandchild (it isn't the wrapper's child, only a group member). Reproduced
# by the reviewer: leader exits 0, a backgrounded descendant is still alive,
# and the "ok" path signalled nothing at all. leader-exits.sh backgrounds a
# long sleep then exits immediately; nudge_stragglers' best-effort TERM after
# a clean reap should reach it even though nothing waits for the result.
cat > "$WORK/leader-exits.sh" <<'EOF'
#!/bin/bash
sleep 300 &
echo $! > "$1"
exit 0
EOF
chmod +x "$WORK/leader-exits.sh"
rm -f "$WORK/lgchild"
run -- "$WORK/leader-exits.sh" "$WORK/lgchild"
LGC=$(cat "$WORK/lgchild" 2>/dev/null || echo 0)
sleep 1
if [[ "$RC" -ne 0 ]]; then
  fail "leader-exits stub: rc=$RC (want 0)"
elif [[ "$LGC" -eq 0 ]]; then
  fail "descendant pin inconclusive: never observed its pid"
elif kill -0 "$LGC" 2>/dev/null; then
  fail "descendant survived a clean leader exit, never signalled (pid=$LGC)"
  kill -KILL "$LGC" 2>/dev/null
else
  pass "nudge_stragglers reaches a descendant left running after a clean exit"
fi

# T39 — a signal arriving AFTER a clean reap but before the report finishes
# must not discard the real result. Timed generously: fast.sh exits in well
# under a second; the external TERM lands 2s later, comfortably after
# block_signals() has already re-engaged on the success path.
rm -f "$LOG"; rmdir "$LOG.lock" 2>/dev/null
bash "$RUN" -- "$WORK/fast.sh" >"$WORK/out.txt" 2>"$WORK/err.txt" &
NPID=$!
sleep 2
kill -TERM "$NPID" 2>/dev/null
wait "$NPID" 2>/dev/null; NRC=$?
# Either outcome is structurally sound (a signal this late almost certainly
# lands after the process has already exited on its own) — what would FAIL
# this pin is a hang, a crash, or a stranded lock, none of which involve any
# process-kill call at all on this path.
[[ -d "$LOG.lock" ]] && fail "post-reap signal left the lock stranded" \
  || pass "post-reap signal handled cleanly (rc=$NRC), no stranded lock"

# 20. No stub survived the suite.
sleep 1
LEFT=$(pgrep -f "$WORK/(forever|blocker|reader|stubborn|leader-exits)\.sh" 2>/dev/null | wc -l | tr -d ' ')
[[ "$LEFT" -eq 0 ]] && pass "no orphaned stub processes" || fail "$LEFT orphaned stub(s)"

# --- Static analysis: the machinery that caused rounds 1-5's defects must not
# be able to exist in the file at all, mechanically, not just behaviourally.
# AST-based, not grep: the module docstring legitimately narrates the rejected
# primitives (ps, kill -0, getpgid) BY NAME as design rationale, so a bare
# text search would false-positive on the file's own comments. Only actual
# Call nodes matter here. Follows the established idiom in
# scripts/validate-rulebook.test.sh (its stdlib-only import grep) but at
# AST precision, because prose about oracles is exactly what this file is
# supposed to contain plenty of. ---

STATIC=$(python3 - "$PY" <<'PYEOF'
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
bad = []
killpg_calls = 0
FORBIDDEN_ATTRS = {"getpgid", "waitpid"}
FORBIDDEN_BINARIES = {"ps", "pgrep", "kill", "killall"}
for node in ast.walk(tree):
    if not isinstance(node, ast.Call):
        continue
    func = node.func
    if isinstance(func, ast.Attribute):
        if func.attr == "killpg":
            killpg_calls += 1
        elif func.attr in FORBIDDEN_ATTRS:
            bad.append("os.%s() at line %d" % (func.attr, node.lineno))
        elif func.attr == "kill" and isinstance(func.value, ast.Name) and func.value.id == "os":
            bad.append("os.kill() at line %d" % node.lineno)
    for arg in node.args:
        values = []
        if isinstance(arg, (ast.List, ast.Tuple)):
            values = [e.value for e in arg.elts
                     if isinstance(e, ast.Constant) and isinstance(e.value, str)]
        elif isinstance(arg, ast.Constant) and isinstance(arg.value, str):
            values = [arg.value]
        if values and values[0] in FORBIDDEN_BINARIES:
            bad.append("subprocess call to '%s' at line %d" % (values[0], node.lineno))
print("BAD:" + ("; ".join(bad) if bad else "NONE"))
print("KILLPG:%d" % killpg_calls)
PYEOF
)
BAD_LINE=$(printf '%s\n' "$STATIC" | sed -n 's/^BAD://p')
KILLPG_LINE=$(printf '%s\n' "$STATIC" | sed -n 's/^KILLPG://p')
[[ "$BAD_LINE" == "NONE" ]] \
  && pass "no process-inspection oracle call sites (AST-checked)" \
  || fail "found oracle call site(s): $BAD_LINE"
[[ "$KILLPG_LINE" == "1" ]] \
  && pass "exactly one os.killpg() call site (signal_group)" \
  || fail "os.killpg() call site count=$KILLPG_LINE (want 1)"

# T32 — stdlib-only import allowlist, the exact idiom validate-rulebook.test.sh
# uses for its own validator.
IMPORT_LEAKS=$(grep -E '^(import|from) ' "$PY" | grep -vE '^(import|from) (datetime|os|re|shutil|signal|subprocess|sys|time)\b')
[[ -z "$IMPORT_LEAKS" ]] \
  && pass "codex-run.py imports are stdlib-only" \
  || fail "non-stdlib import(s): $IMPORT_LEAKS"

echo
if [[ "$FAILS" -eq 0 ]]; then echo "ALL PASS"; else echo "$FAILS FAILURE(S)"; exit 1; fi
