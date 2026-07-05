# Degrade Loudly When the Evaluator Is Missing

**If the `skill-evaluator` skill (or the repo's designated equivalent) is not
available, the gate degrades observably — never silently.**

When a skill change reaches the ship boundary and the evaluator cannot run:

1. **Say so** — state plainly that the verification gate could not run and why
   (skill not installed, not reachable in this session).
2. **Label the change `unverified`** — in the summary, the PR body, or the
   commit message, wherever the change is reported.
3. **Stop for acknowledgment** — proceed only after the user explicitly
   accepts shipping unverified, or installs the evaluator and the gate runs.

"The gate couldn't run" is **HELD, never PASS**. The dangerous failure mode
is the silent one: the absence of a verifier reads exactly like the absence
of findings, and an unverified change ships wearing a verified change's
clothes. This is the prose mirror of the engine's fail-closed posture — an
unreadable check is never a pass.

Suggested wording when degrading:

> Verification gate: skill-evaluator is not available in this session — this
> change is **unverified**. Install it (or name an equivalent split-role
> audit) to run the gate, or say the word to ship unverified.

*Provenance: evidence-format sweep of the kerby record (2026-07-05) — no
convention existed for distinguishing "passed" from "never ran"; fail-closed
principle per `docs/rulebook-contract.md`.*
