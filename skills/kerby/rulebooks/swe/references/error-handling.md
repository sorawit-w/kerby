# Error Handling & Recovery

Use this reference when encountering build failures, test failures, dependencies issues, or blockers.

> **Note:** Examples below use `bun` commands. Adapt to your project's toolchain (`npm`, `yarn`, `pnpm`, `deno`, etc.). The patterns apply regardless of the package manager.

---

## Retry Budgets

Each error type has a maximum retry count and recovery strategy:

| Error Type | Max Attempts | Primary Strategy |
|------------|--------------|------------------|
| **Build failures** | 5 | Check logs, fix imports, reinstall deps, verify syntax |
| **Test failures** | 3 | Read output, fix logic, add logging; a flaky test gets its cause found, never a skip or retry |
| **Lint errors** | 5 | Auto-fix first, then adjust code; suppress one site only with proof; config changes need approval |
| **Dependency issues** | 5 | Clear cache, reinstall, check versions, try --force |
| **Schema validation** | 1 | Validate input — deterministic, either valid or not |

---

## Build Failures (5 attempts)

### Attempt 1-2: Check and Fix

1. Run build with verbose output:
   ```bash
   bun run build --verbose
   ```
2. Scan logs for obvious issues:
   - Missing imports or typos
   - Syntax errors in generated code
   - Circular dependencies
3. Fix the identified issue
4. Re-run build

### Attempt 3-4: Dependency and Cache Cleanup

1. Clear cache:
   ```bash
   bun pm cache rm
   ```
2. Reinstall dependencies:
   ```bash
   bun install --force
   ```
3. Re-run build

### Attempt 5: Deep Inspection

1. Check for platform-specific issues (native modules, OS-specific paths)
2. Verify generated code syntax (if code generation involved)
3. Check for circular dependencies manually
4. If still failing: mark BLOCKED, document in `.kerby/BLOCKERS.md`

---

## Test Failures (3 attempts)

### Attempt 1: Understand the Failure

1. Run the test suite with verbose output:
   ```bash
   bun run test --verbose
   ```
2. Read the full test output carefully
3. Identify root cause: logic error, assertion, flakiness, or environment issue

### Attempt 2: Fix the Cause

If root cause is clear:
- **Logic error:** Fix the code
- **Wrong assertion:** Correct the test — after the intent gate (`references/intent-gate.md`) says the test, not the code, is wrong
- **Environment issue:** Check env vars, setup, teardown

**A flaky test is a symptom, not a cause.** Do not skip it, retry it, widen its timeout or loosen its assertion to get a green run — each one hides the failure the test exists to catch, and a skipped test is not a pass (`references/validation.md` § What Counts as Evidence of Change). Find the cause instead:

1. **Place it.** Find the smallest scope that still reproduces the failure — the test alone, else its file, else the suite (an order or shared-state flake can pass every time alone). Run that same scope at least 10 times on the base branch and on your branch, interleaved (`references/validation.md` § What Counts as Evidence of Change), and record `failed/N` for each. Run the base side in its own checkout — a temporary `git worktree add <dir> <base>`, announced as `BOOTSTRAP.md` § Branching requires and removed when you are done — so your uncommitted edits and build output stay out of it. Then compare the two rates — a failure on the base branch shows the failure existed before, not that your change left it alone:
   - **About the same** (2/10 against 3/10) → it predates your change: flag it to the developer as pre-existing (the baseline rule in `workflows/feature.md` § 1) and leave the test as it is.
   - **Clearly higher on your branch** (1/10 against 8/10) → your change caused it or made it worse. It is yours to fix.
   - **Too close to call** → run more on both. Still unclear → treat it as yours.
2. **Name what it depends on** — timing, test order, shared state, the clock, the network, a resource limit.
3. **Prove it.** Make the test fail every time for the cause you named: inject the delay, pin the order, freeze the clock. No failing probe, no named cause.
4. **Fix the cause** in the code or in the test's isolation, never in its threshold.

If the cause is still unknown when the budget runs out, mark BLOCKED. Quarantining a flaky test is the developer's decision, not a way out of the budget.

**Source:** adapted from `garrytan/gstack` (MIT, 2026-10-21) — its flake recipe (`investigate/sections/flake.md`): place the failure with repeated runs on the base branch, name the dependency, prove it with a forced probe, never loosen. Its tooling (`ship-measure.ts`, CI-run comparison) is not adopted.

### Attempt 3: Add Logging and Retest

If root cause is unclear:
1. Add detailed logging around the failing assertion
2. Run test again
3. If still failing after 3 attempts: mark BLOCKED, document in `.kerby/BLOCKERS.md`

---

## Lint Errors (5 attempts)

### Attempt 1: Auto-Fix

```bash
bun run lint --fix
```

Many lint errors resolve automatically. Check the diff and commit.

### Attempt 2-3: Manual Fixes

If auto-fix doesn't resolve:
1. Read the linter error message
2. Adjust code to meet the rule
3. Re-run lint

### Attempt 4-5: Suppress One Site, or Ask

If you can show the rule is wrong **at this one site** — not merely inconvenient:
1. Suppress that site only, with the reason in the comment:
   ```typescript
   // biome-ignore lint/rule-name: <why the rule is wrong here>
   const someCode = ...;
   ```
2. Document the exception in `.kerby/memory.log` and name it in your report

If the rule is wrong for many files, do **not** edit the linter config yourself — changing lint rules needs the team's agreement (`references/guardrails.md` § What NOT to Do). Propose the config change to the developer and mark the task BLOCKED until they decide.

---

## Dependency Issues (5 attempts)

### Attempt 1-2: Clear and Reinstall

1. Clear package manager cache:
   ```bash
   bun pm cache rm
   ```
2. Remove lock file and node_modules:
   ```bash
   rm -rf bun.lockb node_modules
   bun install
   ```
3. Try again

### Attempt 3: Force Install

```bash
bun install --force
```

### Attempt 4: Check Versions

1. Review `.tool-versions` or `package.json` engines
2. Verify that all declared versions are compatible
3. Check if newer versions of problematic dependencies exist
4. Update if appropriate, re-run install

### Attempt 5: Platform-Specific Issues

1. Check if error is platform-specific (native modules, Windows vs Unix paths)
2. Look for known issues in dependency's GitHub repo
3. If unable to resolve: mark BLOCKED, document in `.kerby/BLOCKERS.md`

---

## Schema Validation (1 attempt)

Schema validation is deterministic — either the input is valid or it isn't. No retry strategy.

If validation fails:
1. Verify the input matches the schema exactly
2. Check data types, required fields, format
3. If input is invalid: fix the data
4. If schema is wrong: update the schema definition
5. Re-validate

---

## When Retries Are Exhausted

### Document the Blocker

Create `.kerby/BLOCKERS.md` with this format:

```markdown
## [blocker-id]: [short description]

**Severity**: Critical | High | Medium

**Category**: Build | Test | Dependencies | Auth | Other

**Description**: [Detailed explanation of what failed and why it matters]

**Error message**:
[Full error output, last 50 lines]

**Attempted solutions**:
- Attempt 1: [what was tried and result]
- Attempt 2: [what was tried and result]
- Attempt N: [what was tried and result]

**Suggested resolution**: [What a human needs to do to unblock]

**Affected tasks**: [List task IDs that depend on this]

**When it happened**: [ISO 8601 timestamp]
```

### Update STATUS.md

Add to `.kerby/STATUS.md` under the Blockers section:

```
## Blockers

- [blocker-id]: [description] (severity: [level])
```

### Log in memory.log

Use the canonical format from `communication.md`:

```
[YYYY-MM-DDTHH:MM:SSZ]
Task: [task-id or description]
Action: Exhausted retry budget for [error type]
Files: [affected files]
Status: BLOCKED
Notes: Blocker=[blocker-id], Attempts=[N], Next=[awaiting human review / needs external action]
```

### Move On

- Skip the blocked task
- Look for other READY tasks (no unmet dependencies)
- Continue work on unblocked items
- Escalate blocker to human reviewer if task is critical

---

## Never Leave the Repo Broken

Before stopping work, ensure the main branch is in a buildable state.

### If Task Cannot Be Completed

1. Identify what changed that broke the build
2. Revert with:
   ```bash
   git revert HEAD
   ```
3. Or reset if not yet pushed:
   ```bash
   git reset --hard HEAD~1
   ```
4. Verify build passes:
   ```bash
   bun run build && bun run lint && bun run test
   ```
5. Document the failed attempt in `.kerby/memory.log`

### If Task is Partially Complete

1. Commit what works
2. Create a separate branch for incomplete work (using standard branch convention):
   ```bash
   git checkout -b wip/[task-id]-incomplete
   git push -u origin wip/[task-id]-incomplete
   ```
3. Leave `main` clean and building
4. Document next steps in `.kerby/memory.log`

---

## Error Triage Decision Tree

```
Error occurs
  ↓
Read error message carefully
  ↓
Match to error type (build|test|lint|dependency|schema)
  ↓
Run recovery strategy for that type
  ↓
Does it pass?
  ├─ YES → Commit and continue
  ├─ NO → Have retries remaining?
  │         ├─ YES → Increment attempt, retry strategy
  │         └─ NO → Exhausted, document blocker
  └─ UNCERTAIN → Add logging, run again
```
