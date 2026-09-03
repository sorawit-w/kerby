# Quick Task Workflow

For simple tasks — single-file edits, config changes, documentation updates, or fixes with obvious root cause (complexity below `plan_threshold` — default 4, i.e. the low band).

**Branching:** use a normal `git checkout -b` — the in-place branch default from `BOOTSTRAP.md` § Branching. (If the task turns out to be more complex than expected, escalate to the task-type workflow — `bugfix.md` for a bug fix, else `feature.md` — and **continue on the same in-place branch**; escalating workflows never changes the branching default, and a worktree is created only if a § Branching escalation trigger applies.)

<fit_check>
## Fit Check (before you start)

The quick-task path is appropriate only when ALL of these hold. If even one fails, switch to the task-type workflow (`bugfix.md` for a bug fix, else `workflows/feature.md`) and start from its step 2 — no exceptions.

- **A change is actually being made** — if the ask is to explain or investigate, the route is `investigate` (BOOTSTRAP.md § 3), not quick-task. Every step below writes; none of them check first
- **No new files** — you're editing existing files only, not adding modules
- **No test logic changes** — tests may *run* during checks, but the change must not require editing an assertion, fixture, or test scaffold. This is one definition, used identically in all three places it appears below: what matters is whether a test file has to change, not whether the file you opened lives in a test directory. A copy edit that a snapshot asserts *does* require a test edit, and so fails this criterion
- **No schema, contract, or public-type changes** — no DB migrations, no exported type/interface shape changes, no public API edits
- **No high-stakes paths** — auth, payments, migrations, infra, CI/CD, production-traffic-shaping constants (see BOOTSTRAP.md §3 "High-stakes path override")
- **Diff stays ≤ ~50 LOC** — rough budget; if you're approaching it, the change isn't a quick task
- **Change is strings, copy, comments, config values, data, or formatting** — not new logic, not refactoring, not behavior change

**Why this is hard-floored, not advisory:** quick-task skips overhead because the risk surface is bounded. Violating any criterion means the risk surface is no longer bounded — at that point the savings are illusory and the discipline of the full task-type workflow (`feature.md` / `bugfix.md`) is the cheaper path overall.

**Grade ceiling vs. risk guard — two independent axes.** The complexity ceiling tracks `plan_threshold` (raising the knob never lowers the bar here); the criteria above are independent risk guards. A change that introduces logic, refactors, exceeds the LOC budget, or touches schema/contracts escalates to the task-type workflow (`bugfix.md` / `feature.md`) *even when its grade is below the threshold*. Both the grade ceiling and the fit check must hold.

### Verify the criteria you can verify *now*, before the first edit

Six of the seven criteria above are knowable from the file list before you change anything. Only the LOC budget genuinely needs the diff. **Resolve the six first** — an escalation found now costs a re-route; the same escalation found after the edit leaves code on disk with no approved plan behind it.

Open the target files and run these, adapting the commands to the project:

```bash
git ls-files <target-paths>                 # do they exist? (new file → escalate)
git check-ignore -v <target-paths>          # untracked/ignored surprises
```

Then read each target and confirm, from what you actually see:

- **No test edit required** — the criterion above, checked before you write. Check the path *and* whether the string you are changing is asserted anywhere: `grep -rn "<the literal>" <test-dirs>`. A hit means a test must change, so the criterion fails here rather than after the diff.
- **Not schema / contract / public type** — no migration dir, no exported type or interface shape, no public API surface.
- **Not a high-stakes path** — match the target against the `BOOTSTRAP.md` § 3 glob list *before* editing, including the prose-only category (retry/timeout/rate-limit constants, feature-flag defaults gating prod traffic, secrets loading). A path match is decided by which file the edit lands in, never by whether the changed lines look risky.
- **Not new logic, refactoring, or behavior change** — you are changing strings, copy, comments, config values, data, or formatting.

If any of the four fails, escalate **now**, before editing. That escalation is an ordinary pre-code re-route: `feature.md` § 3 (or `bugfix.md`) with its plan written the normal way, and the retroactive-plan carve-out in step 3a never comes into play.

**State your fit check before starting**, in 4–6 lines:

```
Quick-task fit:
- Files: <list>
- Change: <what will be different afterwards>
- Estimated LOC: <number>
- Check: <how you will know it worked>
- Verified before editing: not a test/schema/contract/high-stakes path, no new logic — <how you checked>
```

If you can't state it cleanly, the task doesn't fit. Switch workflows.

**On this route the fit check is your plan.** It carries the three things the one-line `plan:` floor asks for (`BOOTSTRAP.md` § 4 Plan Gate) — `Files:`, `Change:`, `Check:` — and it is stated before you start. Emit the fit check, not both artifacts.
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
   - Diff touches a test file, schema/migration file, contract/type file, or a high-stakes path (per BOOTSTRAP.md §3) — same criterion as the fit check, now measured against what actually changed
   - You found yourself changing behavior or logic mid-implementation, not just strings/config

   Escalation is not a setback — it's the system working. Do NOT commit a Tier-mismatched diff to escape the workflow change.

   **Which escalation you hit decides what happens next. Two cases, no third.**

   | You hit | Because | Do this |
   |---|---|---|
   | **The LOC budget only** | genuinely needs the diff to know | Re-grade, then take the plan artifact the § 4 first-match table selects for the new grade. Writing it with code already on disk is licensed *here and nowhere else*: read your own `git diff` and record what is already changed. |
   | **A risk criterion** — new file, test, schema, contract, high-stakes path, or new logic | should have been caught before the first edit | **Stop writing.** Re-grade; at grade ≥ 7 get user approval *before* continuing, because existing code does not approve itself. Say plainly what is already on disk and offer to revert it. |

   The risk-criterion row should be unreachable: § Fit Check verifies all six of those against the file list before anything is written. Reaching it means that block was skipped or a target changed under you — note it in `.kerby/memory.log` as a miss, not a routine path.

   **In both cases the fit check is void** and no longer stands in as your plan. Its replacement is chosen by the same first-match table as any other plan, so a below-threshold escalation takes the one-line floor and an at-or-above-threshold one takes the full block with Expected Outcomes. Say "supersedes the fit check above" so a reader knows which artifact is live.

   **3b. Quality-check (only if 3a passed):** while iterating, run the cheap check for what you are touching — `{lint_command}` for config/docs/comments/formatting, `{lint_command}` + related tests for logic.

   At commit time the tier is re-picked from the **staged diff**, not inherited from the iteration check above. `references/quality-gates.md` § At Commit Time is the single authority for that selection — follow it there rather than restating it here. In practice a quick task usually lands on Standard (`{build_command} && {lint_command} && {test_command}`); Quick applies only when nothing staged feeds a gate, which is narrower than "the file ends in `.md`".
4. **Commit:**
   ```bash
   git add <specific-files>
   git commit -m "<type>(<scope>): <description>"
   ```
5. **Log** — append to `.kerby/memory.log` (the entry carries the commit SHA, so it necessarily follows step 4 — see `references/communication.md` § Session Logging).
6. **Record anything you deferred** — one entry in the sink `references/guardrails.md` § Where a finding goes selects. Usually nothing: a quick task that needed a deferral was probably not a quick task.
7. **Commit the log.** `.kerby/memory.log` is tracked shared state, so step 5 leaves the tree dirty. `git status --short` must be empty before you finish; commit and push the log entry (and any roadmap line) if it is not.
8. **Tell the developer how to verify** — emit the **How to Verify** block per `BOOTSTRAP.md` § 4 (Manual Verification Instructions).
</do_it>

<escalate>
## If It's Not Simple

If the task turns out to be more complex than expected (touching multiple files, unexpected failures, unclear requirements), switch to the full workflow for the task type — **`bugfix.md` for a bug fix** (it keeps the reproduce → diagnose → failing-test path), otherwise **`feature.md`**:

Read that workflow and start from its step 2 (Clarify in `feature.md`, Reproduce in `bugfix.md`). The fit check is void on escalation — re-emit `complexity:` and take the plan artifact the new grade selects, per step 3a above. Step 3a is the authority on which artifact and on whether you may keep writing; do not infer either from this paragraph.
</escalate>
