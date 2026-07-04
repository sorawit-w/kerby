# Rulebook contract — v2

The manifest contract between the kerby engine (loader/validator) and a
**rulebook** — a folder of rules the engine can load, weigh, and enforce
without knowing the domain. One fixed filename: `rulebook.toml` at the
rulebook root (D1); everything else the rulebook contains is declared in the
manifest by relative path. **The manifest is the single authority for what a
rulebook contains — the engine never guesses filenames.**

Mechanical validation:
`python3 skills/kerby/resources/scripts/validate-rulebook.py <rulebook-dir>`
(requires Python ≥ 3.11 for stdlib `tomllib`; the validator has no
third-party imports). The validator ships inside the skill bundle so the
`load` flow can invoke it wherever the skill is installed. An advisory pass
is never a trust grant — `load` always re-checks, cheaply when the hash is
pinned (D10).

## Origins and trust (D6, D7)

| Origin | Where it lives | Path rules | Trust |
|---|---|---|---|
| `builtin` | `skills/kerby/rulebooks/<id>/`, ships inside kerby | **folder-confined like every origin** (contract 2 — the v1 resources-relative exemption is gone; builtins are self-contained) | repo-versioned; no hash pin required. **Builtin trust is anchored to the install location, never *granted* by a lockfile**: an entry claiming `origin: builtin` is the builtin *iff* its `id` resolves to `<install-root>/rulebooks/<id>` and its `path_or_url` is that install path. The validator rejects `--origin builtin` for any path outside `--builtin-root` (E04); a `builtin` claim for a workspace path is invalid HELD, not trusted. A pin claiming `origin: local`/`remote` — even one whose `id` collides with a builtin — is honored as that external rulebook (loaded from its `path_or_url` through TOFU, never silently swapped for the builtin), since it grants no trust; that keeps builtin-id forks reloadable |
| `local` | anywhere on disk, loaded by explicit path | confined: every declared path must resolve **inside** the rulebook root — no `..`, no absolute paths (E04). **No symlinks and no `.git/` anywhere under the folder** (declared *or* undeclared): a rulebook must be self-contained plain files, since a symlink escapes confinement (a mutable-target instruction channel the trust hash can't cover) and `.git/` is skipped by the hash (so content under it would be a hash-blind channel) — both E04. Remote clones strip `.git/` at fetch; a local rulebook must be a clean content dir, not a git working tree | one-time review + hash pin (TOFU) on first load — for **any** local rulebook, including a `data`-only one (loading it replaces the default gate; a prose/code rulebook *additionally* admits external instructions/scripts). Silent re-load only while the hash matches **and** the hash is in the per-machine `~/.claude/kerby/approved-rulebooks.json` — a committed project lockfile is untrusted content and can never by itself pre-approve an external rulebook |
| `remote` | fetched by explicit `load <git-URL \| owner/repo>`, materialized at `.kerby/rulebooks/<id>/` (session temp dir when the workspace is read-only) | confined exactly like `local`; clone's `.git/` deleted after fetch; manifest `id` must be a slug (it becomes the path component) | TOFU exactly like `local`, plus `Source: <url>` provenance in the prompt. **No silent network** (plain `load`/`reload` use the existing clone) and **no silent updates** (re-running `load <source>` re-clones; a changed hash re-prompts). Lockfile entry adds `local_path` — untrusted like every lockfile field: the loader re-derives it from the id; a mismatch or out-of-root path is fail-closed HELD |

Auto-selection is builtin-only (D19): external rulebooks load by explicit
invocation only, whatever they declare.

## Top-level fields

```toml
id = "code"                 # unique rulebook id (required)
version = "1.0.0"           # the rulebook's own semver (required)
contract = 2                # manifest contract version (required; engine rejects unsupported, E03)
accepts = ["git_change"]    # subject types this rulebook can judge (required, non-empty; "*" = any)
description = "…"           # one line for `rulebooks list` (optional string)
extends = ["base"]          # packs composed in — see Merge rules

[gate]                      # severity → verdict mapping; defaults shown
block_on = ["block"]        # severities that DENY
hold_on  = ["warn"]         # severities that HOLD

[tooling]                   # optional; domain facts the core tier ladder consumes (D14)
build = "{build_command}"    # (renamed from v1 [commands] to disambiguate from [[command]],
lint  = "{lint_command}"     #  the user-invocable rulebook commands added in Phase B of the
test  = "{test_command}"     #  v7 PR)

[[command]]                 # user-invocable commands this rulebook provides (V2)
name = "audit"              # dispatch token: slug, non-reserved, no builtin-id collision (E13)
body = "commands/audit.md"  # instruction file read at invocation; folder-confined, trust-hashed
description = "…"           # shown in dispatch listings + the trust prompt (E14)

[detect]                    # RESERVED at contract v2 (D17–D19)
markers = ["package.json"]  # shape-validated only (E12); the loader never matches on it
```

## `[[check]]` fields

| Field | Type | Semantics |
|---|---|---|
| `id` | string | unique within the merged set (E07); colliding with an extended pack's id is an error unless `override_of` names it deliberately |
| `kind` | `data \| code \| prose` (D2) | what the check ships |
| `needs` | array of view names | views the check requires (see View vocabulary). Prose checks omit `needs` — they load as context rules, not executions (E08) |
| `enforcement` | `hard \| partial \| behavioral` (D3) | declared binding. Effective binding **degrades** to `behavioral` when the enforcer isn't registered; degrade is observable via `status` (D4) |
| `enforcer` | path | for `hard`/`partial`: the hook/runner that binds it (E09). Registration state drives degrade. Two checks may share one enforcer script |
| `runner` | string | for `data`: built-in runner id (`gitleaks`, `semgrep`, `regex-floor`) |
| `config` / `entry` / `body` | path | the declared file: ruleset (`data`, optional when the runner carries defaults), script (`code`), markdown (`prose`) |
| `severity` | `block \| warn \| info` | feeds `[gate]` mapping to DENIED / HELD |
| `floor` | bool | non-overridable (D9); no config or extending rulebook may loosen it. Only meaningful in `base` at contract v2 |
| `override` | string | escape-hatch policy for non-floor checks, e.g. `"authorized-scoped"` (the `CODING_RULES_ALLOW_PROTECTED_COMMIT=1` pattern) |
| `gap` | string | for `partial`: the named enforcement gap (warn if absent, E09); surfaces in `status` |
| `event` / `matcher` | strings | how `install` derives the hook registration for this check's enforcer: a Claude Code lifecycle event (unknown events warn) + tool-name pattern (empty = all). An enforcer without `event` cannot be auto-registered (E09 warns). Dedup at registration = **(event, matcher, resolved script path)** — following a one-line `exec` shim to its target, so a builtin's shared script coalesces to one entry while two unrelated rulebooks that share a hook *basename* at different paths each register. Never dedup on filename alone (it would let one rulebook's hook mask another's). `status`/`uninstall` compare the same resolved-path identity |
| `token_cost` | `low \| medium \| high` | prose only: recurring context cost; drives progressive loading order (low loads eagerly) |

Kind/field coherence (E08): `data` → `runner` required (`config` optional);
`code` → `entry` or `enforcer`; `prose` → `body`, and no `needs`.
*(Refinement over the handoff's draft catalog, which read `data → runner +
config`: the normative base manifest declares `secrets-staged` with a
runner-default config, so `config` is optional.)*

## View vocabulary (initial set, provided by core per subject type)

Subject type `git_change` provides: `changed_files`, `changed_content`,
`staged_content`, `added_lines`, `commit`, `branch`, `install_state`,
`repo_tree`. Future subject types (e.g. `document`) provide their own subset.

- Every `needs` entry must name a known view (E10).
- If `accepts` lists concrete subject types, at least one accepted subject
  must provide every needed view (E10).
- `accepts = ["*"]`: any known view is declarable; a check whose `needs`
  cannot be satisfied by the *current* subject is **skipped and reported** in
  `status` — visible, never silent.

## Loading order

Manifest declaration order is significance order. At load, the engine reads
eagerly: every prose body that is **`floor = true` or `token_cost = "low"`**,
plus the **selected** rulebook's first-declared prose check — its *root body*
(for the builtin `code` rulebook that is `operating-rules` → `BOOTSTRAP.md`,
preserving the classic BOOTSTRAP → references pattern). All `floor = true`
prose loads eagerly regardless of `token_cost` — a floor is the always-on
baseline, so it must be in context, not deferred; `token_cost` governs
progressive disclosure only for non-floor prose. All other (non-floor) prose
loads on demand.
Extended packs contribute their own low-cost bodies but no root.

## Merge rules (`extends`)

1. `base` is always merged first, whether or not listed. **Only the real
   builtin base rulebook** (`origin == builtin` **and** `id == base`) is
   exempt from merging itself; for any non-builtin origin the `id` is
   attacker-controlled, so a `local`/`remote` rulebook that sets `id = "base"`
   still gets the real floor force-merged in — it cannot dodge the
   non-overridable checks by naming itself `base` (E04/E07). A rulebook cannot
   subtract a base check.
2. Duplicate `id` across packs → E07, unless the extending check sets
   `override_of = "<id>"` **and** the target is not `floor = true` (E05).
3. `[gate]` maps merge per-key; the extending rulebook wins for non-floor
   severities only. Every `floor = true` check's severity must remain in the
   merged `block_on` (E06).
4. User config sits above the merged result: tighten freely; loosen only to
   the floor; never through it (E06).

## Error catalog (E01–E14)

Messages are fix-forward and literal (VOICE.md zoning: error strings carry no
persona). E09-gap, E11, and E12-non-builtin emit as warnings (exit 0);
everything else is an error (exit 1). E02-unknown-event also warns.

| Code | Invariant |
|---|---|
| E01 | manifest parses as TOML |
| E02 | required fields present, types correct (`id`, `version`, `contract`, `accepts`; per check: `id`, `kind`, `enforcement`, `severity`) |
| E03 | `contract` supported by this engine (currently: 2) |
| E04 | declared paths exist and are readable; non-builtin paths resolve inside the rulebook root (no `..` / absolute / symlink escape) |
| E05 | no base check removed or shadowed; `override_of` never targets `floor = true` |
| E06 | `[gate]` + config only tighten; never below the floor |
| E07 | `id` unique across the merged set |
| E08 | kind/field coherence (see table above) |
| E09 | `enforcement ∈ {hard, partial, behavioral}`; `hard`/`partial` require `enforcer`; `partial` without `gap` → warning |
| E10 | `accepts` non-empty; every `needs` entry known and satisfiable (see View vocabulary) |
| E11 | prose-injection lint, non-builtin origins, **warn-only**: flags `ignore previous`, `you must now`, `disregard the above` in **every prose/text file the trust hash covers** — declared check + command bodies *and* undeclared `references/`/`workflows/` markdown a body can read — so the payload can't be hidden by moving it out of a declared body |
| E12 | `[detect]` shape: `markers` = non-empty array of strings (error if malformed); declared by a non-builtin rulebook → warning (ignored at load, D19) |
| E13 | no `[[command]]` name collides with a reserved engine command, a builtin rulebook id, or another command in the same rulebook |
| E14 | `[[command]]` shape: `name` a slug, `body` a folder-confined path string, `description` non-empty |

**Fail-closed:** a validator crash or an unreadable declared file is an
invalid result, never a pass. Anything gated while the loader is failed is
**HELD** (D11) — "the gate couldn't run" escalates to a human; it is not
DENIED and it is never PASS.

## Lockfile (`.kerby/rulebooks.lock`)

JSON, at the consuming project's root (same tier as `.ai/`). Written by the
first successful load; read by every later load.

```json
{
  "selected": ["code"],
  "rulebooks": [
    { "id": "code", "version": "1.0.0", "origin": "builtin",
      "path_or_url": "<resolved path>", "sha256": null }
  ]
}
```

- Location: `.kerby/rulebooks.lock` (v7). A pre-v7 root `rulebooks.lock` is read
  as fallback for one major version and auto-migrated on the next pin write.
- `selected` is the D17 pin: which rulebooks this project loads. Changing
  rulebooks is an explicit act (`load <x>` replaces, `load +<x>` adds,
  `unload <x>` removes), never drift.
- `remote` entries carry `path_or_url` = the source URL (identity) and
  `local_path` = the clone dir — re-derived from the id at load, never trusted
  from the file.
- `sha256` covers **every file in the rulebook folder**, each framed by its
  root-relative path and byte length (not just manifest-*declared* files). A
  rulebook's instructions dispatch to files the manifest never declares —
  BOOTSTRAP's reference index reads every `references/*.md`, command bodies read
  their `references/`/`workflows/` targets, workflows drive edits to user files.
  Hashing only declared files would leave those undeclared-but-behavior-bearing
  files a mutable-after-approval instruction channel (edit only a reference or
  workflow after approval, the SHA still matches, a later load skips the trust
  prompt while the command follows unapproved instructions — indirect prompt
  injection). Whole-folder coverage closes that channel and removes any
  "is this file behavior-bearing?" classification an attacker could hide
  behind; the cost is that editing *any* file (a README included) re-triggers
  approval for a local/remote rulebook — the safe direction for untrusted
  content. Symlinks and `.git/` metadata are skipped. `builtin` entries may set
  `sha256` `null` — they are repo-versioned and never trust-gated by this hash.
- Validation is hash-keyed, not operation-keyed (D10): unknown/changed hash →
  validate (and re-prompt for non-builtin trust); matching pinned hash → skip
  **for builtins only**. For a `local` rulebook the project lockfile is
  untrusted workspace content — a matching pin proves the files agree with each
  other, not that *this user* approved them. A committed lockfile must never be
  a pre-approval token for external prose/code (indirect prompt injection). The
  skip is conditional on the hash **also** being present in the per-machine
  `~/.claude/kerby/approved-rulebooks.json`; a matching project pin without a
  user-local approval still re-validates and re-prompts.

Compute the hash with
`python3 skills/kerby/resources/scripts/validate-rulebook.py <dir> --hash`.
