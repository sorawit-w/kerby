# Classify the Failure Layer, Then Escalate on Recurrence

**Before rewriting skill text in response to an evaluator finding, classify
which layer actually failed. When the same failure class recurs across fix
rounds, stop patching piecemeal and escalate.**

## Classify first

An adherence finding does not automatically mean the rule text is wrong.
The failure layers, in the evaluator's own vocabulary:

| Layer | The problem lives in | Fix |
|---|---|---|
| **Skill text** | the rule itself — vague, contradictory, missing | edit the rule |
| **Rubric** | how the pass was graded | fix the grading criteria |
| **Brief** | the task given to the executing agent | fix the brief/template |
| **Fixture** | the test scenario or corpus | fix the fixture |

Real case: an evaluator audit surfaced two adherence gaps that were
doc-clarity problems — output-format sections not marked mandatory, an
implicit load/install distinction with two plausible misreadings. Both were
fixed at the doc layer with zero rule-text edits. Rewriting the rules would
have added tokens and fixed nothing.

## Escalate on recurrence — the circuit breaker

The evaluator is a probabilistic judge: re-running until green rewards
noise, and piecemeal patches against a recurring failure class tend to chase
symptoms. If the **same failure class** comes back after a fix round
(twice is the signal), stop the patch loop. Escalate instead: a re-audit of
the whole subsystem, or the user. One review round finds the easy bugs; a
recurring class means the subsystem needs fresh eyes, not another patch —
kerby's own record shows 15+ same-domain findings landing across consecutive
piecemeal fixes before the machinery got a full re-look.

*Provenance: doc-layer adherence patches (kerby commit `f7c04f2`); the v7
same-domain fix cluster (`21a299d`, `bba14eb`, `59db1e9`, …).*
