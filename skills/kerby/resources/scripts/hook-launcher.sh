#!/bin/sh
# kerby-managed:launcher — installed to ~/.claude/kerby/bin/hook by `kerby install`.
# Ownership is this marker; currency is the bytes (install rewrites it on upgrade).
#
# Usage: hook <event> <relpath-under-install-root> [args...]
#   event    PreToolUse | SessionStart | git-hook | any Claude Code hook event
#   relpath  e.g. rulebooks/base/hooks/pre-commit-check.sh
#
# Resolves the kerby install root at RUN time — KERBY_DIR, else
# ~/.claude/kerby/install-root (one line, refreshed by every `kerby load`) — so
# a settings.json registration survives an install that moves. A bare absolute
# path cost nine dead hook entries and a git hook that silently failed open for
# weeks after the install directory moved.
#
# Fails OPEN, visibly: a vanished install must never wedge a tool call or a
# commit (SKILL.md § Phase 3 doctrine), and it must never be silent either —
# the message names the gap and the fix. stdin is passed through untouched;
# the target reads it itself.
#
# POSIX sh, no jq, no bash: GUI git clients run hooks with PATH=/usr/bin:/bin.

event="${1:-}"; rel="${2:-}"
[ $# -ge 2 ] && shift 2

root="${KERBY_DIR:-}"
if [ -z "$root" ] && [ -r "${HOME:-}/.claude/kerby/install-root" ]; then
  IFS= read -r root < "$HOME/.claude/kerby/install-root"
fi

# relpath comes from settings.json, which is workspace-adjacent in the
# project-settings case: confine it to the (trusted) root.
problem=""
case "$rel" in
  ""|/*|..|../*|*/..|*/../*) problem="refusing relpath '$rel' (must be relative, no '..')" ;;
esac
if [ -z "$problem" ]; then
  if [ -z "$root" ]; then
    problem="$rel not found under install root (no pointer)"
  elif [ ! -f "$root/$rel" ] || [ ! -x "$root/$rel" ]; then
    problem="$rel not found under install root $root"
  fi
fi

[ -z "$problem" ] && exec "$root/$rel" "$@"

msg="kerby: $problem — hooks are not enforcing; run \`kerby load\` then \`kerby install\`"
case "$event" in
  git-hook)     printf '%s\n' "$msg" >&2 ;;
  SessionStart) printf '%s\n' "$msg" ;;
  *)
    esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
    printf '{"hookSpecificOutput":{"hookEventName":"%s","additionalContext":"%s"}}\n' \
      "$(esc "$event")" "$(esc "$msg")" ;;
esac
exit 0
