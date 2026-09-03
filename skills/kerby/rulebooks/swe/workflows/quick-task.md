# Quick Task Workflow

For simple tasks — single-file edits, config changes, documentation updates, or fixes with obvious root cause (complexity below `plan_threshold` — default 4, i.e. the low band).

**Branching:** use a normal `git checkout -b` — the in-place branch default from `BOOTSTRAP.md` § Branching. (If the task turns out to be more complex than expected, escalate to the task-type workflow — `bugfix.md` for a bug fix, else `feature.md` — and **continue on the same in-place branch**; escalating workflows never changes the branching default, and a worktree is created only if a § Branching escalation trigger applies.)

<fit_check>
## Fit Check (before you start)

The quick-task path is appropriate only when ALL of these hold. If even one fails, switch to the task-type workflow (`bugfix.md` for a bug fix, else `workflows/feature.md`) and start from its step 2 — no exceptions.

- **A change is actually being made** — if the ask is to explain or investigate, the route is `investigate` (BOOTSTRAP.md § 3), not quick-task. Every step below writes; none of them check first
- **No new files** — you're editing existing files only, not adding modules
- **No test logic changes** — tests may *run* during checks, but you're not modifying assertions, test scaffolding, or fixtures
- **No schema, contract, or public-type changes** — no DB migrations, no exported type/interface shape changes, no public API edits
- **No high-stakes paths** — auth, payments, migrations, infra, CI/CD, production-traffic-shaping constants (see BOOTSTRAP.md §3 "High-stakes path override")
- **Diff stays ≤ ~50 LOC** — rough budget; if you're approaching it, the change isn't a quick task
- **Change is strings, copy, comments, config values, data, or formatting** — not new logic, not refactoring, not behavior change

**Why this is hard-floored, not advisory:** quick-task skips overhead because the risk surface is bounded. Violating any criterion means the risk surface is no longer bounded — at that point the savings are illusory and the discipline of the full task-type workflow (`feature.md` / `bugfix.md`) is the cheaper path overall.

**Grade ceiling vs. risk guard — two independent axes.** The complexity ceiling tracks `plan_threshold` (raising the knob never lowers the bar here); the criteria above are independent risk guards. A change that introduces logic, refactors, exceeds the LOC budget, or touches schema/contracts escalates to the task-type workflow (`bugfix.md` / `feature.md`) *even when its grade is below the threshold*. Both the grade ceiling and the fit check must hold.

**State your fit check before starting**, in 3–5 lines:

```
Quick-task fit:
- Files: <list>
- Estimated LOC: <number>
- Type of change: <strings / config / comments / docs / formatting>
- Check: <how you will know it worked>
- No new files / tests / schema / contracts / high-stakes paths: confirmed
```

If you can't state it cleanly, the task doesn't fit. Switch workflows.

**On this route the fit check is your plan.** It carries the same three things the one-line `plan:` floor asks for (`BOOTSTRAP.md` § 4 Plan Gate) — `Files:` and `Type of change:` are the what-and-where, `Check:` is the check — and it is stated before you start. Emit the fit check, not both artifacts.
</fit_check>

<do_it>
## Steps

1. **Read** — project conventions and recent history (you already did this in BOOTSTRAP.md step 2)
2. **Do** — implement the change, match existing patterns
3. **Scope-check, then quality-check** — first verify the actual diff stayed within fit criteria; then run the appropriate quality gate:

   **3a. Scope-check (diff vs. declared fit):**
   ```bash
   git diff --stat
   ```
   Compare actual diff to your declared fit check. If ANY of these now hold, STOP and escalate to the task-type workflow (`bugfix.md` for a bug fix, else `workflows/feature.md`):
   - Diff exceeds ~50 LOC across the change
   - Diff introduces a new file you didn't declare
   - Diff touches a test file, schema/migration file, contract/type file, or a high-stakes path (per BOOTSTRAP.md §3)
   - You found yourself changing behavior or logic mid-implementation, not just strings/config

   Escalation is not a setback — it's the system working. Do NOT commit a Tier-mismatched diff to escape the workflow change.

   **Escalation voids the fit check, and with it your plan.** The declarations that just failed are the artifact that was standing in for a plan, so you are now mid-change with none. Before continuing: re-emit `complexity:` with the new grade, and write the full plan for the route you escalated to — `feature.md` § 3, including Expected Outcomes at or above `plan_threshold`. Do not carry the void fit check forward as though it still describes the work.

   **This one plan is written with code already on disk, and that is not a violation.** The general rule is no task code before a plan; here the code is what *revealed* the escalation, so the order cannot be otherwise. The plan therefore covers the work that remains and states what is already changed — read your own `git diff` and write it down rather than describing intentions. Expected Outcomes describe the end state you are heading for, not a prediction made before touching anything. Nothing else in the rulebook licenses a plan written after the fact.

   **3b. Quality-check (only if 3a passed):** while iterating, run the cheap check for what you are touching — `{lint_command}` for config/docs/comments/formatting, `{lint_command}` + related tests for logic.

   At commit time the tier is re-picked from the **staged diff**, not inherited from the iteration check above. `references/quality-gates.md` § At Commit Time is the single authority for that selection — follow it there rather than restating it here. In practice a quick task usually lands on Standard (`{build_command} && {lint_command} && {test_command}`); Quick applies only when nothing staged feeds a gate, which is narrower than "the file ends in `.md`".
4. **Commit:**
   ```bash
   git add <specific-files>
   git commit -m "<type>(<scope>): <description>"
   ```
5. **Log** — append to `.kerby/memory.log` (the entry carries the commit SHA, so it necessarily follows step 4 — see `references/communication.md` § Session Logging).
6. **Record anything you deferred** — one `[ ]` line per item in `ROADMAP.md` § Follow-ups, per `references/guardrails.md` § Where a finding goes. Usually nothing: a quick task that needed a deferral was probably not a quick task.
7. **Commit the log.** `.kerby/memory.log` is tracked shared state, so step 5 leaves the tree dirty. `git status --short` must be empty before you finish; commit and push the log entry (and any roadmap line) if it is not.
8. **Tell the developer how to verify** — emit the **How to Verify** block per `BOOTSTRAP.md` § 4 (Manual Verification Instructions).
</do_it>

<escalate>
## If It's Not Simple

If the task turns out to be more complex than expected (touching multiple files, unexpected failures, unclear requirements), switch to the full workflow for the task type — **`bugfix.md` for a bug fix** (it keeps the reproduce → diagnose → failing-test path), otherwise **`feature.md`**:

Read that workflow and start from its step 2 (Clarify in `feature.md`, Reproduce in `bugfix.md`). The fit check is void on escalation — re-emit `complexity:` and write the full plan before continuing, per step 3a above.
</escalate>
