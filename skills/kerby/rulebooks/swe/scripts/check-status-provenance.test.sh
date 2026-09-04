#!/bin/bash
# Test for check-status-provenance.sh — ships in the same commit as the guard,
# because a guard with no test is an untested claim of safety
# (`skills/kerby/CLAUDE.md`). The removed commit-time-gate guard reported a clean
# run on a tree carrying four restatements; that is the failure this file exists
# to prevent for THIS guard.
#
# Run: bash skills/kerby/rulebooks/swe/scripts/check-status-provenance.test.sh
# Exit 0 = every case behaves as specified.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
GUARD="$SCRIPT_DIR/check-status-provenance.sh"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

# Run the guard on a fixture; assert exit code, and optionally that the output
# does/does not contain a substring.
expect() { # $1=label $2=expected-exit $3=fixture-content $4=must-contain(optional)
  local label="$1" want="$2" content="$3" needle="${4:-}"
  local f="$TMP/STATUS.md" out got
  printf '%s\n' "$content" > "$f"
  out=$(bash "$GUARD" "$f" 2>&1); got=$?
  if [[ "$got" -ne "$want" ]]; then
    fail "$label: expected exit $want, got $got"
    printf '%s\n' "$out" | sed 's/^/      /'
    return
  fi
  if [[ -n "$needle" ]] && ! printf '%s' "$out" | grep -q "$needle"; then
    fail "$label: exit $got correct, but output never mentioned '$needle'"
    printf '%s\n' "$out" | sed 's/^/      /'
    return
  fi
  pass "$label"
}

[[ -f "$GUARD" ]] || { echo "FAIL: cannot find $GUARD"; exit 1; }

# 1. A clean position-only file passes.
expect "clean file exits 0" 0 '# Project Status

## Current Position

| Field | Value |
|-------|-------|
| **Phase** | Implementation — the parser is behind the flag |
| **Milestone Goal** | Ship the parser to everyone |

## Next Up

| 1 | Turn the flag on | review |'

# 2. A version inside ordinary prose is caught, and the line is named.
#    This is the exact incident: a semver written from memory, not read.
expect "semver in prose fails" 1 '| **Milestone Goal** | Ship swe 2.11.2 to everyone |' "states a version"

# 3. A commit SHA is caught.
expect "7-char sha fails" 1 '| **Phase** | Shipped — merged as 095605e |' "states a sha"

# 4. A working branch is caught.
expect "branch name fails" 1 '| **Working Branch** | feature/minimal-first-planning |' "states a branch"

# 5. FALSE-POSITIVE PROBE. Hex-looking English words must NOT fire. Without this
#    case the guard could be tightened into something that blocks ordinary prose,
#    and the first person it annoys would delete it.
expect "hex-looking English words pass" 0 'The decision took a decade and the facade was added.
We faced a deed and abided by it.'

# 6. Several hits on one line are all reported, not just the first.
expect "multiple hits all reported" 1 '| Shipped 1.2.3 as 095605e on feature/x |' "states a branch"

# 7. A missing file is announced as SKIP, never as a bare pass.
rm -f "$TMP/STATUS.md"
out=$(bash "$GUARD" "$TMP/STATUS.md" 2>&1); got=$?
if [[ "$got" -eq 0 ]] && printf '%s' "$out" | grep -q "this is not a pass"; then
  pass "missing file exits 0 and says it is not a pass"
else
  fail "missing file: expected exit 0 with a SKIP notice, got exit $got"
  printf '%s\n' "$out" | sed 's/^/      /'
fi

# 8. The real tree must be clean — the guard is only worth shipping if the file
#    it governs already satisfies it.
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
