#!/bin/bash
# Lint: the commit-time gate rule should be stated in exactly ONE place.
#
# `references/quality-gates.md` § At Commit Time is the single authority for
# which gate tier a commit runs. Every other rulebook file should DEFER to it,
# never restate it. This script catches the restatement drift that has bitten
# this corpus repeatedly (six files at its worst, one of them BOOTSTRAP.md,
# which loads eagerly into every session).
#
# WHAT THIS IS, HONESTLY: a heuristic lint over natural-language prose, not a
# proof of the invariant. Two earlier versions claimed more than they delivered
# — the first matched three literal phrasings and passed on a tree carrying four
# more; the second was bypassed by ordinary mandates an independent review wrote
# in seconds ("Every commit requires Standard gates"). Enumerating phrasings is
# a losing game, so this version matches on STRUCTURE instead: a commit-time
# referent within a couple of lines of a totality word, minus anything that
# visibly defers to the canonical section. That is meaningfully harder to trip
# over by accident. It is still defeatable by someone trying. Treat a clean run
# as "no known drift pattern found", never as "the invariant holds" — the
# independent review remains the check that actually reads for meaning.
#
# Run: bash skills/kerby/rulebooks/swe/scripts/check-commit-gate-parity.sh
# Exit 0 = no drift pattern found; non-zero = a probable restatement, the
# canonical rule went missing, or a scan failed.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
RES="$SCRIPT_DIR/.."   # this script lives in <swe-root>/scripts/; RES is the swe root

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

CANONICAL="references/quality-gates.md"
CANONICAL_HEADER="### At Commit Time"

# Deliberate, documented exception: the shutdown ritual overrides tier gating on
# purpose. Pinned to the ONE known sentence — not the whole file, and not a bare
# substring: an ADDITIONAL absolute appended to the same line must still fail.
EXEMPT="references/context-management.md"
EXEMPT_LINE_MATCH='Verify — always run full quality gates\.\*\* Execute'

# A commit-time referent: the line is talking about the gate at commit time.
COMMIT_REF='commit gate|commit check|before committ|before every commit|every commit|at commit time|no commit goes out|prior to committ'
# A totality claim: it says the gate is the whole thing, unconditionally.
TOTALITY='always|full gate|full quality gate|full suite|complete gate|no exceptions|standard gates|the full .?build|build.{0,12}lint.{0,12}test'
# Deferral markers: the line (or its neighbours) points at the authority instead
# of restating it. Presence of any of these clears the line.
DEFERS='quality-gates\.md|At Commit Time|staged diff|single authority|re-pick the tier|tier the staged|selected tier|tier from the'

echo "Canonical authority: $CANONICAL ($CANONICAL_HEADER)"
echo "Scoped exception:    $EXEMPT — the documented shutdown sentence only"
echo "Nature:              heuristic lint, not a proof — see header comment"
echo "---"

# ---------------------------------------------------------------------------
# 1. The canonical SECTION must still state the rule.
#    Section = from an EXACT `### At Commit Time` line to the next header of the
#    same OR higher level (`## ` or `### `). Stopping only at `### ` let the
#    section bleed into every following `##` section, which made the scoping
#    fake — phrases could live anywhere later in the file and still pass.
# ---------------------------------------------------------------------------
SECTION=$(awk -v h="$CANONICAL_HEADER" '
  $0 == h { f = 1; next }
  f && (/^## / || /^### /) { exit }
  f { print }
' "$RES/$CANONICAL" 2>/dev/null)

if [ -z "$SECTION" ]; then
  fail "canonical section '$CANONICAL_HEADER' not found (or empty) in $CANONICAL"
else
  for phrase in "from the staged diff" "no file any gate reads"; do
    if printf '%s' "$SECTION" | grep -qF "$phrase"; then
      pass "canonical section states \"$phrase\""
    else
      fail "canonical section no longer states \"$phrase\" — the rule moved or vanished"
    fi
  done
fi

# ---------------------------------------------------------------------------
# 2. No other rulebook prose may restate the rule as an absolute.
#    Structural match with a 2-line deferral window: a restatement that cites
#    the authority on the same line or immediately around it is a pointer, not
#    a second source of truth.
# ---------------------------------------------------------------------------
FILES=$(find "$RES" -name '*.md' -type f 2>/dev/null); FIND_RC=$?
if [ "$FIND_RC" -ne 0 ]; then
  fail "tree scan failed (find exit $FIND_RC) — results would be incomplete"
fi

OFFENDERS=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  rel="${f#"$RES"/}"
  [ "$rel" = "$CANONICAL" ] && continue

  hits=$(awk -v cref="$COMMIT_REF" -v tot="$TOTALITY" -v def="$DEFERS" '
    # A totality word must sit within PROX characters of a commit-time referent.
    # Line-level co-occurrence is too coarse: one 3000-char reference-table row
    # paired "before committing to a swap" with "always-on-hook" and tripped it.
    function near(line,   s, pos, absstart, winstart, win) {
      s = line; pos = 0
      while (match(s, cref)) {
        absstart = pos + RSTART
        winstart = absstart - PROX; if (winstart < 1) winstart = 1
        win = substr(line, winstart, (2 * PROX) + RLENGTH)
        if (win ~ tot) return 1
        pos = pos + RSTART + RLENGTH - 1
        s = substr(s, RSTART + RLENGTH)
        if (s == "") break
      }
      return 0
    }
    BEGIN { PROX = 120 }
    { lines[NR] = $0 }
    END {
      for (i = 1; i <= NR; i++) {
        if (near(tolower(lines[i]))) {
          # deferral window: this line and its immediate neighbours
          w = tolower(lines[i-1] "\n" lines[i] "\n" lines[i+1])
          if (w ~ def) continue
          printf "%d:%s\n", i, lines[i]
        }
      }
    }
  ' "$f" 2>/dev/null); rc=$?
  if [ "$rc" -ne 0 ]; then
    fail "scan failed on $rel (awk exit $rc)"
    continue
  fi
  [ -n "$hits" ] || continue

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ "$rel" = "$EXEMPT" ] && printf '%s' "$line" | grep -qE "$EXEMPT_LINE_MATCH"; then
      # Allowed only if the line is the documented sentence and carries no
      # SECOND absolute beyond it.
      rest=$(printf '%s' "$line" | sed -E 's/.*Verify — always run full quality gates\.\*\* Execute//')
      if printf '%s' "$rest" | grep -qEi "$TOTALITY"; then
        OFFENDERS="${OFFENDERS}${rel}:${line}"$'\n'
      fi
      continue
    fi
    OFFENDERS="${OFFENDERS}${rel}:${line}"$'\n'
  done <<< "$hits"
done <<< "$FILES"

if [ -n "$OFFENDERS" ]; then
  fail "commit-gate rule appears restated outside $CANONICAL:"
  printf '%s' "$OFFENDERS" | sed 's/^/       /'
  echo "       -> defer to $CANONICAL $CANONICAL_HEADER instead of restating it."
  echo "       (If a hit is a false positive, cite the authority on or beside the line.)"
else
  pass "no restatement pattern found outside the canonical file"
fi

echo "---"
if [ "$FAILS" -eq 0 ]; then
  echo "All assertions passed."
  exit 0
fi
echo "$FAILS assertion(s) failed."
exit 1
