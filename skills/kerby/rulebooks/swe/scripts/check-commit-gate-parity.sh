#!/bin/bash
# Parity: the commit-time gate rule must be stated in exactly ONE place.
#
# `references/quality-gates.md` § At Commit Time is the single authority for
# which gate tier a commit runs. The rule is prose, not a numeric constant, so
# the sibling guard (check-plan-gate-parity.sh) cannot cover it — but the drift
# mode is identical and has bitten twice: a second file restates the rule as an
# absolute ("always run full gates before committing"), the two disagree, and an
# agent reading both has to adjudicate a live rule conflict mid-task.
#
# That is what this guard exists to stop. It is a NEGATIVE check: no file other
# than the canonical one may assert an unconditional full gate at commit time.
# It also asserts the canonical file still states the rule, so the rule cannot
# silently vanish and leave the corpus saying nothing at all.
#
# Run: bash skills/kerby/rulebooks/swe/scripts/check-commit-gate-parity.sh
# Exit 0 = one authority, rule present; non-zero = a restatement reappeared, or
# the canonical statement went missing.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
RES="$SCRIPT_DIR/.."   # this script lives in <swe-root>/scripts/; RES is the swe root

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

# The one file allowed to state the commit-time tier rule.
CANONICAL="references/quality-gates.md"

# Deliberate, documented exception: the shutdown ritual overrides complexity/tier
# gating on purpose and says so in its own prose (see that file's own note on why
# it does not defer to the tier table). Listed here so the exception is explicit
# rather than a silent hole in the pattern.
EXEMPT="references/context-management.md"

# Phrasings that assert an UNCONDITIONAL full gate at commit time. Deliberately
# narrow: they match the absolute form, not ordinary references to running gates.
ABSOLUTES='always run (the )?full gate|always run Standard|no commit goes out without'

echo "Canonical authority: $CANONICAL"
echo "Documented exception: $EXEMPT"
echo "---"

# 1. The canonical file must still state the rule. Two load-bearing phrases: the
#    staged-diff selection, and the definition of the docs carve-out.
for phrase in "from the staged diff" "no file any gate reads"; do
  if grep -qF "$phrase" "$RES/$CANONICAL" 2>/dev/null; then
    pass "canonical states \"$phrase\""
  else
    fail "canonical $CANONICAL no longer states \"$phrase\" — the rule went missing"
  fi
done

# 2. No other rulebook prose may restate the absolute form.
OFFENDERS=""
while IFS= read -r f; do
  rel="${f#"$RES"/}"
  [ "$rel" = "$CANONICAL" ] && continue
  [ "$rel" = "$EXEMPT" ] && continue
  hits=$(grep -nEi "$ABSOLUTES" "$f" 2>/dev/null) || continue
  [ -n "$hits" ] || continue
  while IFS= read -r line; do
    OFFENDERS="${OFFENDERS}${rel}:${line}"$'\n'
  done <<< "$hits"
done < <(find "$RES" -name '*.md' -type f)

if [ -n "$OFFENDERS" ]; then
  fail "commit-gate rule restated outside $CANONICAL:"
  printf '%s' "$OFFENDERS" | sed 's/^/       /'
  echo "       -> defer to $CANONICAL § At Commit Time instead of restating it."
else
  pass "no restatement of the absolute commit-gate form outside the canonical file"
fi

echo "---"
if [ "$FAILS" -eq 0 ]; then
  echo "All assertions passed."
  exit 0
fi
echo "$FAILS assertion(s) failed."
exit 1
