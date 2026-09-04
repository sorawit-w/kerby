#!/bin/bash
# Test for check-status-provenance.sh — ships alongside the guard, because a
# guard with no test is an untested claim of safety (`skills/kerby/CLAUDE.md`).
# The removed commit-time-gate guard reported a clean run on a tree carrying four
# restatements; that is the failure this file exists to prevent for THIS guard.
#
# Every fix here carries its TRUE-POSITIVE TWIN. Killing a false positive by
# loosening a check can gut the real coverage and leave the suite green, so each
# "must pass" case is paired with the "must still fail" case it resembles.
#
# Run: bash skills/kerby/rulebooks/swe/scripts/check-status-provenance.test.sh
# Exit 0 = every case behaves as specified.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
GUARD="$SCRIPT_DIR/check-status-provenance.sh"

TMP=$(mktemp -d)
trap 'chmod -R u+rw "$TMP" 2>/dev/null; rm -rf "$TMP"' EXIT

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

# Run the guard on a fixture; assert the exit code and every required substring.
expect() { # $1=label $2=expected-exit $3=fixture $4..=must-contain
  local label="$1" want="$2" content="$3"; shift 3
  local f="$TMP/STATUS.md" out got needle
  printf '%s\n' "$content" > "$f"
  out=$(bash "$GUARD" "$f" 2>&1); got=$?
  if [[ "$got" -ne "$want" ]]; then
    fail "$label: expected exit $want, got $got"
    printf '%s\n' "$out" | sed 's/^/      /'
    return
  fi
  for needle in "$@"; do
    if ! printf '%s' "$out" | grep -q -- "$needle"; then
      fail "$label: exit correct, but output never contained '$needle'"
      printf '%s\n' "$out" | sed 's/^/      /'
      return
    fi
  done
  pass "$label"
}

[[ -f "$GUARD" ]] || { echo "FAIL: cannot find $GUARD"; exit 1; }

# --- 1. the clean case -------------------------------------------------------
expect "clean file exits 0" 0 '# Project Status

## Current Position

| **Phase** | Implementation — the parser is behind the flag |

## Next Up

| 1 | Turn the flag on | review |'

# --- 2. versions -------------------------------------------------------------
expect "semver in prose fails" 1 '| **Goal** | Ship swe 2.11.3 to everyone |' "states a version"
expect "v-prefixed version fails" 1 'Released as v9.26.3.' "states a version"
# FALSE POSITIVE (adversarial review): an IP address is not a semver. A bare
# three-part match reads the first three octets of 127.0.0.1 as one.
expect "IPv4 address is not a version" 0 'The fixture listens on 127.0.0.1 and 192.168.1.10.'

# --- 3. SHAs -----------------------------------------------------------------
expect "full-length sha fails" 1 'Merged as e9163f1bd957c3db6aad3040e45a0e74d866b67a.' "states a sha"
expect "7-char sha fails" 1 '| **Phase** | Shipped — merged as 095605e |' "states a sha"
# Found by adversarial review: short and uppercase abbreviations are still SHAs.
expect "6-char abbreviated sha fails" 1 'Reviewed at 1a2b3c last night.' "states a sha"
expect "uppercase sha fails" 1 'Reviewed at 095605E last night.' "states a sha"
# DOCUMENTED MISS, asserted so it stays a decision rather than a surprise. An
# ALL-DIGIT abbreviation (095605 resolves in this repo) is not matched, because
# requiring a hex letter is what excludes ordinary numbers — and a status file
# holds far more ordinary six-digit numbers than all-digit SHA abbreviations.
# The cost is bounded: a 7-char abbreviation contains a letter 96.3% of the time
# and a full-length SHA effectively always.
expect "all-digit abbreviation is a documented miss" 0 'Reviewed at 095605 last night.'
# FALSE POSITIVE, and the reason the digit rule exists. "defaced" is 7 chars of
# pure hex letters; the earlier guard flagged it. Its own header documented that
# as an accepted miss while this test claimed English words pass — the two
# disagreed, so the guard changed rather than the claim.
expect "hex-spelled English words pass" 0 'A decade later the facade was defaced; DEFACED again in June.'
# FALSE POSITIVE from lowering the minimum to six: an ordinary number is all
# "hex" digits. Requiring a hex LETTER as well as a digit excludes it.
expect "ordinary six-digit numbers pass" 0 'Milestone 123456 is queued behind 987654.'
# The true-positive twin: a real SHA has both, and must still fail.
expect "sha with digits and letters still fails" 1 'Reviewed at 1a2b3c today.' "states a sha"

# FALSE POSITIVE from GitHub-side review on a different platform: splitting on
# every non-alphanumeric discards a leading `#`, so a CSS colour became a SHA. A
# brand colour is exactly what a real Next Up row carries.
expect "CSS hex colours are not SHAs" 0 '| 1 | Change brand colour from #1a2b3c to #2f4f4f | design |'
expect "8-digit RGBA colours are not SHAs" 0 'Set the overlay to #1a2b3c4d this sprint.'
expect "decimal issue references are not SHAs" 0 'Blocked behind #1234 in the tracker.'
# TRUE-POSITIVE TWINS. The exemption is limited to CSS colour SHAPES (3, 4, 6, 8
# hex digits), so a `#`-prefixed SHA of any other length must still fail —
# blanking every `#`-hex run would have let this escape, which is what the
# narrowing fixed. And the bare token must still fail, or the colour exemption
# could be "achieved" by dropping the SHA check entirely.
expect "a 7-hex sha after a # still fails" 1 'Reviewed commit #1a2b3c7 today.' "states a sha"
expect "a long sha after a # still fails" 1 'Reviewed commit #e9163f1bd957 today.' "states a sha"
expect "the same token bare is still a sha" 1 'Merged as 1a2b3c today.' "states a sha"

# --- 4. branch names are NOT checked ------------------------------------------
# Deliberate removal, asserted so it stays a decision rather than rotting into an
# assumption. Three designs over three review rounds each fixed their cited cases
# and produced new ones, because `docs/README` is both a valid branch name and a
# common file path and no pattern separates them. The script header carries the
# full account. These cases lock in that BOTH directions are now silent: a real
# branch is not flagged, and ordinary prose containing a slash is not either.
expect "a real branch reference is not flagged" 0 '| Working Branch | feature/minimal-first-planning |'
expect "an unlabelled branch reference is not flagged" 0 'Working on fix/status-accuracy now.'
expect "prose mentioning branches and a path is not flagged" 0 'Review branch policy, then edit docs/README.'
expect "nested source paths are not flagged" 0 'Edit src/feature/parser.ts and src/fix/apply.ts.'
# The removal must not have cost the OTHER two checks anything: a line carrying a
# branch plus a version plus a SHA still fails on the version and the SHA.
expect "version and sha still caught on a branch-bearing line" 1 \
  '| Working Branch | feature/x | shipped 1.2.3 as 095605e |' "states a version" "states a sha"

# --- 5. reporting quality ----------------------------------------------------
# Both categories on one line must be reported. Asserting only one lets the
# other silently stop working.
expect "both categories on one line are reported" 1 '| Shipped 1.2.3 as 095605e |' \
  "states a version" "states a sha"
# The guard advertises line-numbered diagnostics; assert the number, not just the
# category, or the diagnostic contract is untested.
expect "the failing line number is named" 1 'clean line one
clean line two
Shipped swe 2.11.3 here.' "STATUS.md:3 states a version"

# --- 6. fail-closed ----------------------------------------------------------
# THE WORST FAILURE CLASS. An unreadable file made awk exit non-zero, leaving the
# capture empty — indistinguishable from a clean file — so the guard printed PASS
# and exited 0. A guard that cannot read its subject must never report a pass.
UNREADABLE="$TMP/unreadable.md"
printf 'swe 2.11.3 at 095605e\n' > "$UNREADABLE"
chmod 000 "$UNREADABLE"
if [[ -r "$UNREADABLE" ]]; then
  # Running as root, or a filesystem that ignores the mode — the case cannot be
  # staged here. Say so; never report a pass for a check that did not run.
  echo "SKIP: cannot stage an unreadable file (running as root?) — fail-closed case NOT verified"
else
  out=$(bash "$GUARD" "$UNREADABLE" 2>&1); got=$?
  if [[ "$got" -ne 0 ]] && printf '%s' "$out" | grep -q "NOT scanned"; then
    pass "unreadable file fails closed instead of reporting a pass"
  else
    fail "unreadable file: expected non-zero exit naming the failure, got exit $got"
    printf '%s\n' "$out" | sed 's/^/      /'
  fi
fi
chmod 644 "$UNREADABLE"

# A DIRECTORY is not a missing file. A bare `! -f` folds the two together, so a
# directory target reported "does not exist" and exited 0 — a pass on something
# never scanned. Same class as the unreadable case above.
mkdir -p "$TMP/adir"
out=$(bash "$GUARD" "$TMP/adir" 2>&1); got=$?
if [[ "$got" -ne 0 ]] && printf '%s' "$out" | grep -q "NOT scanned"; then
  pass "a directory target fails closed rather than reporting SKIP"
else
  fail "directory target: expected non-zero exit naming the failure, got exit $got"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# A DANGLING SYMLINK exists as a link but is false to -e. Reporting it absent is
# a pass on an unresolvable path.
ln -s "$TMP/no-such-target" "$TMP/dangling"
out=$(bash "$GUARD" "$TMP/dangling" 2>&1); got=$?
if [[ "$got" -ne 0 ]] && printf '%s' "$out" | grep -q "NOT scanned"; then
  pass "a dangling symlink fails closed rather than reporting SKIP"
else
  fail "dangling symlink: expected non-zero exit naming the failure, got exit $got"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# AN UNSEARCHABLE PARENT makes a file that really exists look absent to a stat.
# The guard no longer tries to tell that apart from true absence — it just opens
# the file — so this case is covered by the same rule as every other failed open.
mkdir -p "$TMP/locked"; printf 'swe 1.2.3\n' > "$TMP/locked/f.md"; chmod 000 "$TMP/locked"
if [[ -r "$TMP/locked" ]]; then
  echo "SKIP: cannot stage an unsearchable parent (running as root?) — case NOT verified"
else
  out=$(bash "$GUARD" "$TMP/locked/f.md" 2>&1); got=$?
  if [[ "$got" -ne 0 ]] && printf '%s' "$out" | grep -q "NOT scanned"; then
    pass "a file under an unsearchable parent fails closed"
  else
    fail "unsearchable parent: expected non-zero exit, got exit $got"
    printf '%s\n' "$out" | sed 's/^/      /'
  fi
fi
chmod 755 "$TMP/locked"

# AWK-SPECIAL FILENAMES. As an awk OPERAND, `-` is stdin and `x=y` is a variable
# assignment: both scan nothing and exit 0 on a file that does exist. The guard
# feeds input by redirect for exactly this reason, so both must be scanned.
printf 'swe 1.2.3\n' > "$TMP/-"
# stdin MUST be controlled: inherited stdin carrying a version would let the old
# operand-form guard read that instead of the file and satisfy the assertion, and
# a terminal stdin would hang. Empty stdin makes the old form scan nothing.
out=$( cd "$TMP" && bash "$GUARD" "-" < /dev/null 2>&1 ); got=$?
if [[ "$got" -ne 0 ]] && printf '%s' "$out" | grep -q "states a version"; then
  pass "a file named '-' is scanned, not read as stdin"
else
  fail "file named '-': expected it to be scanned and fail, got exit $got"
  printf '%s\n' "$out" | sed 's/^/      /'
fi
printf 'swe 1.2.3\n' > "$TMP/x=y"
# The path must be BARE and relative. Prefixed with "$TMP/", the assignment's
# left-hand side contains slashes, so awk falls back to treating it as a filename
# and the old operand-form guard scanned it correctly — proving nothing.
out=$( cd "$TMP" && bash "$GUARD" "x=y" < /dev/null 2>&1 ); got=$?
if [[ "$got" -ne 0 ]] && printf '%s' "$out" | grep -q "states a version"; then
  pass "a file named 'x=y' is scanned, not read as an awk assignment"
else
  fail "file named 'x=y': expected it to be scanned and fail, got exit $got"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# ABSENCE IS NOT SPECIAL-CASED. There is no SKIP: a file that is not there is one
# of the many ways an open can fail, and all of them exit 1. Four fail-opens on
# this branch came from trying to prove absence — a question with no bounded
# answer, since every ancestor and every path limit is another way to fail to
# observe something that is really there.
out=$(bash "$GUARD" "$TMP/nope.md" 2>&1); got=$?
if [[ "$got" -ne 0 ]] && printf '%s' "$out" | grep -q "NOT scanned"; then
  pass "an absent file fails closed — no SKIP, no exit 0"
else
  fail "absent file: expected non-zero exit naming the failure, got exit $got"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# The two cases that defeated the previous designs. A locked GRANDparent (not the
# immediate parent), and a path long enough that `dirname` itself fails.
mkdir -p "$TMP/lk/sub"; printf 'swe 1.2.3\n' > "$TMP/lk/sub/f.md"; chmod 000 "$TMP/lk"
if [[ -r "$TMP/lk" ]]; then
  echo "SKIP: cannot stage a locked ancestor (running as root?) — case NOT verified"
else
  out=$(bash "$GUARD" "$TMP/lk/sub/f.md" 2>&1); got=$?
  if [[ "$got" -ne 0 ]]; then
    pass "a file under a locked GRANDparent fails closed"
  else
    fail "locked grandparent: expected non-zero exit, got exit $got"
    printf '%s\n' "$out" | sed 's/^/      /'
  fi
fi
chmod 755 "$TMP/lk"

# DERIVE the platform limit; do not assume one. PATH_MAX is 1024 on macOS and
# commonly 4096 on Linux, so a fixture hard-coded for one is under the limit on
# the other and the case silently stops testing anything. Components stay under
# NAME_MAX (255 on both) so the path fails on its total length, not on a segment.
# The old version also asserted that `dirname` fails — GNU dirname is lexical and
# does not, and the guard no longer calls dirname at all, so that assertion tested
# neither the platform nor the code.
# Query the filesystem the fixture actually lives on, not `/`. The previous
# version also "self-validated" with a length check the build loop had already
# guaranteed — a check that cannot fail proves nothing, so it is gone; what is
# asserted instead is that the guard names the precondition it failed, which an
# ordinary absent path would also do, but which a silent pass would not.
_pmax=$(getconf PATH_MAX "$TMP" 2>/dev/null || true)
if ! [[ "$_pmax" =~ ^[0-9]+$ ]]; then
  echo "SKIP: cannot determine PATH_MAX for $TMP — over-long-path case NOT verified"
else
  _seg=$(printf 'a%.0s' {1..200})
  _long="$TMP"
  while [[ "${#_long}" -le "$_pmax" ]]; do _long="$_long/$_seg"; done
  out=$(bash "$GUARD" "$_long" 2>&1); got=$?
  if [[ "$got" -ne 0 ]] && printf '%s' "$out" | grep -q "NOT scanned"; then
    pass "a path over the platform PATH_MAX fails closed (${#_long} > $_pmax bytes)"
  else
    fail "over-long path: expected non-zero exit naming the failure, got exit $got"
    printf '%s\n' "$out" | sed 's/^/      /'
  fi
fi

# --- 7. the real tree --------------------------------------------------------
REPO_STATUS="$SCRIPT_DIR/../../../../../.kerby/STATUS.md"
if [[ -f "$REPO_STATUS" ]]; then
  if bash "$GUARD" "$REPO_STATUS" >/dev/null 2>&1; then
    pass "this repo's own .kerby/STATUS.md is clean"
  else
    fail "this repo's own .kerby/STATUS.md states provenance:"
    bash "$GUARD" "$REPO_STATUS" 2>&1 | sed 's/^/      /'
  fi
else
  fail "cannot find this repo's .kerby/STATUS.md at $REPO_STATUS"
fi

echo "---"
if [[ "$FAILS" -eq 0 ]]; then
  echo "All assertions passed."
  exit 0
else
  echo "$FAILS assertion(s) failed."
  exit 1
fi
