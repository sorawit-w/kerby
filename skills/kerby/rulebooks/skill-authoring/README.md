# skill-authoring — the verification gate for skills

The gate between *building* a skill and *shipping* it: no skill change ships
*as verified* without a fresh pass from the `skill-evaluator` skill (or an
equivalent split-role skill audit the repo designates) against the exact text
being shipped. Build with whatever tool you like — the official `skill-creator`,
your editor, an agent — this rulebook only governs the verification loop. ("Ship"
= reaching the default branch or a publish step; the degrade path lets a change
ship *unverified* only when explicitly labeled and acknowledged.)

## Scope

- **Governs the host repo's skills.** Load it in any repo where you author
  SKILL.md files: `kerby load skill-authoring`, or `kerby load
  +skill-authoring` alongside another rulebook.
- **Does not re-implement the tools.** Building skills is `skill-creator`'s
  job; auditing rule adherence is `skill-evaluator`'s. This rulebook is the
  discipline between them — when the gate opens, what evidence it takes to
  close it, and what happens when the verifier is missing.
- **Does not govern kerby itself.** Edits to kerby's own rules follow
  `skills/kerby/CLAUDE.md`, which sets a strictly higher bar (tiered gates,
  independent-model review).

## Checks

| Check | Kind | What it holds |
|---|---|---|
| `evaluator-gate-on-final-text` | prose | a fresh evaluator pass against the exact shipped text; edits re-open the gate; a clean score is necessary, not sufficient |
| `degrade-loudly-when-evaluator-missing` | prose | verifier absent → say so, label unverified, stop for acknowledgment — BLOCKED, never PASS |
| `classify-then-escalate` | prose | classify the failure layer (skill text / rubric / brief / fixture) before rewriting; same failure class twice → escalate, not another patch |
| `record-evaluator-evidence` | prose | every verdict recorded with date + evaluated SHA, so "fresh pass on exact text" stays checkable |

All four are prose, `behavioral` — no hook can see whether an audit ran; the
agent applies them by judgment, and `base`'s floor (merged first, as always)
backstops the honesty of any claims about them.

## Commands

None. The gate doesn't build skills; it decides when one may ship.

## Provenance

Every check traces to a recorded failure in the kerby repo's own history:
the v4.20.0 clean-pass-with-real-bugs incident (`cb8f699`, documented by
`a386277`), the v4.0.2
external-absorb audit (`7b8b34a`), doc-layer adherence patches (`f7c04f2`),
the v7 same-domain fix cluster, and the 2026-07-05 evidence-format sweep
(no convention existed for recording an evaluator pass). Added in kerby
v8.1.0. Contract: `docs/rulebook-contract.md`.
