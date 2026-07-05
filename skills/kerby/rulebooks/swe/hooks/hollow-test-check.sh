#!/bin/bash
# Hook: swe's soft pre-commit advisory (the hollow-test-heuristic enforcer).
# Type: PreToolUse on Bash matching git commit
# Name: hollow-test-check
# Exit 0 always — this is a SOFT check; the advisory is injected as JSON on STDOUT
# (hookSpecificOutput.additionalContext), which surfaces WITH the tool result.
# kerby reserves the hard block (exit 2) for secrets — base's pre-commit-check.sh
# owns that floor. This hook does NO secret scanning: it is registered as its own
# PreToolUse/Bash entry alongside base's floor, so the two run independently and
# the scan is never duplicated here.
#
# Carries two coding-specific advisories, both soft, both disablable:
#   1. the lint/test/build reminder (surfaces with every git commit under swe)
#   2. the hollow-test heuristic (fires only when staged test files add fake-test
#      markers)
#
# Disable with: CODING_RULES_HOOK_DISABLED=hollow-test-check
# The legacy token `pre-commit-check` is ALSO honored — before v9.3 this logic
# lived in base's pre-commit-check.sh under that name, so anyone who disabled it
# there keeps their setting (additive grace, like the v8 .ai/->.kerby/ migration).

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only check git commit commands
if ! echo "$COMMAND" | grep -qE '^git commit'; then
  exit 0
fi

# Respect the disable list — both the current and legacy tokens.
case ",${CODING_RULES_HOOK_DISABLED:-}," in
  *,hollow-test-check,*|*,pre-commit-check,*) exit 0 ;;
esac

# Hollow-test heuristic (soft) — statically surface the "green run that proves
# nothing" fakes validation.md names: focused/disabled test markers and
# always-true assertions, in ADDED lines of staged test files only. Added-only
# means a teammate's pre-existing .skip never fires, and refactoring one OUT
# never trips it. Runtime fakes (0-match runs, gates over stubbed code) stay
# agent-judged — not statically detectable here. Reports COUNTS only — never echo
# raw test lines into the agent context. Pattern set is apostrophe-free (see the
# bash 3.2 note below) and word-anchored so fit(/xit( do not match the English
# word in a test description. Pathspecs are :(top)-anchored so a commit run from a
# subdirectory still scans staged test files repo-wide (a bare '*test*' is
# cwd-relative); .only/.skip permit a trailing dot so chained forms
# (test.only.each, describe.skip.each) are caught too.
HOLLOW_NOTE=""
TEST_ADDED=$(git diff --cached --diff-filter=ACMR -U0 -- ':(top)*test*' ':(top)*spec*' ':(top)*Test*' ':(top)*Spec*' 2>/dev/null | grep -E '^\+[^+]')
if [[ -n "$TEST_ADDED" ]]; then
  FOCUS=$(printf '%s\n' "$TEST_ADDED" | grep -cE '\.only[ (.]|\.skip[ (.]|\bfdescribe\(|\bfit\(|\bxit\(|\bxdescribe\(|@pytest\.mark\.skip|@(Disabled|Ignore)\b|\bt\.Skip\(')
  TRUE=$(printf '%s\n' "$TEST_ADDED" | grep -cE 'expect\( *true *\)\.(toBe\( *true *\)|toBeTruthy\()|assertTrue\( *[Tt]rue *\)|XCTAssertTrue\( *true *\)|assert\( *[Tt]rue *\)|assert +True\b')
  if [[ "$FOCUS" -gt 0 || "$TRUE" -gt 0 ]]; then
    HOLLOW_NOTE="
HOLLOW-TEST CHECK (kerby): staged test changes added $FOCUS focused/disabled marker(s) (only/skip/fit/xit) and $TRUE always-true assertion(s). A focused test silently disables the rest of the suite; an always-true assert verifies nothing — both yield a green run that proves nothing (validation.md Iron Law). Inspect your staged test/spec files and confirm each is intentional before committing. Advisory only; does NOT block."
  fi
fi

# Soft reminder — injected as context via JSON additionalContext (plain stdout on
# exit 0 is ignored for PreToolUse); does not block. NOTE: a PreToolUse
# additionalContext surfaces WITH the tool result (next turn), so this reminder
# arrives as the commit completes — it is a post-commit safety net, not a gate.
# Making it gate the commit would mean permissionDecision ask/deny — a deliberate
# commit-discipline change, out of scope here.
# Plain double-quoted string (literal newlines), NOT a heredoc-in-$(...). Under
# bash 3.2 (macOS default) the command-substitution parser counts quotes even
# inside a quoted heredoc, so an ODD number of apostrophes in the body fails with
# "unexpected EOF while looking for matching '". Keeping this inline and
# apostrophe-free (like warn-env-read.sh) sidesteps it entirely.
REMINDER="REMINDER (kerby): verify your changes against the project gates —
1. lint on the changed files
2. the test suite
3. the build
This advisory surfaces WITH the commit result and does NOT block it; if your changes broke any gate, run it and amend the commit. Pre-existing failures from other code are acceptable — do not block on them.${HOLLOW_NOTE}"
jq -n --arg ctx "$REMINDER" \
  '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$ctx}}'

exit 0
