# Guardrails, Scope, Security & Documentation

What NOT to do, how to stay on task, security awareness, and documentation hygiene.

**Enforcement legend.** Security rules below are tagged by *how* they hold:
- **[enforced-when-installed]** — a Claude Code hook hard-blocks the action, *but only if* the optional Phase-2 hooks were registered (`install`). Hook registration is opt-in, so these degrade to [behavioral] when hooks aren't installed.
- **[enforced-partial]** — a hook covers some paths but not all; the gap is named inline.
- **[behavioral]** — no hook can reach it (it lives in the model's context, not at a tool boundary); the agent applies it by judgment.

A shell hook fires at the *tool boundary* and can block an action; it cannot reach inside the model's context, so secret-*printing*, prompt-injection resistance, and prod-op safety are structurally [behavioral]. Full map and threat model: `references/threat-model.md`.

The two **[enforced-partial]** hooks today are `warn-env-read` (Read-tool `.env` reads — a Bash `cat .env` is the named gap) and `route-high-stakes` (Edit/Write on BOOTSTRAP §3 high-stakes paths — auth/migrations/payments/infra/CI; §3's prose-only *production-traffic-shaping* category is the named gap, un-globbable by nature). Both advise, never block — they raise the floor where a hook can see the path but the decision still lives in the model's context.

---

## What NOT to Do

| Do NOT                                          | Why                                              |
|-------------------------------------------------|--------------------------------------------------|
| Modify CI/CD configs without approval           | Can break the entire team's workflow              |
| Edit an existing `.env` / `.env.local`, or commit secrets | Unrecoverable overwrite; security risk   |
| Change linter/formatter rules unilaterally      | Team convention — requires consensus             |
| Rewrite large sections unprompted               | Scope creep, hard to review, risky               |
| Commit or push to protected branches (main, master, dev, develop, staging, release/*, trunk) | Always work on a feature branch |
| Skip quality gates to "move faster"             | Tech debt compounds, broken builds cascade       |
| Ignore existing patterns for "better" ones      | Consistency > local optimization                 |
| Install major deps without approval             | Affects bundle size, licensing, maintenance      |
| Delete files without confirming they're unused  | Broken imports are hard to debug later           |
| Overwrite guideline/spec files                  | Read-only — these are team-maintained            |

**Enforcement:** *Edit an existing `.env`* and *commit secrets* (`protect-env`, `pre-commit-check`) and *commit or push to protected branches* (`protect-git`) are **[enforced-when-installed]**. The rest are **[behavioral]**. What `protect-env` does and does *not* cover is in § Environment Files below — it is narrower than "no `.env` edits ever," on purpose.

---

## Destructive Git Commands

These commands cause data loss that's hard or impossible to recover (`git reflog` doesn't always save you). **Do not run them.** If you're certain you need one, ask the developer to run it themselves.

| Don't run                                                | Why                                                                  |
|----------------------------------------------------------|----------------------------------------------------------------------|
| `git push --force` / `-f`                                | Overwrites remote history; lost commits are hard to recover. Use `--force-with-lease` if you genuinely must. |
| `git push <remote> <protected-branch>`                   | Bypasses the feature-branch rule above. Protected list: `main`, `master`, `dev`, `develop`, `staging`, `trunk`, `release/*`. |
| `git reset --hard`                                       | Discards uncommitted work and resets the working tree.               |
| `git clean -f` / `-fd` / `--force`                       | Deletes untracked files — including new work you haven't committed yet. |
| `git branch -D <branch>`                                 | Force-deletes a branch even if unmerged. Use `-d` for safe delete.   |
| `git checkout .` / `git restore .` / `git checkout -- .` | Wholesale-discards uncommitted changes across the whole working tree. Use a targeted pathspec like `git restore -- src/foo.ts` instead. |

**Self-check before running any git command:** match the proposed command against this list. If it matches, stop and ask the developer to run it themselves. (This is the git instance of the universal floor in `rulebooks/base/rules/approval-for-irreversible.md`.)

**[enforced-when-installed]** — `hooks/protect-git.sh` hard-blocks every command in this list (and allows the targeted/safe variants) when the Phase-2 hooks are registered. When they aren't, the rule is **[behavioral]**: rely on the self-check above. See `references/threat-model.md`.

**Commit while on a protected branch** is also hard-blocked by `protect-git.sh` (section 7) when installed — but as a *workflow* guard, not data loss, so it has a scoped escape hatch the destructive blocks above do not: set `CODING_RULES_ALLOW_PROTECTED_COMMIT=1` inline directly before the commit (`CODING_RULES_ALLOW_PROTECTED_COMMIT=1 git commit …`), and **only when the user has explicitly authorized committing to that branch** — never to bypass the guard on your own. The override counts only as a direct prefix of `git commit`; an exported var or the token appearing elsewhere in the command does not. Carve-outs (the repo's first-ever commit, detached HEAD) keep it quiet otherwise; do branch changes — creating (`git switch -c`) **or** switching (`git switch <branch>` / `git checkout <branch>`) — as a **separate** command before committing, not a `&&` one-liner. A branch *switch* chained into a commit (`git switch main && git commit`) can't be reliably caught by the hook (the switch happens after the hook runs, and may fail), so this is enforced behaviorally, not mechanically.

---

## Scope Discipline

Stay on task. Agents tend to "fix while you're here" — refactoring adjacent code, updating unrelated imports, or improving docs that weren't part of the request. This creates larger diffs, unexpected changes, and risk of breaking unrelated functionality.

**Rules:**
- Only change what the task requires. If you notice an issue outside your scope, **log it** (in memory.log, a comment, or the issue tracker) but don't fix it unless asked.
- If scope is growing, pause and check with the developer before continuing.
- If refactoring is needed to complete your task, explain why and get approval for the expanded scope.

---

## Security Awareness

- **Never commit secrets** — API keys, tokens, passwords, certificates. If you find them in code, flag immediately. **[enforced-when-installed]** at commit time — `pre-commit-check.sh` hard-blocks staged secrets (betterleaks or gitleaks if present, else a built-in regex floor). **Install a real scanner.** The built-in floor is a fallback, not a scanner: it matches the two Stripe `sk_` prefixes, `AKIA…`, a PEM private-key header, and a quoted `password =` — modern token shapes (`sk-proj-…`, `ghp_…`, `hf_…`) pass straight through it. (Spelled by description, not literally: this file is committed, and writing a live-key prefix out in full makes the floor flag its own documentation — the same self-match `pre-commit-check.sh` avoids in its own source.) The hook says so on every commit when no scanner is on PATH; `brew install gitleaks` clears it.
- **Never print a live secret** — moved to the base rulebook: `rulebooks/base/rules/no-print-secret.md` (`no-print-secret`, floor). The **[enforced-partial]** `warn-env-read` hook reminds you on `.env` *reads* via the Read tool, but a Bash `cat .env` is not caught.
- **Check for exposed credentials** — scan changed files for patterns like `sk_live_`, `AKIA`, `-----BEGIN PRIVATE KEY-----`, hardcoded passwords
- **Use environment variables** for all secrets, and document the required vars in `DEVELOPER_TODO.md`
- **Review dependency additions** — check for known vulnerabilities, verify license compatibility, prefer well-maintained packages `[A06 · CWE-1104]`

### Configuration vs. Secrets Boundary

Non-secret configuration (default email destinations, default locales, feature toggles, retry budgets) lives in **app config** — typed config object, `config/`, `settings.toml`, or a clearly-named non-secret env var. Secrets live in **`.env`** (existing rule above). Keep non-secrets out of `.env` so the file stays a pure credential store — that is what makes the § Environment Files split below clean. Document any newly-required env var in the project's `.env.example` (the standard handoff surface), and in `DEVELOPER_TODO.md` when the user must obtain a value from somewhere. Triggers for *what* to externalize are in `validation.md` (hardcoded-value code smell).

### Environment Files

`protect-env` is narrower than "never touch a `.env`", because the two classes of env file carry opposite risks:

| Class | In git? | Commit scan can see it? | The real risk | Guard |
|---|---|---|---|---|
| `.env.example`, `.env.template`, `.env.sample` | yes | yes — as well as it sees any file | someone pastes a real key into a template | `pre-commit-check` (commit-time scan) |
| `.env`, `.env.local`, any other variant | no — gitignored | **never, by construction** | overwriting live credentials with no undo | `protect-env` (hard block) |

The distinction is **not** "templates are covered, so relaxing is free." It is that the two classes fail in different directions, and only one of them is beyond a commit-time check's reach.

For a template, the commit scan is **filename-agnostic** — it reads added lines in the staged diff, so a key pasted into `.env.example` is treated exactly as one in `config.ts`. That is genuine coverage, but it is **only as strong as the scanner installed**, and the § Security Awareness note above is the honest measure: with no `gitleaks`/`betterleaks` on PATH the built-in floor matches a handful of shapes and misses most modern tokens, and the static command-recognition gaps in `references/threat-model.md` apply on top. So the accurate claim is: *a committed template is covered by whatever your commit gate catches, same as every other committed file* — not *a template is safe*. Blocking template edits never changed that number; it only broke the workflow, since `.env.example` is how a repo tells a new developer which variables it needs.

A real `.env` is different in kind, and that difference does not depend on scanner quality. It is never staged, so no commit-time check of any strength ever sees it, and it is not in git, so an overwrite cannot be recovered. That is the base floor's `approval-for-irreversible` rule made concrete, which is why this one stays hard.

**What the hook allows:**

- Editing `.env.example` / `.env.template` / `.env.sample`, **when the path is a plain regular file** — matched case-insensitively on the basename suffix, so `.env.example.bak` is *not* a template and stays blocked.
- **Creating** an env file that does not exist yet — scaffolding a project from its `.env.example`. There is nothing there to overwrite. The moment the file exists, it is blocked again.

**What it blocks**, each for its own reason (the message says which):

| Case | Why |
|---|---|
| An **existing** env-family file that is not a template | Replacing it overwrites contents git may not hold |
| A **relative** path, templates included | The hook cannot know the agent's cwd, so every filesystem test below would run against the wrong directory. Fails closed |
| A **symlink** with an env-family name | `.env.example -> .env` is a template *name* pointing at the credential *file*; trusting the name hands over the inode. A dangling symlink is the same problem on the create path — the write follows it to the target |
| A **hard-linked** template | `ln .env .env.sample` gives the credential inode a second, allow-listed name. No path resolution can see that; link count can |
| A template that is **not a regular file** | A FIFO or device named `.env.example` has one link and is not a symlink, so it passed both checks above |
| A spelling the **filesystem folds** onto a differently-named entry | `-e` succeeds through the filesystem's own case folding, and APFS folds beyond ASCII — a real `.env.ſample` (U+017F) is reachable as `.env.sample`. Bash folds ASCII only and can never mirror the filesystem, so the stored name must match byte for byte |
| A payload the hook **cannot parse** (no `jq`, malformed JSON) that mentions `env` at all | A guard that cannot read its input must refuse, not shrug. It matches `env`, not `.env`, because an unparsed payload is still JSON-encoded and `"/tmp/\u002eenv"` carries no literal dot. This over-blocks while degraded; installing `jq` is the fix, and the message says so. **Residual:** an escape that also encodes the letters (`\u0065nv`) still evades — decoding JSON in bash is not reasonable |
| A file `stat` cannot see but the directory still lists | A macOS ACL denying `readattr` makes `-e` false for a file that plainly exists — the hook used to read that as "absent" and allow the overwrite. Existence is now `stat` **or** the directory entry, so an unstattable file counts as present |

The last two are why the carve-out is on *names* but the decision is on *objects*. An allow-list of filenames is only safe if a filename cannot be made to mean another file.

**Case matters, and the hook is case-insensitive on purpose.** macOS filesystems are case-insensitive by default, so `.ENV` and `.env` are one file. A case-sensitive test let an agent blocked on `.env` retry as `.ENV` and clobber the same inode.

**It blocks on existence, not on content.** An empty `.env` blocks too. That is deliberate — a zero-byte file is often one an agent is about to fill, and testing size would add a second thing to get wrong for no safety gain.

**There is no override token, deliberately.** `resources/references/hooks.md` rules out env-var disables for security-critical hooks — a variable drifts in from a shell rc, a CI config, or an `.envrc` that direnv wrote in the very directory holding the `.env`. The inline-prefix form that makes `CODING_RULES_ALLOW_PROTECTED_COMMIT` safe is Bash-only; `protect-env` fires on Edit/Write, which carries no command string to prefix. The documented escape is a deliberate `.claude/settings.json` edit.

When you need a value in a real `.env`, hand the user the variable names and let them paste the values. That keeps the agent useful without giving it the pen on the one file with no undo.

---

## Agent-Authored Artifacts as Untrusted Input

Moved to the base rulebook: `rulebooks/base/rules/untrusted-agent-artifacts.md` (`untrusted-agent-artifacts`, floor) — provenance scope, the shared-knowledge supply-chain warning, and what "untrusted" means in practice all live there.

---

## Documentation Updates

When your changes alter behavior, update documentation to match:

- **README** — if setup steps, commands, or usage changed
- **API docs** — if endpoints, parameters, or responses changed
- **Code comments** — if the "why" behind a design decision changed
- **DEVELOPER_TODO.md** — if new human actions are required

Stale documentation is worse than no documentation — it actively misleads. If you changed how something works, the docs must reflect it.
