# Sub-Agent Delegation

For detailed delegation patterns, load the `sub-agent-coordinator` skill (if available). This stub provides the minimum needed when the skill is not installed.

---

## When to Delegate

Use sub-agents to parallelize independent work. Delegate if ANY of these signals match:

| Signal | Trigger |
|--------|---------|
| 🐛 **Debugging / Iterative Fixes** | Multiple fix-test cycles, error hunting |
| 🔧 **Iterative Work** | Styling, tuning, API integration — expects multiple attempts |
| 🏗️ **Feature (3+ files)** | Touches 3 or more files in different areas |
| 📝 **Documentation** | Updates needed across multiple files |
| 🔍 **Investigation / Research** | Exploring unfamiliar codebases or third-party APIs |

If ANY signal matches AND your platform supports sub-agents (Claude Code, Aider, Cursor agent mode), delegate — subject to the overhead check below. Otherwise implement sequentially.

**Overhead check.** Delegation has fixed coordination cost (briefing, reporting, integration). For a task just over a threshold but genuinely small and single-threaded, doing it inline can be cheaper than the round-trip. Treat the triggers as signals to *consider* delegation, not mandates — the same way the budget anchors below are signals, not caps.

---

## Quick Brief Template

For straightforward tasks (complexity 1–5):

```
Task: [what to do]
Scope: [files/components to touch]
  - [file 1]
  - [file 2]
  Out of scope: [what NOT to touch]
Budget: ~[N] tool calls
Model: [tier] ([alias]) — [reason, if upgraded from orchestrator tier]
Done when:
  ✅ [criterion 1]
  ✅ [criterion 2]
  ✅ Quality gates pass (build + lint + test)
```

Omit the `Model:` line when inheriting the orchestrator's tier — include it only on a deliberate upgrade (or downgrade), per the Disclosure Contract.

### Tool-Call Budget Anchors

Use these as starting values when filling in `Budget: ~[N] tool calls` above. They are **anchors, not caps** — exceed them if the work genuinely demands it, but treat overruns as a signal that the task may be misscoped and worth re-planning rather than grinding through.

| Scope | Anchor | When overshoot is reasonable |
|-------|--------|-------------------------------|
| Lookup / single-file edit | ~10 calls | Rare — past 15 calls you've drifted |
| Targeted bug fix | ~20 calls | Reproduction was hard, or root cause moved between files |
| Feature touching 3–5 files | ~40 calls | Discovery surfaced unknown integration points |
| Cross-cutting refactor | ~80 calls | Genuine multi-file scope — but consider splitting first |
| Investigation / research | ~30 calls | Following an unexpectedly deep call chain |
| QA sub-agent (post-shutdown review) | ~15 calls | Issue density is high enough to warrant deeper inspection |

**Why anchors matter:** tool calls cost both latency and tokens. A stated budget makes overruns visible — if a "small" task balloons past its anchor, stop and re-scope rather than continuing on momentum.

---

## Vertical Slices Over Horizontal Layers

When breaking work into parallel sub-agent tasks, prefer **vertical slices** (each sub-agent owns one user-feature end-to-end — model + API + UI + tests) over **horizontal layers** (one sub-agent does all models, another all APIs, another all UIs).

**Why:** vertical slices ship and verify independently. Horizontal layers create handoff dependencies — the API agent waits for the model agent, the UI agent waits for the API agent — and integration debt surfaces at the worst possible time, after all the layers are "done."

**Heuristic:** if you can write the Done-when criterion as a user-observable behavior, it's a vertical slice. If the Done-when criterion is "interface X exists for layer Y to consume," it's a horizontal layer — re-slice.

**Exception:** foundational work (database schema migration, shared type definitions, build configuration) genuinely belongs in a single horizontal pass before vertical slices begin. Don't force-vertical when the work is shared infrastructure with no user-facing surface.

**Source:** absorbed from `gsd-build/get-shit-done` (2026-05-09); GSD's wave-parallelism doctrine is the load-bearing insight.

---

## Coordination Rules (Essential)

1. **Non-overlapping files** — Each sub-agent works on different files. If two tasks touch the same file, execute sequentially.

2. **Trust-but-verify** — Read the sub-agent's verification report. Only re-run quality gates if the report is missing, incomplete, or shows failures.

3. **No nested sub-agents** — Sub-agents do not spawn their own sub-agents. All spawning is done by the coordinating agent. If work expands beyond scope, report `BLOCKED_SCOPE_EXPANDED` with a proposed split — see `sub-agent-coordinator` for the full protocol.

4. **Shared worktree by default** — Sub-agents operate in the same worktree as the coordinator. Rely on rule 1 (non-overlapping files) to prevent conflicts.

5. **Blind parallel lenses** — To review *one* artifact from multiple angles, run sub-agents on the SAME input, each with a different lens (correctness / security / performance) and blind to the others. Independent context prevents the anchoring you get from asking one session the same question repeatedly — it converges on its first answer's blind spots. Unlike rule 1, the input overlaps by design: agents only read, and each returns a separate report.

6. **Integration gate after fan-out** — When parallel sub-agents have each reported done, the coordinator runs one cross-slice verification before declaring the feature complete: the full build plus the union of tests covering every touched module, run together. Building on rule 4 (shared worktree), the slices already live in one tree — but slice-local green is necessary, not sufficient: the seam between slices is unverified until they run as one. If the gate fails, the conflict is the coordinator's to resolve or re-delegate as a scoped fix; never declare done on slice-local passes alone.

---

## Capability Tier + Reasoning Effort

Model selection axes (capability tier / reasoning effort / speed lane) AND the canonical default mapping for coding work both live in `sub-agent-coordinator` § Model Selection — Capability, Reasoning, Speed. **kerby inherits both without overrides.**

If a kerby-specific override emerges later (e.g., "for this team, every production-path change is `high` regardless of scope"), add it here as a thin overlay table rather than forking the full matrix.

### Sanctioned tier upgrade (the reverse of "never downgrade")

Default stays **inherit**. But "never silently downgrade" reads in reverse too:
an *upgrade* above the orchestrator's tier is allowed — and expected — when the
delegated task is genuinely harder than the orchestrator's tier is sized for.
`[behavioral]` — no hook enforces model routing; this is judgment, like the
rest of `sub-agent-coordinator`'s Model Selection axes.

Upgrade the sub-agent to at least `high` when **any** fires — not merely one
tier above wherever the orchestrator happens to sit. An orchestrator running
on `low` doesn't get to under-serve a governance-surface or approval-gated
task by landing at `standard`; `working-patterns.md`'s Complexity Routing
already says high/critical work gets "the best reasoning model" regardless of
what routed the delegation there. (From `standard`, this is the
`standard → high` step described below; from `low`, it's `low → high`, not
`low → standard`.) The triggers:

- **Approval-gated:** the task's complexity is at or above the fixed grade ≥ 7
  approval point (`BOOTSTRAP.md`'s user-approval gate — distinct from the
  lower, configurable `plan_threshold`) — i.e. the same line that already
  requires user approval before starting. Match the model to the judgment.
- **Blast-radius override:** the change touches the governance surface — a gate,
  verdict logic, a Security Lens rule, or a skill's decline/routing block —
  **regardless of its complexity score**. A low-score edit here is still
  high-stakes bounded authoring. Score gates ceremony; blast radius gates the model.
- **Divergence retry:** a `FAILED → TODO` retry on the *code-wrong* branch
  of an Expected-vs-Realized divergence (`workflows/feature.md` § 7) once
  it has already hit the circuit breaker (3 no-progress / same-error 3x —
  the space turned out unknown, not just the first attempt being off). The
  same applies when a human resumes work after adjudicating an "ambiguous"
  divergence (feature.md's STOP branch) — a human-confirmed unknown is the
  same signal. "Prediction wrong" alone never retries — it updates the
  Expected Outcome and logs, per feature.md § 7.3; it does not reach this
  trigger. Upgrade tier **and** flip reasoning `on`.

Any upgrade is a deliberate axis change, so it MUST be disclosed per the
coordinator's Disclosure Contract, e.g.:

    Tier: high (upgraded from orchestrator's standard — complexity 8, approval-gated).
    Thinking: on (orchestrator had it off — divergence retry, unknown space).

In kerby's own Quick Brief Template (above), the same disclosure collapses
into the single `Model:` line — don't emit both `Tier:`/`Thinking:` and
`Model:` for one brief; use whichever field matches the brief shape you're
writing.

Do **not** upgrade routine work: a complexity 1–3 config change stays at the
orchestrator tier (or lower). Upgrading everything "just in case" is the waste
this overlay exists to prevent.

---

## Picking the Role

See `sub-agent-coordinator` § Picking the Role for the full protocol. kerby adds no overrides — Task verb conveys role implicitly; optionally tag with a canonical persona name from `team-composer`'s catalog (e.g., `Role: @security_specialist`, `Role: @dataviz_engineer`) when a richer lens is wanted. For multi-perspective discussion of one decision (panel, not worker), use `team-composer` directly.

---

## Platform Fallback

If your agent platform does not support sub-agents, implement sequentially. Each implementation task should still follow the task loop (implement → check → commit → log → repeat).

---

## For Full Patterns & Templates

→ Load the `sub-agent-coordinator` skill for:
- Full briefing template (context, scope, constraints, reporting)
- Coordination patterns (fan-out, pipeline, specialist routing, review)
- Communication protocol & check-in intervals
- Example scenarios (monorepo setup, translation work, parallel review)
- Spawning checklist
- Common mistakes & how to avoid them
