#!/bin/bash
# V14 shim: the pre-commit check is base's floor enforcer (secrets-staged owns the
# script); code's hollow-test-heuristic rides the same scan. This 2-line shim keeps
# code's declaration folder-confined (E04) while executing the base-owned script.
exec "$(dirname "$0")/../../base/hooks/pre-commit-check.sh" "$@"
