#!/bin/bash
# Hook: Hard-block edits to files that hold live credentials (security guardrail)
# Type: PreToolUse on Edit|Write matching .env
# Name: protect-env
# Exit 2 = block action, stderr shown to agent as feedback
#
# This hook is NOT disablable via CODING_RULES_HOOK_DISABLED.
# Security-critical hooks cannot be toggled off by an env var. hooks.md is
# explicit about why: an env var is too easy to set accidentally (shell rc, CI
# config, .envrc — and direnv writes .envrc in the same directory as .env).
# To bypass, remove the hook from .claude/settings.json — a deliberate file edit.
#
# WHAT THIS GUARDS, AND WHAT IT DOES NOT.
# The risk here is NOT a secret reaching git — base's pre-commit-check.sh scans
# the staged diff and is filename-agnostic, so a real secret pasted into ANY
# committed file is caught there. The risk this hook owns is the one the commit
# scan structurally cannot see: a real `.env` is gitignored, never staged, and
# therefore has no undo. Overwriting one destroys credentials git cannot restore.
# That is the base floor's `approval-for-irreversible` rule, made concrete.
#
# The two classes have opposite risk profiles, so they get opposite treatment:
#
#   .env.example / .env.template / .env.sample   committed, no secrets, and the
#     documented handoff surface for required-var names -> ALLOWED. The commit
#     scan already covers the "someone pasted a real key in the template" case,
#     so blocking here bought nothing and broke a standard workflow.
#
#   .env, .env.local, and every other .env variant  gitignored, holds live
#     credentials, unrecoverable -> BLOCKED once it exists.
#
# CREATE-IF-ABSENT. The thing worth protecting is an EXISTING populated file. If
# the target does not exist there is nothing to destroy, so creating one is
# allowed — that is what lets an agent scaffold a project's .env from
# .env.example. The moment the file has content, it is blocked again.
#
# Deliberately NOT keyed on the tool name (Write vs Edit): Edit fails on a
# missing file anyway, so existence alone carries the same guarantee without
# depending on a payload field this hook would otherwise have to trust.
#
# RELATIVE PATHS FAIL CLOSED. An existence test only means something if it runs
# against the path the agent actually targets. This hook cannot know the agent's
# cwd, so a relative path is blocked rather than resolved against the hook's own
# cwd — resolving it there could report "absent" for a populated file and allow
# the overwrite. Claude Code's Write/Edit tools pass absolute paths, so this
# costs nothing in practice and removes the one way create-if-absent could be
# wrong.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# 1. Not an env file at all -> not our business.
if ! echo "$FILE_PATH" | grep -qE '\.env($|\.)'; then
  exit 0
fi

# 2. Template carve-out. Anchored on the BASENAME suffix, never a substring:
#    `.env.example.bak` is not a template and must not slip through.
BASENAME=$(basename "$FILE_PATH")
if echo "$BASENAME" | grep -qE '\.env\.(example|template|sample)$'; then
  exit 0
fi

# 3. Create-if-absent — absolute paths only (see RELATIVE PATHS FAIL CLOSED).
if [[ "$FILE_PATH" == /* ]] && [[ ! -e "$FILE_PATH" ]]; then
  exit 0
fi

# 4. Everything else: an existing credential file, or a path we cannot resolve.
echo "BLOCKED: $BASENAME holds live credentials and is not in git — an overwrite cannot be undone." >&2
echo "Hand the required variables to the user to add themselves:" >&2
echo "  <VAR>=<value>" >&2
echo "Placeholders belong in .env.example / .env.template / .env.sample, which you may edit." >&2
echo "See kerby guardrails (references/guardrails.md § Environment Files)." >&2
exit 2
