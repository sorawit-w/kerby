#!/bin/bash
# Parity: the commit-time gate rule must be stated in exactly ONE place.
#
# `references/quality-gates.md` § At Commit Time is the single authority for
# which gate tier a commit runs. The rule is prose, not a numeric constant, so
# the sibling guard (check-plan-gate-parity.sh) cannot cover it — but the drift
# mode is identical and has bitten repeatedly: another file restates the rule as
# an absolute ("always run full gates before committing"), the two disagree, and
# an agent reading both adjudicates a live rule conflict mid-task.
#
# NEGATIVE check: no file other than the canonical one may assert an
# unconditional full/Standard gate at commit time. It also asserts the canonical
# section still states the rule, so the rule cannot silently vanish.
#
# Run: bash skills/kerby/rulebooks/swe/scripts/check-commit-gate-parity.sh
# Exit 0 = one authority, rule present; non-zero = a restatement reappeared, the
# canonical statement went missing, or a scan failed.
#
# History: the first version of this guard matched only three phrasings and
# passed on a tree carrying four more restatements ("Full gates must pass before
# every commit", "Commit check (full gates)", "run full quality gates before
# committing", "runs the full build · lint · test"). An independent review caught
# them. The pattern set below is deliberately phrase-family-based, not
# literal-string-based, for that reason.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
RES="$SCRIPT_DIR/.."   # this script lives in <swe-root>/scripts/; RES is the swe root

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

# The one file allowed to state the commit-time tier rule.
CANONICAL="references/quality-gates.md"
CANONICAL_SECTION="### At Commit Time"

# Deliberate, documented exception: the shutdown ritual overrides tier gating on
# purpose (that file explains why in its own prose). Scoped to the ONE known
# line, not the whole file — a different restatement appearing there must still
# fail, which a blanket file exemption would hide.
EXEMPT="references/context-management.md"
EXEMPT_ALLOW='Verify — always run full quality gates'

# Phrasings asserting an UNCONDITIONAL full/Standard gate at commit time.
# Phrase-family based: each alternative is a way of saying "the commit gate is
# always the full one", not one literal sentence.
ABSOLUTES='always run (the )?full (quality )?gates?'
ABSOLUTES="$ABSOLUTES"'|always run Standard'
ABSOLUTES="$ABSOLUTES"'|full (quality )?gates? must (pass|run)'
ABSOLUTES="$ABSOLUTES"'|run full (quality )?gates? before committ'
ABSOLUTES="$ABSOLUTES"'|commit check \(full gates\)'
ABSOLUTES="$ABSOLUTES"'|runs the full .?build'
# Narrowed: requires a gate-ish object nearby, so "no commit goes out without a
# signed-off ticket" no longer matches.
ABSOLUTES="$ABSOLUTES"'|no commit goes out without[^.]{0,60}(gate|build|lint|test)'

echo "Canonical authority: $CANONICAL ($CANONICAL_SECTION)"
echo "Scoped exception:    $EXEMPT — only the documented shutdown line"
echo "---"

# 1. The canonical SECTION must still state the rule. Scoped to the section, not
#    the whole file: a stray mention elsewhere (or a negated one) must not
#    satisfy this.
SECTION=$(awk -v h="$CANONICAL_SECTION" '
  index($0,h)==1 {f=1; next}
  f && /^### / {exit}
  f {print}
' "$RES/$CANONICAL" 2>/dev/null)

if [ -z "$SECTION" ]; then
  fail "canonical section '$CANONICAL_SECTION' not found in $CANONICAL"
else
  for phrase in "from the staged diff" "no file any gate reads"; do
    if printf '%s' "$SECTION" | grep -qF "$phrase"; then
      pass "canonical section states \"$phrase\""
    else
      fail "canonical section no longer states \"$phrase\" — the rule went missing"
    fi
  done
fi

# 2. No other rulebook prose may restate the absolute form.
OFFENDERS=""
while IFS= read -r f; do
  rel="${f#"$RES"/}"
  [ "$rel" = "$CANONICAL" ] && continue
  hits=$(grep -nEi "$ABSOLUTES" "$f" 2>/dev/null); rc=$?
  # grep: 0 = matched, 1 = no match, >1 = real error. Never treat an error as clean.
  if [ "$rc" -gt 1 ]; then
    fail "scan failed on $rel (grep exit $rc)"
    continue
  fi
  [ "$rc" -eq 0 ] || continue
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    # Scoped exception: allowed only for the documented line in the exempt file.
    if [ "$rel" = "$EXEMPT" ] && printf '%s' "$line" | grep -qE "$EXEMPT_ALLOW"; then
      continue
    fi
    OFFENDERS="${OFFENDERS}${rel}:${line}"$'\n'
  done <<< "$hits"
done < <(find "$RES" -name '*.md' -type f)

if [ -n "$OFFENDERS" ]; then
  fail "commit-gate rule restated outside $CANONICAL:"
  printf '%s' "$OFFENDERS" | sed 's/^/       /'
  echo "       -> defer to $CANONICAL $CANONICAL_SECTION instead of restating it."
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
