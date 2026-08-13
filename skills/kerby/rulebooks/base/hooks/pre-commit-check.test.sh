#!/bin/bash
# Self-test for pre-commit-check.sh — zero-framework, self-contained.
# Exercises the gitleaks/regex secret-scan branches deterministically by stubbing
# `gitleaks` and controlling PATH, so results don't depend on gitleaks being
# installed on the test machine.
#
# Run from anywhere: bash pre-commit-check.test.sh
# Exit 0 = all assertions pass; non-zero = a failure.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
HOOK="$SCRIPT_DIR/pre-commit-check.sh"

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# --- Controlled PATHs: no scanner / stub gitleaks / stub betterleaks+gitleaks --
BIN_NO="$TMP/bin_no"   # tools only, NO scanner (forces regex fallback)
BIN_GL="$TMP/bin_gl"   # tools + stub gitleaks
BIN_BL="$TMP/bin_bl"   # tools + stub betterleaks AND stub gitleaks (precedence)
mkdir -p "$BIN_NO" "$BIN_GL" "$BIN_BL"
for t in bash git jq grep sed cat head tail env tr awk; do
  real="$(command -v "$t")" && ln -s "$real" "$BIN_NO/$t" && ln -s "$real" "$BIN_GL/$t" && ln -s "$real" "$BIN_BL/$t"
done
ARGS_FILE="$TMP/scanner_args"

# Each stub records "<name> <args>" then exits the code the test asked for via the
# named env var. Built line-by-line so $2/$3 expand now but $* / exit value don't.
mk_scanner_stub() { # $1=path  $2=scanner-name  $3=rc-env-var-name
  # The stub CONSUMES stdin and records both the payload and its cwd. An earlier
  # version exited a fixed code without reading either, so every
  # target-resolution assertion passed regardless of which repo was scanned —
  # they proved "the hook blocked", never "the hook scanned the right index".
  {
    echo '#!/bin/bash'
    echo "payload=\$(cat)"
    echo "printf '$2 %s\\n' \"\$*\" >> \"\${SCANNER_ARGS_FILE:-/dev/null}\""
    echo "printf 'cwd=%s\\n' \"\$PWD\" >> \"\${SCANNER_ARGS_FILE:-/dev/null}\""
    echo "printf '%s' \"\$payload\" > \"\${SCANNER_STDIN_FILE:-/dev/null}\""
    echo 'if [[ -n "${SCANNER_REAL:-}" ]]; then'
    echo '  if printf "%s" "$payload" | grep -q "sk_live_"; then exit 7; else exit 0; fi'
    echo 'fi'
    echo "exit \"\${$3:-0}\""
  } > "$1"
  chmod +x "$1"
}
mk_scanner_stub "$BIN_GL/gitleaks"    gitleaks    GITLEAKS_STUB_RC
mk_scanner_stub "$BIN_BL/betterleaks" betterleaks BETTERLEAKS_STUB_RC
mk_scanner_stub "$BIN_BL/gitleaks"    gitleaks    GITLEAKS_STUB_RC

# --- Fixture git repo --------------------------------------------------------
REPO="$TMP/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q

COMMIT_INPUT='{"tool_input":{"command":"git commit -m test"}}'

stage_clean() {
  echo "const port = 3000;" > "$REPO/app.js"
  git -C "$REPO" add app.js
}
stage_secret() {
  # A fake Stripe-style key the built-in regex matches.
  echo 'const k = "sk_live_ABCDEFG1234567890fake";' > "$REPO/secret.js"
  git -C "$REPO" add secret.js
}
reset_index() { git -C "$REPO" rm -r --cached -q -f . >/dev/null 2>&1 || true; rm -f "$REPO"/*.js "$REPO"/*.go; }

# The hollow-test heuristic and the lint/test/build reminder moved to swe's
# hollow-test-check.sh in v9.3 — this floor script is now a PURE secret scan. Its
# fixtures/assertions live in swe/hooks/hollow-test-check.test.sh. base's job here
# is only the scan; the purity assertion below guards against re-bundling.

run_hook() { # $1=PATH  $2=gitleaks_rc(opt)  $3=betterleaks_rc(opt)
  ( cd "$REPO" && echo "$COMMIT_INPUT" | PATH="$1" \
      GITLEAKS_STUB_RC="${2:-0}" BETTERLEAKS_STUB_RC="${3:-0}" \
      SCANNER_ARGS_FILE="$ARGS_FILE" bash "$HOOK" >/dev/null 2>&1 )
}

# --- Assertions --------------------------------------------------------------

# A. gitleaks reports a finding (DISTINCT leak code 7) -> hard-block (exit 2).
reset_index; stage_clean; : > "$ARGS_FILE"
run_hook "$BIN_GL" 7; rc=$?
[[ "$rc" -eq 2 ]] && pass "gitleaks finding (exit 7) -> exit 2" || fail "gitleaks finding should exit 2 (got $rc)"

# A2. The hook MUST use the version-stable `stdin` mode (NOT the deprecated
#     `protect`) and request a DISTINCT leak code (default exit 1 = "leaks OR error").
grep -q 'gitleaks stdin' "$ARGS_FILE" \
  && pass "hook uses stdin mode (not deprecated protect)" \
  || fail "hook should call '<scanner> stdin' (args: $(cat "$ARGS_FILE"))"
grep -q -- '--exit-code 7' "$ARGS_FILE" \
  && pass "hook requests --exit-code 7" \
  || fail "hook must pass --exit-code 7 (args: $(cat "$ARGS_FILE"))"
grep -q 'protect' "$ARGS_FILE" \
  && fail "hook still uses deprecated 'protect' subcommand" \
  || pass "hook does not use deprecated 'protect'"

# B. scanner clean (rc 0) is TRUSTED -> regex skipped even with a secret staged -> exit 0.
reset_index; stage_secret
run_hook "$BIN_GL" 0; rc=$?
[[ "$rc" -eq 0 ]] && pass "gitleaks clean trusted, skips regex -> exit 0" || fail "gitleaks clean should exit 0 (got $rc)"

# C. NO scanner + staged secret -> regex fallback hard-blocks (exit 2).
reset_index; stage_secret
run_hook "$BIN_NO"; rc=$?
[[ "$rc" -eq 2 ]] && pass "no scanner + secret -> regex fallback exit 2" || fail "regex fallback should exit 2 (got $rc)"

# D. scanner ERROR returning the AMBIGUOUS default code 1 + clean staged ->
#    must be a TOOL ERROR (not a finding) -> fall back -> NOT blocked.
#    Codex P2 scenario: a malformed scanner config must not phantom-block.
reset_index; stage_clean
run_hook "$BIN_GL" 1; rc=$?
[[ "$rc" -eq 0 ]] && pass "gitleaks exit 1 (error, not leak) + clean -> exit 0 (no phantom block)" || fail "exit-1 error+clean should exit 0 (got $rc)"

# E. scanner ERROR (rc 1) + staged secret -> fall back to regex -> exit 2.
reset_index; stage_secret
run_hook "$BIN_GL" 1; rc=$?
[[ "$rc" -eq 2 ]] && pass "gitleaks error (exit 1) + secret -> regex fallback exit 2" || fail "error+secret should exit 2 (got $rc)"

# E2. A different error code (2) + clean -> also falls back, not blocked.
reset_index; stage_clean
run_hook "$BIN_GL" 2; rc=$?
[[ "$rc" -eq 0 ]] && pass "gitleaks exit 2 (error) + clean -> exit 0 (no phantom block)" || fail "exit-2 error+clean should exit 0 (got $rc)"

# G. betterleaks present -> its finding (exit 7) hard-blocks, and the hook called
#    BETTERLEAKS (not gitleaks). Proves the new scanner is actually wired.
reset_index; stage_clean; : > "$ARGS_FILE"
run_hook "$BIN_BL" 0 7; rc=$?   # gitleaks_rc=0, betterleaks_rc=7
[[ "$rc" -eq 2 ]] && pass "betterleaks finding (exit 7) -> exit 2" || fail "betterleaks finding should exit 2 (got $rc)"
grep -q 'betterleaks stdin' "$ARGS_FILE" \
  && pass "hook invoked betterleaks (not gitleaks)" \
  || fail "hook should have called betterleaks (args: $(cat "$ARGS_FILE"))"

# H. PRECEDENCE: with BOTH installed, betterleaks wins. betterleaks=clean(0),
#    gitleaks=would-block(7) -> result 0 proves gitleaks was never consulted.
reset_index; stage_clean
run_hook "$BIN_BL" 7 0; rc=$?   # gitleaks_rc=7 (ignored), betterleaks_rc=0
[[ "$rc" -eq 0 ]] && pass "betterleaks takes precedence over gitleaks" || fail "betterleaks should win over gitleaks (got $rc)"

# F. Non-commit command exits 0 early (no scan).
reset_index; stage_secret
rc=0; ( cd "$REPO" && echo '{"tool_input":{"command":"git status"}}' | PATH="$BIN_NO" bash "$HOOK" >/dev/null 2>&1 ) || rc=$?
[[ "$rc" -eq 0 ]] && pass "non-commit command exits 0 early" || fail "non-commit should exit 0 (got $rc)"

# I. PURITY: a clean commit through the floor emits NOTHING — no stdout, no stderr,
#    exit 0. The hollow-test heuristic + lint/test/build reminder moved to swe in
#    v9.3; this guards against re-bundling any coding advisory into the floor.
#    Capture stdout and stderr separately (mirrors the warn-env-read assertions).
reset_index; stage_clean
ERRF="$TMP/purity_err"
OUT=$( cd "$REPO" && echo "$COMMIT_INPUT" | PATH="$BIN_NO" SCANNER_ARGS_FILE="$ARGS_FILE" bash "$HOOK" 2>"$ERRF" ); rc=$?
ERRTXT=$(cat "$ERRF")
[[ "$rc" -eq 0 ]] && pass "clean commit -> exit 0" || fail "clean commit should exit 0 (got $rc)"
[[ -z "$OUT" ]] && pass "floor emits nothing on stdout for a clean commit" \
  || fail "floor must be silent on stdout (got '$OUT')"
[[ -z "$ERRTXT" ]] && pass "floor emits nothing on stderr for a clean commit" \
  || fail "floor must be silent on stderr (got '$ERRTXT')"

# I2. The floor must NEVER emit coding advisories, even with test/spec files
#     staged. Stage a focused test + an always-true assertion — a bundled
#     heuristic WOULD fire here; the pure floor stays silent.
reset_index
printf 'describe.only("x", () => { it("y", () => { expect(true).toBe(true); }); });\n' > "$REPO/widget.test.js"
git -C "$REPO" add widget.test.js
OUT=$( cd "$REPO" && echo "$COMMIT_INPUT" | PATH="$BIN_NO" bash "$HOOK" 2>&1 ); rc=$?
{ [[ "$rc" -eq 0 ]] && ! printf '%s' "$OUT" | grep -qE 'REMINDER \(kerby\)|HOLLOW-TEST CHECK'; } \
  && pass "floor emits no REMINDER/HOLLOW-TEST even with staged test files (no re-bundling)" \
  || fail "floor must not emit coding advisories (rc=$rc, out='$OUT')"

# --- J. Invocation forms (issue #46) -----------------------------------------
# The hook used to match `^git commit`, so any git global option before the
# subcommand — or a `cd` first — skipped the scan entirely and a staged secret
# went through a check documented as a hard floor. Each form below is pinned.
#
# run_form runs the hook from a NEUTRAL cwd (not $REPO) for the -C/--git-dir
# cases, so a pass cannot come from the hook happening to sit in the right repo.
run_form() { # $1=command-string  $2=cwd
  ( cd "$2" && printf '{"tool_input":{"command":"%s"}}' "$1" \
      | PATH="$BIN_NO" bash "$HOOK" >/dev/null 2>&1 )
}

NEUTRAL="$TMP/neutral"; mkdir -p "$NEUTRAL"

reset_index; stage_secret
run_form "git commit -m x" "$REPO"; rc=$?
[[ "$rc" -eq 2 ]] && pass "form: bare 'git commit' blocks a staged secret" \
                  || fail "form: bare 'git commit' should block (got $rc)"

run_form "git -C $REPO commit -m x" "$NEUTRAL"; rc=$?
[[ "$rc" -eq 2 ]] && pass "form: 'git -C <repo> commit' blocks (was the #46 bypass)" \
                  || fail "form: 'git -C <repo> commit' should block (got $rc)"

run_form "git --git-dir=$REPO/.git --work-tree=$REPO commit -m x" "$NEUTRAL"; rc=$?
[[ "$rc" -eq 2 ]] && pass "form: 'git --git-dir=… commit' blocks" \
                  || fail "form: 'git --git-dir=… commit' should block (got $rc)"

run_form "cd $REPO && git commit -m x" "$NEUTRAL"; rc=$?
[[ "$rc" -eq 2 ]] && pass "form: 'cd <repo> && git commit' blocks" \
                  || fail "form: 'cd <repo> && git commit' should block (got $rc)"

run_form "git -c user.name=x commit -m x" "$REPO"; rc=$?
[[ "$rc" -eq 2 ]] && pass "form: value-taking global ('-c k=v') before commit blocks" \
                  || fail "form: '-c k=v commit' should block (got $rc)"

# Must NOT over-match: `commit-graph`/`commit-tree` are different subcommands.
run_form "git commit-graph write" "$REPO"; rc=$?
[[ "$rc" -eq 0 ]] && pass "form: 'git commit-graph' is not a commit (no block)" \
                  || fail "form: 'git commit-graph' must not block (got $rc)"

# --- K. Target resolution: scan the repo the commit actually targets ---------
# The dangerous half-fix is recognising `git -C other commit` but still scanning
# the cwd — a check that runs, reports clean, and proves nothing. These two
# assertions fail that half-fix in both directions.
CLEANREPO="$TMP/cleanrepo"; mkdir -p "$CLEANREPO"; git -C "$CLEANREPO" init -q
echo "const port = 3000;" > "$CLEANREPO/app.js"; git -C "$CLEANREPO" add app.js

# secret is staged in $REPO; committing to the CLEAN repo must not block
run_form "git -C $CLEANREPO commit -m x" "$REPO"; rc=$?
[[ "$rc" -eq 0 ]] && pass "target: commit to a clean repo does not block on another repo's secret" \
                  || fail "target: scanned the wrong repo — blocked a clean target (got $rc)"

# inverse: cwd is clean, target holds the secret -> must block
run_form "git -C $REPO commit -m x" "$CLEANREPO"; rc=$?
[[ "$rc" -eq 2 ]] && pass "target: commit to a dirty repo blocks even from a clean cwd" \
                  || fail "target: missed the secret in the -C target (got $rc)"

# --- K2. Regressions found by review of the #46 fix ---------------------------
# The first version of this fix made two cases WORSE than the code it replaced.
# Both are pinned so they cannot come back.
reset_index; stage_secret

# `-C` is ALSO a `git commit` option (reuse a message). Reading the trailing
# `-C HEAD` as a directory made the scan run against a nonexistent path and
# report clean — a regression: the old `^git commit` matcher scanned this
# correctly. Target selectors are only the globals BEFORE the subcommand.
run_form "git commit -C HEAD" "$REPO"; rc=$?
[[ "$rc" -eq 2 ]] && pass "regression: 'git commit -C HEAD' (commit-local -C) still scans the right repo" \
                  || fail "regression: commit-local -C misread as a target (got $rc)"

# Combined globals must keep git's own ordering, not pick one and drop the other.
run_form "git -C $REPO --git-dir=.git commit -m x" "$NEUTRAL"; rc=$?
[[ "$rc" -eq 2 ]] && pass "regression: '-C' + '--git-dir' together resolve to the right repo" \
                  || fail "regression: combined globals dropped one selector (got $rc)"

# `cd X || git commit`: the real shell runs the commit in the ORIGINAL directory
# precisely because the cd failed. Carrying the failed cd forward scanned a path
# that does not exist and reported clean.

# Git's env selectors redirect the real commit; the scan must follow them.
run_form "GIT_DIR=$REPO/.git GIT_WORK_TREE=$REPO git commit -m x" "$NEUTRAL"; rc=$?
[[ "$rc" -eq 2 ]] && pass "env: GIT_DIR/GIT_WORK_TREE redirect the scan too" \
                  || fail "env: GIT_DIR ignored, scanned the caller's index (got $rc)"

# FALSE BLOCKS. This hook is non-disablable — a wrong block can only be escaped
# by editing settings.json, so over-blocking is as much a defect as under-.
# The old matcher ignored these; the first fix blocked them.
run_form "git log --format='run git commit now'" "$REPO"; rc=$?
[[ "$rc" -eq 0 ]] && pass "false-block: 'git commit' inside a quoted arg is not a commit" \
                  || fail "false-block: quoted text treated as a commit (got $rc)"

run_form "echo git commit" "$REPO"; rc=$?
[[ "$rc" -eq 0 ]] && pass "false-block: 'echo git commit' is not a commit" \
                  || fail "false-block: a mere mention treated as a commit (got $rc)"

run_form "git log --grep=commit" "$REPO"; rc=$?
[[ "$rc" -eq 0 ]] && pass "false-block: 'git log --grep=commit' is not a commit" \
                  || fail "false-block: --grep=commit treated as a commit (got $rc)"


# --- K2e. Round-5 review findings --------------------------------------------
# run_scan: the scanner DECIDES FROM STDIN (SCANNER_REAL), so a block proves the
# right index was scanned rather than merely that a stub fired.
run_scan() { # $1=command  $2=cwd
  ( cd "$2" && jq -nc --arg c "$1" '{tool_input:{command:$c}}' \
      | PATH="$BIN_GL" SCANNER_REAL=1 SCANNER_ARGS_FILE="$ARGS_FILE" \
        bash "$HOOK" >/dev/null 2>&1 )
}
PARENT="$TMP/parent"; mkdir -p "$PARENT"

# --- K2d. Kept behaviours that earlier rounds established ---------------------
# These run the SCANNER path (stdin-deciding stub), so a block proves WHICH
# index was read — the regex-only, absolute-path tests above cannot show that.
reset_index; stage_secret
run_scan "git -C repo commit -m x" "$TMP"; rc=$?
[[ "$rc" -eq 2 ]] && pass "kept: relative 'git -C repo commit' scans the target" \
                  || fail "kept: relative -C failed open (got $rc)"
run_scan "git 'commit' -m x" "$REPO"; rc=$?
[[ "$rc" -eq 2 ]] && pass "kept: quoted subcommand \"git 'commit'\" blocks" \
                  || fail "kept: quoted subcommand missed (got $rc)"
run_scan "'git' commit -m x" "$REPO"; rc=$?
[[ "$rc" -eq 2 ]] && pass "kept: quoted \"'git' commit\" blocks" \
                  || fail "kept: quoted git missed (got $rc)"
run_scan "git --work-tree=$REPO --git-dir=$REPO/.git commit -m x" "$PARENT"; rc=$?
[[ "$rc" -eq 2 ]] && pass "kept: detached --git-dir + --work-tree is honoured" \
                  || fail "kept: detached git-dir/work-tree ignored (got $rc)"
run_scan "GIT_INDEX_FILE=$REPO/.git/index git commit -m x" "$REPO"; rc=$?
[[ "$rc" -eq 2 ]] && pass "kept: GIT_INDEX_FILE is honoured" \
                  || fail "kept: GIT_INDEX_FILE ignored (got $rc)"

# Removing a secret must NOT block: `-G --name-only` also matched removals, so
# the floor used to block the very commit taking a secret out.
RMREPO="$TMP/rmrepo"; mkdir -p "$RMREPO"; git -C "$RMREPO" init -q
printf 'k = "sk_live_ABCDEFG1234567890fake"\n' > "$RMREPO/s.py"; git -C "$RMREPO" add s.py
git -C "$RMREPO" -c user.email=a@b -c user.name=x commit -q -m base
printf 'k = os.environ["K"]\n' > "$RMREPO/s.py"; git -C "$RMREPO" add s.py
( cd "$RMREPO" && jq -nc --arg c "git commit -m x" '{tool_input:{command:$c}}' | PATH="$BIN_NO" bash "$HOOK" >/dev/null 2>&1 ); rc=$?
[[ "$rc" -eq 0 ]] && pass "kept: removing a secret does not block (added-lines-only)" \
                  || fail "kept: blocked a commit that REMOVES a secret (got $rc)"
reset_index; stage_secret
# `||` must still SPLIT segments; removing the sentinel dropped it from the split
# entirely, so `false || git commit` was one unparsed segment.
run_scan "false || git commit -m x" "$REPO"; rc=$?
[[ "$rc" -eq 2 ]] && pass "review5: 'false || git commit' is split and scanned" \
                  || fail "review5: '||' not split — commit unseen (got $rc)"

# Forms that never create a commit must NOT block. This hook is non-disablable.
for nc in "git commit --dry-run" "git commit --help"; do
  run_scan "$nc" "$REPO"; rc=$?
  [[ "$rc" -eq 0 ]] && pass "review5: '$nc' does not block (no commit is created)" \
                    || fail "review5: FALSE BLOCK on '$nc' (got $rc)"
done

# Round 5 added pathspec handling; round 6 showed it was built on a false premise
# — `git commit <path>` commits WORKING-TREE content, not the index — and that
# identifying the pathspec needs full git-commit arg parsing. It was removed.
# A pathspec commit now scans the whole staged index: it can OVER-block, which is
# the safe direction for a floor. These pin that removal.
echo "ok" > "$REPO/plain.js"; git -C "$REPO" add plain.js
run_scan "git commit plain.js -m x" "$REPO"; rc=$?
[[ "$rc" -eq 2 ]] && pass "review6: pathspec commit scans the whole index (over-blocks by design)" \
                  || fail "review6: pathspec commit skipped the scan (got $rc)"

# Quoted and bundled arguments must not derail the git-invocation match.
for q in 'git commit -m "two words"' "git commit -am 'two words'" 'git commit -S -m msg' \
         'git commit --author="A U <a@b>" -m x'; do
  run_scan "$q" "$REPO"; rc=$?
  [[ "$rc" -eq 2 ]] && pass "review6: '$q' is recognised as a commit" \
                    || fail "review6: MISSED commit in '$q' (got $rc)"
done

# --dry-run/--help are read from the UNQUOTED text: a message that merely
# mentions them is not a help invocation, and must not skip the scan.
for fake in 'git commit -m "use --help"' 'git commit -m "try --dry-run first"'; do
  run_scan "$fake" "$REPO"; rc=$?
  [[ "$rc" -eq 2 ]] && pass "review6: '$fake' is not treated as help/dry-run" \
                    || fail "review6: FAIL-OPEN — '$fake' skipped the scan (got $rc)"
done

# `+++` is a diff HEADER only when it follows `--- `. Matching `^+++ ` alone also
# ate added CONTENT beginning `++ `.
for lead in '++sk_live_ABCDEFG1234567890fake' '++ sk_live_ABCDEFG1234567890fake'; do
  PR="$TMP/plus$RANDOM"; mkdir -p "$PR"; git -C "$PR" init -q
  printf '%s\n' "$lead" > "$PR/d.patch"; git -C "$PR" add d.patch
  ( cd "$PR" && jq -nc --arg c "git commit -m x" '{tool_input:{command:$c}}' | PATH="$BIN_NO" bash "$HOOK" >/dev/null 2>&1 ); rc=$?
  [[ "$rc" -eq 2 ]] && pass "review5: added content starting '${lead:0:3}' is scanned" \
                    || fail "review5: diff filter ate content starting '${lead:0:3}' (got $rc)"
done

# --- K3. Known residuals — pinned so a change in behaviour is VISIBLE ---------
# NOT passing behaviour. These record what a PreToolUse string parser cannot do,
# so a future change that fixes OR worsens one is loud instead of silent.
# Wrapper and conditional-cd handling were REMOVED deliberately: each needed a
# per-tool CLI model, and getting it wrong produced FALSE BLOCKS in a hook that
# cannot be disabled — a worse failure than the gap it closed.
reset_index
echo 'const k = "sk_live_ABCDEFG1234567890fake";' > "$REPO/late.js"   # NOT staged
run_form "git add late.js && git commit -m x" "$REPO"; rc=$?
[[ "$rc" -eq 0 ]] && pass "residual: staging in the same command is invisible (hook runs before 'git add')" \
                  || fail "residual changed: pre-staging now returns $rc — update docs + threat model"
rm -f "$REPO/late.js"

reset_index; stage_secret
run_form "sudo git commit -m x" "$REPO"; rc=$?
[[ "$rc" -eq 0 ]] && pass "residual: wrapper-prefixed commit is not recognised" \
                  || fail "residual changed: wrapper now returns $rc — update docs + threat model"

run_form "cd /nonexistent-kerby-xyz || git commit -m x" "$REPO"; rc=$?
[[ "$rc" -eq 0 ]] && pass "residual: a FAILED conditional cd is still applied" \
                  || fail "residual changed: conditional cd now returns $rc — update docs"

git -C "$REPO" config alias.ci commit
run_form "git ci -m x" "$REPO"; rc=$?
[[ "$rc" -eq 0 ]] && pass "residual: a git alias resolves at runtime and is not seen" \
                  || fail "residual changed: alias now returns $rc — update docs + threat model"
git -C "$REPO" config --unset alias.ci

# FALSE BLOCKS these residuals buy back — the reason the machinery was removed.
run_form "sudo --user git commit -m x" "$REPO"; rc=$?
[[ "$rc" -eq 0 ]] && pass "no false block: 'sudo --user git commit' is not a git commit" \
                  || fail "false block: wrapper parsing misread a user name as the command (got $rc)"
CLEANC="$TMP/condclean"; mkdir -p "$CLEANC"; git -C "$CLEANC" init -q
echo ok > "$CLEANC/a"; git -C "$CLEANC" add a
run_form "cd $CLEANC || true; git commit -m x" "$REPO"; rc=$?
[[ "$rc" -eq 0 ]] && pass "no false block: conditional cd to a CLEAN repo does not block" \
                  || fail "false block: scanned the caller's index for a commit elsewhere (got $rc)"

# --- L. Matcher parity with swe's protect-git.sh ------------------------------
# base cannot depend on swe (base is the floor), so the commit matcher is
# duplicated. A regex literal is a constant, so the duplication is mechanically
# checkable — unlike a prose invariant. This is the guard that keeps the two
# copies from drifting; see skills/kerby/CLAUDE.md § Guard a constant.
SWE_HOOK="$SCRIPT_DIR/../../swe/hooks/protect-git.sh"
if [[ -f "$SWE_HOOK" ]]; then
  base_re=$(grep -m1 '^GIT_GLOBAL_OPT=' "$HOOK")
  swe_re=$(grep -m1 '^GIT_GLOBAL_OPT=' "$SWE_HOOK")
  { [[ -n "$base_re" && "$base_re" == "$swe_re" ]]; } \
    && pass "parity: GIT_GLOBAL_OPT identical to protect-git.sh" \
    || fail "parity: GIT_GLOBAL_OPT drifted from protect-git.sh"
  base_c=$(grep -m1 '^GIT_COMMIT_RE=' "$HOOK")
  swe_c=$(grep -m1 '^GIT_COMMIT_RE=' "$SWE_HOOK")
  { [[ -n "$base_c" && "$base_c" == "$swe_c" ]]; } \
    && pass "parity: GIT_COMMIT_RE identical to protect-git.sh" \
    || fail "parity: GIT_COMMIT_RE drifted from protect-git.sh"
else
  echo "SKIP: swe rulebook not present — matcher parity not checked"
fi

# --- Summary -----------------------------------------------------------------
echo "---"
if [[ "$FAILS" -eq 0 ]]; then
  echo "All assertions passed."
  exit 0
else
  echo "$FAILS assertion(s) failed."
  exit 1
fi
