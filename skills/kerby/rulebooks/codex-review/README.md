# codex-review — opt-in Codex workflows for kerby

Wires the Codex CLI (an independent model line) into three workflows, under one
stance: **Codex advises, Claude decides.**

| Workflow | Prose | Mechanics |
|---|---|---|
| PR gate — review before `gh pr create`; P0/P1 block; 3-round cap; PASS/DENIED/HELD | `references/pr-workflow.md` | `hooks/codex-pr-gate.sh` (PreToolUse/Bash) + `scripts/codex-mark.sh` (sole marker writer) |
| Plan review — adversarial pass on complex plans, dissent disclosed | `references/plan-review.md` | none (behavioral, `warn`) |
| Rescue delegation — independent diagnosis before human escalation | `references/delegation.md` | none (behavioral, `info`) |

The root body (`references/stance.md`) is a thin eager index: stance, on-disk
preflight, when-to-read pointers. The heavy references load on demand.

## Opt-in and install

`codex-review` declares no `[detect]` markers — it never auto-selects. Opt a repo
in explicitly:

```
kerby load +codex-review     # add to the selection (pin persists)
kerby install                # register the gate hook (Phase 2)
```

Until `kerby install` binds the hook, `pr-create-gate` is declared `hard` but
effectively behavioral — `kerby status` shows the degrade. `kerby pr-check`
reports preflight, marker/rounds/audit state, hook binding, and duplicate rules.

**Duplicate rules:** if the global or repo CLAUDE.md still carries the old codex
sections, the stance's adoption check (and `pr-check`) surfaces a
remove/proceed/stop menu. While duplicates coexist there is no mechanical winner —
identical copies waste tokens; drifted copies are ambiguous (CLAUDE.md nominally
outranks loaded prose). Migration is move-not-copy: delete the old copy.

**Per-check opt-out (contract 2): none.** User config remaps severities at the
gate level only (`block_on`/`hold_on`) — it cannot disable one check. A repo that
wants the PR gate but not plan review relies on plan review's complexity
self-gating (~zero cost on simple plans). `hold_on = []` would demote ALL
warn-severity checks — blunt; not recommended.

## State files (per-clone, in `$GIT_DIR`, never committed)

| File | Written by | Meaning |
|---|---|---|
| `codex-reviewed` | `scripts/codex-mark.sh` ONLY | marker: the reviewed HEAD sha |
| `codex-review.log` | the agent (tee of the review output) | evidence codex-mark verifies |
| `codex-review-rounds` | `scripts/codex-mark.sh` | branch + round counter (cap 3) |
| `codex-review-audit.log` | `scripts/codex-mark.sh` | append-only PASS history |

## Bypass

`CODEX_GATE_BYPASS=1` **directly prefixing** the gh invocation, user-authorized
only (manifest `override = "authorized-scoped"`). The prefix form is the only
honored one: an embedded token (PR-body text) authorizes nothing, and one
authorized invocation never authorizes a second one in the same command. The one
sanctioned marker-less use is the step-4 fallback (GitHub-side review) when local
Codex is genuinely missing.

## Known ceilings (deliberate)

- **String-match gate, not a shell parser.** Whitespace-tolerant regex catches
  `gh  pr create` variants, but a line-continuation split evades it, and a
  `gh pr create`-shaped string inside quoted prose over-blocks (safe direction:
  rerun standalone or bypass). ` -C ` in quoted title/body text can likewise
  false-block.
- **codex-mark trusts the teed log.** Forging a log is deliberate deception, not
  drift; `$GIT_DIR/codex-review-audit.log` keeps history visible.
- **jq required for the gate hook.** Missing jq degrades to an announced ALLOW
  (stderr) — install jq to restore enforcement.
- **Plan review has no mechanical backstop.** The eager stance's trigger line is
  the only prompt; if rules seem to stop applying mid-session (compaction), run
  `kerby reload`.
- **`accepts = ["git_change"]`** scopes the subject model to the mechanical gate;
  the plan-review/delegation prose is behavioral and not subject-scoped.

## Provenance

Ported 2026-07-07 from the maintainer's global CLAUDE.md (v3) and
`~/.claude/hooks/{codex-pr-gate.sh,codex-mark.sh}` — the complete port: nothing
codex-coupled remains global after migration. Hook hardened over the global
original: whitespace-tolerant detection, per-invocation strip-then-residual
bypass, explicit no-jq degrade. codex-mark hardened: all four `CODEX_VERDICT`
counts required (fail-closed on a partial line).
