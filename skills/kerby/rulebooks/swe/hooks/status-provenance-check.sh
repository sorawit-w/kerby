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
#   -p / --interactive    hunks chosen from the working tree over the index — BOTH
#                         sources are scanned
# `--pathspec-from-file` contributes pathspecs like the command line; `--no-all`
# and friends negate (last option wins); a redirection is never a pathspec; the
# command ends at the first unquoted separator, attached or not.
# EVERYTHING THE CLASSIFIER CANNOT PROVE SCANS BOTH SOURCES: an option it does
# not list (an abbreviation like `--inc`, an unknown short letter, a flag git adds
# later), a variable, glob or tilde in a pathspec (the shell expands them after
# this hook sees the text), a heredoc, an unbalanced quote, a quoted line in a
# pathspec file. An unquoted `$`, backtick or `{` anywhere is an expansion (or a
# `{fd}>` redirection) the shell rewrites after this hook looks, so it is
# undecidable too (a quoted one is one literal word and is fine). A quoted word
# that merely LOOKS like a redirection (`'>x'`) is treated as one — the cost is a
# false block on a pathspec named `>x`, never a miss. `--dry-run` records nothing and is let through. An unquoted `#` or newline ends the command; `-u<mode>` and `-S<key>` carry
# their value attached; `--only --amend` with no pathspec records HEAD's tree. The cost is a
# visible block on a working-tree STATUS.md that was not going to be committed;
# the alternative is a silent miss, and this hook always takes the block.
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
# unbalanced quote (undecidable). Unquoted `;` `|` `||` `&` `&&` are emitted as
# their own tokens even when attached to a word (`-m x;echo`), so the loop below
# can stop at the first separator; `>&`, `<&` and `&>` stay redirections.
tokens() {
  printf '%s' "$1" | awk '
    BEGIN { RS = "\001" }                       # the whole command is ONE record, so a newline reaches the loop
    function flush() { if (t != "" || qd) { if (x) print "\002"; if (qd) print "\003"; print t; t = ""; x = 0; qd = 0 } }
    { s = $0; L = length(s); q = ""; t = ""; x = 0; qd = 0
      for (i = 1; i <= L; i++) { c = substr(s, i, 1); nx = substr(s, i + 1, 1)
        if (q != "") { if (c == q) q = ""; else t = t c }
        else if (c == "\"" || c == "\047") { q = c; qd = 1 }          # a quoted word: shell operators inside it are literal
        else if (c == "\\") { i++; t = t substr(s, i, 1) }
        else if (c == " " || c == "\t") flush()
        else if (c == "\n" || c == "\r") { flush(); print ";" }   # an unquoted newline separates commands
        else if (c == ";") { flush(); print ";" }
        else if (c == "|") { if (t ~ />$/) t = t c; else { flush(); if (nx == "|") { print "||"; i++ } else print "|" } }
        else if (c == "&") {
          if (t ~ /[<>]$/) t = t c
          else if (nx == ">") t = t c
          else { flush(); if (nx == "&") { print "&&"; i++ } else print "&" } }
        else { if (c == "$" || c == "`" || c == "{") x = 1; t = t c } }   # expansion, substitution, brace expansion or a {fd}> redirection
      flush()
      if (q != "") print "\001" }'
}

# --- Classify the commit: ALL (-a), INCLUDE (-i), INTERACTIVE (-p), and the
# positional pathspecs. Git's last-option-wins applies (`--all --no-all`).
# Shell redirections are not pathspecs; a heredoc, a command substitution or a
# newline inside a token is undecidable and falls to the safe side (both).
ALL=0; INCLUDE=0; INTERACTIVE=0; ONLY=0; AMEND=0; DRYRUN=0; SPECS=(); UNDECIDABLE=0; PSFILE=""; NUL=0
n=0; expect_value=0; expect_psfile=0; expect_redirect_target=0; after_dashdash=0; literal=0
while IFS= read -r tok; do
  [[ "$tok" == $'\001' ]] && { UNDECIDABLE=1; break; }
  [[ "$tok" == $'\002' ]] && { UNDECIDABLE=1; break; }   # an UNQUOTED expansion: the shell word-splits it into words this hook cannot see
  [[ "$tok" == $'\003' ]] && { literal=1; continue; }     # the next word was quoted: `>` `;` `#` `|` `&` inside it are text, not operators
  was_literal=$literal; literal=0                           # the flag belongs to THIS word only
  case "$tok" in '<<'*) UNDECIDABLE=1; break ;; esac      # a heredoc makes the rest unparseable
  n=$((n + 1)); [[ $n -le 2 ]] && continue            # `git` `commit`
  # redirections: the shell removes them from the arguments wherever they sit, so
  # they are handled BEFORE an option consumes its value or `--` takes effect. A
  # bare operator takes the next token as its target; an attached one is
  # self-contained.
  if [[ $expect_redirect_target -eq 1 ]]; then expect_redirect_target=0; continue; fi
  if [[ $was_literal -eq 0 ]]; then
    case "$tok" in
      '>'|'>>'|'>|'|'<'|'<>'|'&>'|'&>>'|[0-9]'>'|[0-9]'>>'|[0-9]'>|'|[0-9]'<'|[0-9]'<>') expect_redirect_target=1; continue ;;
      '>'*|'<'*|'&>'*|[0-9]'>'*|[0-9]'<'*) continue ;;
    esac
  fi
  if [[ $after_dashdash -eq 1 ]]; then SPECS+=("$tok"); continue; fi
  if [[ $expect_psfile -eq 1 ]]; then expect_psfile=0; PSFILE="$tok"; continue; fi
  if [[ $expect_value -eq 1 ]]; then expect_value=0; continue; fi
  case "$tok" in
    '&&'|'||'|';'|'|'|'&') [[ $was_literal -eq 1 ]] && { SPECS+=("$tok"); continue; }; break ;;
    '#'*) [[ $was_literal -eq 1 ]] && { SPECS+=("$tok"); continue; }; break ;;   # an unquoted # starts a shell comment
    --) after_dashdash=1 ;;
    --all) ALL=1 ;;          --no-all) ALL=0 ;;
    --include) INCLUDE=1 ;;  --no-include) INCLUDE=0 ;;
    --only) ONLY=1 ;;        --no-only) ONLY=0 ;;
    --amend) AMEND=1 ;;      --no-amend) AMEND=0 ;;
    --dry-run) DRYRUN=1 ;;   --no-dry-run) DRYRUN=0 ;;
    --patch|--interactive) INTERACTIVE=1 ;;
    --no-patch|--no-interactive) INTERACTIVE=0 ;;
    --pathspec-from-file=*) PSFILE="${tok#*=}" ;;
    --pathspec-from-file) expect_psfile=1 ;;
    --pathspec-file-nul) NUL=1 ;;
    --author|--date|--cleanup|--template|--file|--message|--fixup|--squash|--reuse-message|--reedit-message|--trailer) expect_value=1 ;;
    --author=*|--date=*|--cleanup=*|--template=*|--file=*|--message=*|--fixup=*|--squash=*|--reuse-message=*|--reedit-message=*|--trailer=*) ;;
    # long options that select no content — the only ones passed through. An
    # option this list does not know (an abbreviation like `--inc`, a new flag) is
    # undecidable: git may resolve it to something content-selecting.
    --edit|--no-edit|--quiet|--no-quiet|--verbose|--no-verbose|--signoff|--no-signoff|--verify|--no-verify|--allow-empty|--no-allow-empty|--allow-empty-message|--status|--no-status|--short|--branch|--no-branch|--porcelain|--long|--null|--post-rewrite|--no-post-rewrite|--reset-author|--gpg-sign|--gpg-sign=*|--no-gpg-sign|--untracked-files|--untracked-files=*|--ahead-behind|--no-ahead-behind) ;;
    --*) UNDECIDABLE=1; break ;;
    -?*)                                               # short cluster: -am "x", -i, -p, -mfoo, -Ffile, -uall, -Skey
      letters="${tok#-}"
      while [[ -n "$letters" ]]; do
        l="${letters:0:1}"; letters="${letters:1}"
        case "$l" in
          a) ALL=1 ;;
          i) INCLUDE=1 ;;
          o) ONLY=1 ;;
          p) INTERACTIVE=1 ;;
          e|q|v|s|n|z) ;;                                     # no content selection
          u|S) break ;;                                       # optional value is attached: the rest of the token is it
          m|F|C|c|t) if [[ -z "$letters" ]]; then expect_value=1; fi; break ;;   # attached value, or the next token
          *) UNDECIDABLE=1; break 2 ;;                        # an unknown letter is undecidable
        esac
      done ;;
    *) # a pathspec: the shell expands variables, globs and tildes AFTER this hook
       # sees the text, and a stray heredoc body lands here too — undecidable, both.
       case "$tok" in *'$'*|*'`'*|*'*'*|*'?'*|*'['*|'~'*|*$'\n'*) UNDECIDABLE=1; break ;; esac
       SPECS+=("$tok") ;;
  esac
done < <(tokens "$COMMAND")

# --pathspec-from-file: the file's entries are pathspecs too (`-` is stdin, undecidable).
if [[ -n "$PSFILE" && $UNDECIDABLE -eq 0 ]]; then
  if [[ "$PSFILE" == "-" || ! -r "$PSFILE" ]]; then UNDECIDABLE=1
  elif [[ $NUL -eq 1 ]]; then while IFS= read -r -d '' spec || [[ -n "$spec" ]]; do [[ -n "$spec" ]] && SPECS+=("$spec"); done < "$PSFILE"
  else
    # git's file syntax: one pathspec per line, CRLF tolerated, a line in double
    # quotes is C-style quoted — decoding that is git's job, so it is undecidable.
    while IFS= read -r spec || [[ -n "$spec" ]]; do
      spec="${spec%$'\r'}"
      [[ -n "$spec" ]] || continue
      case "$spec" in '"'*) UNDECIDABLE=1; break ;; esac
      SPECS+=("$spec")
    done < "$PSFILE"
  fi
fi

covered() { # do the pathspecs resolve to STATUS.md? 0 yes / 1 no / 2 undecidable
  [[ ${#SPECS[@]} -gt 0 ]] || return 1
  local out
  out=$(git ls-files --full-name -- "${SPECS[@]}" 2>/dev/null) || return 2
  grep -qx "$STATUS_REL" <<<"$out"
}

if [[ $UNDECIDABLE -eq 1 || $INTERACTIVE -eq 1 ]]; then MODE=both   # undecidable first: an expansion may negate anything below, --dry-run included
elif [[ $DRYRUN -eq 1 ]]; then MODE=none                             # --dry-run records nothing; previewing the state is the point
elif [[ $ALL -eq 1 ]]; then MODE=worktree
elif [[ $ONLY -eq 1 && $AMEND -eq 1 && ${#SPECS[@]} -eq 0 ]]; then MODE=none   # --only --amend: HEAD's tree, the staged blob stays staged
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
  [[ -e "$STATUS" || -L "$STATUS" ]] || return 0
  git -C "$TOP" diff --quiet HEAD -- "$STATUS_REL" 2>/dev/null && return 0
  if [[ -L "$STATUS" ]]; then
    # a symlink commits as a blob holding its TARGET TEXT — that is what is scanned,
    # not the file it points at (which may not even exist)
    TMPF=$(mktemp) || warn_open "cannot create a temp file for the symlink target"
    readlink "$STATUS" > "$TMPF"
    run_guard "$TMPF" "working tree, symlink target"
    rm -f "$TMPF"; TMPF=""
    return 0
  fi
  run_guard "$STATUS" "working tree"
}
scan_index() { # the staged blob, when STATUS.md is staged
  git -C "$TOP" diff --cached --name-only --diff-filter=ACMRT -- ":(top)$STATUS_REL" 2>/dev/null | grep -q . || return 0
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
