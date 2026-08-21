#!/bin/sh
# codex-mark.sh — the ONLY sanctioned writer of the Codex review marker.
#
# Usage:
#   1. Run the Codex review through this rulebook's watchdog, which writes the
#      transcript to the log with the fresh inode the dur= field below needs:
#        scripts/codex-run.sh -- codex exec "<review brief>"
#      (`codex exec`, NOT `codex exec review` — the subcommand refuses --base
#       together with a prompt, and without a prompt there is no rubric, so no
#       CODEX_VERDICT line. Never bare, never piped to tee — neither form can be
#       bounded; see references/delegation.md § Bounded delegation)
#   2. Then run codex-mark.sh (this rulebook's scripts/codex-mark.sh; the
#      workflow prose names the installed path).
#      (optional first arg = alternate log path)
#
# The review brief MUST instruct Codex to end with one final line:
#   CODEX_VERDICT: P0=<n> P1=<n> P2=<n> P3=<n>   (counting OPEN findings)
# All four counts are required — a line missing any of them is malformed and
# fails closed (the contract names all four; a partial line usually means the
# brief drifted).
#
# Behavior (kerby verdict vocabulary):
#   PASS   (exit 0) — P0=0 and P1=0: writes the marker, resets the round
#                     counter, appends to the audit log, prints the PR-note line.
#   DENIED (exit 1) — open P0/P1 within the cap: fix, scoped re-review, re-mark.
#   HELD   (exit 2) — open P0/P1 at round >= 3: stop, escalate to the user.
#
# Fail-closed: no verdict line, malformed verdict, dirty worktree, or stale
# log => no marker.
# Known ceiling: this trusts the teed log's content. Forging a log is
# possible, but that is deliberate deception, not drift; the audit log
# ($GIT_DIR/codex-review-audit.log) keeps the history visible.

set -u

fail() { echo "codex-mark: $1" >&2; exit 1; }

gitdir=$(git rev-parse --git-dir 2>/dev/null) || fail "not inside a git repo"
head=$(git rev-parse HEAD 2>/dev/null) || fail "no HEAD commit"
branch=$(git rev-parse --abbrev-ref HEAD)

log="${1:-$gitdir/codex-review.log}"

# 1. Reviewed tree must be exactly the tree that gets pushed.
[ -z "$(git status --porcelain --untracked-files=no)" ] \
  || fail "worktree has uncommitted tracked changes — commit them, re-review, then mark"

# 2. Review log must exist and be newer than the last commit.
[ -f "$log" ] || fail "no review log at $log — tee the Codex review output there first"
log_mtime=$(stat -c %Y "$log" 2>/dev/null || stat -f %m "$log" 2>/dev/null) \
  || fail "cannot stat $log"
# Attempt duration: tee creates the log at review start and last-writes it at
# review end, so birth->mtime spans the run — valid ONLY because this script
# consumes the log after each parse (see below); tee's truncation of an
# existing file does NOT reset birth time. Advisory only (the dur= audit
# field is the observed-good baseline for delegation.md's wall-clock ceiling);
# "?" when the filesystem has no birth time (Linux %W returns 0 there).
log_birth=$(stat -c %W "$log" 2>/dev/null || stat -f %B "$log" 2>/dev/null)
case "$log_birth" in
  ''|*[!0-9]*|0) dur="?" ;;
  *) dur=$((log_mtime - log_birth)); [ "$dur" -ge 0 ] || dur="?" ;;
esac
head_time=$(git log -1 --format=%ct)
[ "$log_mtime" -gt "$head_time" ] \
  || fail "review log is older than HEAD — a commit landed after the review; re-review this exact tree"

# 3. Round counter (per branch; resets on branch switch or on PASS). Compute the
# incremented value here but DEFER the write until after the verdict parses
# (step 4). A malformed / missing-verdict attempt must NOT consume a round —
# otherwise a couple of brief-drift mark attempts push the counter to 3 and the
# first real review with an open P0/P1 is instantly HELD instead of getting its
# three legitimate rounds.
rounds_file="$gitdir/codex-review-rounds"
rounds=0
if [ -f "$rounds_file" ]; then
  saved_branch=$(head -n1 "$rounds_file")
  [ "$saved_branch" = "$branch" ] && rounds=$(sed -n 2p "$rounds_file")
fi
case "$rounds" in ''|*[!0-9]*) rounds=0 ;; esac
rounds=$((rounds + 1))

# 4a. The transcript must be COMPLETE. codex-run stamps this line on its clean
# exit path ONLY — never after a stall (4), a runtime failure (5) or an
# outlived-SIGKILL (6).
#
# This is not belt-and-braces; without it step 4b is unsound. "Last verdict
# wins" is correct only for a run that FINISHED, because the reviewer emits its
# verdict last. A killed run has no conclusion — and its transcript can still
# hold verdict-shaped lines the reviewer QUOTED while reading prior review
# transcripts as evidence. Observed here: a stalled run left six such lines, the
# last being another PR's clean `P0=0 P1=0`. Parsing that would have written a
# PASS marker for a review that never reached a verdict — a check that runs,
# reports clean, and proves nothing.
#
# A pre-stamp log (written before this guard existed) is refused too. That is
# the safe direction: re-running a review is cheap, a false-clean marker is not.
complete_line=$(grep -n 'codex-run: TRANSCRIPT COMPLETE rc=0' "$log" | tail -n1)
[ -n "$complete_line" ] \
  || fail "transcript at $log is not marked complete — the run stalled, failed, or predates this check. A killed run has no verdict; re-run the review rather than parsing what it left behind"
complete_at=${complete_line%%:*}

# 4b. Parse the verdict line — the last occurrence BEFORE the completion stamp,
# so nothing appended afterwards can be mistaken for the conclusion. Fail closed
# if absent or malformed; done BEFORE persisting the round, so a failed parse
# costs nothing.
verdict=$(head -n "$complete_at" "$log" | grep -E 'CODEX_VERDICT:' | tail -n1)
[ -n "$verdict" ] \
  || fail "no CODEX_VERDICT line in $log — the review brief must require it; re-run the review with the rubric + verdict contract included"

get() { printf '%s' "$verdict" | sed -n "s/.*$1=\([0-9][0-9]*\).*/\1/p"; }
p0=$(get P0); p1=$(get P1); p2=$(get P2); p3=$(get P3)
[ -n "$p0" ] && [ -n "$p1" ] && [ -n "$p2" ] && [ -n "$p3" ] \
  || fail "malformed CODEX_VERDICT line (all four counts P0..P3 required): $verdict"

# Verdict is well-formed — NOW this counts as a real round. Persist the
# increment (PASS overwrites it to 0 below; DENIED/HELD keep it for the next
# attempt). A failed parse above exited before reaching here, costing no round.
printf '%s\n%s\n' "$branch" "$rounds" > "$rounds_file"

# Consume the log now that its verdict is parsed: the next attempt's tee must
# create a FRESH inode or its dur= would span since the first attempt (birth
# time survives truncation). Kept as .prev for the audit trail. A malformed
# log exits above without being consumed, so it stays inspectable. Fail closed
# if the move can't happen — a silent failure would leave the reused inode the
# consume exists to prevent, and we must not mark PASS on a broken baseline.
mv -f "$log" "$log.prev" || fail "cannot consume review log ($log -> $log.prev) — clear it, re-review, re-mark"

# 5. Verdict.
if [ "$p0" -eq 0 ] && [ "$p1" -eq 0 ]; then
  printf '%s\n' "$head" > "$gitdir/codex-reviewed"
  printf '%s %s rounds=%s P0=%s P1=%s P2=%s P3=%s dur=%ss\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$head" "$rounds" "$p0" "$p1" "$p2" "$p3" "$dur" \
    >> "$gitdir/codex-review-audit.log"
  printf '%s\n%s\n' "$branch" 0 > "$rounds_file"
  echo "codex-mark: PASS — marker written for $head"
  echo "PR note: Codex-reviewed locally at $head · rounds=$rounds · P0/P1=0 · P2/P3 logged=$((p2 + p3))"
  exit 0
fi

if [ "$rounds" -ge 3 ]; then
  echo "codex-mark: HELD — round $rounds and P0=$p0 P1=$p1 still open. Stop: no merge, no marker. Escalate to the user with the open findings." >&2
  exit 2
fi

echo "codex-mark: DENIED — P0=$p0 P1=$p1 open (round $rounds of 3). Fix them, run a SCOPED re-review (verify the fixes + scan the fix diff) through scripts/codex-run.sh, then mark again. P2=$p2 P3=$p3 -> log as debt (issue or ponytail-debt), never re-loop on them." >&2
exit 1
