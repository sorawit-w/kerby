#!/bin/bash
# Tests for check-commit-gate-parity.sh.
#
# Why this exists: the guard's FIRST version passed on a tree that carried four
# restatements it could not see. A guard that silently under-matches is worse
# than no guard — it converts "nobody checked" into "the check passed". Every
# phrasing found in the wild is pinned here as a must-catch case, so a future
# narrowing of the pattern set fails loudly.
#
# SAFETY: this test NEVER mutates the working tree. It copies the rulebook to a
# temp dir and runs the copied guard against copied files. An earlier version
# mutated real tracked files (context-management.md, quality-gates.md) and its
# EXIT trap only *deleted* paths — including the backups — so an interrupt
# between mutation and restore left the repo corrupted with the backup gone.
# Operating on a disposable copy removes that failure mode by construction
# rather than by careful cleanup.
#
# Run: bash skills/kerby/rulebooks/swe/scripts/check-commit-gate-parity.test.sh

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
SRC="$SCRIPT_DIR/.."          # the real swe rulebook root — READ ONLY in this test

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/kerby-parity-test.XXXXXX")" || {
  echo "FAIL: could not create temp dir"; exit 1
}
cleanup() { [ -n "${WORK:-}" ] && [ -d "$WORK" ] && rm -rf "$WORK"; }
trap cleanup EXIT INT TERM

# Disposable copy of the rulebook. The guard resolves its own root from its
# location, so the copied guard scans the copied tree.
cp -R "$SRC"/. "$WORK"/ 2>/dev/null || { echo "FAIL: could not copy rulebook"; exit 1; }
GUARD="$WORK/scripts/check-commit-gate-parity.sh"
FIXTURE="$WORK/_commit-gate-parity-fixture.md"
EXEMPT="$WORK/references/context-management.md"
CANON="$WORK/references/quality-gates.md"

[ -f "$GUARD" ] || { echo "FAIL: guard not found in the copy"; exit 1; }

# Baseline: the pristine copy must be clean, or every case below is meaningless.
if bash "$GUARD" >/dev/null 2>&1; then
  pass "baseline: pristine rulebook copy is clean"
else
  fail "baseline: the rulebook itself fails the guard — fix that before trusting these tests"
  echo "---"; echo "$FAILS assertion(s) failed."; exit 1
fi

# $1 = label, $2 = line planted in a scratch file inside the copy, $3 = wanted exit
case_line() {
  printf '%s\n' "$2" > "$FIXTURE"
  bash "$GUARD" >/dev/null 2>&1; local rc=$?
  rm -f "$FIXTURE"
  if [ "$rc" -eq "$3" ]; then pass "$1"; else fail "$1 (exit $rc, wanted $3)"; fi
}

# --- must CATCH: phrasings found in the wild by independent review ------------
case_line "catches: Full gates must pass before every commit" \
  'Full gates must pass before every commit.' 1
case_line "catches: Commit check (full gates)" \
  'COMMIT - Commit check (full gates) + commit:' 1
case_line "catches: run full quality gates before committing" \
  '4. Commit check - run full quality gates before committing:' 1
case_line "catches: runs the full build/lint/test" \
  'the commit gate runs the full `build - lint - test` on every iteration' 1
case_line "catches: always run full gates" \
  'Then always run full gates before committing:' 1
case_line "catches: always run Standard" \
  'always run Standard gates before committing.' 1
case_line "catches: no commit goes out without <gate>" \
  'no commit goes out without build+lint+test passing.' 1

# --- must CATCH: mandate phrasings an independent review constructed ----------
# These bypassed an earlier pattern set; they are pinned so a future narrowing
# cannot silently reopen the hole.
case_line "catches: Every commit requires Standard gates" \
  'Every commit requires Standard gates.' 1
case_line "catches: before every commit the complete gate must pass" \
  'Before every commit, the complete gate - build, lint, and test - must pass.' 1
case_line "catches: the commit gate is always the full suite" \
  'The commit gate is always the full suite: build, lint, and test.' 1

# --- must NOT catch: false-positive class ------------------------------------
case_line "ignores: no commit goes out without a signed-off ticket" \
  'no commit goes out without a signed-off ticket.' 0
case_line "ignores: ordinary deferral prose" \
  'Re-pick the tier from the staged diff; see quality-gates.md § At Commit Time.' 0
case_line "ignores: prose about the iteration check" \
  'During iteration, run the cheap check for what you are touching.' 0

# --- exempt file is line-scoped, not blanket ---------------------------------
printf '\n**Always run full gates before committing.**\n' >> "$EXEMPT"
bash "$GUARD" >/dev/null 2>&1
[ $? -eq 1 ] && pass "exempt file: a DIFFERENT restatement still fails" \
             || fail "exempt file: blanket exemption — a new restatement slipped through"
cp "$SRC/references/context-management.md" "$EXEMPT"

# An extra absolute appended to the SAME line as the allowed one must still fail.
perl -pi -e 's/(Verify — always run full quality gates\.)/$1 Always run Standard before every commit./' "$EXEMPT" 2>/dev/null
if grep -q "Always run Standard before every commit" "$EXEMPT"; then
  bash "$GUARD" >/dev/null 2>&1
  [ $? -eq 1 ] && pass "exempt line: a second absolute on the allowed line still fails" \
               || fail "exempt line: substring exemption swallowed an added absolute"
else
  echo "SKIP: could not construct the same-line case (perl unavailable)"
fi
cp "$SRC/references/context-management.md" "$EXEMPT"

# --- canonical rule cannot silently vanish or migrate ------------------------
sed 's/from the staged diff/from the vibes/g' "$CANON" > "$CANON.tmp" && mv "$CANON.tmp" "$CANON"
bash "$GUARD" >/dev/null 2>&1
[ $? -eq 1 ] && pass "canonical: losing the rule text fails the guard" \
             || fail "canonical: rule text vanished and the guard still passed"
cp "$SRC/references/quality-gates.md" "$CANON"

# The required phrases must live in the At Commit Time section, not merely
# somewhere in the file — moving them to a later section must fail.
awk '
  /^### At Commit Time/ {inac=1}
  inac && /from the staged diff/ {next}
  inac && /no file any gate reads/ {next}
  {print}
  END {print "\n### Appendix\n\nfrom the staged diff and no file any gate reads\n"}
' "$SRC/references/quality-gates.md" > "$CANON"
bash "$GUARD" >/dev/null 2>&1
[ $? -eq 1 ] && pass "canonical: phrases moved out of the section fail the guard" \
             || fail "canonical: section scoping is not real — a later section satisfied it"
cp "$SRC/references/quality-gates.md" "$CANON"

# --- the real tree must be untouched by this test ----------------------------
if [ -e "$SRC/_commit-gate-parity-fixture.md" ]; then
  fail "hygiene: test left a fixture in the real rulebook"
else
  pass "hygiene: real rulebook untouched (all mutation happened in the temp copy)"
fi

echo "---"
if [ "$FAILS" -eq 0 ]; then echo "All assertions passed."; exit 0; fi
echo "$FAILS assertion(s) failed."; exit 1
