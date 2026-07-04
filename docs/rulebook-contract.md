# Rulebook contract — v1

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
| `builtin` | `skills/kerby/resources/rulebooks/<id>/`, ships inside kerby | may declare repo-relative paths — resolved against the rulebook root first, then against `resources/` (so `references/quality-gates.md` and `hooks/protect-git.sh` declare existing files in place) | repo-versioned; no hash pin required |
| `local` | anywhere on disk, loaded by explicit path | confined: every declared path must resolve **inside** the rulebook root — no `..`, no absolute paths, no symlink escapes (E04) | one-time review + hash pin (TOFU) on first load when the rulebook carries `prose` or `code` checks; silent re-load only while the hash matches **and** the hash is in the per-machine `~/.claude/kerby/approved-rulebooks.json` — a committed project `rulebooks.lock` is untrusted content and can never by itself pre-approve external prose/code |
| `remote` | — | — | **reserved**; no fetching at v1 |

Auto-selection is builtin-only (D19): external rulebooks load by explicit
invocation only, whatever they declare.

## Top-level fields

```toml
id = "code"                 # unique rulebook id (required)
version = "1.0.0"           # the rulebook's own semver (required)
contract = 1                # manifest contract version (required; engine rejects unsupported, E03)
accepts = ["git_change"]    # subject types this rulebook can judge (required, non-empty; "*" = any)
extends = ["base"]          # packs composed in — see Merge rules

[gate]                      # severity → verdict mapping; defaults shown
block_on = ["block"]        # severities that DENY
hold_on  = ["warn"]         # severities that HOLD

[commands]                  # optional; domain facts the core tier ladder consumes (D14)
build = "{build_command}"
lint  = "{lint_command}"
test  = "{test_command}"

[detect]                    # RESERVED at contract v1 (D17–D19)
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
| `floor` | bool | non-overridable (D9); no config or extending rulebook may loosen it. Only meaningful in `base` at contract v1 |
| `override` | string | escape-hatch policy for non-floor checks, e.g. `"authorized-scoped"` (the `CODING_RULES_ALLOW_PROTECTED_COMMIT=1` pattern) |
| `gap` | string | for `partial`: the named enforcement gap (warn if absent, E09); surfaces in `status` |
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

1. `base` is always merged first, whether or not listed (a rulebook whose
   `id` is `base` is itself the floor and merges nothing). A rulebook cannot
   subtract a base check.
2. Duplicate `id` across packs → E07, unless the extending check sets
   `override_of = "<id>"` **and** the target is not `floor = true` (E05).
3. `[gate]` maps merge per-key; the extending rulebook wins for non-floor
   severities only. Every `floor = true` check's severity must remain in the
   merged `block_on` (E06).
4. User config sits above the merged result: tighten freely; loosen only to
   the floor; never through it (E06).

## Error catalog (E01–E12)

Messages are fix-forward and literal (VOICE.md zoning: error strings carry no
persona). E09-gap, E11, and E12-non-builtin emit as warnings (exit 0);
everything else is an error (exit 1).

| Code | Invariant |
|---|---|
| E01 | manifest parses as TOML |
| E02 | required fields present, types correct (`id`, `version`, `contract`, `accepts`; per check: `id`, `kind`, `enforcement`, `severity`) |
| E03 | `contract` supported by this engine (currently: 1) |
| E04 | declared paths exist and are readable; non-builtin paths resolve inside the rulebook root (no `..` / absolute / symlink escape) |
| E05 | no base check removed or shadowed; `override_of` never targets `floor = true` |
| E06 | `[gate]` + config only tighten; never below the floor |
| E07 | `id` unique across the merged set |
| E08 | kind/field coherence (see table above) |
| E09 | `enforcement ∈ {hard, partial, behavioral}`; `hard`/`partial` require `enforcer`; `partial` without `gap` → warning |
| E10 | `accepts` non-empty; every `needs` entry known and satisfiable (see View vocabulary) |
| E11 | prose-injection lint, non-builtin origins, **warn-only**: flags `ignore previous`, `you must now`, `disregard the above` in prose bodies |
| E12 | `[detect]` shape: `markers` = non-empty array of strings (error if malformed); declared by a non-builtin rulebook → warning (ignored at load, D19) |

**Fail-closed:** a validator crash or an unreadable declared file is an
invalid result, never a pass. Anything gated while the loader is failed is
**HELD** (D11) — "the gate couldn't run" escalates to a human; it is not
DENIED and it is never PASS.

## Lockfile (`rulebooks.lock`)

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

- `selected` is the D17 pin: which rulebooks this project loads. Changing
  rulebooks is an explicit act (`kerby load <id>`), never drift.
- `sha256` covers the manifest **plus every declared file** (a manifest-only
  hash would let a declared body mutate silently). `builtin` entries may set
  it `null` — they are repo-versioned.
- Validation is hash-keyed, not operation-keyed (D10): unknown/changed hash →
  validate (and re-prompt for non-builtin trust); matching pinned hash → skip.

Compute the hash with
`python3 skills/kerby/resources/scripts/validate-rulebook.py <dir> --hash`.
