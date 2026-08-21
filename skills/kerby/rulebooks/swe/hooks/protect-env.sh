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
# the staged diff and is filename-agnostic. The risk this hook owns is the one a
# commit-time scan structurally cannot see: a real `.env` is gitignored, never
# staged, and therefore has no undo. Overwriting one destroys credentials git
# cannot restore. That is the base floor's `approval-for-irreversible` rule,
# made concrete.
#
# Coverage is Edit/Write only. A shell `printf > .env` never reaches this hook
# (references/threat-model.md records that gap). So this guards the accidental
# and the casual overwrite, not an agent determined to evade it.
#
# THE DECISION, IN ORDER. Each step exists because skipping it was exploitable:
#
#   1. Classify on the BASENAME, never the full path. `/repo/.env.d/notes.txt`
#      is not an env file; matching the whole path blocked it and told the user
#      it held credentials.
#   2. Env-family paths must be ABSOLUTE. This hook cannot know the agent's cwd,
#      so a relative path makes every later test (exists? symlink? hard link?) a
#      guess against the wrong directory. Fail closed. Claude Code's Edit/Write
#      pass absolute paths, so this costs nothing real.
#   3. No symlinks, ever. `.env.example -> .env` is a template NAME pointing at
#      the credential FILE; trusting the name hands over the inode. A dangling
#      symlink is just as bad on the create path — the write follows it to the
#      target. A legitimate template is a regular file.
#   4. Templates must not be hard-linked. `ln .env .env.sample` gives the
#      credential inode a second, allow-listed name, and no amount of path
#      resolution can see it — both names are equally real. Link count can.
#   5. Only then: an existing env file blocks; an absent one is allowed, so an
#      agent can scaffold a project's .env from its .env.example. Once the file
#      exists the door shuts again.
#
# Matching uses bash `case` with `nocasematch`, not `grep`:
#   - case-insensitive because macOS filesystems are. `.ENV` and `.env` are ONE
#     file there, and a case-sensitive test allowed an agent blocked on `.env`
#     to retry as `.ENV` and clobber the same inode.
#   - `case` has no line semantics. `grep -E '…$'` anchors at any embedded
#     newline, so a file literally named `.env.example\n.live` matched the
#     template allow-list on its first line.
#
# Deliberately NOT keyed on the tool name (Write vs Edit): Edit fails on a
# missing file anyway, so existence alone carries the same guarantee without
# depending on a payload field this hook would otherwise have to trust.

INPUT=$(cat)
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.path // empty')

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

BASENAME=${FILE_PATH##*/}

shopt -s nocasematch

# 1. Not an env-family basename -> not our business. Checked on the basename so a
#    directory component like `.env.d/` cannot drag ordinary files in.
case "$BASENAME" in
  *.env|*.env.*) ;;
  *) exit 0 ;;
esac

block() { # $1 = reason line
  echo "BLOCKED: $1" >&2
  echo "Env files are the one class git cannot restore — a real .env is gitignored, so an" >&2
  echo "overwrite has no undo. Hand the required variables to the user to add themselves:" >&2
  echo "  <VAR>=<value>" >&2
  echo "Placeholders belong in .env.example / .env.template / .env.sample — a regular file," >&2
  echo "named absolutely, which is neither a symlink nor a hard link to another file." >&2
  echo "See kerby guardrails (references/guardrails.md § Environment Files)." >&2
  exit 2
}

# 2. Env-family paths must be absolute, templates included — every test below
#    resolves against the filesystem and is meaningless on a relative path.
if [[ "$FILE_PATH" != /* ]]; then
  block "relative path '$FILE_PATH' — cannot tell which file this resolves to."
fi

# 3. A symlink named like an env file (template or not) is an alias for whatever
#    it points at, including a dangling target the write would create.
if [[ -L "$FILE_PATH" ]]; then
  block "'$BASENAME' is a symlink — an env-file name may not alias another path."
fi

# 4. Template names are allow-listed, so they are the thing worth aliasing.
#    A hard link is invisible to path resolution; link count is not.
case "$BASENAME" in
  *.env.example|*.env.template|*.env.sample)
    if [[ -e "$FILE_PATH" ]]; then
      # Unknown link count fails closed — an unstattable existing file is not
      # something to hand a write to.
      NLINK=$(stat -f %l "$FILE_PATH" 2>/dev/null || stat -c %h "$FILE_PATH" 2>/dev/null || echo 2)
      [[ "$NLINK" =~ ^[0-9]+$ ]] || NLINK=2
      if [[ "$NLINK" -gt 1 ]]; then
        block "'$BASENAME' is hard-linked ($NLINK names) — a template name may not share an inode."
      fi
    fi
    exit 0
    ;;
esac

# 5. A real env file: absent is safe to create, existing is not safe to replace.
if [[ ! -e "$FILE_PATH" ]]; then
  exit 0
fi

block "'$BASENAME' already exists — replacing it would overwrite its current contents."
