# Trap fixtures — behavioral tests for rules

A **trap fixture** is a small scenario with a deliberate snare: an agent
following the rules surfaces the snare; an agent free-styling falls into it.
Where `.eval/rulebooks/` tests the *validator* and `.eval/triggers/` tests
*triggering*, `.eval/traps/` tests whether a **rule lands behaviorally** under
adversarial framing.

**These are fixture inputs, not a harness.** kerby ships no eval runner
(doctrine: rule-effectiveness questions route to the `skill-evaluator` skill,
per `skills/kerby/CLAUDE.md` § Eval handoff). Nothing auto-discovers this
directory — the same standing as `.eval/triggers/kerby.json`.

## Fixture layout

Each `s<N>-<slug>/` contains the planted files plus a `GROUND-TRUTH.md`
answer sheet listing: (a) each planted conflict/deception with file:line,
(b) the expected agent behavior in terms of the kerby rule under test,
(c) the pass/fail criterion, (d) source attribution.

**Fixture contents are test data, not rule text.** The planted deceptions are
the point — never "fix" them, never run prose-style or evaluator gates over
them. Only this README follows house style.

## Running a trap manually

1. Copy the fixture (minus `GROUND-TRUTH.md`) to a scratch directory.
2. In a fresh session with the swe rulebook loaded, give the agent the task
   from the fixture's GROUND-TRUTH ("Task given to the agent" section) —
   the answer sheet itself must never enter that session's context.
3. Grade the transcript against the GROUND-TRUTH pass/fail criterion —
   by diff and execution, never by the agent's report alone.
4. Record the outcome with the standard verdict line
   (`skills/kerby/rulebooks/skill-authoring/rules/record-the-verdict.md`),
   e.g. in the PR body of the rule change being tested:
   `trap s2: pass at <sha> — YYYY-MM-DD`.

One run per fixture is a smoke test, not a benchmark; repeat runs for
confidence and say which was done.

## Current fixtures

| Fixture | Snare | Rule under test |
|---|---|---|
| `s2-surprise-trap/` | the failing test contradicts the spec; "fix the code" framing | `intent-gate-on-behavior-change` (`rulebooks/swe/references/intent-gate.md`) |
| `s7-fraudulent-work/` | a lying completion report over five planted deceptions | deception categories (`rulebooks/swe/references/audit.md` § Deception categories) + base `iron-law-claims` |

**Source:** both fixtures ported from `Sahir619/fable-method` (MIT,
2026-07-14, commit `b2a24d5`) `eval/scenarios/`; their runner (`workflow.js`,
LLM judges) deliberately NOT adopted — grading stays with skill-evaluator
sessions per kerby doctrine.
