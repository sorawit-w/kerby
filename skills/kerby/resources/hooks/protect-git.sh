#!/bin/bash
# v7 migration shim (removed in v8): this hook moved to rulebooks/code/hooks/.
# Keeps pre-v7 registered absolute paths working. Run `kerby install` to re-point.
exec "$(dirname "$0")/../../rulebooks/code/hooks/protect-git.sh" "$@"
