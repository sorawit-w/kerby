#!/bin/bash
# Hook: STATUS.md holds position, never provenance — enforced at commit time.
# Type: PreToolUse on Bash matching git commit
# Name: status-provenance-check  (swe's status-provenance enforcer)
# Exit 2 = block action, stderr shown to the agent as feedback.
#
# Runs scripts/check-status-provenance.sh against the .kerby/STATUS.md that is
# ABOUT TO BE COMMITTED and refuses the commit when it states a version, a SHA,
# or a PR/issue number. The guard has existed since swe 2.11.3 and nothing ran
# it: a STATUS.md naming a PR number, "awaiting review" and a SHA shipped in a
# sibling repo with the prose rule in force (2026-09-16), after a compaction had
# summarized the rule away. Prose cannot hold through that; a commit-time check
# can, and the shapes it matches are tokens, not phrasings (the guard's header).
#
# WHICH FILE IS SCANNED. The staged blob (`git show :.kerby/STATUS.md`), because
# that is what the commit records — a clean working tree over a dirty index is
# exactly the case a working-tree scan would pass. Except when the command
# bypasses the index: `-a`/`--all`, `-i`/`--include`, or a pathspec naming the
# file commit the WORKING-TREE version, so those scan the working tree (when it
# differs from HEAD).
#
# NOT DISABLABLE via CODING_RULES_HOOK_DISABLED: severity is `block`, so the tier
# is `recommended` (docs/rulebook-contract.md § Hook tiers) and the token is
# refused. Decline it at `kerby install` if you do not want it. To get one commit
# through, move the token out of STATUS.md — into memory.log or the commit
# message, where it belongs — and re-stage.
#
# CEILINGS, stated:
#   - Recognises `git commit` at the start of the command only. `git -C <dir>
#     commit` and `cd x && git commit` are not seen — the same ceiling as
#     hollow-test-check.sh (base's secret scan carries the full tokenizer; this
#     sibling deliberately does not copy it).
#   - FAILS OPEN when its own guard script is missing or cannot scan: it says so
#     through additionalContext and exits 0 — the launcher's doctrine. A missing
#     guard means the kerby install is broken, and wedging every commit on it is
#     the wrong signal; the message names the repair.
#   - Scans the repo whose top level `git rev-parse` reports from the cwd; a
#     commit run from a subdirectory still finds the file.

set -u

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only git commit commands.
if ! echo "$COMMAND" | grep -qE '^git commit'; then
  exit 0
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
TOP=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
STATUS="$TOP/.kerby/STATUS.md"
GUARD="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd -P )/scripts/check-status-provenance.sh"

warn_open() { # $1 = why; visible fail-open via additionalContext, exit 0
  jq -n --arg ctx "STATUS-PROVENANCE CHECK (kerby): $1 — the .kerby/STATUS.md this commit records was NOT checked for provenance. Re-run kerby install to repair the kerby install, and check the file by hand for a version, a SHA, or a PR/issue number." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}'
  exit 0
}
[[ -r "$GUARD" ]] || warn_open "guard script missing at $GUARD"

# Which version of the file this commit records.
SCAN=""
TMPF=""
if echo "$COMMAND" | grep -qE -- '(^|[[:space:]])(--all|--include|-[a-zA-Z]*[ai][a-zA-Z]*)([[:space:]]|$)' \
   || echo "$COMMAND" | grep -qE '\.kerby/STATUS\.md'; then
  # Index bypassed: the working-tree file is what gets committed — if it changed.
  if [[ -f "$STATUS" ]] && ! git -C "$TOP" diff --quiet HEAD -- .kerby/STATUS.md 2>/dev/null; then
    SCAN="$STATUS"
  fi
elif git -C "$TOP" diff --cached --name-only --diff-filter=ACMR -- ':(top).kerby/STATUS.md' 2>/dev/null | grep -q .; then
  TMPF=$(mktemp) || warn_open "cannot create a temp file for the staged blob"
  if ! git -C "$TOP" show :.kerby/STATUS.md > "$TMPF" 2>/dev/null; then
    rm -f "$TMPF"; warn_open "cannot read the staged .kerby/STATUS.md"
  fi
  SCAN="$TMPF"
fi
[[ -n "$SCAN" ]] || exit 0

OUT=$(bash "$GUARD" "$SCAN" 2>&1); rc=$?
[[ -n "$TMPF" ]] && rm -f "$TMPF"
[[ $rc -eq 0 ]] && exit 0

# Non-zero without a hit means the guard could not scan — fail open, visibly.
echo "$OUT" | grep -q 'states a' || warn_open "guard could not scan the file: $(echo "$OUT" | grep '^FAIL' | head -1 | cut -c1-160)"

{
  echo "BLOCKED: the .kerby/STATUS.md this commit records states provenance."
  echo "$OUT" | grep '^FAIL:' | sed "s#${SCAN}#.kerby/STATUS.md#"
  echo "Reason: STATUS.md holds position, never provenance — a version, a SHA, or a PR/issue number has an authority elsewhere (the manifests, git, the tracker, the commit message), and a copy here can only drift."
  echo "Fix: name the change in words, and keep the number in the commit message or memory.log; then re-stage the file. This check is not disablable — decline it at 'kerby install' if you do not want it."
  echo "See kerby guardrails (rulebooks/swe/references/communication.md § Status Tracking; hooks/status-provenance-check.sh)."
} >&2
exit 2
