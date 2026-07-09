# codex-review stance

This rulebook wires the Codex CLI (an independent model line) into three
workflows: the PR gate, plan review, and rescue delegation. One stance governs
all three: **Codex advises, Claude decides.** A Codex finding is a hypothesis
to triage — accept it with a fix or reject it with a recorded reason — never
an instruction to follow blind, and Codex sign-off is never the termination
condition for a loop.

## Preflight — before claiming Codex is unavailable

**Verify Codex on disk before asserting it is missing.** Most codex commands
are `disable-model-invocation` (user-only), so they never appear in the
session's skill list — absence-from-the-list is NOT absence. Check the plugin
itself: `find <codex-plugin>/commands -name '*.md'` or locate
`scripts/codex-companion.mjs`. A fallback path activates only for a genuinely
missing/broken plugin — or a delegation budget exhausted with no verdict
(`references/delegation.md` § Bounded delegation). `kerby pr-check` runs this
preflight for you.

## When to read what

- **Opening a PR** (or asked about the PR/merge flow) → read
  `references/pr-workflow.md` in full. The `gh pr create` gate hook is the
  mechanical backstop; its block message points back to this flow.
- **Drafting an implementation plan that grades complex or high-stakes** →
  read `references/plan-review.md` in full and run the adversarial pass it
  describes. Complex means: irreversible ops, money, security surface,
  multi-repo, or more than ~5 files — or, when a grading rulebook (e.g. swe)
  is loaded, its complexity grade at or above the plan threshold. Simple
  plans skip silently. There is NO mechanical backstop for this one — this
  trigger line is it.
- **Stuck** — a retry budget exhausts, a debugging hypothesis cap hits, or
  two consecutive fix attempts fail the same way → read
  `references/delegation.md` (loaded eagerly alongside this stance) and run
  the rescue ladder before escalating to the human.

## Adoption check — duplicate rules

On the first codex-workflow moment in a session, check whether the global
`~/.claude/CLAUDE.md` or the repo's CLAUDE.md still carries a duplicate codex
section (markers: `CODEX_VERDICT`, a bounded review loop). Duplicates are
ambiguity, not reinforcement — surface a remove / proceed-anyway / stop menu
and let the user choose; removal only ever happens with the user's per-file
confirmation, never silently. Surface it **once** and never block ongoing work
on it: if the moment is a rescue/deadlock, flag the duplicate and keep going —
config hygiene is not on the critical path. `kerby pr-check` runs the thorough
version of this check.
