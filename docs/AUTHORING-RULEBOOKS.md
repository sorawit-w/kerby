# Authoring a kerby rulebook

kerby's engine is domain-blind: it loads, weighs, and enforces whatever a
manifest declares. A rulebook is how you tell it what your domain's rules
are. This guide is everything an external author needs; the normative schema
lives in [`rulebook-contract.md`](rulebook-contract.md), and the shipped
[`base`](../skills/kerby/rulebooks/base/rulebook.toml) and
[`code`](../skills/kerby/rulebooks/code/rulebook.toml) rulebooks
are the worked examples.

kerby will read your manifest, validate it, show the user exactly what your
rulebook wants to put in their session, and refuse anything it can't verify.
That is not an obstacle course; it is the reason anyone will trust a
rulebook they didn't write.

## When a rulebook makes sense — and when it doesn't

Write a rulebook when all three hold:

1. **The discipline repeats.** The same rules govern every session in the domain —
   not a one-off check you could just ask for.
2. **The failure is irreversible or expensive.** Something gets sent, published,
   deployed, deleted, or promised — and un-doing it costs more than gating it.
3. **The gate is verifiable.** An agent can check evidence mechanically or
   near-mechanically: a register entry exists, a test passed, a citation resolves,
   a matrix approves the number. "Feels right" is not a gate.

Sketches that pass the test (none exist yet — they're folders you could write):

| Domain | The repeated, irreversible, verifiable gate |
|---|---|
| Sales | outbound quotes checked against the approved-discount matrix before sending |
| Support | refund promises require a policy citation; replies scanned for pasted PII |
| Ops | runbook steps refuse to execute without a named, tested rollback step |
| Editorial | pieces don't publish with unverified quotes or unsourced claims |
| Compliance | public claims must match an entry in the approved-claims register |

**Skip the rulebook** when a linter or CI job already enforces the thing (wire that
in directly — don't wrap it), when the "rule" is a style preference with no failure
mode (that's a doc, not a gate), or when the call is pure human judgment with no
checkable evidence — a rulebook can *route* that decision to a human
(`severity = "block"` on a prose rule that demands approval), but it cannot replace
the human.

## Where your rulebook keeps project state

**Default: write project state under `.kerby/`** in the consuming repo — it is
kerby's project-state dir (the engine already keeps `rulebooks.lock` and external
clones there, and the `code` rulebook keeps `memory.log`, `STATUS.md`, `knowledge/`,
`audits/` there). One dir to gitignore-or-commit deliberately, one dir the user
audits, one dir that never collides with their sources. Never write under
`.kerby/rulebooks/` — that subtree is the engine's external-rulebook
materialization area and the uninstall sweep treats everything in it as removable.

**Opt-out:** if your domain has an entrenched location (say, a docs pipeline that
must emit into `content/`), your rulebook may write there instead — but say so in
your rulebook's README and in the relevant rule bodies, so the user knows which
paths your rulebook touches before they approve it at the trust prompt.

## Folder structure

One folder, one fixed filename at its root. Everything else is yours to
arrange — the manifest declares it by relative path:

```
my-rulebook/
├── rulebook.toml        # the only fixed name — the manifest
├── README.md            # what this rulebook is for, its checks + commands
├── rules/               # prose bodies (markdown)
│   └── cite-sources.md
├── commands/            # bodies of user-invocable commands, if you provide any
│   └── review.md
└── hooks/               # enforcer scripts, if you ship any
    └── check-citations.sh
```

Every rulebook is **path-confined** (contract 2 — builtins too): every declared
path must resolve inside the folder. No `..`, no absolute paths, no symlinks
that point out (E04). If a file matters, it lives in the folder. That is what
makes a rulebook **plug-and-play**: copy the folder, and the receiving kerby
has everything — it will still ask its own user for approval before loading.

## The manifest, walked through

```toml
id = "prose-review"          # unique id; how users load you: kerby load ./my-rulebook
version = "1.0.0"            # your semver — bump it when rules change; the hash pin will notice anyway
contract = 2                 # the manifest contract this targets (E03)
accepts = ["document"]       # subject types you can judge; "*" = anything

[gate]                       # how severities become verdicts
block_on = ["block"]         # -> DENIED
hold_on  = ["warn"]          # -> HELD

[[check]]
id = "cite-sources"
kind = "prose"
body = "rules/cite-sources.md"
enforcement = "behavioral"
severity = "block"
token_cost = "low"

[[command]]                  # optional: a flow users invoke as `kerby [your-id] review`
name = "review"              # slug; must not collide with engine commands or builtin ids (E13)
body = "commands/review.md"  # read in full at invocation — write it as instructions to the agent
description = "Run the review flow."   # shown in listings + the trust prompt (E14)
```

Add `description = "one line"` at the top level too — `kerby rulebooks list`
shows it. If you ship a `hard`/`partial` enforcer, also declare its trigger so
`install` can register it: `event = "PreToolUse"`, `matcher = "Bash"` (an
enforcer without an `event` cannot be auto-registered; the validator warns).

Validate while you work (advisory; the load flow re-runs the same logic
authoritatively):

```
python3 <install-root>/resources/scripts/validate-rulebook.py ./my-rulebook
```

### Choosing `kind`

| kind | You ship | Declared via | Example |
|---|---|---|---|
| `prose` | markdown that becomes rules in the agent's context | `body` | a review checklist, a style floor |
| `data` | a ruleset a built-in runner executes | `runner` (+ optional `config`) | a gitleaks config, a semgrep pack |
| `code` | an executable check | `entry` or `enforcer` | a hook script that blocks an action |

Most rulebooks are mostly prose — that's the honest slot the old
declarative/executable split never had (D2).

### Choosing `enforcement` — declare what's true, not what sounds strong

- `hard` — a registered enforcer **blocks** the action at the tool boundary.
- `partial` — an enforcer covers some paths; name the hole in `gap` (E09
  warns if you don't). The gap surfaces in `status`; an honest gap beats an
  implied guarantee.
- `behavioral` — no tool boundary can reach it; the agent applies it by
  judgment. Prose is always behavioral — a hook cannot see chat output.

Enforcement **degrades observably**: declare `hard` all you like — until the
user registers your enforcer (`install` is the executable trust opt-in),
the effective level is `behavioral`, and `kerby status` shows
`degraded — run install to bind`. You do not get to look enforced without
being enforced.

### Choosing `severity` and `floor`

- `severity` maps through `[gate]`: `block` → DENIED, `warn` → HELD, `info`
  → advisory.
- `floor = true` marks a check nothing may loosen — not user config, not an
  extending rulebook (E05/E06). Floors belong in `base`; at contract v2
  declaring your own floors outside base is legal but pointless, since only
  base is implicitly composed into everyone else.
- Non-floor checks may declare an `override` policy naming a scoped,
  user-authorized escape hatch (the code rulebook's
  `protected-branch-commit` → `CODING_RULES_ALLOW_PROTECTED_COMMIT=1` is the
  canonical shape).

### `needs` and subject types

Executable checks declare the **views** they need (`staged_content`,
`branch`, `added_lines`, … — full vocabulary in the contract). The engine
adapts subjects into views so your runner doesn't re-parse the world. Two
rules (E10): every view name must exist, and if your `accepts` is concrete,
at least one accepted subject must actually provide what you need. A check
whose needs the current subject can't satisfy is *skipped and reported* —
visible, never silent.

### Extending

`base` merges first whether you list it or not; you cannot subtract or
soften its checks (E05, E06). To deliberately replace another pack's
non-floor check, redeclare its id with `override_of = "<id>"` — an
undeclared collision is an error, not a merge (E07).

### `[detect]` — reserved

You may declare workspace fingerprints, but at contract v2 the engine never
matches on them, and for non-builtin rulebooks it never will (E12 warns):
auto-selection is builtin-only, because untrusted workspace content must
never steer which gate governs. Users load your rulebook by name or path,
on purpose. That is the feature.

## The trust model, from your side of the gate

For an LLM-bound engine, prose is instructions. So kerby treats your
rulebook the way it treats any external input:

1. **First load** (or any content change): the validator runs, then the user
   sees a trust prompt — your id/version/origin, every check with its kind,
   and any lint warnings. They approve or decline.
2. **Approval pins a hash** over the manifest *and every declared file* — in
   two places: the project `.kerby/rulebooks.lock` (for selection + drift detection)
   and a **per-machine** `~/.claude/kerby/approved-rulebooks.json` (the record
   that *this user* approved *this content*). Later loads are silent only while
   the hash matches **and** it's in that per-machine store. A lockfile
   you ship inside your rulebook cannot pre-approve it for someone who clones
   it — they still get the prompt on first load. (Don't commit a
   lockfile expecting it to skip the prompt; it won't, by design.)
3. **Any edit re-opens the gate.** One changed character → re-validation and
   a fresh prompt. Version fields are courtesy; the hash is the truth.
4. Your prose enters context framed as rules-not-instructions (`DATA>`
   provenance). Text like "ignore previous instructions" gets flagged by the
   injection lint (E11) and shown to the user in the prompt. Write rules,
   not payloads.

## Creating a rulebook interactively — `kerby rulebooks create`

You don't have to hand-write any of this. `kerby rulebooks create` runs the
authoring interview and builds the folder with you:

1. **Interview** — domain, purpose, `id` (slug-checked), one-line
   `description`, subject types.
2. **Checks, one at a time** — kind, enforcement (with an honest `gap` for
   `partial`), severity, `token_cost`; prose bodies are drafted *with* you.
3. **Commands** (optional) — name (E13-checked live), body, description.
4. **Continuous validation** — the validator runs after every addition;
   E-codes surface fix-forward; the E11 injection lint runs on each prose
   body and shows hits.
5. **Emit** — `rulebook.toml`, `README.md`, `rules/` (+ `hooks/`,
   `commands/` as declared).
6. **Test load** — through the normal trust prompt. Creating a rulebook is
   not pre-approval; your own gate still gates you.

## Sharing your rulebook

A rulebook folder is the distribution unit — self-containment is what makes it
portable:

- **Hand someone the folder** (or commit it inside a project): they run
  `kerby load ./path-to-it`, review the trust prompt, approve. Done.
- **Publish it as a git repo whose root is the rulebook** (manifest at the
  repo root). Anyone can then run `kerby load your-name/your-rulebook` (GitHub
  shorthand) or the full git URL — kerby shallow-clones it to
  `.kerby/rulebooks/<id>/`, validates, and shows the trust prompt with a
  `Source:` line. Updates are never silent: users re-run `load <source>` to
  fetch a new version, and any change re-opens the approval gate.
- You cannot pre-approve your rulebook for anyone — not with a shipped
  lockfile, not with anything. Each user's approval lives on their machine.
  Design for the prompt: a clear `description`, honest `gap`s, and clean E11
  lint results are what make a stranger click yes.

## Error catalog — what the validator will tell you

Each code is the mechanical face of an authoring rule above. Messages are
literal and name the fix.

| Code | It fires when | The authoring rule behind it |
|---|---|---|
| E01 | `rulebook.toml` is missing or not valid TOML | one fixed filename, parseable manifest (Folder structure) |
| E02 | a required field is missing or mistyped (`id`, `version`, `contract`, `accepts`; per check `id`, `kind`, `enforcement`, `severity`) | the manifest walkthrough |
| E03 | `contract` isn't supported by this engine | declare the contract you actually target |
| E04 | a declared path is missing, unreadable, or escapes the rulebook root | path confinement (Folder structure); fail-closed — an unreadable file is never a pass |
| E05 | `override_of` targets a `floor = true` check | floors are non-overridable (Choosing severity and floor) |
| E06 | `[gate]` or user config drops a floor check out of `block_on` | same — you can tighten, never loosen through the floor |
| E07 | duplicate check id across the merged set | extend deliberately with `override_of`, or rename (Extending) |
| E08 | kind/field mismatch — `data` without `runner`, `code` without `entry`/`enforcer`, `prose` without `body` or *with* `needs` | choosing `kind` |
| E09 | `hard`/`partial` without an `enforcer`; warns when `partial` lacks a `gap` | declare what's true (Choosing enforcement) |
| E10 | unknown view name, or `needs` unsatisfiable by any accepted subject | `needs` and subject types |
| E11 | *(warning)* prose body contains an instruction-override pattern | write rules, not payloads (Trust model) |
| E12 | `[detect].markers` malformed; warns when a non-builtin declares it | `[detect]` is reserved, auto-selection is builtin-only |
| E13 | a command name collides with a reserved engine command, a builtin rulebook id, or a sibling command | Commands (the manifest walkthrough) — dispatch tokens must be unambiguous |
| E14 | a command is malformed (name not a slug, `body` missing/not a path, empty `description`) | Commands — every command is a named, described, folder-confined instruction file |

## Checklist before you ship

1. `validate-rulebook.py ./my-rulebook` exits 0 — warnings read and either
   fixed or defensible.
2. `kerby load ./my-rulebook` on a scratch project: the trust prompt shows
   what you'd expect a stranger to approve.
3. Edit one character in a body, load again: the prompt re-fires. If it
   doesn't, something is wrong — report it, don't ship around it.
4. `kerby status`: every check shows the declared and effective enforcement
   you intended, gaps named.

The gate reads manifests, not intentions. Declare honestly and you'll pass
on the first try.
