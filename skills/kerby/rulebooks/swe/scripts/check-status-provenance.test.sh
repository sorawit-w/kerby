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
# Both found by adversarial review: a six-char abbreviation still resolves to a
# real commit, and an uppercase one is still a SHA.
expect "6-char abbreviated sha fails" 1 'Reviewed at 095605 last night.' "states a sha"
expect "uppercase sha fails" 1 'Reviewed at 095605E last night.' "states a sha"
# FALSE POSITIVE, and the reason the digit rule exists. "defaced" is 7 chars of
# pure hex letters; the earlier guard flagged it. Its own header documented that
# as an accepted miss while this test claimed English words pass — the two
# disagreed, so the guard changed rather than the claim.
expect "hex-spelled English words pass" 0 'A decade later the facade was defaced; DEFACED again in June.'

# --- 4. branches -------------------------------------------------------------
# All seven types in communication.md § Branch Naming must be caught. `wip`,
# `docs` and `test` were missing from the first version.
for ty in feature fix refactor test docs chore wip; do
  expect "branch type '$ty' fails" 1 "Working on $ty/status-cleanup now." "states a branch"
done
# FALSE POSITIVES: the type must be a whole word, and path-shaped tokens are not
# branches. "prefix/name" hit the `fix` inside "prefix" in the first version.
expect "type inside a longer word is not a branch" 0 'Use the prefix/name pair; the suffix/value pair mirrors it.'
expect "nested source path is not a branch" 0 'Edit src/feature/parser.ts and src/fix/apply.ts.'
expect "doc path with an extension is not a branch" 0 'See docs/rulebook-contract.md and test/fixtures/a.md.'
# Documented ceiling, asserted so it stays a known gap rather than an assumption:
# a BARE protected-branch name is ordinary English and is not matched.
expect "bare protected branch name is a documented miss" 0 'That is the main reason we did it; dev follows.'

# --- 5. reporting quality ----------------------------------------------------
# All three categories on one line must ALL be reported. Asserting only one lets
# the other two silently stop working.
expect "every category on one line is reported" 1 '| Shipped 1.2.3 as 095605e on feature/x |' \
  "states a version" "states a sha" "states a branch"
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
printf 'swe 2.11.3 at 095605e on fix/x\n' > "$UNREADABLE"
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

# A missing file is a different case: nothing to check, announced as SKIP so it
# can never read as a green assertion.
out=$(bash "$GUARD" "$TMP/nope.md" 2>&1); got=$?
if [[ "$got" -eq 0 ]] && printf '%s' "$out" | grep -q "this is not a pass"; then
  pass "missing file exits 0 and says it is not a pass"
else
  fail "missing file: expected exit 0 with a SKIP notice, got exit $got"
  printf '%s\n' "$out" | sed 's/^/      /'
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
