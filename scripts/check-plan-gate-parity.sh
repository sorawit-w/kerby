#!/bin/bash
# Parity: the Plan Gate constants must agree across the files that restate them.
#
# The plan_threshold DEFAULT (4) and the fixed APPROVAL point (grade >= 7) are
# hardcoded in BOTH resources/BOOTSTRAP.md (§2.5 / §4) and
# resources/workflows/feature.md (§3). Each file must stand alone, so the values
# are deliberately duplicated -- but nothing stopped them drifting when one file
# is edited and the others aren't. This does.
#
# Mirrors the glob-parity guard in hooks/route-high-stakes.test.sh: same
# teeth-bearing shape, so the two docs can't silently disagree.
#
# Run: bash scripts/check-plan-gate-parity.sh
# Exit 0 = constants agree and the cap invariant holds; non-zero = drift,
# a missing constant, or default > approval.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
BOOTSTRAP="$SCRIPT_DIR/../skills/kerby/resources/BOOTSTRAP.md"
FEATURE="$SCRIPT_DIR/../skills/kerby/resources/workflows/feature.md"

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

for f in "$BOOTSTRAP" "$FEATURE"; do
  [[ -f "$f" ]] || { fail "cannot find $f"; }
done
[[ "$FAILS" -eq 0 ]] || { echo "---"; echo "$FAILS assertion(s) failed."; exit 1; }

# Default plan_threshold: the digit in "default <N>" on a planThreshold line.
# BOOTSTRAP renders it "default **4**"; feature.md renders it "default 4".
# Returns every DISTINCT value found (one per line) — see uniq_or_fail below.
extract_default() { # $1=file
  grep -iE 'planThreshold' "$1" | grep -oE 'default \**[0-9]+' | grep -oE '[0-9]+' | sort -u
}

# Fixed approval point: the N in "grade >= N" / "capped at N". The >= is the
# Unicode glyph (U+2265) in both files. Returns every DISTINCT value found.
extract_approval() { # $1=file
  grep -oE 'capped at [0-9]+|≥ ?[0-9]+' "$1" | grep -oE '[0-9]+' | sort -u
}

# A file must state exactly ONE value per constant. Zero = the constant was
# dropped; more than one = a stale+updated pair drifting WITHIN the file (e.g.
# the main rule says "≥ 8" but a "capped at 7" line was left behind). Collapsing
# that with head -1 would let the gate pass on the exact inconsistency it exists
# to catch — so treat it as a failure, then compare the single values across files.
uniq_or_fail() { # $1=label ; $2=raw multiline values ; sets VALUE
  local label="$1" raw="$2" n
  n=$(printf '%s\n' "$raw" | grep -c .)
  if   [[ "$n" -eq 0 ]]; then VALUE=""; fail "$label: constant not found"
  elif [[ "$n" -gt 1 ]]; then VALUE=""; fail "$label: conflicting values within file -> $(printf '%s' "$raw" | tr '\n' ',' | sed 's/,$//')"
  else VALUE="$raw"; pass "$label states one value ($raw)"
  fi
}

uniq_or_fail "BOOTSTRAP plan_threshold default"  "$(extract_default "$BOOTSTRAP")";  bs_default="$VALUE"
uniq_or_fail "feature.md plan_threshold default" "$(extract_default "$FEATURE")";    ft_default="$VALUE"
uniq_or_fail "BOOTSTRAP approval point"          "$(extract_approval "$BOOTSTRAP")"; bs_approval="$VALUE"
uniq_or_fail "feature.md approval point"         "$(extract_approval "$FEATURE")";   ft_approval="$VALUE"

# --- Cross-file agreement (the real anti-drift teeth) ------------------------
if [[ -n "$bs_default" && -n "$ft_default" ]]; then
  [[ "$bs_default" == "$ft_default" ]] \
    && pass "default agrees across files ($bs_default)" \
    || fail "default DRIFT: BOOTSTRAP=$bs_default vs feature.md=$ft_default"
fi
if [[ -n "$bs_approval" && -n "$ft_approval" ]]; then
  [[ "$bs_approval" == "$ft_approval" ]] \
    && pass "approval point agrees across files ($bs_approval)" \
    || fail "approval DRIFT: BOOTSTRAP=$bs_approval vs feature.md=$ft_approval"
fi

# --- Documented invariant: plan_threshold is "capped at" the approval point --
if [[ -n "$bs_default" && -n "$bs_approval" ]]; then
  [[ "$bs_default" -le "$bs_approval" ]] \
    && pass "invariant holds: default ($bs_default) <= approval ($bs_approval)" \
    || fail "invariant broken: default ($bs_default) > approval ($bs_approval)"
fi

echo "---"
if [[ "$FAILS" -eq 0 ]]; then
  echo "All assertions passed."
  exit 0
else
  echo "$FAILS assertion(s) failed."
  exit 1
fi
