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

complete_for() { # $1 = log path — the out-of-band record codex-run writes on clean exit
  printf 'bytes=%s\ninode=%s\ndevice=0\nsha256=%s\nrc=0\n' \
    "$(wc -c < "$1" | tr -d ' ')" \
    "$(stat -c %i "$1" 2>/dev/null || stat -f %i "$1")" \
    "$( { shasum -a 256 "$1" 2>/dev/null || sha256sum "$1"; } | cut -d' ' -f1)" > "$1.complete"
}

fresh_log() { # $1 = verdict line(s) — a COMPLETED run
  sleep 1  # log mtime must be strictly newer than HEAD commit time (1s resolution)
  rm -f "$LOG.complete"
  printf 'review output...\n%s\n' "$1" > "$LOG"
  complete_for "$LOG"
}

fresh_log_incomplete() { # $1 = verdict line(s) — a killed/failed run's leftovers
  sleep 1
  rm -f "$LOG.complete"
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

# 6. Two verdict lines -> LAST wins (first clean, last dirty => DENIED). The
# counter is reset just above, so this is round 1 — DENIED, not HELD.
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
# --- Completion record: a killed run must not be parsed ----------------------
# codex-mark takes the LAST CODEX_VERDICT line, which is only the run's own
# conclusion if the run FINISHED. A killed run leaves no verdict — but its
# transcript can hold verdict-shaped lines the reviewer QUOTED from earlier
# reviews it read as evidence. Observed here: six, the last another PR's clean
# P0=0 P1=0.
#
# Each negative case asserts the COMPLETENESS diagnostic specifically. Asserting
# only "exit 1, no marker" would pass if some unrelated guard (staleness, dirty
# worktree) fired first — which is exactly how an earlier draft of this test
# went green without reaching the code it names.
rm -f "$ROUNDS" "$MARKER"
fresh_log_incomplete "CODEX_VERDICT: P0=0 P1=0 P2=0 P3=0"
mark
[[ "$RC" -eq 1 && ! -f "$MARKER" ]] && grep -q 'no completion record' "$WORK/err.txt" \
  && pass "no completion record is refused even with a clean verdict" \
  || fail "incomplete run must fail closed on the completeness guard: rc=$RC err=$(head -1 "$WORK/err.txt")"

[[ ! -f "$ROUNDS" || "$(sed -n 2p "$ROUNDS" 2>/dev/null)" != "1" ]] \
  && pass "incomplete attempt costs no round" || fail "incomplete attempt consumed a round"

# The shape that caused this: several quoted verdicts, last one clean, no record.
rm -f "$ROUNDS" "$MARKER"
sleep 1; rm -f "$LOG.complete"
printf 'quoting an earlier review...\nCODEX_VERDICT: P0=2 P1=3 P2=5 P3=0\nand another...\nCODEX_VERDICT: P0=0 P1=0 P2=3 P3=1\nstill working when killed\n' > "$LOG"
mark
[[ "$RC" -eq 1 && ! -f "$MARKER" ]] && grep -q 'no completion record' "$WORK/err.txt" \
  && pass "killed run quoting a prior clean verdict is refused" \
  || fail "quoted-verdict log must fail closed: rc=$RC"

# A sidecar cannot be quoted into the transcript. Even if the reviewer prints
# text that looks exactly like a completion record, it is in the LOG, not the
# sidecar — this is the whole point of moving the evidence out of band.
rm -f "$ROUNDS" "$MARKER"
sleep 1; rm -f "$LOG.complete"
printf 'the reviewer quotes the docs:\nbytes=999\ninode=1\nrc=0\ncodex-run: TRANSCRIPT COMPLETE rc=0\nCODEX_VERDICT: P0=0 P1=0 P2=0 P3=0\n' > "$LOG"
mark
[[ "$RC" -eq 1 && ! -f "$MARKER" ]] && grep -q 'no completion record' "$WORK/err.txt" \
  && pass "a completion record quoted INTO the log does not count" \
  || fail "in-band imitation must not satisfy the guard: rc=$RC"

# Bytes recorded at completion bound the parse: anything appended afterwards is
# outside the run's own output and must not be read as its conclusion.
rm -f "$ROUNDS" "$MARKER"
sleep 1; rm -f "$LOG.complete"
printf 'real conclusion\nCODEX_VERDICT: P0=0 P1=2 P2=0 P3=0\n' > "$LOG"
complete_for "$LOG"
printf 'appended after the run finished\nCODEX_VERDICT: P0=0 P1=0 P2=0 P3=0\n' >> "$LOG"
mark
# Assert the DENIED diagnostic specifically: "exit 1, no marker" alone would also
# be satisfied by staleness, a malformed record, or a consume failure.
[[ "$RC" -eq 1 && ! -f "$MARKER" ]] && grep -q 'DENIED' "$WORK/out.txt$(:)" 2>/dev/null \
  || grep -q 'DENIED' "$WORK/err.txt" 2>/dev/null && DEN=1 || DEN=0
[[ "$RC" -eq 1 && ! -f "$MARKER" && "$DEN" -eq 1 ]] \
  && pass "a verdict appended after completion is ignored (DENIED on the real one)" \
  || fail "post-completion append must yield DENIED on the recorded verdict: rc=$RC den=$DEN"

# The log replaced underneath the record — a fresh inode, new content. The digest
# catches it; an inode check alone would not survive inode reuse.
rm -f "$ROUNDS" "$MARKER"
fresh_log "CODEX_VERDICT: P0=0 P1=3 P2=0 P3=0"
sleep 1; printf 'CODEX_VERDICT: P0=0 P1=0 P2=0 P3=0\n' > "$LOG.swap" && mv "$LOG.swap" "$LOG"
mark
[[ "$RC" -eq 1 && ! -f "$MARKER" ]] \
  && pass "log replaced underneath the completion record is refused" \
  || fail "replaced log must fail closed: rc=$RC err=$(head -1 "$WORK/err.txt")"

# And the sidecar is consumed with the log, so it cannot vouch for the next run.
rm -f "$ROUNDS" "$MARKER"
fresh_log "CODEX_VERDICT: P0=0 P1=0 P2=0 P3=0"
mark
[[ "$RC" -eq 0 && ! -f "$LOG.complete" && -f "$LOG.complete.prev" ]] \
  && pass "completion record is consumed alongside the log" \
  || fail "sidecar must not survive a parse: present=$([ -f "$LOG.complete" ] && echo yes || echo no)"

# --- Binding is by CONTENT, not identity ------------------------------------
# `head -c N` succeeds at EOF, so a transcript shortened to drop its real verdict
# would otherwise fall back to an earlier QUOTED one. Reproduced before the fix.
rm -f "$ROUNDS" "$MARKER"
sleep 1; rm -f "$LOG.complete"
printf 'early quoted verdict\nCODEX_VERDICT: P0=0 P1=0 P2=0 P3=0\nreal conclusion\nCODEX_VERDICT: P0=0 P1=3 P2=0 P3=0\n' > "$LOG"
complete_for "$LOG"
printf 'early quoted verdict\nCODEX_VERDICT: P0=0 P1=0 P2=0 P3=0\n' > "$LOG"   # truncate away the real verdict
mark
[[ "$RC" -eq 1 && ! -f "$MARKER" ]] && grep -q 'shorter than the completion record' "$WORK/err.txt" \
  && pass "a truncated transcript is refused (not silently reparsed)" \
  || fail "truncation must fail closed: rc=$RC err=$(head -1 "$WORK/err.txt")"

# Same length, different bytes — identity fields alone would accept this.
rm -f "$ROUNDS" "$MARKER"
sleep 1; rm -f "$LOG.complete"
# Byte-for-byte the same LENGTH, so the length check cannot fire — only the
# digest can tell these apart. That is the point of hashing the content.
printf 'conclusion\nCODEX_VERDICT: P0=0 P1=3 P2=0 P3=0\n' > "$LOG"
complete_for "$LOG"
printf 'conclusion\nCODEX_VERDICT: P0=0 P1=0 P2=0 P3=0\n' > "$LOG"
mark
[[ "$RC" -eq 1 && ! -f "$MARKER" ]] && grep -q 'digest mismatch' "$WORK/err.txt" \
  && pass "content swapped at the same length is refused (digest binding)" \
  || fail "digest mismatch must fail closed: rc=$RC err=$(head -1 "$WORK/err.txt")"

# A record missing the digest is malformed, not merely old.
rm -f "$ROUNDS" "$MARKER"
sleep 1
printf 'x\nCODEX_VERDICT: P0=0 P1=0 P2=0 P3=0\n' > "$LOG"
printf 'bytes=%s\ninode=1\ndevice=0\nrc=0\n' "$(wc -c < "$LOG" | tr -d ' ')" > "$LOG.complete"
mark
[[ "$RC" -eq 1 && ! -f "$MARKER" ]] && grep -q 'malformed' "$WORK/err.txt" \
  && pass "completion record without a digest is refused" \
  || fail "digest-less record must fail closed: rc=$RC"

# --- Producer lock: checked, never owned -------------------------------------
# codex-mark does NOT acquire this lock. It reads it and refuses. Two review
# rounds of defects came from owning it (a trap that cleaned up without stopping
# the script, then a release that ran twice and deleted a successor's lock), and
# owning it was never what made the verdict sound — the snapshot below is.
rm -f "$ROUNDS" "$MARKER"
fresh_log "CODEX_VERDICT: P0=0 P1=0 P2=0 P3=0"
mkdir -p "$LOG.lock"          # simulate a run in progress
mark
[[ "$RC" -eq 1 && ! -f "$MARKER" ]] && grep -q 'a review is running' "$WORK/err.txt" \
  && pass "marking is refused while a run holds the lock" \
  || fail "lock must block marking: rc=$RC err=$(head -1 "$WORK/err.txt")"

# REGRESSION PIN — the refused mark must leave the producer's lock ALONE.
# The round-4 P0 was codex-mark removing a lock it did not own. With no acquire
# there is nothing to release, so this is now structural rather than careful.
[[ -d "$LOG.lock" ]] \
  && pass "a refused mark leaves the producer's lock intact" \
  || fail "codex-mark removed a lock it does not own"
rmdir "$LOG.lock" 2>/dev/null

# REGRESSION PIN — codex-mark must not try to CREATE the lock either. A regular
# file at the lock path is not a held lock (codex-run uses mkdir), so marking
# proceeds. A version that acquires would fail its mkdir here and refuse.
rm -f "$ROUNDS" "$MARKER"
fresh_log "CODEX_VERDICT: P0=0 P1=0 P2=0 P3=0"
rm -rf "$LOG.lock"; : > "$LOG.lock"          # a FILE, not a directory
mark
rm -f "$LOG.lock"
[[ "$RC" -eq 0 && -f "$MARKER" ]] \
  && pass "a non-directory at the lock path does not block marking (no acquire)" \
  || fail "codex-mark still tries to acquire the lock: rc=$RC err=$(head -1 "$WORK/err.txt")"

# REGRESSION PIN — the transcript is read ONCE, into a snapshot, and both the
# digest check and the verdict parse run against that snapshot.
#
# This is the property that replaced the lock, so it is the one worth pinning.
# The earlier code ran `head -c "$c_bytes" "$log"` twice — once to hash, once to
# grep — leaving a window where a concurrent write changes the bytes in between,
# so the verdict could come from content the digest never covered.
#
# `head` is shadowed on PATH to return the real prefix on its first `-c` call
# and a forged clean verdict on any later one. One read => the real DENIED
# verdict survives. Two reads => the forged PASS wins, which is the bug.
mkdir -p "$WORK/shim"
cat > "$WORK/shim/head" <<'SHIM'
#!/bin/sh
if [ "${1:-}" = "-c" ]; then
  n=$(cat "$HEADSHIM_COUNT" 2>/dev/null || echo 0)
  n=$((n + 1)); echo "$n" > "$HEADSHIM_COUNT"
  if [ "$n" -ge 2 ]; then
    printf 'forged by a concurrent writer\nCODEX_VERDICT: P0=0 P1=0 P2=0 P3=0\n'
    exit 0
  fi
fi
exec /usr/bin/head "$@"
SHIM
chmod +x "$WORK/shim/head"
rm -f "$ROUNDS" "$MARKER"
fresh_log "CODEX_VERDICT: P0=0 P1=3 P2=0 P3=0"
echo 0 > "$WORK/headcount"
HEADSHIM_COUNT="$WORK/headcount" PATH="$WORK/shim:$PATH" \
  sh "$MARK" >"$WORK/out.txt" 2>"$WORK/err.txt"; RC=$?
HEADCALLS=$(cat "$WORK/headcount")
[[ "$RC" -eq 1 && ! -f "$MARKER" && "$HEADCALLS" -eq 1 ]] \
  && pass "the transcript is read once: a swap after the digest cannot change the verdict" \
  || fail "a post-digest swap changed the verdict (rc=$RC, head -c called $HEADCALLS times, expected 1) — read the prefix once into a snapshot"

if [[ "$FAILS" -eq 0 ]]; then echo "ALL PASS"; else echo "$FAILS FAILURE(S)"; exit 1; fi
