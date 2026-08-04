#!/bin/bash
# Self-test for codex-run.sh — the watchdog contract: usage/precondition errors
# spawn nothing; a clean child exits 0; a crashing child exits 5; stdin is
# closed (the documented deadlock); a stall is killed at the ceiling (exit 4)
# and takes its whole process group with it; a deterministic hang is classified
# early (exit 3); the review log gets a FRESH inode per attempt (the birth-time
# contract codex-mark's dur= depends on); the ceiling is 2x the observed-good
# median, ignoring dur=?, clamped to [300,3600] with a 900s cold-start default;
# killed runs keep their log and leave an attempts-log trace; stderr stays
# prefixed even through a job-control kill.
#
# No real Codex, no network: every child is a generated stub under $WORK.
#
# Run from anywhere: bash codex-run.test.sh
# Exit 0 = all assertions pass; non-zero = a failure.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
RUN="$SCRIPT_DIR/codex-run.sh"

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

run() { bash "$RUN" "$@" >"$WORK/out.txt" 2>"$WORK/err.txt"; RC=$?; }
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
cat > "$WORK/blocker.sh" <<'EOF'
#!/bin/bash
echo "Reading additional input from stdin..."
sleep 300
EOF
cat > "$WORK/reader.sh" <<'EOF'
#!/bin/bash
cat > /dev/null
echo "stdin-eof"
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

# 19. stderr hygiene: bash prints its own "Terminated: 15" job-control notice
# when it reaps a killed job. Every line must still be ours.
BAD=$(grep -v '^codex-run: ' "$WORK/err.txt" | wc -l | tr -d ' ')
[[ "$BAD" -eq 0 ]] && pass "stderr stays prefixed through a kill" || fail "leaked $BAD stderr line(s): $(grep -v '^codex-run: ' "$WORK/err.txt" | head -2)"

# 7b. The killed attempt left a trace — today a hang that never marks is
# invisible, because only codex-mark PASSes reach the audit log.
[[ -s "$ATTEMPTS" ]] && grep -q "stall" "$ATTEMPTS" \
  && pass "killed attempt logged to codex-run-attempts.log" || fail "no attempts-log entry"

# 9. Deterministic hang -> classified EARLY at the block-point, not at the
# ceiling. With classification dropped this returns 4 sixty seconds later.
t0=$(now); run --ceiling 60 -- "$WORK/blocker.sh"; t1=$(now)
[[ "$RC" -eq 3 && $((t1 - t0)) -lt 20 ]] \
  && pass "block-point hang classified early (exit 3, $((t1 - t0))s)" || fail "hang: rc=$RC elapsed=$((t1 - t0))"

# --- The birth-time contract ---

# 10. REGRESSION PIN — fresh inode per attempt. codex-mark derives dur= from
# the log's filesystem BIRTH time, and truncation does NOT reset it. Replace
# `rm -f` with `: > "$log"` and this asserts >= 3; pre-create the log and birth
# predates the run. Either way a stale leftover is how dur=85344s gets recorded.
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

# 20. No stub survived the suite.
sleep 1
LEFT=$(pgrep -f "$WORK/(forever|blocker|reader)\.sh" 2>/dev/null | wc -l | tr -d ' ')
[[ "$LEFT" -eq 0 ]] && pass "no orphaned stub processes" || fail "$LEFT orphaned stub(s)"

echo
if [[ "$FAILS" -eq 0 ]]; then echo "ALL PASS"; else echo "$FAILS FAILURE(S)"; exit 1; fi
