# Scenario 1 — `kerby load` (no args), v5.8.0

Source of truth: `skills/kerby/SKILL.md` § `load` (lines 60–81 at `fbf6085`).

## Expected behavior

1. **Resolve BOOTSTRAP.md** — first success wins:
   1. Glob `**/skills/kerby/resources/BOOTSTRAP.md`
   2. `${KERBY_DIR}/resources/BOOTSTRAP.md`
   3. Ask the user.
2. **Read `BOOTSTRAP.md` in full with the Read tool** — full content enters
   context as a tool result; paraphrasing/summarizing is a violation.
3. **Confirm verbatim:**

   > **kerby loaded.** BOOTSTRAP is in context for this session — I will follow
   > its rules until the session ends or context is compacted. If rules seem to
   > stop applying mid-session, invoke `kerby` with `args: reload`.

4. Rules active for all subsequent work.
5. **Readiness nudge (read-only, no writes):**
   - has-real-code = any project manifest (`package.json`, `deno.json`,
     `pyproject.toml`, `go.mod`, `Cargo.toml`) or populated source tree
   - already-prepared = `agent-context.yaml` with non-empty `project.name`
     AND (`CONTEXT.md` ≥1 glossary entry OR `.ai/knowledge/` ≥1 entry beyond
     `KNOWLEDGE.md`)
   - has-real-code AND NOT already-prepared → append the one-line `prepare`
     suggestion; otherwise silent. Never auto-run `prepare`.

## `reload` variant

Same procedure; confirmation is:

> **kerby reloaded.** BOOTSTRAP refreshed in context.

## What v6 must preserve (material intent)

- BOOTSTRAP.md still read IN FULL via the Read tool on a no-arg load.
- Same verbatim confirmation lines.
- Same readiness-nudge conditions and silence rules.
- No new prompts, no writes, on the default path.

## Permitted additive difference (v6)

One literal announcement line (D19), e.g.
`rulebook: code@1.0.0 (builtin) — source: default (…)` on first load and
`… — source: pinned` thereafter, plus the first-load write of `rulebooks.lock`
(the D17 pin — the only new write, and it is announced).
