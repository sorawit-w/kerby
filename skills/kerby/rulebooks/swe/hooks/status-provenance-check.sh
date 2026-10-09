#!/bin/bash
# Hook: STATUS.md holds position, never provenance — enforced at commit time.
# Type: PreToolUse on Bash matching git commit; also git's pre-commit hook (--git-hook)
# Name: status-provenance-check  (swe's status-provenance enforcer)
# Exit 2 = block action, stderr shown to the agent as feedback.
#
# Runs scripts/check-status-provenance.sh against .kerby/STATUS.md before a
# commit and refuses the commit when the file states a version, a SHA, or a
# PR/issue number. The guard has existed since swe 2.11.3 and nothing ran it: a
# STATUS.md naming a PR number, "awaiting review" and a SHA shipped in a sibling
# repo with the prose rule in force (2026-09-16), after a compaction had
# summarized the rule away. Prose cannot hold through that; a commit-time check
# can, and the shapes it matches are tokens, not phrasings (the guard's header).
#
# WHAT IS SCANNED — BOTH COPIES, EVERY TIME. Two copies of STATUS.md can differ
# from HEAD: the staged blob and the working-tree file. Which one a given
# `git commit` records depends on its flags and pathspecs, and this hook does
# NOT try to work that out. The first cut did — it tokenized the command,
# resolved pathspecs, modelled -a/-i/-p/--only/--dry-run, stripped redirections
# — and nine review rounds found a hole in every model of the shell it tried:
# key order, attached separators, quoted operators, escaped operators, braces,
# globs in option values, `{fd}>` redirections, abbreviated long options. Each
# hole was a MISS. So the classifier is gone: whenever either copy differs from
# HEAD it is scanned, and a hit in either blocks. The cost is a block on a
# STATUS.md that carries a token in a copy this particular commit would not
# have recorded — a state the rule forbids anyway, and the message names which
# copy. There is no shell shape left that turns a scan into a skip.
#
# TWO FRONT DOORS, one guard.
#
#   (default)    Claude Code PreToolUse — reads the tool call as JSON on stdin,
#                decides from the command TEXT whether a commit is happening,
#                then scans both copies as above.
#   --git-hook   git's own pre-commit hook — git already resolved the repo, the
#                flags and the index, so only the staged copy is scanned, and
#                only when this commit adds or changes STATUS.md. A committed
#                STATUS.md that this commit does not touch is not re-checked:
#                blocking every unrelated commit until someone edits the file is
#                the wrong cost. This path MUST NOT touch jq — a GUI git client
#                runs hooks with PATH=/usr/bin:/bin — so its fail-open is one
#                stderr line and exit 0. `kerby install` Phase 3 writes it into
#                one pre-commit file with every other in-scope git_hook check.
#
# NOT DISABLABLE via CODING_RULES_HOOK_DISABLED: severity is `block`, so the tier
# is `recommended` (docs/rulebook-contract.md § Hook tiers) and the token is
# refused. Decline the PreToolUse door at `kerby install` Phase 2 if you do not
# want it; the git door is declined only by declining Phase 3 as a whole, which
# also drops the git-side secret scan that shares its file. To get a commit
# through, move the token out of STATUS.md — into memory.log or the commit
# message, where it belongs — in whichever copy the message names.
#
# CEILINGS, stated:
#   - The PreToolUse door recognises `git … commit` with the subcommand in
#     position: after a line start, `;`, `&`, `|`, `(` or `$(`, with only
#     assignments (`GIT_DIR=x`) before git and only global options (`-C <dir>`,
#     `-c k=v`, `--no-pager`, …) between git and `commit`. So `cd x; git add … &&
#     git commit` and `git -C "<dir>" commit` are seen; `git log --grep commit`
#     and `echo "git commit"` are not commits. NOT seen: a wrapper before git
#     (`env`, `command`, `sudo`, `xargs`, `bash -c '…'`) or a git alias. grep
#     matches per line, so any line of a multi-line command can trigger it;
#     matching too much only costs a scan.
#   - The PreToolUse door scans the repo at the cwd, NOT a `-C`/`cd` target: a
#     commit into another repo may be blocked on, or pass, this repo's STATUS.md.
#     Resolving the target is the model-the-shell trap above. The git door
#     covers every shape in these two bullets, because git resolves them.
#   - The git door is skipped by `git commit --no-verify` and exists only in a
#     clone where Phase 3 was accepted (git hooks are never cloned). The
#     PreToolUse door still sees `--no-verify`; that is why both are kept.
#   - FAILS OPEN when its own guard script is missing or cannot scan: it says so
#     through additionalContext (stderr in --git-hook mode) and exits 0 — the
#     launcher's doctrine. A missing
#     guard means the kerby install is broken, and wedging every commit on it is
#     the wrong signal; the message names the repair.
#   - Scans the repo whose top level `git rev-parse` reports from the cwd; a
#     commit run from a subdirectory still finds the file.
#   - A `--dry-run` is blocked like a real commit when a copy carries a token: the
#     block message is the preview.
#   - It runs BEFORE the shell evaluates the command, at the tool boundary. A
#     command that rewrites STATUS.md as part of its own execution — a command
#     substitution with a side effect, a chained write — is out of reach of any
#     PreToolUse hook (references/threat-model.md § the tool-boundary limit). The
#     post-expansion home for this check is git's own pre-commit hook — the
#     --git-hook door above.

set -u

GIT_HOOK_MODE=0
if [[ "${1:-}" == "--git-hook" ]]; then
  GIT_HOOK_MODE=1   # a commit is definitionally happening; no command to read
else
  INPUT=$(cat)
  COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
  # git, then only global options, then the commit subcommand — after a line start,
  # `;` `&` `|` `(` or `$(` — never commit-tree / commit-graph (see CEILINGS).
  q="'"
  COMMIT_RE='(^|[;&|(]|\$\()[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*git([[:space:]]+((-C|-c|--git-dir|--work-tree|--namespace)[[:space:]]+("[^"]*"|'"$q[^$q]*$q"'|[^[:space:]]+)|-[A-Za-z]+|--[A-Za-z-]+(=[^[:space:]]+)?))*[[:space:]]+commit([[:space:];&|)]|$)'
  echo "$COMMAND" | grep -qE "$COMMIT_RE" || exit 0
fi

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
TOP=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
STATUS_REL=".kerby/STATUS.md"
STATUS="$TOP/$STATUS_REL"
GUARD="$( cd "$( dirname "${BASH_SOURCE[0]}" )/.." >/dev/null 2>&1 && pwd -P )/scripts/check-status-provenance.sh"
TMPF=""

warn_open() { # $1 = why; visible fail-open (additionalContext, or stderr in git mode), exit 0
  [[ -n "$TMPF" ]] && rm -f "$TMPF"
  local msg="STATUS-PROVENANCE CHECK (kerby): $1 — .kerby/STATUS.md was NOT checked for provenance before this commit. Re-run kerby install to repair the kerby install, and check the file by hand for a version, a SHA, or a PR/issue number."
  if [[ $GIT_HOOK_MODE -eq 1 ]]; then
    echo "$msg" >&2
  else
    jq -n --arg ctx "$msg" '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}'
  fi
  exit 0
}
[[ -r "$GUARD" ]] || warn_open "guard script missing at $GUARD"

run_guard() { # $1 = file to scan, $2 = which copy; blocks (exit 2) on a hit
  local out rc
  out=$(bash "$GUARD" "$1" 2>&1); rc=$?
  [[ $rc -eq 0 ]] && return 0
  # Non-zero without a hit means the guard could not scan — fail open, visibly.
  echo "$out" | grep -q 'states a' || warn_open "guard could not scan the $2 copy: $(echo "$out" | grep '^FAIL' | head -1 | cut -c1-160)"
  {
    echo "BLOCKED: .kerby/STATUS.md ($2) states provenance."
    echo "$out" | grep '^FAIL:' | sed "s#${1}#.kerby/STATUS.md#"
    echo "Reason: STATUS.md holds position, never provenance — a version, a SHA, or a PR/issue number has an authority elsewhere (the manifests, git, the tracker, the commit message), and a copy here can only drift."
    if [[ $GIT_HOOK_MODE -eq 1 ]]; then
      echo "git's pre-commit hook checks the staged copy this commit records."
    else
      echo "Both the staged and the working-tree copy are checked on every commit, whatever the flags."
    fi
    echo "Fix: name the change in words in the $2 copy, keep the number in the commit message or memory.log, and re-stage. This check is not disablable — decline it at 'kerby install' if you do not want it."
    echo "See kerby guardrails (rulebooks/swe/references/communication.md § Status Tracking; hooks/status-provenance-check.sh)."
  } >&2
  [[ -n "$TMPF" ]] && rm -f "$TMPF"
  exit 2
}

# Git door: git runs this hook from the worktree top level with GIT_INDEX_FILE
# pointing at the index being committed, so plain git reads exactly what will be
# recorded. Only a STATUS.md this commit adds or changes is scanned.
if [[ $GIT_HOOK_MODE -eq 1 ]]; then
  if git diff --cached --name-only --diff-filter=ACMRT -- ":(top)$STATUS_REL" 2>/dev/null | grep -q .; then
    TMPF=$(mktemp) || warn_open "cannot create a temp file for the staged blob"
    git show ":$STATUS_REL" > "$TMPF" 2>/dev/null || warn_open "cannot read the staged .kerby/STATUS.md"
    run_guard "$TMPF" "staged"
    rm -f "$TMPF"
  fi
  exit 0
fi

# The staged copy, when STATUS.md is staged (any change kind, type changes included).
if git -C "$TOP" diff --cached --name-only --diff-filter=ACMRT -- ":(top)$STATUS_REL" 2>/dev/null | grep -q .; then
  TMPF=$(mktemp) || warn_open "cannot create a temp file for the staged blob"
  git -C "$TOP" show ":$STATUS_REL" > "$TMPF" 2>/dev/null || warn_open "cannot read the staged .kerby/STATUS.md"
  run_guard "$TMPF" "staged"
  rm -f "$TMPF"; TMPF=""
fi

# The working-tree copy, when it is untracked or differs from HEAD (or HEAD is
# absent) — an interactive commit can add an untracked file. A symlink commits as
# a blob holding its TARGET TEXT, so that is what is scanned.
if [[ -e "$STATUS" || -L "$STATUS" ]] && { ! git -C "$TOP" ls-files --error-unmatch -- "$STATUS_REL" >/dev/null 2>&1 || ! git -C "$TOP" diff --quiet HEAD -- "$STATUS_REL" 2>/dev/null; }; then
  if [[ -L "$STATUS" ]]; then
    TMPF=$(mktemp) || warn_open "cannot create a temp file for the symlink target"
    readlink "$STATUS" > "$TMPF"
    run_guard "$TMPF" "working tree, symlink target"
    rm -f "$TMPF"; TMPF=""
  else
    run_guard "$STATUS" "working tree"
  fi
fi

exit 0
