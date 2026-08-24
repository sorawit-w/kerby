#!/bin/bash
# Self-test for check-hook-disable-tier.sh — zero-framework, self-contained.
# Run from anywhere: bash scripts/check-hook-disable-tier.test.sh
# Exit 0 = all assertions pass; non-zero = a failure.
#
# WHY THIS FILE EXISTS, AND WHY IT MUTATES.
# skills/kerby/CLAUDE.md: "if you do write [a guard], write its test in the same
# commit … a guard that under-matches converts nobody checked into the check passed."
# Asserting only that the guard passes on the real tree would prove nothing — a script
# that printed "All assertions passed" unconditionally would satisfy it. So every case
# below mutates a COPY of the tree into a known-broken state and requires the guard to
# NOTICE. The guard reads $KERBY_ROOT precisely so this is possible without touching
# the real skill.
#
# Note check-plan-gate-parity.sh ships without a test, so there was no in-repo shape to
# copy here; this file is the first of its kind and its own shape is the likeliest
# defect. Assertions are therefore on SPECIFIC output lines, not just exit codes — an
# exit-code-only test would pass even if the guard failed for an unrelated reason.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
REPO_ROOT="$SCRIPT_DIR/.."
GUARD="$SCRIPT_DIR/check-hook-disable-tier.sh"

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

[[ -f "$GUARD" ]] || { echo "FAIL: cannot find $GUARD"; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# One pristine copy, re-cloned per case so mutations never accumulate.
PRISTINE="$TMP/pristine"
mkdir -p "$PRISTINE/skills"
cp -R "$REPO_ROOT/skills/kerby" "$PRISTINE/skills/kerby"

fresh_root() { # echoes a new mutable root containing skills/kerby
  local d="$TMP/case-$1"
  rm -rf "$d"; mkdir -p "$d/skills"
  cp -R "$PRISTINE/skills/kerby" "$d/skills/kerby"
  echo "$d"
}

run_guard() { # $1=root -> stdout captured, exit code in $RC
  OUT="$(KERBY_ROOT="$1" bash "$GUARD" 2>&1)"; RC=$?
}

# The canonical honoring block, as the real optional hooks write it.
CASE_BLOCK='case ",${CODING_RULES_HOOK_DISABLED:-}," in
  *,protect-env,*) exit 0 ;;
esac'

# --- Case 0: the real tree passes -------------------------------------------
# Baseline only. On its own this proves nothing (see header); it exists so a genuine
# regression in the shipped tree is distinguishable from a broken mutation harness.
run_guard "$REPO_ROOT"
[[ "$RC" -eq 0 ]] && pass "real tree: guard exits 0" \
                  || fail "real tree: guard exited $RC (expected 0)"
echo "$OUT" | grep -q "^unclassified: 0$" \
  && pass "real tree: reports unclassified: 0" \
  || fail "real tree: did not report 'unclassified: 0'"
# Every enumerated script must actually be reported on — under-coverage is the exact
# failure this guard was written to avoid, so assert the count, not just the exit code.
n=$(echo "$OUT" | grep -cE '^(PASS|FAIL|ERROR): ')
[[ "$n" -eq 12 ]] && pass "real tree: all 12 scripts classified" \
                  || fail "real tree: classified $n scripts (expected 12)"
# hollow-test-check.sh is the file a naive `grep -v test` silently drops. Name it
# explicitly so that shortcut can never be reintroduced unnoticed.
echo "$OUT" | grep -q "hollow-test-check.sh" \
  && pass "real tree: hollow-test-check.sh is covered (filename contains 'test')" \
  || fail "real tree: hollow-test-check.sh missing from output"

# --- Case 1: a `recommended` hook starts honoring the token -----------------
# Inserted just after the shebang, not appended: protect-env.sh ends past terminal
# control flow, so an appended block would never run. The guard reads statically and
# would not notice, but a fixture whose mutation is behaviorally dead is a fixture that
# stops meaning what it claims the moment anyone checks it by hand.
R="$(fresh_root 1)"
P="$R/skills/kerby/rulebooks/swe/hooks/protect-env.sh"
{ head -1 "$P"; printf '%s\n' "$CASE_BLOCK"; tail -n +2 "$P"; } > "$P.new" && mv "$P.new" "$P"
run_guard "$R"
[[ "$RC" -ne 0 ]] && pass "case 1: guard fails when protect-env.sh honors the token" \
                  || fail "case 1: guard passed a recommended hook that honors the token"
echo "$OUT" | grep -q "protect-env.sh — recommended must declare NO disable block" \
  && pass "case 1: names the specific violation" \
  || fail "case 1: did not name the recommended-must-refuse violation"

# --- Case 2: an `optional` hook stops honoring the token --------------------
R="$(fresh_root 2)"
H="$R/skills/kerby/rulebooks/swe/hooks/hollow-test-check.sh"
grep -v 'CODING_RULES_HOOK_DISABLED' "$H" > "$H.new" && mv "$H.new" "$H"
run_guard "$R"
[[ "$RC" -ne 0 ]] && pass "case 2: guard fails when hollow-test-check.sh drops the token" \
                  || fail "case 2: guard passed an optional hook that refuses the token"
echo "$OUT" | grep -q "hollow-test-check.sh — optional must declare a canonical disable block" \
  && pass "case 2: names the specific violation" \
  || fail "case 2: did not name the optional-must-honor violation"

# --- Case 3: a case block with its arm removed disables nothing -------------
# A `case` header present but no arm must NOT read as "honors the token".
R="$(fresh_root 3)"
H="$R/skills/kerby/rulebooks/swe/hooks/warn-env-read.sh"
grep -vE '^[[:space:]]*\*,[^)]+,\*\)' "$H" > "$H.new" && mv "$H.new" "$H"
run_guard "$R"
[[ "$RC" -ne 0 ]] && pass "case 3: guard fails when the disable block has no arm" \
                  || fail "case 3: guard passed a hook whose disable block has no arm"
echo "$OUT" | grep -q "warn-env-read.sh — optional must declare a canonical disable block" \
  && pass "case 3: reports it precisely as refusing, not as unclassifiable" \
  || fail "case 3: did not report warn-env-read.sh as refusing the token"

# --- Case 3b: a script with no `# Name:` header IS unclassifiable -----------
# Keeps the error-not-pass property under test now that an empty case block has a
# precise verdict of its own. Without a name there is no token to look for, so the
# guard must say it cannot tell rather than guessing either way.
R="$(fresh_root 3b)"
H="$R/skills/kerby/rulebooks/swe/hooks/warn-env-read.sh"
grep -v '^# Name:' "$H" > "$H.new" && mv "$H.new" "$H"
run_guard "$R"
[[ "$RC" -ne 0 ]] && pass "case 3b: guard fails on a script with no '# Name:' header" \
                  || fail "case 3b: guard passed a script whose token cannot be determined"
echo "$OUT" | grep -q "^ERROR: warn-env-read.sh" \
  && pass "case 3b: reports it as ERROR, not as a pass or a plain mismatch" \
  || fail "case 3b: did not report the nameless script as unclassifiable"
echo "$OUT" | grep -q "^unclassified: 0$" \
  && fail "case 3b: still reported 'unclassified: 0' despite an unclassifiable script" \
  || pass "case 3b: the unclassified count reflects it"

# --- Case 4: a declared enforcer that does not exist ------------------------
R="$(fresh_root 4)"
rm -f "$R/skills/kerby/rulebooks/swe/hooks/route-high-stakes.sh"
run_guard "$R"
[[ "$RC" -ne 0 ]] && pass "case 4: guard fails when a declared enforcer is missing" \
                  || fail "case 4: guard passed with a declared enforcer absent"
echo "$OUT" | grep -q "^ERROR: route-high-stakes.sh" \
  && pass "case 4: reports the missing enforcer as unclassifiable" \
  || fail "case 4: did not report the missing enforcer"

# --- Case 5: an engine service that refuses the token -----------------------
# Engine services are `optional` by definition (contract § Hook tiers rule 3), so one
# that refuses the variable is a real disagreement. Case 2 covers this for a rulebook
# enforcer; this covers the other half of the population.
#
# Note what this case deliberately no longer tests: a *deleted* engine service. Engine
# services are globbed, so a deleted one is simply absent from the sweep rather than
# flagged. That is the accepted cost of globbing instead of hardcoding a list — a
# hardcoded list caught deletions but silently skipped ADDITIONS, and made the guard
# key on names the engine-independence rule keeps out of engine surfaces. Inventory is
# not this guard's job; parity is, and a hook that does not exist has no behavior to
# disagree with its tier.
R="$(fresh_root 5)"
H="$R/skills/kerby/resources/hooks/knowledge-lint.sh"
grep -v 'CODING_RULES_HOOK_DISABLED' "$H" > "$H.new" && mv "$H.new" "$H"
run_guard "$R"
[[ "$RC" -ne 0 ]] && pass "case 5: guard fails when an engine service refuses the token" \
                  || fail "case 5: guard passed an engine service that refuses the token"
echo "$OUT" | grep -q "knowledge-lint.sh — optional must declare a canonical disable block" \
  && pass "case 5: names the engine service and what it must do" \
  || fail "case 5: did not name the offending engine service"

# --- Case 6: a manifest with zero enforcers must not error ------------------
# skill-authoring declares no enforcers. Covered by case 0's clean run, but asserted
# directly so a future "every manifest must yield enforcers" refactor is caught.
run_guard "$REPO_ROOT"
echo "$OUT" | grep -q "skill-authoring" \
  && fail "case 6: skill-authoring (zero enforcers) produced output; it should be silent" \
  || pass "case 6: an enforcer-free manifest is handled silently, not as an error"

# --- Case 7: the tier really comes from `severity`, not from the filename ---
# Without this, a guard that hardcoded filename->tier would pass every case above.
# Flip protect-env's severity block->warn: it becomes `optional`, and since the script
# still refuses the token, the guard must now object.
R="$(fresh_root 7)"
M="$R/skills/kerby/rulebooks/swe/rulebook.toml"
awk '/^id = "protect-env"/{f=1} f && /^severity = "block"/{sub(/"block"/,"\"warn\""); f=0} {print}' "$M" > "$M.new" && mv "$M.new" "$M"
run_guard "$R"
[[ "$RC" -ne 0 ]] && pass "case 7: a severity flip in the manifest changes the verdict" \
                  || fail "case 7: guard ignored a severity change — tier may be filename-keyed"
echo "$OUT" | grep -q "protect-env.sh — optional must declare a canonical disable block" \
  && pass "case 7: reclassified protect-env as optional from the manifest alone" \
  || fail "case 7: did not reclassify protect-env after the severity flip"

# --- Case 8: `floor` drives locked, and script granularity is manifest-driven
# Drop floor from destructive-git and warn-ify both protect-git checks. The script
# should fall locked -> optional and, still refusing the token, fail.
R="$(fresh_root 8)"
M="$R/skills/kerby/rulebooks/swe/rulebook.toml"
sed -i '' 's/^floor = true.*$//' "$M"
sed -i '' 's/^severity = "block"$/severity = "warn"/' "$M"
run_guard "$R"
[[ "$RC" -ne 0 ]] && pass "case 8: removing floor + block reclassifies protect-git" \
                  || fail "case 8: guard ignored floor/severity removal — tier may be filename-keyed"
echo "$OUT" | grep -q "protect-git.sh — optional must declare a canonical disable block" \
  && pass "case 8: protect-git fell out of locked once its manifest stopped saying so" \
  || fail "case 8: protect-git did not reclassify after floor was removed"

# --- Case 9: an arm naming the WRONG token is not "honors" ------------------
# Found by review, not by this test: the first guard grepped for a case header and,
# separately, any arm-shaped line, so a hook whose arm named some other token still
# reported agreement. CODING_RULES_HOOK_DISABLED=warn-env-read would not have worked.
R="$(fresh_root 9)"
sed -i '' 's/\*,warn-env-read,\*)/*,zzz-not-this-hook,*)/' "$R/skills/kerby/rulebooks/swe/hooks/warn-env-read.sh"
run_guard "$R"
[[ "$RC" -ne 0 ]] && pass "case 9: an arm naming the wrong token fails" \
                  || fail "case 9: guard accepted an arm that names a different hook"
echo "$OUT" | grep -q "no arm names its token 'warn-env-read'" \
  && pass "case 9: names the token the user would actually type" \
  || fail "case 9: did not report the specific missing token"

# --- Case 10: an arm that does not exit 0 disables nothing ------------------
R="$(fresh_root 10)"
sed -i '' 's/\*,warn-env-read,\*) exit 0/*,warn-env-read,*) exit 2/' "$R/skills/kerby/rulebooks/swe/hooks/warn-env-read.sh"
run_guard "$R"
[[ "$RC" -ne 0 ]] && pass "case 10: an arm exiting non-zero fails" \
                  || fail "case 10: guard accepted an arm that does not exit 0"

# --- Case 11: an INDENTED manifest field is still read ----------------------
# Leading whitespace is legal TOML. The first parser anchored at ^ and silently lost
# the enforcer entirely, dropping a hook from coverage while still exiting 0.
R="$(fresh_root 11)"
M="$R/skills/kerby/rulebooks/swe/rulebook.toml"
sed -i '' 's|^enforcer = "hooks/warn-env-read.sh"|  enforcer = "hooks/warn-env-read.sh"|' "$M"
run_guard "$R"
echo "$OUT" | grep -q "warn-env-read.sh" \
  && pass "case 11: an indented enforcer line is still parsed" \
  || fail "case 11: an indented enforcer line silently dropped the hook"

# --- Case 12: a NEWLY ADDED rulebook is covered, not skipped ----------------
# The first version listed manifests explicitly, so an added rulebook was ignored in
# silence — under-coverage wearing a green exit code.
R="$(fresh_root 12)"
NR="$R/skills/kerby/rulebooks/zz-extra"
mkdir -p "$NR/hooks"
cat > "$NR/rulebook.toml" <<'TOML'
id = "zz-extra"
version = "1.0.0"
contract = 2
accepts = ["git_change"]
description = "fixture"

[[check]]
id = "extra-check"
kind = "code"
enforcement = "hard"
enforcer = "hooks/extra.sh"
event = "PreToolUse"
matcher = "Bash"
severity = "warn"
TOML
printf '#!/bin/bash\n# Name: extra\nexit 0\n' > "$NR/hooks/extra.sh"
run_guard "$R"
echo "$OUT" | grep -q "extra.sh" \
  && pass "case 12: a newly added rulebook's enforcer is covered" \
  || fail "case 12: an added rulebook was silently skipped"
[[ "$RC" -ne 0 ]] && pass "case 12: and its optional hook refusing the token is caught" \
                  || fail "case 12: covered the new hook but did not check it"

# --- Case 13: `exit 01` is not `exit 0` -------------------------------------
# Found by review. An unbounded `exit[[:space:]]+0` matched `exit 01`, which exits 1.
R="$(fresh_root 13)"
sed -i '' 's/\*,warn-env-read,\*) exit 0/*,warn-env-read,*) exit 01/' "$R/skills/kerby/rulebooks/swe/hooks/warn-env-read.sh"
run_guard "$R"
[[ "$RC" -ne 0 ]] && pass "case 13: 'exit 01' is not accepted as 'exit 0'" \
                  || fail "case 13: guard accepted 'exit 01' as honoring the token"
echo "$OUT" | grep -q "^ERROR: warn-env-read.sh" \
  && pass "case 13: refuses to guess rather than passing it" \
  || fail "case 13: did not report the deviant arm as unclassifiable"

# --- Case 14: a commented-out block is not live code ------------------------
# Found by review. The block was located before comments were stripped, so commenting
# the whole thing out still read as "honors the token".
R="$(fresh_root 14)"
H="$R/skills/kerby/rulebooks/swe/hooks/warn-env-read.sh"
sed -i '' -e 's|^\(case ",${CODING_RULES_HOOK_DISABLED.*\)|# \1|' \
          -e 's|^\(  \*,warn-env-read,\*.*\)|# \1|' \
          -e 's|^\(esac\)$|# \1|' "$H"
run_guard "$R"
[[ "$RC" -ne 0 ]] && pass "case 14: a commented-out disable block does not count" \
                  || fail "case 14: guard read a commented-out block as live code"
echo "$OUT" | grep -q "warn-env-read.sh — optional must declare a canonical disable block" \
  && pass "case 14: reports it as refusing the token" \
  || fail "case 14: did not report the commented-out hook as refusing"

# --- Case 15: indented `[[check]]` headers are still parsed -----------------
# Found by review. The field patterns allowed indentation but the block header did not,
# so indenting the headers made every swe enforcer vanish with a clean exit.
R="$(fresh_root 15)"
sed -i '' 's/^\[\[check\]\]/  [[check]]/' "$R/skills/kerby/rulebooks/swe/rulebook.toml"
run_guard "$R"
n=$(echo "$OUT" | grep -cE '^(PASS|FAIL|ERROR): ')
[[ "$n" -eq 12 ]] && pass "case 15: indented [[check]] headers keep all 12 hooks covered" \
                  || fail "case 15: indented headers dropped coverage to $n hooks"

# --- Case 16: derivation is manifest-driven for base too --------------------
# Cases 7-8 only exercised swe. Without these, a guard could hardcode the tiers of
# base and codex-review and still pass the suite.
R="$(fresh_root 16)"
M="$R/skills/kerby/rulebooks/base/rulebook.toml"
sed -i '' 's/^floor = true$//' "$M"
sed -i '' 's/^severity = "block"$/severity = "warn"/' "$M"
run_guard "$R"
echo "$OUT" | grep -q "pre-commit-check.sh — optional must declare a canonical disable block" \
  && pass "case 16: base's floor hook reclassifies from its own manifest" \
  || fail "case 16: pre-commit-check did not follow base's manifest — tier may be hardcoded"

# --- Case 17: ...and for codex-review -------------------------------------
R="$(fresh_root 17)"
M="$R/skills/kerby/rulebooks/codex-review/rulebook.toml"
sed -i '' 's/^severity = "block"$/severity = "warn"/' "$M"
run_guard "$R"
echo "$OUT" | grep -q "codex-pr-gate.sh — optional must declare a canonical disable block" \
  && pass "case 17: codex-review's gate reclassifies from its own manifest" \
  || fail "case 17: codex-pr-gate did not follow its manifest — tier may be hardcoded"

# --- Case 18: an earlier arm shadowing the canonical one --------------------
# The round-3 false green, and the reason the whole block must be canonical rather
# than merely containing one canonical arm. bash runs the FIRST matching arm, so this
# hook really exits 2 when the variable is set while the old guard called it honoring.
R="$(fresh_root 18)"
W="$R/skills/kerby/rulebooks/swe/hooks/warn-env-read.sh"
sed -i '' 's|^\(  \*,warn-env-read,\*) exit 0 ;;\)|  *,warn-env-read,*) exit 2 ;;\
\1|' "$W"
run_guard "$R"
[[ "$RC" -ne 0 ]] && pass "case 18: an earlier shadowing arm is caught" \
                  || fail "case 18: guard accepted a block whose first matching arm exits 2"
echo "$OUT" | grep -q "^ERROR: warn-env-read.sh" \
  && pass "case 18: refuses to guess rather than reporting it honors the token" \
  || fail "case 18: did not report the shadowed block as unclassifiable"
# Prove the fixture is real, not just guard-visible: the hook must actually exit 2.
echo '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}' \
  | CODING_RULES_HOOK_DISABLED=warn-env-read bash "$W" >/dev/null 2>&1
[[ "$?" -eq 2 ]] && pass "case 18: and the mutated hook really does exit 2 at runtime" \
                 || fail "case 18: fixture does not reproduce the runtime behavior it claims"

# --- Case 19: the token appears only in a trailing comment ------------------
# Found by review. The canonical form permits `# ...` after the `;;`, and the token
# check matched the whole line, so a comment carrying ",<token>," satisfied an arm
# that named something else entirely.
R="$(fresh_root 19)"
W="$R/skills/kerby/rulebooks/swe/hooks/warn-env-read.sh"
sed -i '' 's|^  \*,warn-env-read,\*) exit 0 ;;|  *,zzz-not-this-hook,*) exit 0 ;;  # ,warn-env-read,|' "$W"
run_guard "$R"
[[ "$RC" -ne 0 ]] && pass "case 19: a token in a trailing comment does not count" \
                  || fail "case 19: guard accepted a comment as the arm's token"
echo "$OUT" | grep -q "no arm names its token 'warn-env-read'" \
  && pass "case 19: reports the arm as naming the wrong token" \
  || fail "case 19: did not report the wrong-token arm"

# --- Case 20: a canonical block inside a heredoc is data, not code ----------
# Found by review. The block was located by text, so one sitting inside a heredoc
# reported as a live declaration with unclassified: 0.
R="$(fresh_root 20)"
W="$R/skills/kerby/rulebooks/swe/hooks/warn-env-read.sh"
awk '/^case ",\$\{CODING_RULES_HOOK_DISABLED/{skip=1} skip&&/^esac/{skip=0;next} !skip' "$W" > "$W.t" && mv "$W.t" "$W"
{ head -1 "$W"
  printf 'cat <<EOF >/dev/null\n'
  printf 'case ",${CODING_RULES_HOOK_DISABLED:-}," in\n'
  printf '  *,warn-env-read,*) exit 0 ;;\n'
  printf 'esac\nEOF\n'
  tail -n +2 "$W"; } > "$W.n" && mv "$W.n" "$W"
run_guard "$R"
[[ "$RC" -ne 0 ]] && pass "case 20: a block inside a heredoc is not a declaration" \
                  || fail "case 20: guard read heredoc data as a live disable block"
echo "$OUT" | grep -q "warn-env-read.sh — optional must declare a canonical disable block" \
  && pass "case 20: reports the hook as declaring none" \
  || fail "case 20: did not report the heredoc-only hook as undeclared"

echo "---"
if [[ "$FAILS" -eq 0 ]]; then
  echo "All assertions passed."
  exit 0
else
  echo "$FAILS assertion(s) failed."
  exit 1
fi
