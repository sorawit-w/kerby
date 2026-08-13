# CLAUDE.md — the `kerby` repo

`kerby` is the gate guardian for agentic coding: a loadable rule-corpus + opt-in
guardrail hooks that govern how an agent does coding work (clarity over cleverness,
safety over speed, never leave the repo broken — and *nothing unproven passes the
gate*). The skill itself lives at [`skills/kerby/`](skills/kerby/SKILL.md); the rules
it loads live in [`skills/kerby/rulebooks/swe/BOOTSTRAP.md`](skills/kerby/rulebooks/swe/BOOTSTRAP.md).

This file is the repo-root context doc. Its main job is to hold the **harness-engineering
vocabulary** that `SKILL.md` references — the named primitives behind how `kerby` is
built. `kerby` is the canonical, working implementation of these primitives; when the
vocabulary below cites one abstractly, the concrete machinery is somewhere under
`skills/kerby/resources/`.

---

## Harness vocabulary

Building a rule-corpus like `kerby` is **harness engineering** — designing everything
*around* an agent that determines whether it succeeds: context, scaffolding, feedback,
state, evaluation. Naming the primitives lets edits be deliberate instead of accidental.

| Primitive | What it means | Concrete artifact in `kerby` |
|---|---|---|
| **Context engineering** | Organize information so the agent can reason over it — repo-local, versioned, not in chat threads. | `CONTEXT.md` (project glossary) + `BOOTSTRAP.md` (operating rules) + vendor agent-context files kept in sync — see `skills/kerby/resources/references/multi-tool.md`. |
| **Progressive disclosure** | Load detail on demand instead of front-loading everything. | `BOOTSTRAP.md` is the index; `rulebooks/swe/references/*.md` carry the long-tail, loaded only when cited. |
| **Observable feedback loops** | Prefer machine-checkable signal over aspirational prose. | `rulebooks/base/hooks/pre-commit-check.sh`, `protect-env.sh`, `warn-env-read.sh`, `protect-git.sh` + gates in `references/quality-gates.md` and `references/validation.md`. |
| **State preservation** | Carry useful context across session boundaries. | `.kerby/memory.log` (append-only history) + `.kerby/STATUS.md` (current state) + `.kerby/knowledge/` (curated wiki) + `.kerby/BLOCKERS.md`, bootstrapped by `session-start-context.sh` + `knowledge-bootstrap.sh`. |
| **Eval discipline** | Decide what "working" means before shipping. | `references/quality-gates.md` + the verification-before-completion pattern; the pre-commit hook enforces gates mechanically rather than relying on agent memory. |

**External reading:** Anthropic ([effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents), [harness design for long-running apps](https://www.anthropic.com/engineering/harness-design-long-running-apps)); OpenAI ([harness engineering](https://openai.com/index/harness-engineering/)); the [`AGENTS.md`](https://agents.md/) convention.

**How to use this vocabulary.** When you propose a new rule, ask: *which primitive is
this serving?* If you can't answer, the change is probably speculative. When you debug a
rule that "just isn't working," ask: *is the environment underspecified (context,
scaffolding, feedback) or is the prompt wrong?* Most agent failures are environment
failures wearing a prompt-failure mask.

### Control loop (loop engineering)

Prompt engineering optimizes a single forward pass. **Loop engineering** optimizes the
trajectory across many passes: the agent acts, observes a result (test output, build
error, screenshot), and that observation re-enters context and shapes the next action.
It is the runtime-control-flow half of harness engineering. `kerby` implements the loop
primitives; this table is the map — each row points to where the primitive is enforced.

| Primitive | One-line meaning | Lives in |
|---|---|---|
| Inner / outer check split | cheap check while coding, full gate at the boundary | `rulebooks/swe/workflows/feature.md` (iteration-check tiers vs commit check) |
| Termination condition | what must be true to exit the loop | `rulebooks/swe/references/validation.md` (Iron Law: no claim without fresh evidence) |
| Retry budget / circuit breaker | bounded retries per failure type, then escalate | `rulebooks/swe/references/error-handling.md` (build 5 / test 3 / lint 5 → BLOCKED) |
| Bounded search | cap the hypothesis count so the loop can't flail | `rulebooks/swe/references/debugging.md` (max 3 hypotheses) |
| State across iterations | what carries forward so the loop has no amnesia | `.kerby/memory.log`, `.kerby/STATUS.md`, checkpoint-before-context-fills |
| Iteration cost is the speed limit | a faster loop buys more hypotheses | `rulebooks/swe/references/debugging.md` (assess the feedback loop first) |
| Parallel loops (fan-out) | independent iterations run concurrently | `rulebooks/swe/references/sub-agent-delegation.md` (vertical slices, blind lenses) |

These are the runtime expression of the harness primitives above: *State across
iterations* is *State preservation* applied mid-task; the two check rows are *Observable
feedback loops* applied per-iteration. The rest (termination, retry budget, bounded
search, fan-out) are loop-specific.

**Bounded by design.** kerby's termination condition is deliberately *bounded*: the
loop exits on fresh verification evidence (the Iron Law) **or** on an exhausted
retry budget that escalates to a human (`BLOCKED`). It does **not** iterate
unboundedly toward "perfect." That bound is a choice, not an omission — *never leave
the repo broken* outranks autonomous self-correction, so a stuck loop hands off
rather than flails. This is the intended departure from naive "verify-until-done"
framings: a self-verification loop with no circuit breaker burns its budget
re-deriving the same wrong fix. The verification gate also leans behavioral by
design — the methodology travels across toolchains where a hardcoded check would not
(`skills/kerby/CLAUDE.md` § Authoring style). The one mechanical floor under it is
`rulebooks/base/hooks/pre-commit-check.sh`: a pure, non-disablable secret scan. Riding
alongside it (only when `swe` is selected) is `rulebooks/swe/hooks/hollow-test-check.sh`,
a soft heuristic that statically flags the green-but-empty fakes
(`rulebooks/swe/references/validation.md` § What Counts as Evidence).

---

## Editing the rules

The skill-internal authoring guide lives at
[`skills/kerby/CLAUDE.md`](skills/kerby/CLAUDE.md) — read it before changing rule text
(every rule carries a recurring input-token cost; each should trace to a real past
failure). Run `python3 scripts/check-skill-compat.py` after any frontmatter or
version-bearing change, and `bash skills/kerby/rulebooks/swe/scripts/check-plan-gate-parity.sh` after any
change to the plan_threshold default or the grade-≥7 approval point (it fails if
those constants drift across the files that restate them — BOOTSTRAP, the
workflows, working-patterns, the schema, the template; the checked set is listed
in the script). If you add a new restatement, add the file to that set.

Also run `bash skills/kerby/rulebooks/swe/scripts/check-commit-gate-parity.sh` after any
change to the commit-time gate-tier rule. Unlike the plan-gate guard it is a *negative*
check: `references/quality-gates.md` § At Commit Time is the sole authority, and the script
fails if any other rulebook file restates the rule as an absolute ("always run full
gates…"). Defer to the canonical section instead of repeating it. Both guards exist because
cross-file restatement drift is the failure mode the corpus is most prone to and the one
the adherence harness is blind to — the commit-gate rule had drifted into **four** files
before the guard was written.

Engine edits (`skills/kerby/SKILL.md`, `resources/`, repo-root `scripts/`) are
additionally bound by the **engine-independence zoning rule** in
[`docs/rulebook-contract.md`](docs/rulebook-contract.md) § Engine independence:
builtin rulebook names appear in engine surfaces only as worked examples or
bundle contents, never as something behavior keys on.

The product voice — how kerby *talks* in the README, verdict output, and CHANGELOG — is
specified in [`VOICE.md`](VOICE.md). Read it before editing any persona-bearing copy; the
rules and command references stay literal regardless (see its Zoning table).

---

## PR Workflow

Defined here in full — the gate must never depend on unversioned, user-local config
(a maintainer's personal `~/.claude/CLAUDE.md` may mirror this as a cross-repo default,
but this section is authoritative for kerby).

1. Branch, commit.
2. Open the PR. **Every merge-gating check is defined in
   [`skills/kerby/CLAUDE.md`](skills/kerby/CLAUDE.md) § Gate tiers** — run those against the
   exact tree you push, and report which ones ran in the PR body.
3. `gh pr merge --squash --delete-branch`.

**No Codex review — local or on the PR — is part of this gate.** kerby is mostly rule prose
rather than application code, and neither the headless local loop nor the GitHub round-trip
returned enough at that ratio to keep. The `codex-review` builtin still ships for repos that
want either; this repo does not use it, and nothing here depends on a machine-local marker,
so the workflow no longer varies by which machine you are sitting at.

**What that costs, stated plainly:** the independent-model review was the only check that
removed *author framing* — it caught internal contradictions the adherence harness is
structurally blind to (see `skills/kerby/CLAUDE.md` § Gate tiers for the incident). That bias
is now unmitigated. The compensating control is mechanical, not judgmental: when a rule ends
up stated in more than one file, add a parity guard under
`skills/kerby/rulebooks/swe/scripts/` so the drift becomes a hard failure instead of
something a reviewer has to notice.

**Merge conventions:** squash is the default — one commit per PR on `main`; don't use
`--merge` / `--rebase` without being asked. Always pass `--delete-branch` (this repo's
`deleteBranchOnMerge` is off). Merging via this workflow **overrides kerby's own "leave
for human review" guardrail** for this repo — the owner has opted in.

At session start, invoke the `kerby` skill (args: load) to load kerby guardrails into context.
