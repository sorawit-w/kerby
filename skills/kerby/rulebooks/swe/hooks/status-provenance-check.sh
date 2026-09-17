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
# WHICH FILE IS SCANNED. `git commit` has three shapes, and each records a
# different STATUS.md:
#   plain                 the INDEX (the staged blob) — a clean working tree over
#                         a dirty index is exactly what a working-tree scan passes
#   -a / --all            the WORKING TREE of every tracked file
#   <pathspec>...         the WORKING TREE of the named paths ONLY; the index is
#                         NOT recorded — unless -i/--include adds it as well
# A pathspec need not spell the file name — `.`, `.kerby`, `:/`, a relative path
# from a subdirectory — so it is RESOLVED, never text-matched: the tokens are
# handed to `git ls-files --full-name` from the cwd, and the answer is whether
# .kerby/STATUS.md is among them. The tokenizer is minimal (quotes, backslashes,
# stop at the first shell separator); an unbalanced quote is undecidable and
# falls to the SAFE side — both sources are scanned.
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
STATUS_REL=".kerby/STATUS.md"
STATUS="$TOP/$STATUS_REL"
GUARD="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd -P )/scripts/check-status-provenance.sh"
TMPF=""

warn_open() { # $1 = why; visible fail-open via additionalContext, exit 0
  [[ -n "$TMPF" ]] && rm -f "$TMPF"
  jq -n --arg ctx "STATUS-PROVENANCE CHECK (kerby): $1 — the .kerby/STATUS.md this commit records was NOT checked for provenance. Re-run kerby install to repair the kerby install, and check the file by hand for a version, a SHA, or a PR/issue number." \
    '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}'
  exit 0
}
[[ -r "$GUARD" ]] || warn_open "guard script missing at $GUARD"

# --- Tokenize the command: one shell word per line; a final \001 line means an
# unbalanced quote (undecidable).
tokens() {
  printf '%s' "$1" | awk '
    { s = $0; L = length(s); q = ""; t = ""
      for (i = 1; i <= L; i++) { c = substr(s, i, 1)
        if (q != "") { if (c == q) q = ""; else t = t c }
        else if (c == "\"" || c == "\047") q = c
        else if (c == "\\") { i++; t = t substr(s, i, 1) }
        else if (c == " " || c == "\t") { if (t != "") { print t; t = "" } }
        else t = t c }
      if (t != "") print t
      if (q != "") print "\001" }'
}

# --- Classify the commit: ALL (-a), INCLUDE (-i), and the positional pathspecs.
ALL=0; INCLUDE=0; SPECS=(); UNDECIDABLE=0; n=0; expect_value=0; after_dashdash=0
while IFS= read -r tok; do
  [[ "$tok" == $'\001' ]] && { UNDECIDABLE=1; break; }
  n=$((n + 1)); [[ $n -le 2 ]] && continue            # `git` `commit`
  if [[ $after_dashdash -eq 1 ]]; then SPECS+=("$tok"); continue; fi
  if [[ $expect_value -eq 1 ]]; then expect_value=0; continue; fi
  case "$tok" in
    '&&'|'||'|';'|'|') break ;;
    --) after_dashdash=1 ;;
    --all) ALL=1 ;;
    --include) INCLUDE=1 ;;
    --author|--date|--cleanup|--template|--file|--message|--fixup|--squash|--reuse-message|--reedit-message|--trailer|--pathspec-from-file) expect_value=1 ;;
    --*) ;;                                            # long option, value attached with = or none
    -?*)                                               # short cluster: -am "x", -i, -mfoo, -Ffile
      letters="${tok#-}"
      while [[ -n "$letters" ]]; do
        l="${letters:0:1}"; letters="${letters:1}"
        case "$l" in
          a) ALL=1 ;;
          i) INCLUDE=1 ;;
          m|F|C|c|t) if [[ -z "$letters" ]]; then expect_value=1; fi; break ;;   # attached value, or the next token
        esac
      done ;;
    *) SPECS+=("$tok") ;;
  esac
done < <(tokens "$COMMAND")

covered() { # do the pathspecs resolve to STATUS.md? 0 yes / 1 no / 2 undecidable
  [[ ${#SPECS[@]} -gt 0 ]] || return 1
  local out
  out=$(git ls-files --full-name -- "${SPECS[@]}" 2>/dev/null) || return 2
  grep -qx "$STATUS_REL" <<<"$out"
}

if [[ $UNDECIDABLE -eq 1 ]]; then MODE=both
elif [[ $ALL -eq 1 ]]; then MODE=worktree
elif [[ ${#SPECS[@]} -gt 0 ]]; then
  covered; rc=$?
  case $rc in
    0) MODE=worktree ;;
    1) if [[ $INCLUDE -eq 1 ]]; then MODE=index; else MODE=none; fi ;;
    *) MODE=both ;;
  esac
else MODE=index; fi

run_guard() { # $1 = file to scan, $2 = which source; blocks (exit 2) on a hit
  local out rc
  out=$(bash "$GUARD" "$1" 2>&1); rc=$?
  [[ $rc -eq 0 ]] && return 0
  # Non-zero without a hit means the guard could not scan — fail open, visibly.
  echo "$out" | grep -q 'states a' || warn_open "guard could not scan the $2 file: $(echo "$out" | grep '^FAIL' | head -1 | cut -c1-160)"
  {
    echo "BLOCKED: the .kerby/STATUS.md this commit records ($2) states provenance."
    echo "$out" | grep '^FAIL:' | sed "s#${1}#.kerby/STATUS.md#"
    echo "Reason: STATUS.md holds position, never provenance — a version, a SHA, or a PR/issue number has an authority elsewhere (the manifests, git, the tracker, the commit message), and a copy here can only drift."
    echo "Fix: name the change in words, and keep the number in the commit message or memory.log; then re-stage the file. This check is not disablable — decline it at 'kerby install' if you do not want it."
    echo "See kerby guardrails (rulebooks/swe/references/communication.md § Status Tracking; hooks/status-provenance-check.sh)."
  } >&2
  [[ -n "$TMPF" ]] && rm -f "$TMPF"
  exit 2
}

scan_worktree() { # the working-tree file, when it differs from HEAD (or HEAD is absent)
  [[ -f "$STATUS" ]] || return 0
  git -C "$TOP" diff --quiet HEAD -- "$STATUS_REL" 2>/dev/null && return 0
  run_guard "$STATUS" "working tree"
}
scan_index() { # the staged blob, when STATUS.md is staged
  git -C "$TOP" diff --cached --name-only --diff-filter=ACMR -- ":(top)$STATUS_REL" 2>/dev/null | grep -q . || return 0
  TMPF=$(mktemp) || warn_open "cannot create a temp file for the staged blob"
  git -C "$TOP" show ":$STATUS_REL" > "$TMPF" 2>/dev/null || warn_open "cannot read the staged .kerby/STATUS.md"
  run_guard "$TMPF" "staged"
  rm -f "$TMPF"; TMPF=""
}

case "$MODE" in
  none)     exit 0 ;;
  worktree) scan_worktree ;;
  index)    scan_index ;;
  both)     scan_index; scan_worktree ;;
esac
exit 0
