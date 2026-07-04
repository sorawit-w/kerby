# Hooks — coding enforcers

The coding rulebook's tool-boundary enforcers. Hook mechanics — registration,
runtime toggles, strictness levels, the SessionStart state trio — live in the
engine doc: `<install-root>/resources/references/hooks.md`.

### PreToolUse → .env File Protection

**Script:** `hooks/protect-env.sh`
**Strictness:** Hard-block (exit 2)
**Matcher:** `Edit|Write` targeting `.env` files

Prevents the agent from editing `.env` files directly. This is a security guardrail — secrets should never be modified by an agent. If the agent needs environment variables set, it should document them in `DEVELOPER_TODO.md` instead.

---

### PreToolUse → .env Read Warning

**Script:** `hooks/warn-env-read.sh`
**Strictness:** Soft-warn (exit 0; injects the reminder via stdout JSON `hookSpecificOutput.additionalContext`) — disablable
**Matcher:** `Read` targeting `.env` files

The behavioral counterpart to `protect-env`. Reading a `.env` is legitimate (the agent often needs the variable *names* to wire things up), so this never blocks — it only reminds the agent not to print secret *values* into the conversation. Disablable via `CODING_RULES_HOOK_DISABLED=warn-env-read`.

**Coverage gap (by design, not a bug):** the Claude Code matcher fires on the `Read` tool only. An agent reading a `.env` via Bash (`cat .env`, `grep KEY .env`) is invisible to this hook — that path stays a [behavioral] rule (`guardrails.md`: "never print a live secret"). See `references/threat-model.md` for why the in-context boundary can't be hook-enforced. Self-tested by `hooks/warn-env-read.test.sh`.

---

### PreToolUse → High-Stakes Path Routing

**Script:** `hooks/route-high-stakes.sh`
**Strictness:** Soft-warn (exit 0; injects a reminder via stdout JSON `hookSpecificOutput.additionalContext`) — disablable
**Matcher:** `Edit|Write` targeting BOOTSTRAP §3 high-stakes paths

Makes BOOTSTRAP §3's high-stakes path override **[enforced-partial]** instead of pure [behavioral]. When the agent edits a path matching §3's globs (auth, schema migrations, payments/billing, infrastructure, CI/CD), it emits a one-line reminder that the change requires `workflows/feature.md` / `bugfix.md` + the §4 Plan Gate — **not** `quick-task.md`, even for a one-liner. It never blocks: routing is a *decision*, not a destructive-action veto. Disablable via `CODING_RULES_HOOK_DISABLED=route-high-stakes`.

**Single source of truth:** the matched globs are embedded in the script byte-identical to BOOTSTRAP §3, and `hooks/route-high-stakes.test.sh` asserts parity — it fails if §3 gains a glob the hook doesn't carry, so the two can't silently drift.

**Coverage gap (by design, not a bug):** §3's sixth category — *production-traffic-shaping values* (retry/timeout/rate-limit constants, feature-flag defaults, secrets-loading code) — is prose with no glob and cannot be path-matched; it stays [behavioral]. That named gap is what makes this rule [enforced-partial] rather than [enforced]. Matching is case-insensitive so filename patterns catch `Login.tsx` / `UserToken.ts`. **Delivery mechanism:** the reminder is emitted as stdout JSON (`hookSpecificOutput.additionalContext`), *not* stderr — on exit 0 a PreToolUse hook's stderr is not surfaced to the agent, only its JSON-on-stdout is. It carries no `permissionDecision`, so the edit proceeds through normal permissions (it reminds, never auto-approves). Self-tested by `hooks/route-high-stakes.test.sh`. *(Pattern absorbed concept-only from `paulDuvall/ai-development-patterns` (MIT) — Progressive Disclosure; see `NOTICE`.)*

---

### PreToolUse → Pre-Commit Check

**Script:** `hooks/pre-commit-check.sh`
**Strictness:** Soft-warn (exit 0; reminder via stdout JSON `hookSpecificOutput.additionalContext`) + Hard-block on secrets (exit 2 + stderr)
**Matcher:** `Bash` running `git commit`

Two checks before every commit:
1. **Secret scan (hard-block)** — Capability-gated on the binary: prefers `betterleaks`, then `gitleaks`, if either is on `PATH` (broader coverage, respects the scanner's repo-local allowlist), scanning the staged *added* lines via the version-stable `stdin` mode (`git diff --cached -U0 | <scanner> stdin --exit-code 7`). Falls back to a built-in regex (`sk_live_`, `AKIA`, private keys, hardcoded passwords) when no scanner is present or it errors. A *finding* (distinct exit code 7) blocks the commit; a *tool error* (any other nonzero — their default exit 1 means "leaks OR error") falls through to the regex rather than phantom-blocking. Cannot be disabled via env var. Self-tested by `hooks/pre-commit-check.test.sh`. *(betterleaks is the gitleaks author's feature-frozen-gitleaks successor; the `stdin` invocation is what survives gitleaks' 8.19 reorg that deprecated `protect`.)*
2. **Quality gate reminder (soft-warn)** — Injects a reminder to run lint/test on changed files via `additionalContext`. Does NOT hard-block — this avoids trapping the agent on pre-existing lint errors from other developers. Because a PreToolUse `additionalContext` surfaces *with* the tool result (next turn), this reminder arrives as the commit completes — it is a **post-commit safety net** (run the gates, amend if your changes broke them), not a pre-commit veto. The veto in this hook is the secret scan above (exit 2, pre-execution). Turning the reminder into a true checkpoint would mean `permissionDecision: ask`/`deny` — a deliberate commit-discipline change, intentionally not made here.

---

### Stop → Quality Gate Verification

**Type:** Prompt hook (LLM evaluation)
**Strictness:** Soft-verify

When the agent finishes responding, a prompt hook checks whether quality gates (build, lint, test) were run during the turn. If the agent made code changes but skipped quality gates, it's flagged. This is advisory — it doesn't prevent the agent from stopping, but surfaces the gap.

---
