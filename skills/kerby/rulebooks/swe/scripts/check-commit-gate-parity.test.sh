#!/bin/bash
# Tests for check-commit-gate-parity.sh.
#
# Why this exists: the guard's FIRST version passed on a tree that carried four
# restatements it could not see. A guard that silently under-matches is worse
# than no guard — it converts "nobody checked" into "the check passed". Every
# phrasing an independent review found in the wild is pinned here as a
# must-catch case, so a future narrowing of the regex fails loudly.
#
# Run: bash skills/kerby/rulebooks/swe/scripts/check-commit-gate-parity.test.sh

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
GUARD="$SCRIPT_DIR/check-commit-gate-parity.sh"
RES="$SCRIPT_DIR/.."
FIXTURE="$RES/_commit-gate-parity-fixture.md"
EXEMPT="$RES/references/context-management.md"

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

cleanup() { rm -f "$FIXTURE" "$FIXTURE.bak" "$EXEMPT.testbak"; }
trap cleanup EXIT

# Baseline: the real tree must be clean, or every case below is meaningless.
if bash "$GUARD" >/dev/null 2>&1; then
  pass "baseline: current tree is clean"
else
  fail "baseline: current tree already fails the guard — fix that before trusting these tests"
  echo "---"; echo "$FAILS assertion(s) failed."; exit 1
fi

# $1 = label, $2 = line to plant in a scratch rulebook file, $3 = wanted exit code
case_line() {
  printf '%s\n' "$2" > "$FIXTURE"
  bash "$GUARD" >/dev/null 2>&1; local rc=$?
  rm -f "$FIXTURE"
  if [ "$rc" -eq "$3" ]; then pass "$1"; else fail "$1 (exit $rc, wanted $3)"; fi
}

# --- must CATCH: phrasings found in the wild by an independent review ---------
case_line "catches: Full gates must pass before every commit" \
  'Full gates must pass before every commit.' 1
case_line "catches: Commit check (full gates)" \
  'COMMIT - Commit check (full gates) + commit:' 1
case_line "catches: run full quality gates before committing" \
  '4. Commit check - run full quality gates before committing:' 1
case_line "catches: runs the full build/lint/test" \
  'the commit gate runs the full `build - lint - test` on every iteration' 1

# --- must CATCH: the phrasings the first version already handled -------------
case_line "catches: always run full gates" \
  'Then always run full gates before committing:' 1
case_line "catches: always run Standard" \
  'always run Standard gates before committing.' 1
case_line "catches: no commit goes out without <gate>" \
  'no commit goes out without build+lint+test passing.' 1

# --- must NOT catch: false-positive class ------------------------------------
case_line "ignores: no commit goes out without a signed-off ticket" \
  'no commit goes out without a signed-off ticket.' 0
case_line "ignores: ordinary deferral prose" \
  'Re-pick the tier from the staged diff; see quality-gates.md § At Commit Time.' 0

# --- exempt file is line-scoped, not blanket ---------------------------------
cp "$EXEMPT" "$EXEMPT.testbak"
printf '\n**Always run full gates before committing.**\n' >> "$EXEMPT"
bash "$GUARD" >/dev/null 2>&1
[ $? -eq 1 ] && pass "exempt file: a DIFFERENT restatement still fails" \
             || fail "exempt file: blanket exemption — a new restatement slipped through"
cp "$EXEMPT.testbak" "$EXEMPT"; rm -f "$EXEMPT.testbak"
bash "$GUARD" >/dev/null 2>&1
[ $? -eq 0 ] && pass "exempt file: restored, guard clean again" \
             || fail "exempt file: restore left the tree dirty"

# --- canonical rule cannot silently vanish -----------------------------------
CANON="$RES/references/quality-gates.md"
cp "$CANON" "$CANON.testbak"
sed 's/from the staged diff/from the vibes/g' "$CANON.testbak" > "$CANON"
bash "$GUARD" >/dev/null 2>&1
[ $? -eq 1 ] && pass "canonical: losing the rule text fails the guard" \
             || fail "canonical: rule text vanished and the guard still passed"
cp "$CANON.testbak" "$CANON"; rm -f "$CANON.testbak"

echo "---"
if [ "$FAILS" -eq 0 ]; then echo "All assertions passed."; exit 0; fi
echo "$FAILS assertion(s) failed."; exit 1
