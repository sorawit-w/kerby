#!/bin/bash
# Self-test for codex-pr-gate.sh — verifies `gh pr create` is blocked without
# a fresh marker (exit 2), allowed with one (exit 0), bypass is per-invocation
# direct-prefix only, cd/pushd/-C combos are refused, and jq-missing degrades
# to an announced allow. Runs against a scratch git repo fixture.
#
# Run from anywhere: bash codex-pr-gate.test.sh
# Exit 0 = all assertions pass; non-zero = a failure.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
HOOK="$SCRIPT_DIR/codex-pr-gate.sh"

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

# Scratch git repo fixture (the hook resolves the repo from its cwd).
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
git -C "$WORK" init -q
git -C "$WORK" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
GITDIR=$(git -C "$WORK" rev-parse --git-dir)
case "$GITDIR" in /*) ;; *) GITDIR="$WORK/$GITDIR" ;; esac
HEAD_SHA=$(git -C "$WORK" rev-parse HEAD)
MARKER="$GITDIR/codex-reviewed"

run() { # $1 = command string -> sets RC (hook runs with cwd = fixture repo)
  printf '{"tool_input":{"command":%s}}' "$(printf '%s' "$1" | jq -R .)" \
    | (cd "$WORK" && bash "$HOOK") >/dev/null 2>&1
  RC=$?
}

# --- No marker: guarded forms must BLOCK (exit 2) ----------------------------
rm -f "$MARKER"
BLOCK_NO_MARKER=(
  "gh pr create --title t --body b"
  "gh  pr create"                                       # double space
  $'gh\tpr\tcreate'                                     # tabs
  'gh pr create --body "set CODEX_GATE_BYPASS=1 to bypass"'  # embedded token: NOT a bypass
  "CODEX_GATE_BYPASS=1 gh pr create; gh pr create"      # masking: 2nd invocation unauthorized
  "gh pr create; CODEX_GATE_BYPASS=1 gh pr create"      # reversed masking
  "gh --help pr create"                                 # non-repo global flag before subcommand: still gated
  "gh pr new"                                           # built-in alias for pr create
  "gh pr new --fill"
  "gh -Xfoo pr create"                                  # arbitrary attached short flag: broad matcher still gates
)
for cmd in "${BLOCK_NO_MARKER[@]}"; do
  run "$cmd"
  [[ "$RC" -eq 2 ]] && pass "blocks (no marker): $cmd" || fail "should block, got $RC: $cmd"
done

# --- cd/pushd/-C combos: refused regardless of marker ------------------------
printf '%s\n' "$HEAD_SHA" > "$MARKER"
REFUSE=(
  "cd /tmp && gh pr create"
  "pushd /tmp && gh pr create"
  "git -C /tmp pull && gh pr create"
  "gh -R owner/repo pr create"          # repo-targeting global flag: wrong-repo refusal
  "gh --repo owner/repo pr create"
  "gh --repo=owner/repo pr create"
  "gh -R owner/repo pr new"             # alias + repo-targeting flag
  "gh -Rowner/repo pr create"           # attached -R value (verified valid gh syntax)
  "gh -R=owner/repo pr create"          # -R=value form
  "GH_REPO=other/repo gh pr create"     # env-var repo retarget: wrong-repo refusal
)
for cmd in "${REFUSE[@]}"; do
  run "$cmd"
  [[ "$RC" -eq 2 ]] && pass "refuses combo: $cmd" || fail "should refuse, got $RC: $cmd"
done

# --- Fresh marker: standalone form passes -------------------------------------
run "gh pr create --fill"
[[ "$RC" -eq 0 ]] && pass "allows with fresh marker" || fail "should allow with marker, got $RC"

# --- Stale marker (marker != HEAD): block -------------------------------------
printf '0000000000000000000000000000000000000000\n' > "$MARKER"
run "gh pr create"
[[ "$RC" -eq 2 ]] && pass "blocks stale marker" || fail "should block stale marker, got $RC"
rm -f "$MARKER"

# --- Bypass: direct prefix only ------------------------------------------------
ALLOW_BYPASS=(
  "CODEX_GATE_BYPASS=1 gh pr create --fill"
  "cd /tmp && CODEX_GATE_BYPASS=1 gh pr create"   # bypass precedes cd-refusal (precedence rule 1)
  "CODEX_GATE_BYPASS=1 gh -R owner/repo pr create"  # strip swallows the global flag too
  "CODEX_GATE_BYPASS=1 gh pr new"                   # alias bypass
)
for cmd in "${ALLOW_BYPASS[@]}"; do
  run "$cmd"
  [[ "$RC" -eq 0 ]] && pass "bypass allows: $cmd" || fail "bypass should allow, got $RC: $cmd"
done

# --- Non-guarded commands pass through ----------------------------------------
ALLOW=(
  "git status"
  "gh pr view 12"
  "echo 'gh pr created a thing'"                  # 'created' != create-invocation... still matches? see below
)
run "git status";   [[ "$RC" -eq 0 ]] && pass "allows: git status" || fail "should allow git status, got $RC"
run "gh pr view 12"; [[ "$RC" -eq 0 ]] && pass "allows: gh pr view" || fail "should allow gh pr view, got $RC"

# 'gh pr create' inside quoted prose still string-matches — documented ceiling
# (safe direction: over-block). Pin the behavior so a change is deliberate.
run "echo 'how gh pr create works'"
[[ "$RC" -eq 2 ]] && pass "quoted-prose match over-blocks (documented ceiling)" || fail "ceiling behavior changed, got $RC"

# --- Empty / no-jq -------------------------------------------------------------
printf '{"tool_input":{"command":""}}' | (cd "$WORK" && bash "$HOOK") >/dev/null 2>&1
[[ "$?" -eq 0 ]] && pass "empty command exits 0" || fail "empty command should exit 0"

# no-jq: degraded allow, announced via additionalContext JSON on STDOUT (not
# stderr — exit-0 stderr is invisible to the agent). Build a PATH with the tools
# the hook needs but deliberately no jq.
FAKEBIN=$(mktemp -d)
for t in bash sh cat printf grep sed git; do
  p=$(command -v "$t" 2>/dev/null) && ln -s "$p" "$FAKEBIN/$t"
done
NOJQ_OUT=$(printf '{"tool_input":{"command":"gh pr create"}}' \
  | (cd "$WORK" && PATH="$FAKEBIN" "$FAKEBIN/bash" "$HOOK") 2>/dev/null)
NOJQ_RC=$?
rm -rf "$FAKEBIN"
if [[ "$NOJQ_RC" -eq 0 && "$NOJQ_OUT" == *'"additionalContext"'* && "$NOJQ_OUT" == *DEGRADED* ]]; then
  pass "no-jq degrades to allow with additionalContext JSON on stdout"
else
  fail "no-jq should allow (0) with DEGRADED additionalContext on stdout, got rc=$NOJQ_RC out=$NOJQ_OUT"
fi

echo
if [[ "$FAILS" -eq 0 ]]; then echo "ALL PASS"; else echo "$FAILS FAILURE(S)"; exit 1; fi
