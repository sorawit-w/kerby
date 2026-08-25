# Multi-Tool Support

kerby is a playbook. The hook scripts happen to target Claude Code, but the *rules themselves* — the prime directive, hard rules, workflows, and references — are vendor-independent and should work wherever an AI coding agent reads a project context file.

This document defines how to expose the playbook to multiple agent runtimes without duplicating content.

---

## Vendor-Independent Default

The canonical context file is **`AI-CONTEXT.md`** at the project root.

- Any agent that doesn't know about vendor-specific names can be pointed at `AI-CONTEXT.md`
- It is a symlink (or a thin pointer file) to `kerby/BOOTSTRAP.md` or your project's `CLAUDE.md`
- Prefer a symlink — keeps one source of truth

```bash
# At project root
ln -s kerby/BOOTSTRAP.md AI-CONTEXT.md
```

If your platform doesn't handle symlinks cleanly (Windows, some CI), use a one-line pointer file:

```markdown
# AI Context

See `kerby/BOOTSTRAP.md` for the operating rules.
```

---

## Vendor-Specific Files

When a runtime expects a specific filename, add a symlink. The rule: **only two supported vendors** — Claude Code and Codex. Other tools fall back to `AI-CONTEXT.md`.

| Runtime | Expected file | How to wire |
|---------|---------------|-------------|
| Claude Code | `CLAUDE.md` | `ln -s kerby/BOOTSTRAP.md CLAUDE.md` |
| Codex (OpenAI) | `AGENTS.md` | `ln -s kerby/BOOTSTRAP.md AGENTS.md` |
| Other agents | `AI-CONTEXT.md` | Same symlink — the fallback |

**Why only these two:** the maintenance cost of vendor-specific tweaks is non-zero. Supporting N vendors means N matrices to keep synchronized and eval. Claude Code + Codex is the smallest set that covers the current team's daily use.

Cursor, OpenCode, and others are not explicitly supported, but will still read `AI-CONTEXT.md` or `CLAUDE.md` if configured to do so. The rules apply; the delivery is best-effort.

---

## Hook Behavior Across Runtimes

Hooks are shell scripts triggered by Claude Code's lifecycle events (`SessionStart`, `PreToolUse`, etc.). Automatic invocation is not **Claude Code only** in the sense of being attempted: Copilot CLI also reads `.claude/settings.json` and runs what it finds there, in whatever shell the CLI itself is running. On Windows that is PowerShell, which cannot execute a `.sh`. See § GitHub Copilot.

Consequences for other runtimes:

- **Codex** does not invoke `hooks/*.sh` automatically. The rules in `BOOTSTRAP.md` and `references/*.md` still apply — the agent is expected to follow them manually.
- **Cursor** likewise. `.cursorrules` can be a symlink to `BOOTSTRAP.md` if you want Cursor's rule-injection to see the playbook.
- The text rules are the source of truth. Hooks are *enforcement scaffolding*, not the rules themselves.

If you need a hook-equivalent in Codex, write it as a shell command in Codex's configuration and have it invoke the same script in `kerby/hooks/`. The scripts are plain bash and don't depend on Claude Code internals beyond the JSON input format (which you can mock for Codex via a thin wrapper).

---

## Sub-Agent Model Pinning (Claude Code)

The tier-upgrade rule in `sub-agent-delegation.md` § Capability Tier needs a
concrete way to pin a sub-agent's model. Claude Code exposes three, pick by how
the sub-agent is spawned:

| Spawn shape | Mechanism |
|---|---|
| Persistent, reusable sub-agent | `model:` field in the sub-agent's frontmatter (`.claude/agents/*.md`) |
| One-shot delegation | the Agent/Task tool's `model` parameter |
| Session-wide default for all sub-agents | `CLAUDE_CODE_SUBAGENT_MODEL` env var |

**Precedence — the env var wins.** Claude Code resolves these in a fixed
order: env var > per-invocation parameter > frontmatter > main conversation's
model. If a team sets `CLAUDE_CODE_SUBAGENT_MODEL` to a fixed alias (e.g.
`sonnet`) as a blanket default, this rule's per-invocation/frontmatter
attempts to upgrade a task to `opus` are silently ignored until the env var is
unset or set to `inherit` — the tier-upgrade rule then runs at the wrong tier
with no error. If your team sets this env var, unset it or set it to
`inherit` before delegating an upgraded task.

**Tier → alias binding (quarantined here; the only place it lives):**

    low      → haiku
    standard → sonnet
    high     → opus

Use the **aliases**, never dated strings. Claude Code's `opus` / `sonnet` /
`haiku` aliases auto-resolve to the current flagship, so this binding never rots
and needs no edit when a new version ships. (As of 2026-06-30: `opus` = Opus 4.8,
`sonnet` = Sonnet 5, `haiku` = Haiku 4.5 — informational only; do not pin these.)

Blocked-model safety: a blocked sub-agent model override falls back to the
inherited/default model rather than failing the request. That's fine for an
optional choice, but for the mandatory upgrade triggers above, silent
fallback means the upgrade gate can appear satisfied while the sub-agent
actually runs at the lower, un-upgraded tier — no error, no signal. For any
mandatory upgrade trigger — approval-gated, blast-radius, or divergence-retry
— verify the resolved model rather than assuming the requested alias took
effect, and escalate instead of proceeding silently if it was blocked.

**Codex:** custom agent files support their own `model` and
`model_reasoning_effort` fields (inherited from the parent session when
omitted) — use those to pin a Codex sub-agent's tier directly, the same
concept as Claude Code's frontmatter `model:` field. No env-var-level default
equivalent to `CLAUDE_CODE_SUBAGENT_MODEL` is documented; set per-agent-file
`model` explicitly on any task that needs an upgrade.

**Orthogonal alternative (interactive sessions):** `opusplan` gives Opus-grade
planning that auto-drops to Sonnet for execution — zero config, but it keys off
Claude Code's *native* plan mode, not kerby's `plan_threshold`. Use it when you
drive interactively; use sub-agent pinning when kerby delegates. They compose.

---

## GitHub Copilot — advisory-only

Some teams are *required* to use Copilot (org mandate, no opt-out). Copilot is a harder case than Codex or Cursor on two axes:

- **Hooks are attempted, not ignored — and on Windows they do not run.** Codex and Cursor simply never invoke `hooks/*.sh`. Copilot differs: it reads `.claude/settings.json` and `.claude/settings.local.json` and does try to run what it finds, in the same shell the CLI is running in. **On Windows that shell is PowerShell**, which cannot execute a `.sh`, so the entire mechanical-enforcement half of kerby (`pre-commit-check`, `protect-env`, `protect-git`) does not fire there. [github/copilot-cli#4001](https://github.com/github/copilot-cli/issues/4001) (open as of 2026-08-25) documents that execution model: bash-syntax commands fail with PowerShell parser errors, `$CLAUDE_PROJECT_DIR` is unset, and hooks run from `/` rather than the project root. A registered `.sh` path is the same mismatch from another angle — PowerShell falls through to the file association instead of running the script. Maintainers of this repo have observed that as an "open with" dialog, once per invocation; that specific symptom is a local observation, not something the issue records.

  **Scope this honestly in both directions.** The shell mismatch is Windows-specific: on macOS and Linux the CLI's shell runs a `.sh` normally, so kerby's hooks are not known to be broken there. But #4001's other two findings — unset `$CLAUDE_PROJECT_DIR`, and hooks running from `/` — are not described as Windows-only, so do not read "not Windows" as "verified working." Nothing here establishes that kerby's hooks enforce correctly under Copilot on any platform; it establishes that on Windows they demonstrably do not.

  **What to do about it: turn the hooks off on Copilot's side, not kerby's.** Set `disableAllHooks: true` in **`.github/copilot/settings.local.json`** — a Copilot-only file, so Claude Code on the same machine keeps enforcing. Two things to know before you do. It is **Copilot CLI only**, not the cloud agent. And its reach is the repository, not the file: every hook from every source — repository files, user files, plugins, inline blocks — is skipped for sessions in that repo, with only policy hooks exempt. It silences more than kerby, deliberately, so weigh that rather than discovering it later.

  Do **not** put the flag in `.claude/settings.json` or `.claude/settings.local.json`. Copilot honors it there, but so does Claude Code — which would switch off the hooks that were working. For the same reason, moving kerby's registrations between those two files does not avoid Copilot: it reads both. And prefer the flag to `kerby uninstall`, which removes kerby's entries outright and takes that enforcement with them.

  **kerby does not change what it writes.** A `bash -c '<script>'` form does parse under both shells, and #4001 suggests it — but shipping it would mean depending on `bash` resolving from `PATH`, and on Windows that does not reliably reach Git Bash: Git for Windows' default `PATH` selection omits its `bin` directory. What it reaches instead varies by machine — on a WSL install, plausibly `C:\Windows\System32\bash.exe`, whose bash runs in the distro's filesystem view rather than the one the agent is editing. Unreliable, not impossible; but a guardrail that binds to whichever bash happens to be first is not a guardrail. Quoting an absolute path avoids that, but then PowerShell needs its `&` call operator, which Git Bash rejects — so the shape that fixes Copilot breaks Claude Code. Such a wrapper would also have to restore the project cwd and pass stdin through, reimplementing on kerby's side a contract the harness is expected to provide. The fix belongs where the bug is.
- **Weaker rule adherence.** In practice Copilot attends to less of a long context than Claude Code or Codex. Loading the full corpus *plus* extra contract text makes adherence worse, not better — on a weak harness, rule-count dilutes attention.

**Consequence — set expectations honestly: on Copilot, treat kerby as advisory, not enforced.** On Windows that is established; elsewhere it is simply unverified, and an unverified gate is not one to trust output against. The human reviewer is the substitute for the hooks that are not enforcing.

**Delivery.** Copilot reads `.github/copilot-instructions.md` and won't reliably chase reference files. Don't point it at the full `BOOTSTRAP.md` and expect compliance — give it a short, front-loaded kernel in that file. Recommended minimum:

```markdown
## Before writing code — state this (kerby's hooks do not enforce on Copilot; you are the gate)

- **Workflow:** feature / fix / refactor
- **Done means:** the one check that proves this works — a test name, a command, or "open X and see Y"
- **Not checked:** what I am NOT verifying this pass

No hook will catch a skipped check here. A human must read this block and the
evidence before the change is trusted. If the evidence can't be produced, the
change is unproven — say so; don't claim done.
```

This is kerby's Iron Law ("no completion claims without fresh evidence") compressed to what a weak, unenforced harness can hold. It deliberately drops the longer "operating-contract acknowledgement" pattern, which fails twice on Copilot: a runtime can't "acknowledge" anything, and adding contract text to a harness that already skips rules just spends tokens it won't read. Front-load the kernel instead, and rely on the human as the gate.

---

## Keeping Multiple Context Files in Sync

The symlink approach makes this automatic. If you chose pointer files instead (e.g., for Windows), add a check to your CI or a pre-commit hook that compares SHAs:

```bash
# In a repo hook or CI step
canonical=$(sha256sum kerby/BOOTSTRAP.md | cut -d' ' -f1)
for f in CLAUDE.md AGENTS.md AI-CONTEXT.md; do
  [[ -f "$f" ]] || continue
  if ! grep -q "$canonical" "$f" 2>/dev/null; then
    echo "Drift: $f does not reference the canonical BOOTSTRAP.md SHA"
  fi
done
```

This is advisory. The symlink path avoids it entirely.

---

## Why This Shape

An earlier absorb-vs-switch review considered pulling in a larger framework (`everything-claude-code`) with full cross-tool adapter infrastructure. The decision was to borrow the *idea* of cross-tool parity — not the implementation — because:

- A symlink convention is auditable in minutes; an adapter layer is not
- The playbook's value is its rules, not its delivery mechanism
- Two supported vendors is the smallest set that covers the team; more than two demands a real eval matrix

Cross-tool behavior is a candidate eval surface for `skill-evaluator`: does the same rule produce the same agent behavior under Claude Code vs Codex? If not, that's a signal the rule is over-specified for one runtime.
