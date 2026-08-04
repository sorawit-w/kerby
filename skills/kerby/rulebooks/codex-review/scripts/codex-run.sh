#!/bin/bash
# codex-run.sh — thin shim. The watchdog logic lives in codex-run.py; see its
# module docstring for the CLI, exit codes, and the WHY-PYTHON rationale (five
# review rounds of a pure-bash predecessor found seven defects, all one shape:
# `ps`/`kill -0`/`kill`/`wait` each have a third answer besides yes and no,
# and every guard folding it into one of the other two produced an unbounded
# wait or a misdirected signal. proc.wait(timeout=) has no third answer).
#
# This file exists, rather than a straight rename to codex-run.py, so:
#   - a missing python3 announces itself here instead of surfacing as the OS's
#     raw "bad interpreter" error, on the one script that runs when everything
#     else is broken;
#   - the ~10 prose references to codex-run.sh across this rulebook, and the
#     test suite's `bash "$RUN"` invocations, need no changes.
#
# python3 is not a new dependency for this rulebook's HOST: kerby already
# requires it for skills/kerby/resources/scripts/validate-rulebook.py, run on
# every rulebook load. Any machine that has loaded codex-review has already
# exercised it.
set -u

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

command -v python3 >/dev/null 2>&1 || {
  echo "codex-run: python3 not found on PATH — the watchdog needs it (kerby already requires python3 for rulebook validation, so this is likely a broken PATH rather than a missing install). Install or fix PATH, then re-run." >&2
  exit 1
}

exec python3 "$DIR/codex-run.py" "$@"
