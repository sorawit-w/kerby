#!/bin/bash
# Self-test for context-bootstrap.sh — verifies the hook scaffolds CONTEXT.md
# only when the repo has no glossary at all, and never writes next to an
# existing one (CONTEXT.md, GLOSSARY.md, or GLOSSARY-MAP.md).
#
# Run from anywhere: bash context-bootstrap.test.sh
# Exit 0 = all assertions pass; non-zero = a failure.

set -u

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"
HOOK="$SCRIPT_DIR/context-bootstrap.sh"
ENGINE_ROOT="$( cd "$SCRIPT_DIR/../.." && pwd -P )"
TEMPLATE="$ENGINE_ROOT/resources/templates/CONTEXT.md.template"

FAILS=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; FAILS=$((FAILS + 1)); }

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Each case runs the hook in its own empty project dir.
newcase() { local d="$TMP/$1"; mkdir -p "$d"; echo "$d"; }
run_hook() { ( cd "$1" && env -u CODING_RULES_HOOK_DISABLED "${@:2}" bash "$HOOK" </dev/null >/dev/null ); }

# a1. No glossary, template reachable through KERBY_DIR → CONTEXT.md is the template.
D=$(newcase a1)
run_hook "$D" KERBY_DIR="$ENGINE_ROOT"
cmp -s "$D/CONTEXT.md" "$TEMPLATE" \
  && pass "a1: no glossary → CONTEXT.md scaffolded from the template" \
  || fail "a1: CONTEXT.md missing or not the template"

# a2. No glossary, no template reachable → the minimal stub is written.
D=$(newcase a2)
LONE="$TMP/lone/hooks"; mkdir -p "$LONE"; cp "$HOOK" "$LONE/"
( cd "$D" && env -u CODING_RULES_HOOK_DISABLED -u KERBY_DIR bash "$LONE/context-bootstrap.sh" </dev/null >/dev/null )
grep -q '^# Project Context$' "$D/CONTEXT.md" 2>/dev/null \
  && pass "a2: no template → minimal stub written" \
  || fail "a2: stub not written"

# b. CONTEXT.md with content → untouched.
D=$(newcase b)
printf '# Mine\n\n**Order**: a thing.\n' > "$D/CONTEXT.md"
cp "$D/CONTEXT.md" "$TMP/b.orig"
run_hook "$D" KERBY_DIR="$ENGINE_ROOT"
cmp -s "$D/CONTEXT.md" "$TMP/b.orig" \
  && pass "b: existing CONTEXT.md unchanged" \
  || fail "b: existing CONTEXT.md was changed"

# c. GLOSSARY.md only → no CONTEXT.md is created next to it.
D=$(newcase c)
printf '# Shop\n\n## Language\n\n**Order**:\nA request to buy.\n' > "$D/GLOSSARY.md"
run_hook "$D" KERBY_DIR="$ENGINE_ROOT"
[[ ! -e "$D/CONTEXT.md" ]] \
  && pass "c: GLOSSARY.md present → no CONTEXT.md created" \
  || fail "c: CONTEXT.md created next to GLOSSARY.md"

# c2. GLOSSARY-MAP.md only (multi-context repo) → no CONTEXT.md.
D=$(newcase c2)
printf '# Glossary Map\n' > "$D/GLOSSARY-MAP.md"
run_hook "$D" KERBY_DIR="$ENGINE_ROOT"
[[ ! -e "$D/CONTEXT.md" ]] \
  && pass "c2: GLOSSARY-MAP.md present → no CONTEXT.md created" \
  || fail "c2: CONTEXT.md created next to GLOSSARY-MAP.md"

# d. Both names exist → both unchanged, nothing new.
D=$(newcase d)
printf '# Ctx\n' > "$D/CONTEXT.md"; printf '# Gl\n' > "$D/GLOSSARY.md"
run_hook "$D" KERBY_DIR="$ENGINE_ROOT"
[[ "$(cat "$D/CONTEXT.md")" == "# Ctx" && "$(cat "$D/GLOSSARY.md")" == "# Gl" && "$(ls "$D" | wc -l | tr -d ' ')" == "2" ]] \
  && pass "d: both present → nothing changed or added" \
  || fail "d: a file changed or was added"

# e. Disable token → nothing created.
D=$(newcase e)
( cd "$D" && CODING_RULES_HOOK_DISABLED=context-bootstrap KERBY_DIR="$ENGINE_ROOT" bash "$HOOK" </dev/null >/dev/null )
[[ ! -e "$D/CONTEXT.md" ]] \
  && pass "e: disable token → nothing created" \
  || fail "e: CONTEXT.md created despite disable token"

# f. context.enabled: false → nothing created.
D=$(newcase f)
printf 'context:\n  enabled: false\n' > "$D/agent-context.yaml"
run_hook "$D" KERBY_DIR="$ENGINE_ROOT"
[[ ! -e "$D/CONTEXT.md" ]] \
  && pass "f: context.enabled false → nothing created" \
  || fail "f: CONTEXT.md created despite opt-out"

echo "---"
if [[ "$FAILS" -eq 0 ]]; then
  echo "All assertions passed."
  exit 0
else
  echo "$FAILS assertion(s) failed."
  exit 1
fi
