#!/bin/bash
# Parity: every hook script must DECLARE the canonical disable block that its manifest
# TIER calls for.
#
# WHAT THIS CHECKS, AND WHAT IT DOES NOT — read this before trusting a green run.
# The rule in docs/rulebook-contract.md § Hook tiers is about runtime behavior: a hook
# honors CODING_RULES_HOOK_DISABLED iff its tier is `optional`. This script does NOT
# verify runtime behavior. It verifies the weaker, checkable claim that the script
# declares — or does not declare — kerby's canonical disable block, matching its tier.
#
# The distinction is load-bearing and was learned the hard way. Three review rounds
# defeated successive attempts to infer behavior from text: an arm naming a different
# token, `exit 2`, `exit 01`, a commented-out block, an earlier shadowing arm, and a
# canonical block inside a heredoc. Bash has too many ways to express "exit early" for
# a text scan to be right about all of them, and a guard that is wrong about one is a
# false green — the artifact skills/kerby/CLAUDE.md calls the worst this repo can hold.
# So the claim was narrowed to fit the evidence instead of the evidence being stretched
# to fit the claim.
#
# What survives the narrowing is the drift this guard exists for: a new hook that
# forgets its block, a block naming the wrong token, and a `severity`/`floor` flip that
# moves a hook between tiers. What it CANNOT catch is a hook that disables itself by
# some mechanism other than the canonical block — it will report "declares no disable
# block", which is true, without noticing the hook is disablable anyway. Catching that
# needs a behavioral harness (run each hook with and without the variable, compare),
# which needs a triggering payload per hook. That trade is open, not overlooked.
#
# THE TIER RULE (docs/rulebook-contract.md § Hook tiers is the authority):
#   A hook honors CODING_RULES_HOOK_DISABLED  <=>  its tier is `optional`.
# Tiers derive from two [[check]] fields, never a hand-kept list:
#   floor = true                       -> locked       (must REFUSE the token)
#   severity = "block", not floor      -> recommended  (must REFUSE the token)
#   severity = warn|info               -> optional     (must HONOR the token)
#   engine services (no [[check]])     -> optional     (must HONOR the token)
#
# Why a guard and not prose: the hook set has relocated four times (v9.0 code->swe
# rename, v9.3 hollow-test moving out of base, v9.16 git_hook), and the hand-written
# table in resources/references/hooks.md fell behind each time — it omitted one
# rulebook's enforcer entirely. The correspondence is also invisible to a human reading the
# files, which is exactly when a machine check earns its place.
#
# SHAPE NOTES — both of these produced CONFIDENTLY WRONG answers during design, so
# neither shortcut may be reintroduced:
#   1. NEVER filter scripts by the SUBSTRING "test" (e.g. `grep -v test`). That silently
#      drops hollow-test-check.sh, whose own filename contains it. Enforcers come from
#      [[check]].enforcer in the manifests; engine services are globbed with a `.test.sh`
#      SUFFIX exclusion, which is precise where the substring is not.
#   2. NEVER match the bare token CODING_RULES_HOOK_DISABLED. protect-env.sh and
#      protect-git.sh both mention it in COMMENTS that say they
#      REFUSE it. Only a canonical arm inside the `case` block counts, the block must
#      not be heredoc data, and the token must sit in the arm's PATTERN — a trailing
#      comment carrying ",<token>," once satisfied an arm that named something else.
# And per skills/kerby/CLAUDE.md: a guard that under-matches converts "nobody checked"
# into "the check passed". So anything this script cannot classify is an ERROR, never
# a silent pass.
#
# This guard belongs to repo maintenance, not engine runtime — it lives beside
# check-skill-compat.py and does not ship inside the skill bundle.
#
# Run: bash scripts/check-hook-disable-tier.sh
# Exit 0 = every enumerated script agrees with its tier and nothing was unclassifiable;
# non-zero = a mismatch, a missing file, an unparseable manifest block, or an
# unclassifiable script.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
ROOT="${KERBY_ROOT:-$SCRIPT_DIR/..}"          # repo root; overridable so the test can
SKILL="$ROOT/skills/kerby"                    # run the guard against a mutated COPY

FAILS=0
UNCLASSIFIED=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }
# An unclassifiable input is its own outcome: it is neither agreement nor a known
# mismatch, and reporting it as either would be the false-green this guard exists to
# prevent.
unclassified() { echo "ERROR: $1"; UNCLASSIFIED=$((UNCLASSIFIED + 1)); FAILS=$((FAILS + 1)); }

# Manifests are DISCOVERED, never listed. An earlier draft hardcoded the four builtin
# paths, reasoning that a missing one would then fail loudly. That was backwards twice
# over: the pre-flight only notices a listed file going *missing*, so a newly ADDED
# rulebook was skipped in silence — the exact under-coverage this guard exists to
# prevent — and naming builtins made engine machinery key on rulebook identity, which
# docs/rulebook-contract.md § Engine independence forbids. A glob has neither problem.
MANIFESTS=()
for m in "$SKILL"/rulebooks/*/rulebook.toml; do
  [[ -f "$m" ]] && MANIFESTS[${#MANIFESTS[@]}]="$m"
done
[[ ${#MANIFESTS[@]} -gt 0 ]] || fail "no rulebook manifests found under $SKILL/rulebooks/"

# Engine services likewise. Per contract § Hook tiers rule 3, tier is a property of the
# hook, not of registration: every engine service is `optional`, including the ones
# `install` never registers, so all of them must honor the token.
# Excluding `*.test.sh` by SUFFIX is safe; excluding the substring "test" would not be —
# that shortcut silently drops rulebooks/swe/hooks/hollow-test-check.sh, whose own name
# contains "test". Same trap, one directory over.
ENGINE_SERVICES=()
for s in "$SKILL"/resources/hooks/*.sh; do
  case "$s" in *.test.sh) continue ;; esac
  [[ -f "$s" ]] && ENGINE_SERVICES[${#ENGINE_SERVICES[@]}]="$s"
done
[[ ${#ENGINE_SERVICES[@]} -gt 0 ]] || fail "no engine-service hooks found under $SKILL/resources/hooks/"
[[ "$FAILS" -eq 0 ]] || { echo "---"; echo "$FAILS assertion(s) failed."; exit 1; }

# Does this script honor the disable list FOR ITS OWN NAME?
#
# This function is deliberately a RECOGNIZER, not a parser. Three earlier drafts tried
# to understand the arm — grep for the token, separately grep for `exit 0` — and a
# review defeated every one: an arm naming a DIFFERENT token passed, `exit 2` passed,
# `exit 01` satisfied an unbounded `exit 0`, a commented-out block read as live code,
# and a token on a different line from its `exit 0` was misjudged both ways. The
# user-visible bug behind the first: `CODING_RULES_HOOK_DISABLED=warn-env-read` would
# not have disabled warn-env-read, and the guard would have called that agreement.
#
# The lesson was not "write a better regex" — it was that inferring runtime behavior
# from bash text cannot be made sound by pattern-matching. So this recognizes the one
# canonical form the repo actually ships and refuses to guess about anything else.
# Deviations are `noncanonical`, which is an ERROR (a failed run), never a pass.
#
# Echoes yes / no / wrongtoken / noncanonical / noname / missing.
honors_token() { # $1=absolute script path
  [[ -f "$1" ]] || { echo "missing"; return; }

  local name
  name=$(sed -n 's/^#[[:space:]]*Name:[[:space:]]*//p' "$1" | head -1 | tr -d '[:space:]')
  [[ -n "$name" ]] || { echo "noname"; return; }

  # Comment-only and blank lines are dropped BEFORE the block is located, so a
  # commented-out `case` cannot be read as live code — a review found exactly that.
  local arms
  arms=$(awk '
    { s = $0; sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s) }
    s == "" || s ~ /^#/ { next }
    # Heredoc BODIES are data, not code. A canonical-looking block inside one was
    # reported as a live declaration — found by review. Track the delimiter and skip
    # to it. `<<<` is a herestring with no body, so it is excluded.
    hd != "" { if (s == hd) hd = ""; next }
    index($0, "<<") > 0 && index($0, "<<<") == 0 {
      d = $0; sub(/^.*<</, "", d); sub(/^-/, "", d)
      gsub(/[^A-Za-z0-9_]/, " ", d)
      split(d, parts, " ")
      if (parts[1] != "") { hd = parts[1]; next }
    }
    index($0, "case \",${CODING_RULES_HOOK_DISABLED:-},\" in") { inblk = 1; next }
    inblk && $0 ~ /^[[:space:]]*esac/                          { inblk = 0 }
    inblk                                                      { print }
  ' "$1")

  [[ -n "$arms" ]] || { echo "no"; return; }

  # THE CANONICAL ARM. Every disable block kerby ships is one line of this shape:
  #     *,<token>,*) exit 0 ;;
  # optionally `|`-joining several tokens (hollow-test-check also answers to its
  # pre-v9.3 name). This pattern is anchored end to end on purpose. Three earlier
  # drafts tried to *understand* the arm — grep the token, then grep `exit 0` — and a
  # review defeated each: `exit 01` satisfied an unbounded `exit 0`, and a token on a
  # different line from its `exit 0` was misjudged in both directions.
  #
  # So this no longer tries to understand bash. It recognizes the one form the repo
  # actually uses and refuses to guess about anything else: a block that deviates is
  # reported `noncanonical`, which is an ERROR, not a pass. That is the trade — the
  # guard cannot bless an unusual-but-valid arm, and in exchange it cannot be fooled
  # by one either. If a hook ever needs a different shape, a human decides that, and
  # this pattern is where the decision gets recorded.
  local canon='^[[:space:]]*\*,[A-Za-z0-9_.-]+,\*(\|\*,[A-Za-z0-9_.-]+,\*)*\)[[:space:]]+exit[[:space:]]+0[[:space:]]*;;[[:space:]]*(#.*)?$'

  # EVERY line in the block must be a canonical arm — not merely one of them. Accepting
  # a block because *some* arm was canonical let an earlier `*,<token>,*) exit 2 ;;`
  # shadow the real one: bash runs the FIRST matching arm, so the hook exited 2 while
  # this guard reported that it honored the token. Requiring the whole block to be
  # canonical removes arm ordering from the question entirely.
  printf '%s\n' "$arms" | grep -qvE "$canon" && { echo "noncanonical"; return; }

  # The token must appear in the arm's PATTERN, never in its trailing comment. The
  # canonical form permits `# …` after the `;;`, and matching the whole line let a
  # comment containing ",<token>," satisfy an arm that named something else entirely —
  # found by review. Truncating at the first `)` leaves only the pattern.
  printf '%s\n' "$arms" | sed 's/).*$//' | grep -qF ",$name," && echo "yes" || echo "wrongtoken"
}

# Tier for one [[check]] block, from floor + severity. Echoes the tier or `unparseable`.
tier_of() { # $1=floor(true|""), $2=severity
  if   [[ "$1" == "true"  ]]; then echo "locked"
  elif [[ "$2" == "block" ]]; then echo "recommended"
  elif [[ "$2" == "warn" || "$2" == "info" ]]; then echo "optional"
  else echo "unparseable"; fi
}

# A script may back several checks. The unit of registration is the SCRIPT, so the
# strictest tier among its checks wins (contract § Hook tiers rule 1) — which is why
# protect-git.sh is locked even though protected-branch-commit alone is not.
strictest() { # $1=incumbent $2=candidate
  case "$1|$2" in
    locked*|*\|locked)          echo "locked" ;;
    recommended*|*\|recommended) echo "recommended" ;;
    *)                           echo "optional" ;;
  esac
}

# Walk one manifest, accumulating "enforcer<TAB>tier" for every check declaring one.
# awk (not a bash TOML parse) because [[check]] blocks are order-independent and a
# block may declare enforcer before or after floor/severity.
collect_enforcers() { # $1=absolute manifest path
  awk '
    /^[[:space:]]*\[\[check\]\]/ { flush(); id=""; enf=""; sev=""; flr=""; inblock=1; next }
    /^[[:space:]]*\[/ && !/^[[:space:]]*\[\[check\]\]/ { flush(); inblock=0 }
    # Leading whitespace is legal TOML. Anchoring at ^ dropped an indented `enforcer`
    # line entirely (silently losing a hook) and an indented `floor` line demoted a
    # locked script to recommended. Both were found by review, not by this guard.
    inblock {
      if ($0 ~ /^[[:space:]]*id[[:space:]]*=/)        { id  = val() }
      if ($0 ~ /^[[:space:]]*enforcer[[:space:]]*=/)  { enf = val() }
      if ($0 ~ /^[[:space:]]*severity[[:space:]]*=/)  { sev = val() }
      if ($0 ~ /^[[:space:]]*floor[[:space:]]*=/)     { flr = boolval() }
    }
    END { flush() }
    function val(   s) { s=$0; sub(/^[^=]*=[[:space:]]*/,"",s); sub(/[[:space:]]*#.*$/,"",s); gsub(/^"|"[[:space:]]*$/,"",s); gsub(/[[:space:]]+$/,"",s); return s }
    function boolval(  s){ s=$0; sub(/^[^=]*=[[:space:]]*/,"",s); sub(/[[:space:]]*#.*$/,"",s); gsub(/[[:space:]]+$/,"",s); return s }
    function flush() { if (enf != "") printf "%s\t%s\t%s\t%s\n", enf, sev, flr, id }
  ' "$1"
}

# One reporter for both loops. Keeping the verdict-to-outcome mapping in a single place
# is what stops a new honors_token verdict from being handled for enforcers and silently
# ignored for engine services — a `case` with an unhandled value falls through to nothing,
# which would read as a pass.
report_hook() { # $1=display name (filename) $2=tier $3=verdict $4=path
  # The disable TOKEN is the `# Name:` header, not the filename — they differ by the
  # `.sh` suffix, and naming the file where the token belongs would send a reader to
  # type a value that does not work.
  local tok; tok=$(sed -n 's/^#[[:space:]]*Name:[[:space:]]*//p' "${4:-/dev/null}" 2>/dev/null | head -1 | tr -d '[:space:]')
  [[ -n "$tok" ]] || tok="${1%.sh}"
  case "$3" in
    yes)        [[ "$2" == "optional" ]] \
                  && pass "$1 — $2, declares the canonical disable block for '$tok'" \
                  || fail "$1 — $2 must declare NO disable block, but declares one for '$tok'" ;;
    no)         [[ "$2" == "optional" ]] \
                  && fail "$1 — $2 must declare a canonical disable block for '$tok', but declares none" \
                  || pass "$1 — $2, declares no disable block" ;;
    wrongtoken) fail "$1 — $2 declares a canonical disable block, but no arm names its token '$tok'; CODING_RULES_HOOK_DISABLED=$tok would not reach it" ;;
    noncanonical) unclassified "$1: its disable block is not in kerby's canonical arm form (\`*,<token>,*) exit 0 ;;\`) — refusing to guess whether it honors '$tok'" ;;
    noname)     unclassified "$1: no '# Name:' header — cannot tell which token should disable it" ;;
    missing)    unclassified "$1: declared or listed, but no such file" ;;
    *)          unclassified "$1: unrecognized disable-block verdict '$3'" ;;
  esac
}

echo "=== enforcers (tier derived from manifest) ==="
for man in "${MANIFESTS[@]}"; do
  man_dir="$(dirname "$man")"
  # bash 3.2: no associative arrays. Two parallel indexed arrays instead.
  SEEN_PATHS=(); SEEN_TIERS=()
  while IFS=$'\t' read -r enf sev flr cid; do
    [[ -n "$enf" ]] || continue
    t=$(tier_of "$flr" "$sev")
    if [[ "$t" == "unparseable" ]]; then
      unclassified "$man: check '$cid' has severity='$sev' floor='$flr' — no tier derivable"
      continue
    fi
    abs="$man_dir/$enf"
    idx=-1; i=0
    while [[ $i -lt ${#SEEN_PATHS[@]} ]]; do
      [[ "${SEEN_PATHS[$i]}" == "$abs" ]] && idx=$i && break
      i=$((i + 1))
    done
    if [[ $idx -ge 0 ]]; then
      SEEN_TIERS[$idx]=$(strictest "${SEEN_TIERS[$idx]}" "$t")
    else
      SEEN_PATHS[${#SEEN_PATHS[@]}]="$abs"
      SEEN_TIERS[${#SEEN_TIERS[@]}]="$t"
    fi
  done < <(collect_enforcers "$man")

  i=0
  while [[ $i -lt ${#SEEN_PATHS[@]} ]]; do
    abs="${SEEN_PATHS[$i]}"; t="${SEEN_TIERS[$i]}"; i=$((i + 1))
    name=$(basename "$abs")
    h=$(honors_token "$abs")
    report_hook "$name" "$t" "$h" "$abs"
  done
done

echo "=== engine services (optional by definition) ==="
for abs in "${ENGINE_SERVICES[@]}"; do
  report_hook "$(basename "$abs")" "optional" "$(honors_token "$abs")" "$abs"
done

echo "---"
echo "unclassified: $UNCLASSIFIED"
if [[ "$FAILS" -eq 0 ]]; then
  echo "All assertions passed."
  exit 0
else
  echo "$FAILS assertion(s) failed."
  exit 1
fi
