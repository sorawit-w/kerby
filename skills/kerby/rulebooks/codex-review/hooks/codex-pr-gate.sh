#!/bin/bash
# Hook: block `gh pr create` unless a Codex review marker exists for HEAD.
# Type: PreToolUse on Bash
# Name: codex-pr-gate
#
# The marker ($GIT_DIR/codex-reviewed) is written ONLY by this rulebook's
# scripts/codex-mark.sh after a clean CODEX_VERDICT (P0=0 P1=0) — never by
# hand. Hand-writing it is gate-dodging.
#
# Check precedence (each step sees the STRIPPED command — authorized
# invocations removed):
#   1. No guarded `gh pr create` invocation remains -> allow. This is why a
#      direct-prefix bypass (`CODEX_GATE_BYPASS=1 gh pr create`) skips ALL
#      later checks including the cd-refusal: with no marker check to run,
#      there is no wrong-repo risk. The bypass is per-invocation (the
#      strip-then-residual pattern below, same idiom as swe's protect-git):
#      one authorized invocation never authorizes a second bare one, and the
#      token embedded in PR-body text never authorizes anything.
#   2. Residual guarded invocation combined with cd/pushd/-C -> refuse: the
#      marker check runs in the hook's cwd, so a directory-changing command
#      would be checked against the WRONG repo.
#   3. Marker check: $GIT_DIR/codex-reviewed must hold the current HEAD sha.
#
# Escape hatch: CODEX_GATE_BYPASS=1 directly prefixing the gh invocation,
# user-authorized only (manifest override = "authorized-scoped"). An
# ambient/exported var or an embedded token is deliberately NOT honored.
# NOT disablable via CODING_RULES_HOOK_DISABLED — this is a gate.
#
# Known ceilings (README): string-match, not a shell parser — a
# line-continuation split across lines evades it, and ` -C ` in quoted
# title/body text can false-BLOCK (safe direction; rerun standalone or
# bypass). jq missing -> degraded ALLOW, announced on stderr.
# Exit codes: 0 = allow, 2 = block (reason on stderr).

set -u

INPUT=$(cat)

if ! command -v jq >/dev/null 2>&1; then
  # Surface the degrade on STDOUT via additionalContext — the channel the agent
  # reads on a PreToolUse exit 0 (plain stderr on exit 0 is NOT shown to the
  # model, so the announce would otherwise be silent). Built by hand, not jq —
  # jq is the missing thing; the message is a fixed literal with no interpolation.
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","additionalContext":"codex-pr-gate: jq not found — the PR gate cannot parse the command and is DEGRADED (allowing gh pr create without a marker check). Install jq to restore enforcement."}}'
  exit 0
fi

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty')
[ -z "$CMD" ] && exit 0

# Whitespace-tolerant guarded-command matcher. Three ways a naive match failed:
#   - a literal substring let `gh  pr create` / tab forms through;
#   - matching only contiguous `gh pr create` let `gh <global-opts> pr create`
#     (e.g. `gh -R owner/repo pr create`) fail OPEN — the hook exited before the
#     marker check on ordinary CLI syntax;
#   - `create` alone missed `gh pr new`, gh's built-in alias for `pr create`
#     (verified: `gh pr new --help` prints "Create a pull request").
# So: allow gh global option-SHAPED tokens (same idea as protect-git's
# GIT_GLOBAL_OPT) between `gh` and `pr`, and match both subcommand spellings.
# create-side flags already follow the subcommand and need no handling here.
# Ceiling: user-defined `gh alias set` shortcuts are not resolved (documented).
GH_GLOBAL_OPT='(-R[[:space:]]+[^[:space:]]+|--repo[=[:space:]][^[:space:]]+|--[A-Za-z][A-Za-z-]*=[^[:space:]]+|--[A-Za-z][A-Za-z-]*|-[A-Za-z])'
GH_PR_OPEN_RE="(^|[^[:alnum:]_-])gh([[:space:]]+${GH_GLOBAL_OPT})*[[:space:]]+pr[[:space:]]+(create|new)\\b"

echo "$CMD" | grep -qE "$GH_PR_OPEN_RE" || exit 0

# Strip every bypass-AUTHORIZED invocation (token directly prefixing the gh,
# consuming through to the next command separator — so it also swallows any
# global flags after gh), then re-test the residual.
STRIPPED=$(printf '%s' "$CMD" | sed -E 's/(^|[[:space:]])CODEX_GATE_BYPASS=1[[:space:]]+gh[^|;&]*//g')

echo "$STRIPPED" | grep -qE "$GH_PR_OPEN_RE" || exit 0  # all guarded invocations authorized

# The marker check below runs in the hook's cwd and validates the LOCAL repo's
# HEAD. A residual command that changes directory (cd/pushd/-C) or retargets
# the PR to another repo (gh -R/--repo flags, or an in-command GH_REPO=
# assignment) would be checked against, or create the PR in, the WRONG repo —
# so refuse. Run the command plain, from the repo it belongs to.
# Ceiling: an already-EXPORTED GH_REPO (not in the command string) is invisible
# to a PreToolUse hook, same as protect-git's ambient-var blindness — documented.
if echo "$STRIPPED" | grep -qE '(^|[^[:alnum:]_-])(cd|pushd)[[:space:]]' || \
   echo "$STRIPPED" | grep -qE '[[:space:]]-C[[:space:]]' || \
   echo "$STRIPPED" | grep -qE '[[:space:]](-R[[:space:]]|--repo([[:space:]]|=))' || \
   echo "$STRIPPED" | grep -qE '(^|[[:space:]])GH_REPO='; then
  echo "Codex PR gate: run 'gh pr create' as a standalone command from the session's working directory — no cd/pushd/-C, no -R/--repo, no GH_REPO= (those would make the gate check, or the PR target, the wrong repo). To bypass deliberately (user-authorized only), prefix the gh invocation with CODEX_GATE_BYPASS=1." >&2
  exit 2
fi

gitdir=$(git rev-parse --git-dir 2>/dev/null) || exit 0
head=$(git rev-parse HEAD 2>/dev/null) || exit 0

marker="$gitdir/codex-reviewed"
if [ -f "$marker" ] && [ "$(cat "$marker")" = "$head" ]; then
  exit 0
fi

echo "Codex PR gate: no P0/P1-clean Codex review recorded for HEAD ($head)." >&2
echo "Run the Codex review teed to \"$gitdir/codex-review.log\" (the brief must require the final CODEX_VERDICT line), then run this rulebook's scripts/codex-mark.sh — the only sanctioned marker writer." >&2
echo "codex-mark writes the marker only on PASS (P0=0 P1=0). To bypass deliberately (user-authorized only), prefix the gh invocation with CODEX_GATE_BYPASS=1. See kerby guardrails (hooks/codex-pr-gate.sh)." >&2
exit 2
