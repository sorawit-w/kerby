#!/bin/sh
# kerby-managed:launcher — installed to ~/.claude/kerby/bin/hook by `kerby install`.
# Ownership is this marker; currency is the bytes (install rewrites it on upgrade).
#
# Usage: hook <event> <relpath-under-install-root> [args...]
#   event    PreToolUse | SessionStart | git-hook | any Claude Code hook event
#   relpath  e.g. rulebooks/base/hooks/pre-commit-check.sh
#
# Resolves the kerby install root at RUN time from ~/.claude/kerby/install-root
# (one line, refreshed by every `kerby load`), so a settings.json registration
# survives an install that moves. A bare absolute path cost nine dead hook
# entries and a git hook that silently failed open for weeks after the install
# directory moved.
#
# The root comes ONLY from that user-local pointer, never from the environment:
# a project settings file can set env vars for its hooks, so honoring one here
# (KERBY_DIR included) would let workspace content steer a user-local launcher —
# the exact thing the pointer exists to prevent. `kerby load` writes the pointer
# from the locator's trusted rungs; this file just reads it.
#
# Fails OPEN, visibly: a vanished install must never wedge a tool call or a
# commit (SKILL.md § Phase 3 doctrine), and it must never be silent either —
# the message names the gap and the fix, on the channel the event reads. stdin
# is passed through untouched; the target reads it itself.
#
# POSIX sh, no jq, no bash: GUI git clients run hooks with PATH=/usr/bin:/bin.

event="${1:-}"; rel="${2:-}"
[ $# -ge 2 ] && shift 2

root=""
if [ -n "${HOME:-}" ] && [ -r "$HOME/.claude/kerby/install-root" ]; then
  IFS= read -r root < "$HOME/.claude/kerby/install-root"
  cr=$(printf '\r'); root="${root%"$cr"}"   # tolerate a CRLF pointer
fi

# relpath comes from settings.json, which is workspace-adjacent in the
# project-settings case: confine it to the (trusted) root — lexically first,
# then by resolving the target's directory, so a symlinked directory cannot
# walk out. A symlinked *file* inside the root still runs: the root is kerby's
# own install, and anything able to plant a symlink there could edit the
# scripts outright, so that is not a boundary this guard claims.
problem=""
case "$rel" in
  ""|/*|..|../*|*/..|*/../*) problem="refusing relpath '$rel' (must be relative, no '..')" ;;
esac
if [ -z "$problem" ]; then
  if [ -z "$root" ]; then
    problem="$rel not found under install root (no pointer)"
  elif [ ! -f "$root/$rel" ] || [ ! -x "$root/$rel" ]; then
    problem="$rel not found under install root $root"
  else
    dir="${rel%/*}"; [ "$dir" = "$rel" ] && dir=.
    rootc=$(cd "$root" 2>/dev/null && pwd -P) || rootc=""
    dirc=$(cd "$root/$dir" 2>/dev/null && pwd -P) || dirc=""
    if [ -z "$rootc" ] || [ -z "$dirc" ]; then
      problem="install root $root cannot be resolved"
    else
      case "$dirc/" in
        "$rootc"/*) ;;
        *) problem="refusing relpath '$rel' (resolves outside install root $root)" ;;
      esac
    fi
  fi
fi

if [ -z "$problem" ]; then
  # A child, not exec: exec of a file whose interpreter is missing dies with
  # 126/127 and no message on the event's channel — silently open for a tool
  # call, closed for a commit. Run it as a child and translate those two
  # statuses into the visible fail-open below; every other status passes
  # through untouched. Ceiling: a target that itself exits 126 or 127 is
  # reported the same way.
  "$root/$rel" "$@"
  rc=$?
  case $rc in
    126|127) problem="$rel could not be launched (exit $rc: missing interpreter or not executable)" ;;
    *) exit $rc ;;
  esac
fi

msg="kerby: $problem — hooks are not enforcing; run \`kerby load\` then \`kerby install\`"
# JSON string escaping without jq: fold line breaks and tabs to spaces, drop
# the other control characters, then escape backslash and double quote.
esc() { printf '%s' "$1" | tr '\n\r\t' '   ' | tr -d '\000-\010\013\014\016-\037\177' | sed 's/\\/\\\\/g; s/"/\\"/g'; }
case "$event" in
  git-hook)     printf '%s\n' "$msg" >&2 ;;
  SessionStart) printf '%s\n' "$msg" ;;
  *)
    printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' \
      "$(esc "$event")" "$(esc "$msg")" ;;
esac
exit 0
