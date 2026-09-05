# Feature / Enhancement / Refactor Workflow

You are implementing a new feature, enhancement, or refactoring task. Follow these steps in order.

<pre_work>
## 1. Pre-Work

You MUST complete these before writing any code:

1. Read `references/working-patterns.md` — task approach, code standards
2. Read `references/communication.md` — commit format, logging, branch naming
3. Read project conventions — linter config, formatter config, existing code patterns
4. **Set up the branch — check the § Branching triggers FIRST** (BOOTSTRAP.md), then take exactly ONE of these paths:

   **No trigger (the default) — branch in place, from the protected base:**
   ```bash
   git checkout -b <type>/<short-description> <protected-base>   # omit the base only when already on it
   ```
   **A trigger applies** (concurrent different-branch work; explicit user/harness request; dirty-state preservation) — announce it in one line, then create the worktree **instead of** the in-place branch, from the protected base (never from another branch's HEAD):
   ```bash
   git worktree add .worktrees/<branch-name> -b <type>/<short-description> <protected-base>
   cd .worktrees/<branch-name>
   {package_manager} install    # bun install, pnpm install, etc.
   ```
   (A harness-provided worktree already satisfies its trigger — work in it; create nothing.)
   Ensure `.worktrees/` is in `.gitignore` before creating one. Worktree costs (npm `node_modules` duplication, Windows path limits): `references/git-worktrees.md`.
5. **Baseline check** — confirm you're starting from a clean state:
   - If you just created this worktree or in-place branch from a known-good base (main/develop passed CI): **skip baseline gates**
   - If `git status` shows a clean working tree and the last commit's gates passed: **skip baseline gates**
   - Otherwise, run Standard gates to establish baseline:
     ```bash
     {build_command} && {lint_command} && {test_command}
     ```
     If the baseline is broken, fix it first or flag it to the user.
</pre_work>

<clarify>
## 2. Clarify

If the request is ambiguous, ask 1–2 targeted questions. State your assumptions explicitly. Don't silently guess.

Check the knowledge base (`.kerby/knowledge/`) for relevant decisions, conventions, or lessons that apply to this task. If the knowledge base answers a "why" question, use it instead of guessing or asking.

**Better-approach check (propose once, then defer).** If the user specified an approach, hasn't planned, and you see a *materially* better one for the *requested task*: surface it once — the option, why it's better, the cost of their choice, and a one-line "so you learn" note — in ≤3 lines. Then build what they asked unless they pivot. Do not relitigate after they choose; skip entirely for trivial tasks. This concerns the *requested task's* approach only — out-of-scope improvements stay logged-not-suggested (`BOOTSTRAP.md` §4 Guardrails).
</clarify>

<plan>
## 3. Plan

This block is added *on top of* the `plan:` line (`BOOTSTRAP.md` § 4 Plan Gate), which is emitted on every change route regardless of grade. Steps 1–3 expand what that line states in one sentence.

1. Restate the problem — confirm you understand what's being asked
2. Identify affected files — scope the change before editing
3. Check dependencies — will this change break anything downstream?
3b. **State the check** — how you will know the change worked: the command to run, the endpoint to call, the screen to open. This is the third slot of the `plan:` line (`BOOTSTRAP.md` § 4 Plan Gate), restated in full here; at or above `plan_threshold` the Expected Outcomes block below refines it into a prediction, but the check itself is named here so a plan is never missing it.
4. **If the feature introduces a new third-party vendor** (auth, db, payments, mailer, etc.), consult `references/vendor-adapters.md` for the ports/adapters pattern. Define the port from consumer needs; add the adapter under `adapters/<vendor>/`.
5. Rate complexity (1–10). **This table is the canonical complexity ladder — the single source of truth; other files point here.**

| Grade | Indicators | Approach |
|-------|-----------|----------|
| Low (1–3) | Single file, config, typo | Handle directly. Self-review when done. |
| Med (4–6) | Multiple related files, moderate logic | **Plan + Expected Outcomes** (below), then implement. Self-check when done. |
| High (7–8) | Multi-file, design decisions, new patterns | **Plan + Expected Outcomes, get user approval before starting.** QA sub-agent when done. |
| Critical (9–10) | Cross-cutting, architectural, breaking | Plan + approval + staged rollout. QA sub-agent when done. |

`plan_threshold` (`ai.planThreshold`, default 4) is the grade at/above which a written plan is required (`BOOTSTRAP.md` § 2.5 / § 4 Plan Gate). The table's **Plan + Expected Outcomes** entries assume that default; the plan requirement tracks the knob (raise it and more Med grades handle-directly), while the approval gate at grade ≥ 7 is fixed. For complexity 6+, read `references/implementation-planning.md` for structured planning.

### Expected Outcomes (grade ≥ `plan_threshold`)

Before any code, predict the **observable end-state** — what the change will look like from outside, in the medium that fits. This is the prediction the finish step (§ 7) checks against. Predict the result, not the implementation.

| Change medium | Predict |
|---|---|
| UI | 2–3 line description or rough sketch of the surface + key states (empty / loading / error) |
| API | the request/response payload shape |
| CLI / script | the output lines the user will see |
| Data / state | the state transition (before → after) |

**Case table — the tester's half of the prediction.** The medium table predicts one end-state; a tester enumerates cases. Add, in the same block:

```
| case | action / input | expected |
|---|---|---|
| happy path | <what is done> | <what is observed> |
| edge | … | … |
| failure | … | … |
```

At least the happy path plus one edge case and one failure case, where the change has them; where it has none, one row whose `case` is `none`. This is a forced artifact, not advice: an absent table is a missing plan, not a stylistic choice. Each row is a check the finish step (§ 7 step 6) runs for real and fills an `actual` column for, and at the High/Critical tiers it is the QA sub-agent's Stage 1 checklist (`references/validation.md`).

Below `plan_threshold` this block is optional.

### Smallest version, and what you are deferring (grade ≥ `plan_threshold`)

**This block belongs to the full plan only.** The `plan:` line does not carry it — below the threshold, a change small enough to skip the full block is small enough that "the smallest version" is the whole of it. Anything deferred there is still named in the report's `skipped:` line, which is never waived.

The full plan states two things, in one line each:

```
smallest: <the least you can build that fully satisfies the request>
deferring: <items, comma-separated> | none
```

**Fully satisfies** is the load-bearing half. Minimal is not partial (`BOOTSTRAP.md` § 1b) — you are building less *around* the request, never less *of* it. Only hardening beyond the ask, refactors, adjacent cleanup and polish are deferrable, and the never-defer list in § 1b overrides all of it.

Every item you name in `deferring:` appears word for word in the report's `skipped:` line and in the deferral sink (`references/guardrails.md` § Where a finding goes). That is what makes this checkable rather than a good intention: a reviewer can compare the three.

**On the bugfix route, the minimal version is the root-cause fix.** A symptom patch is never the minimal version, however few lines it is — `references/debugging.md` and `BOOTSTRAP.md` § Diagnosis both outrank this section, and the root-cause fix is usually the smaller diff anyway (one guard where the callers meet, not one per caller).
</plan>

<delegate_check>
## 4. Check: Should You Delegate?

**Before implementing, check the delegation signals below.** If ANY signal matches, you MUST read `references/sub-agent-delegation.md` before deciding — then delegate, *unless* its overhead check says an inline pass is cheaper (a small, single-threaded task just over a threshold). The signals trigger the decision; they don't pre-make it.

| Signal | Match? |
|--------|--------|
| Task touches 3+ files | → Delegate |
| Task involves iterative debugging/fixing | → Delegate |
| Multiple independent sub-tasks exist | → Delegate in parallel |
| You catch yourself thinking "this should be quick" | → Delegate |
| Task estimated at >15 minutes of focused work | → Delegate |

If NO signals match (single-file change, trivial fix), proceed to implement yourself.

**If your agent platform does not support spawning sub-agents** (e.g., Cursor, Windsurf, Copilot), skip delegation and implement sequentially using the task loop below. The loop still applies — commit after each piece of work.

If you delegate, brief each sub-agent with: task + scope + files + done-when + constraints. Use quick briefs for complexity ≤5, full briefs for 6+. See `references/sub-agent-delegation.md` for templates.
</delegate_check>

<implement>
## 5. Implement — Task Loop

Whether you implement yourself or coordinate sub-agents, repeat this loop for each piece of work:

```
┌─→ 1. PICK   — Choose the next task or sub-task
│              If tracked in ROADMAP.md, flip [ ] → [~]
│   2. DO     — Implement (prefer TDD: failing test → minimal code → pass)
│   3. CHECK  — Iteration check (fast feedback):
│              Choose tier based on what you changed (see below)
│   4. COMMIT — Commit check (tier from the staged diff) + commit:
│              {build_command} && {lint_command} && {test_command}
│              git add <specific-files>
│              git commit -m "<type>(<scope>): <description>"
│              If commit completes a ROADMAP feature, flip [~] → [x]
│              and sweep to ## Shipped (immediately or in batches)
│   5. LOG    — Append to .kerby/memory.log (see BOOTSTRAP.md section 4 for format)
│   6. PUSH   — In multi-session work: git push
└─── 7. REPEAT — Go to step 1 for the next task
```

### Iteration Check Tiers (step 3)

Pick the tier that matches your change. See `references/quality-gates.md` for details.

| Changed... | Iteration check | Why |
|-----------|----------------|-----|
| Config, docs, comments, formatting only | `{lint_command}` | No logic changed — lint catches typos/format |
| Logic in 1–2 files | `{lint_command}` + related tests only | Fast feedback on what you just touched |
| 3+ files, cross-cutting, or dependency changes | Standard: `{build_command} && {lint_command} && {test_command}` | Too risky to skip — run everything |

**"Related tests only"** = run the test file(s) that cover the module you changed. If unsure which tests are related, run the full suite.

### Commit Check (step 4)

**Re-pick the tier from the staged diff — never inherit the iteration check.** That check gave fast feedback on a tree that has since moved; the commit check is your safety net and must be chosen against what is actually staged. `references/quality-gates.md` § At Commit Time is the single authority for the selection; a feature-sized diff lands on Standard or higher in practice.

```bash
{build_command} && {lint_command} && {test_command}
```

If gates fail, fix the issue and re-run before committing.

**Rules for this loop:**
- Do NOT batch commits at the end. Each piece of completed work gets its own commit.
- Do NOT skip the commit check. The tier it selects must pass before every commit.
- If stuck after 3 attempts on one task, log what you tried, mark BLOCKED, move to the next task.
- If a ROADMAP item is blocked mid-loop, flip `[~]` → `[!]` with a one-line reason and continue. Resume by flipping back to `[~]` when the blocker clears.
- Match existing patterns in the codebase — consistency over local optimization.
- **Debug systematically** — reproduce → hypothesize (max 3) → fix. No trial-and-error. Details: `references/debugging.md`
- **Cheapen the loop before grinding** — if two fix-test cycles on one task have failed, stop before a third and reduce the cost of a single cycle (minimal reproduction, focused test command, or watch mode) instead of grinding through more attempts. A faster loop changes how many hypotheses you can afford. Why: `references/debugging.md` § feedback loop.
</implement>

<validate>
## 6. Validate

After all tasks in the loop are complete, perform final validation:

| Complexity | Validation |
|-----------|-----------|
| Low (1–3) | Self-review: run gates, re-read diff, confirm it does what was asked |
| Med (4–6) | Self-check: spec compliance check + run gates fresh |
| High (7+) | Spawn QA sub-agent for two-stage review: spec compliance then code quality |

- **If work was fanned out to parallel sub-agents**, run the integration gate before declaring done — see `references/sub-agent-delegation.md` rule 6 (cross-slice build + union of touched-module tests). Slice-local passes are not sufficient.

**No completion claims without fresh verification evidence.** Never say "should work" or "probably passes" — run the check, read the output, state the result.

Details: `references/validation.md`
</validate>

<finish>
## 7. Finish

Complete ALL of these before declaring done:

1. **Final quality gates pass:**
   ```bash
   {build_command} && {lint_command} && {test_command}
   ```
2. **Project state written — before the commit, not after.** These are shared, committed artifacts (`references/communication.md` § Session Logging), so they belong to the change that produced them. Writing them after the commit is what leaves them dangling outside the PR:
   - **`.kerby/memory.log`** — session summary appended
   - **`.kerby/STATUS.md`** — where things stand, not what happened. **Read `references/communication.md` § Status Tracking before writing it** — that section is the authority on what may and may not go in this file, and it is not loaded until you read it
   - **`.kerby/knowledge/` entry** — a new decision, convention, or lesson. Propose before writing; skip if nothing applies
   - **`CONTEXT.md`** — new domain terms used 2+ times. See `references/domain-glossary.md`
   - **The deferral sink** — one entry per item you named in the plan's `deferring:` list, each saying what it was deferred from. `references/guardrails.md` § Where a finding goes selects which sink. Nothing deferred means nothing to write
3. **All changes committed and pushed:**
   ```bash
   git status  # must show clean working tree
   git worktree list  # verify no other worktrees have uncommitted work
   ```
4. **`ROADMAP.md` self-check** — completed features flipped to `[x]` and swept to `## Shipped`; new in-scope items added if scope expanded mid-task. The flips should already have happened in the COMMIT step of the loop; this is the verification
5. **Manual verification instructions provided** — emit the **How to Verify** block per `BOOTSTRAP.md` § 4 (Manual Verification Instructions): steps to test, what to look for, edge cases, env setup.
6. **Realized Outcomes captured (grade ≥ `plan_threshold`)** — distinct from "How to Verify" above (that's instructions for the human; this is *your* check against the § 3 prediction). *Skip this step only when the plan was waived by a logged user opt-out (`BOOTSTRAP.md` § 2.5) — there is no Expected Outcome to compare against; standard Verification (§ 6) still applies.* After implementing:
   1. Capture the **actual** result from a real run — or a dry-run transcript where no runnable surface exists — and place it next to the § 3 Expected Outcome. Evidence is an object (screenshot path / captured JSON / CLI dump / diff), **not** prose. When the plan carries a case table, fill its `actual` column row by row from real runs — one evidence object per row.
   2. Emit `outcome: match | mismatch` — one line per case when the plan carries a case table (`outcome: <case> — match | mismatch`), a single line otherwise.
   3. On any `mismatch`, classify the cause and route — **only one branch changes code**:
      - **Code wrong** (real bug) → fix via the § 5 task loop, bounded by the existing circuit breaker (`references/working-patterns.md`: 3 no-progress / same error 3×; `references/error-handling.md`: build 5 / test 3 / lint 5 → BLOCKED). No new loop.
      - **Prediction wrong** (system is fine) → update the § 3 Expected Outcome with a one-line reason and log it to `.kerby/memory.log` (recurring wrong predictions signal mis-calibrated planning). No code change.
      - **Ambiguous** → STOP. Surface both artifacts + your hypothesis. The human adjudicates.

   Realized evidence is recorded as-observed — never edited to match the prediction (`references/validation.md` Iron Law).
7. **DEVELOPER_TODO.md created** if any human actions are needed (API keys, cloud resources, etc.)
8. **Working tree clean — the terminal gate.** Re-run `git status`. Step 3 is not the last thing that writes: step 6 (Realized Outcomes) can find a real bug and change code, step 7 can add `DEVELOPER_TODO.md`, per-iteration `memory.log` entries from the § 5 loop are still uncommitted, and a late knowledge entry can land here too. Commit **and push** anything outstanding now, before the PR exists — a commit that never leaves the machine is not in the PR either.

   ```bash
   git status --short          # must be empty
   git push                    # then confirm it reported everything up to date
   ```

   Two traps, both verified: `git log @{u}..` exits `fatal: no upstream configured` on a branch that has never been pushed, so it errors rather than reporting success — check it only once an upstream exists. And do **not** reach for `git push -u origin HEAD` to force one: on a branch that already tracks a differently-named remote branch it creates a second remote branch and silently retargets the upstream to it. When `git push` complains there is no upstream, follow the exact command it prints.

   This gate is why step 2 is not sufficient on its own. Ordering alone would still leave whatever steps 5–7 produced sitting outside the PR — which is the failure this section was reordered to fix.

   **If step 9 itself writes anything** — the Preserve-branch option notes the branch and reason in `.kerby/memory.log` — commit and push that too, then re-run this check. Finalization is the one step that can dirty the tree after its own gate.

9. **Branch finalization — pick one of four options** (ask the user if unclear):

   | Option | When to use | Action |
   |--------|-------------|--------|
   | **Open PR** (default) | Work is ready for human review | Push branch; open PR; if a worktree was used, keep it until the PR is merged |
   | **Merge locally** | Solo project, fast-path, or approved | `git checkout <base>`, merge; if a worktree was used, `git worktree remove .worktrees/<name>` |
   | **Preserve branch** | More work expected later | Note branch + reason in `.kerby/memory.log`; keep the worktree if one was used |
   | **Discard** | Work is a dead-end or spike | Requires explicit "discard" confirmation from user; then leave the branch: `git worktree remove --force .worktrees/<name>` if one was used, else `git checkout <base>` — and only then `git branch -D <branch>` (git refuses to delete a checked-out branch) |

   On an in-place branch (the default), skip the worktree actions — they apply only when an escalation trigger created one.

10. **Do NOT merge to a protected branch without explicit user instruction** — leave option 1 (PR) as the default.

Details: `references/context-management.md`, `references/git-worktrees.md`
</finish>
