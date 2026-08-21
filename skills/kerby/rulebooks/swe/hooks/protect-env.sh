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

# Set early: the degraded-input check below must be case-insensitive too, and it
# has to work before any external tool is known to exist.
shopt -s nocasematch

# A security hook that cannot read its input must not shrug and allow. Without
# jq — or with a payload jq cannot parse — the path is unknowable, so anything
# mentioning an env file is refused rather than waved through. This deliberately
# over-blocks in the degraded case (a Write whose CONTENT merely mentions .env
# also trips it); the remedy is to install jq, and the message says so. Failing
# open here made the hook a no-op on any machine missing one binary.
if ! command -v jq >/dev/null 2>&1 \
   || ! printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1; then
  # Pure bash — no grep, no printf pipeline. This branch exists precisely because
  # tooling is missing, so it must not itself depend on any.
  if [[ "$INPUT" == *.env* ]]; then
    echo "BLOCKED: cannot parse this tool call — jq is missing or the payload is malformed," >&2
    echo "and the request mentions an env file. Refusing rather than guessing." >&2
    echo "Install jq (brew install jq) so this hook can read the target path." >&2
    exit 2
  fi
  exit 0
fi

# Capture the path WITHOUT losing a trailing newline. `$(...)` strips every
# trailing LF, and `jq -r` adds one of its own — so a file literally named
# `.env.example<LF>` arrived as `.env.example`, was inspected as an absent
# template, and returned 0 while the real (symlinked) target was `.env`.
# `jq -j` emits no trailing newline; the sentinel preserves any that belong to
# the name itself.
FILE_PATH=$(printf '%s' "$INPUT" \
  | jq -j '.tool_input.file_path // .tool_input.path // empty'; printf 'x')
FILE_PATH=${FILE_PATH%x}

if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Strip trailing slashes before taking the basename. `${p##*/}` on `/x/.env/`
# yields an EMPTY basename, which matched nothing and fell straight out the
# allow door. A raw shell write to `.env/` fails with ENOTDIR, but whether that
# holds depends on the caller normalizing the path, and "safe as long as the
# caller normalizes" is not a property this hook should rely on. A bare "/" is
# left alone.
while [[ "$FILE_PATH" == */ && ${#FILE_PATH} -gt 1 ]]; do
  FILE_PATH=${FILE_PATH%/}
done

BASENAME=${FILE_PATH##*/}

# 1. Not an env-family basename -> not our business. Checked on the basename so a
#    directory component like `.env.d/` cannot drag ordinary files in.
case "$BASENAME" in
  *.env|*.env.*) ;;
  *) exit 0 ;;
esac

# True only when the parent directory really holds an entry spelled exactly like
# this basename. Runs in a subshell so the glob options do not leak.
name_is_exact() (
  shopt -s nullglob dotglob
  dir=${1%/*}; [ -z "$dir" ] && dir=/
  base=${1##*/}
  for f in "$dir"/*; do
    [ "${f##*/}" = "$base" ] && return 0
  done
  return 1
)

# Existence must not rest on stat() alone. A macOS ACL denying `readattr` makes
# `-e` FALSE for a file that plainly exists — and the hook then took the
# create-if-absent door and allowed an overwrite of live credentials. The
# directory entry is still listable in that state, so either signal counts as
# existing. Fail-closed by construction: a file we cannot stat is treated as
# present, never as absent.
env_exists() { [[ -e "$1" ]] || name_is_exact "$1"; }

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
    if env_exists "$FILE_PATH"; then
      # A template must be a REGULAR file. `-L` above rules out symlinks, but a
      # FIFO named `.env.example` has nlink=1 and sailed through, contradicting
      # the "plain regular file" contract the docs state.
      if [[ ! -f "$FILE_PATH" ]]; then
        block "'$BASENAME' exists but is not a regular file — a template may not be a device, FIFO or directory."
      fi
      # The on-disk name must match BYTE FOR BYTE. `-e` succeeds through the
      # filesystem's own case folding, and APFS folds more than ASCII: a real
      # file named `.env.Å¿ample` (U+017F) is reachable as `.env.sample`, so the
      # ASCII spelling hit the template allow-list and wrote to an inode the
      # hook blocks under its true name. Bash `nocasematch` folds ASCII only and
      # can never mirror the filesystem, so compare names instead of trusting
      # the lookup. `[` is byte-exact and unaffected by nocasematch.
      if ! name_is_exact "$FILE_PATH"; then
        block "'$BASENAME' resolves to a file stored under a different name — the filesystem folded the lookup; a template must match its real name exactly."
      fi
      # GNU form FIRST, BSD second — the order the rest of this repo already
      # uses (codex-mark.sh, codex-run.test.sh). It is not cosmetic: GNU `stat -f`
      # means --file-system, where `%l` is "maximum length of filenames" and
      # returns 255 on ext4. Probing BSD-first therefore SUCCEEDS on Linux with a
      # number that is not a link count, never falls through, and blocks every
      # template on the platform. BSD stat has no `-c` at all, so it errors and
      # falls through cleanly. Unknown link count fails closed — an unstattable
      # existing file is not something to hand a write to.
      NLINK=$(stat -c %h "$FILE_PATH" 2>/dev/null || stat -f %l "$FILE_PATH" 2>/dev/null || echo 2)
      [[ "$NLINK" =~ ^[0-9]+$ ]] || NLINK=2
      if [[ "$NLINK" -gt 1 ]]; then
        block "'$BASENAME' is hard-linked ($NLINK names) — a template name may not share an inode."
      fi
    fi
    exit 0
    ;;
esac

# 5. A real env file: absent is safe to create, existing is not safe to replace.
if ! env_exists "$FILE_PATH"; then
  exit 0
fi

block "'$BASENAME' already exists — replacing it would overwrite its current contents."
