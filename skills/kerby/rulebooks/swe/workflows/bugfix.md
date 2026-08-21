# Bug Fix Workflow

You are fixing a bug. Follow these steps in order.

<pre_work>
## 1. Pre-Work

You MUST complete these before writing any code:

1. Read `references/debugging.md` — systematic debugging approach
2. Read `references/communication.md` — commit format, logging
3. **Set up the branch — check the § Branching triggers FIRST** (BOOTSTRAP.md), then take exactly ONE of these paths:

   **No trigger (the default) — branch in place, from the protected base:**
   ```bash
   git checkout -b fix/<short-description> <protected-base>   # omit the base only when already on it
   ```
   **A trigger applies** (concurrent different-branch work; explicit user/harness request; dirty-state preservation) — announce it in one line, then create the worktree **instead of** the in-place branch, from the protected base (never from another branch's HEAD):
   ```bash
   git worktree add .worktrees/<branch-name> -b fix/<short-description> <protected-base>
   cd .worktrees/<branch-name>
   {package_manager} install
   ```
   (A harness-provided worktree already satisfies its trigger — work in it; create nothing.)
   Worktree costs (npm `node_modules` duplication, Windows path limits): `references/git-worktrees.md`.
4. **Baseline check** — establish which tests already fail vs. which are yours:
   - If you just created this worktree or in-place branch from a known-good base: **skip the baseline gate** — run only `{test_command}` to note any pre-existing failures
   - If `git status` shows a clean working tree and the last commit's gates passed: **skip the baseline gate**
   - Otherwise, run Standard gates:
     ```bash
     {build_command} && {lint_command} && {test_command}
     ```
   Note which tests fail — these are your baseline (not caused by your fix).
</pre_work>

<reproduce>
## 2. Reproduce

Before fixing anything, reproduce the bug:

1. Identify the exact steps or input that trigger the bug
2. Confirm you can see the failure (test failure, error message, wrong output)
3. If you cannot reproduce, ask the user for more details — do not guess at a fix

Document the reproduction: what you did, what happened, what should have happened.
</reproduce>

<diagnose>
## 3. Diagnose

Follow the systematic debugging process:

1. **Hypothesize** — form up to 3 hypotheses for the root cause
2. **Test each hypothesis** — narrow down with targeted checks (logs, breakpoints, assertions)
3. **Identify the root cause** — not just the symptom

Do NOT apply trial-and-error fixes. If 3 hypotheses fail, document what you tried, mark BLOCKED, and ask for help.

Check the knowledge base (`.kerby/knowledge/`) — a similar bug or lesson may already be documented.
</diagnose>

<delegate_check>
## 4. Check: Should You Delegate?

If the fix touches 3+ files, involves iterative debugging cycles, or will take >15 minutes, read `references/sub-agent-delegation.md` and delegate. If your platform does not support sub-agents, implement sequentially but still follow the commit gate in section 5.
</delegate_check>

<fix>
## 5. Fix — Commit Gate

Execute these steps in order. Do NOT skip the commit.

1. Write a failing test that captures the bug (the test MUST fail before your fix)
2. Apply the minimal fix — don't refactor unrelated code
3. **Iteration check** — run the failing test + related tests to confirm the fix works. This is fast feedback, not full verification.
4. **Commit check** — re-pick the tier from the staged diff (`references/quality-gates.md` § At Commit Time is the single authority); a bugfix diff lands on Standard or higher in practice:
   ```bash
   {build_command} && {lint_command} && {test_command}
   ```
5. Confirm no regressions — all tests that passed before still pass
6. **COMMIT now:**
   ```bash
   git add <specific-files>
   git commit -m "fix(<scope>): <description>"
   ```
7. Append to `.kerby/memory.log`

If the fix requires multiple changes, repeat steps 1–7 for each change. Each completed fix gets its own commit. See `references/quality-gates.md` for gate tier details.
</fix>

<finish>
## 6. Finish

Complete ALL of these before declaring done:

1. **Quality gates pass** — all tests green, no regressions
2. **Project state written — before the commit, not after.** These are shared, committed artifacts (`references/communication.md` § Session Logging), so they belong to the change that produced them:
   - **`.kerby/memory.log`** — what the bug was, what caused it, how you fixed it
   - **`.kerby/STATUS.md`** — reflects current state
   - **`.kerby/knowledge/` lesson** if this bug reveals an operational lesson worth keeping. Propose before writing; skip if nothing applies
   - **`CONTEXT.md`** if a new domain term was introduced or renamed. See `references/domain-glossary.md`
3. **All changes committed and pushed:**
   ```bash
   git status  # must show clean working tree
   git worktree list  # verify no other worktrees have uncommitted work
   ```
4. **Manual verification instructions provided** — emit the **How to Verify** block per `BOOTSTRAP.md` § 4 (Manual Verification Instructions). For a bug fix, include: steps to reproduce the original bug (should no longer occur), steps confirming the fix, and related areas to spot-check for regressions.
5. **Realized Outcomes captured (grade ≥ `plan_threshold`)** — per `BOOTSTRAP.md` § 4 / `workflows/feature.md` § 7: place the actual run result next to the § 3 Expected Outcome, emit `outcome: match | mismatch`, and on mismatch route code-wrong (fix via this workflow's loop, bounded by the circuit breaker) / prediction-wrong (update + log) / ambiguous (STOP). Skip only when the plan was waived by a logged user opt-out (§ 2.5).
6. **Working tree clean — the terminal gate.** Re-run `git status --short`; it must be empty. Then `git push` and confirm it reported everything up to date. Do not use `git push -u origin HEAD` to force an upstream — on a branch already tracking a differently-named remote branch it creates a second remote branch and retargets the upstream to it. And check `git log @{u}..` only once an upstream exists; without one it exits `fatal: no upstream configured` rather than reporting success. Step 3 is not the last thing that writes — step 5 can find a real bug and change code, and per-iteration `memory.log` entries from § 5 are still uncommitted. Commit **and push** anything outstanding now, before the PR exists. **If step 7 itself writes anything** (the Preserve-branch option notes the branch and reason in `.kerby/memory.log`), commit and push that too, then re-run this check.
7. **Branch finalization — pick one of four options** (same as feature workflow):
   - **Open PR** (default) — push branch; open PR; if a worktree was used, keep it until the PR is merged
   - **Merge locally** (solo project / approved hotfix) — merge; if a worktree was used, `git worktree remove .worktrees/<name>`
   - **Preserve branch** (more work expected) — note reason in `.kerby/memory.log`; keep the worktree if one was used
   - **Discard** (requires explicit user confirmation) — leave the branch first (`git worktree remove --force .worktrees/<name>` if one was used, else `git checkout <base>`), then `git branch -D <branch>` (git refuses to delete a checked-out branch)
   
   On an in-place branch (the default), skip the worktree actions — they apply only when an escalation trigger created one.

8. **Do NOT merge to a protected branch without explicit user instruction.**

Full worktree lifecycle details: `references/git-worktrees.md`
</finish>
