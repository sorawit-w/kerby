#!/bin/bash
# Self-test for codex-mark.sh — the red/green suite from the handoff plus the
# contract-fix cases: missing log; DENIED on open P1 (exit 1); HELD at round 3
# (exit 2); PASS writes marker + audit + PR-note + resets rounds (exit 0);
# stale log after a new commit; dirty tracked worktree; malformed verdict
# (missing P2/P3) fails closed; two verdict lines -> last wins.
# Exercises the macOS `stat -f %m` fallback natively when run on Darwin.
#
# Run from anywhere: bash codex-mark.test.sh
# Exit 0 = all assertions pass; non-zero = a failure.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
MARK="$SCRIPT_DIR/codex-mark.sh"

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
MARKER="$GITDIR/codex-reviewed"
ROUNDS="$GITDIR/codex-review-rounds"

fresh_log() { # $1 = verdict line(s)
  sleep 1  # log mtime must be strictly newer than HEAD commit time (1s resolution)
  printf 'review output...\n%s\n' "$1" > "$LOG"
}

mark() { sh "$MARK" >"$WORK/out.txt" 2>"$WORK/err.txt"; RC=$?; }

# 1. Missing log -> fail (exit 1), no marker.
rm -f "$LOG" "$MARKER" "$ROUNDS"
mark
[[ "$RC" -eq 1 && ! -f "$MARKER" ]] && pass "missing log fails closed" || fail "missing log: rc=$RC"

# 2. No verdict line -> fail, no marker.
fresh_log "no verdict here"
mark
[[ "$RC" -eq 1 && ! -f "$MARKER" ]] && pass "no CODEX_VERDICT fails closed" || fail "no verdict: rc=$RC"

# 3. Malformed verdict (missing P2/P3) -> fail closed (contract fix).
rm -f "$ROUNDS"
fresh_log "CODEX_VERDICT: P0=0 P1=0"
mark
[[ "$RC" -eq 1 && ! -f "$MARKER" ]] && pass "missing P2/P3 fails closed" || fail "partial verdict: rc=$RC marker=$([ -f "$MARKER" ] && echo yes || echo no)"

# 3b. A malformed/missing-verdict attempt must NOT consume a round.
rm -f "$ROUNDS"
fresh_log "no verdict here at all"
mark  # fails closed
[[ "$RC" -eq 1 && ( ! -f "$ROUNDS" || "$(sed -n 2p "$ROUNDS" 2>/dev/null)" != "1" ) ]] \
  && pass "malformed attempt costs no round" || fail "malformed consumed a round: rounds=$(sed -n 2p "$ROUNDS" 2>/dev/null)"
fresh_log "CODEX_VERDICT: P0=0 P1=1 P2=0"  # missing P3
mark
[[ "$RC" -eq 1 && ( ! -f "$ROUNDS" || "$(sed -n 2p "$ROUNDS" 2>/dev/null)" != "1" ) ]] \
  && pass "partial-verdict attempt costs no round" || fail "partial consumed a round: rounds=$(sed -n 2p "$ROUNDS" 2>/dev/null)"

# 4. DENIED on open P1 (exit 1), round counts up (first VALID round), no marker.
rm -f "$ROUNDS"
fresh_log "CODEX_VERDICT: P0=0 P1=2 P2=1 P3=0"
mark
[[ "$RC" -eq 1 && ! -f "$MARKER" && "$(sed -n 2p "$ROUNDS")" == "1" ]] \
  && pass "DENIED on open P1 (round 1)" || fail "DENIED: rc=$RC rounds=$(sed -n 2p "$ROUNDS" 2>/dev/null)"

# 5. HELD at round 3 (exit 2). Each round tees a fresh log — codex-mark
# consumed the previous one on parse.
fresh_log "CODEX_VERDICT: P0=0 P1=2 P2=1 P3=0"
mark  # round 2 -> DENIED
fresh_log "CODEX_VERDICT: P0=1 P1=0 P2=0 P3=0"
mark  # round 3 -> HELD
[[ "$RC" -eq 2 && ! -f "$MARKER" ]] && pass "HELD at round 3" || fail "HELD: rc=$RC round=$(sed -n 2p "$ROUNDS" 2>/dev/null)"

# 6. Two verdict lines -> LAST wins (first clean, last dirty => DENIED... rounds now past cap => HELD).
rm -f "$ROUNDS"
fresh_log $'CODEX_VERDICT: P0=0 P1=0 P2=0 P3=0\nmore output\nCODEX_VERDICT: P0=0 P1=1 P2=0 P3=0'
mark
[[ "$RC" -eq 1 && ! -f "$MARKER" ]] && pass "last verdict line wins" || fail "last-wins: rc=$RC marker=$([ -f "$MARKER" ] && echo yes || echo no)"

# 7. PASS: writes marker with HEAD sha, appends audit line, prints PR note, resets rounds to 0.
fresh_log "CODEX_VERDICT: P0=0 P1=0 P2=2 P3=1"
mark
HEAD_SHA=$(git rev-parse HEAD)
ok=1
[[ "$RC" -eq 0 ]] || ok=0
[[ "$(cat "$MARKER" 2>/dev/null)" == "$HEAD_SHA" ]] || ok=0
grep -q "P2=2 P3=1" "$GITDIR/codex-review-audit.log" || ok=0
grep -Eq "P2=2 P3=1 dur=([0-9]+|\?)s" "$GITDIR/codex-review-audit.log" || ok=0  # duration baseline field
grep -q "PR note: Codex-reviewed locally at $HEAD_SHA" "$WORK/out.txt" || ok=0
grep -q "P2/P3 logged=3" "$WORK/out.txt" || ok=0
[[ "$(sed -n 2p "$ROUNDS")" == "0" ]] || ok=0
[[ "$ok" -eq 1 ]] && pass "PASS writes marker+audit+PR-note, resets rounds" || fail "PASS case: rc=$RC out=$(cat "$WORK/out.txt")"

# 7b. Log is consumed on parse (fresh inode per attempt), so the next dur=
# measures ITS OWN run — not the span since the first attempt (tee truncation
# does not reset birth time; without the consume this asserts dur>=3).
[[ ! -f "$LOG" && -f "$LOG.prev" ]] && pass "log consumed to .prev after parse" || fail "log not consumed"
sleep 3
fresh_log "CODEX_VERDICT: P0=0 P1=0 P2=0 P3=0"
mark
last_dur=$(tail -n1 "$GITDIR/codex-review-audit.log" | sed -n 's/.*dur=\([0-9?]*\)s$/\1/p')
[[ "$last_dur" == "?" || "$last_dur" -le 1 ]] && pass "dur is per-attempt (${last_dur}s)" || fail "dur spans attempts: ${last_dur}s"

# 8. Stale log after a new commit -> fail, marker not refreshed.
fresh_log "CODEX_VERDICT: P0=0 P1=0 P2=0 P3=0"
git -c user.email=t@t -c user.name=t commit -q --allow-empty -m next
mark
[[ "$RC" -eq 1 ]] && pass "stale log after new commit fails" || fail "stale log: rc=$RC"

# 9. Dirty tracked worktree -> fail.
echo x > tracked.txt && git add tracked.txt
git -c user.email=t@t -c user.name=t commit -q -m add-file
echo y > tracked.txt   # dirty, tracked
fresh_log "CODEX_VERDICT: P0=0 P1=0 P2=0 P3=0"
mark
[[ "$RC" -eq 1 ]] && pass "dirty tracked worktree fails" || fail "dirty worktree: rc=$RC"
git checkout -q -- tracked.txt

# 10. stat fallback sanity: the script stat'ed the log successfully on this OS.
fresh_log "CODEX_VERDICT: P0=0 P1=0 P2=0 P3=0"
mark
[[ "$RC" -eq 0 ]] && pass "stat works on $(uname -s) (marker written)" || fail "stat fallback: rc=$RC err=$(cat "$WORK/err.txt")"

# 11. Log consume fails closed: if the log can't be moved to .prev, no marker.
# Force mv failure by making the destination path ($LOG.prev/codex-review.log)
# a non-empty directory — mv into it fails "Directory not empty" on BSD & GNU.
rm -f "$MARKER" "$ROUNDS"
rm -rf "$LOG.prev"
mkdir -p "$LOG.prev/$(basename "$LOG")/blocker"
fresh_log "CODEX_VERDICT: P0=0 P1=0 P2=0 P3=0"
mark
[[ "$RC" -ne 0 && ! -f "$MARKER" ]] && pass "log-consume failure fails closed (no marker)" || fail "consume failure: rc=$RC marker=$([ -f "$MARKER" ] && echo yes || echo no)"
rm -rf "$LOG.prev"

echo
if [[ "$FAILS" -eq 0 ]]; then echo "ALL PASS"; else echo "$FAILS FAILURE(S)"; exit 1; fi
