# Rulebook contract — v2 (selection semantics amended in kerby v9.1)

The contract *number* stays **2**: the manifest shape is unchanged, E12 is
unchanged, and every existing external manifest remains valid — a bump to 3
would force churn on external rulebooks for zero shape change. What v9.1 amends
is *loader behavior*: `[detect]` moves from reserved to live for builtins, and
the selection default (`code`) is replaced by marker detection with an
ask-the-user fallback (`source: … | detected | chosen`, no `default`).
kerby v9.4 follows the same precedent: it adds the **optional** `[identity]`
table (E15) — a manifest without it is untouched, so the number still stays 2.
That is the standing rule for contract evolution: *new optional fields are
contract-2-compatible; requiring a field, reshaping an existing one, or
removing one forces v3.*

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
| `local` | anywhere on disk, loaded by explicit path | confined: every declared path must resolve **inside** the rulebook root — no `..`, no absolute paths (E04). **No symlinks and no `.git/` anywhere under the folder** (declared *or* undeclared): a rulebook must be self-contained plain files, since a symlink escapes confinement (a mutable-target instruction channel the trust hash can't cover) and `.git/` is skipped by the hash (so content under it would be a hash-blind channel) — both E04. Remote clones strip `.git/` at fetch; a local rulebook must be a clean content dir, not a git working tree | one-time review + hash pin (TOFU) on first load — for **any** local rulebook, including a `data`-only one (loading it makes it part of the session's governing gate — selecting an external gate is a trust decision whether it joins or stands alone, and a cloned lockfile's `selected` array can still put it in place of a builtin outright; a prose/code rulebook *additionally* admits external instructions/scripts). Silent re-load only while the hash matches **and** the hash is in the per-machine `~/.claude/kerby/approved-rulebooks.json` — a committed project lockfile is untrusted content and can never by itself pre-approve an external rulebook |
| `remote` | fetched by explicit `load <git-URL \| owner/repo>`, materialized at `.kerby/rulebooks/<id>/` (session temp dir when the workspace is read-only) | confined exactly like `local`; clone's `.git/` deleted after fetch; manifest `id` must be a slug (it becomes the path component) | TOFU exactly like `local`, plus `Source: <url>` provenance in the prompt. **No silent network** (plain `load`/`reload` use the existing clone) and **no silent updates** (re-running `load <source>` re-clones; a changed hash re-prompts). Lockfile entry adds `local_path` — untrusted like every lockfile field: the loader re-derives it from the id; a mismatch or out-of-root path is fail-closed HELD |

Auto-selection is builtin-only (D19): external rulebooks load by explicit
invocation only, whatever they declare — `[detect]` steers selection only
among builtins. For a builtin, the loader matches its `[detect].markers` as
root-relative globs during selection (v9.1); for a non-builtin the markers are
shape-checked and ignored (E12 warns).

## Top-level fields

```toml
id = "swe"                 # unique rulebook id (required)
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

[detect]                    # builtin auto-selection markers (D17–D19; live for builtins since v9.1)
markers = ["package.json"]  # root-relative globs; loader matches among BUILTINS only (E12 warns + ignores for non-builtins)

[identity]                  # optional presentation table (E15; defined in v9.4, consumed from v9.5 — still contract 2)
signature_phrases = ["…"]   # distinctive root-body text `status` will scan context for (scan-only, never echoed)
load_confirmation = "…"     # load/reload confirmation text; to be rendered verbatim for install-resolved
reload_confirmation = "…"   #   builtins ONLY — every other origin gets the engine's generic template
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
| `event` / `matcher` | strings | how `install` derives the hook registration for this check's enforcer: a Claude Code lifecycle event (unknown events warn) + tool-name pattern (empty = all). An enforcer without `event` cannot be auto-registered (E09 warns). Dedup at registration = **(event, matcher, resolved script path)** — follow an enforcer shim to the script it `exec`s (reading the final `exec` target, resolving a `target=` variable if the shim guards resolvability first; not required to be one physical line), so a shared script — e.g. an external rulebook shimming into the floor — coalesces to one entry while two rulebooks that share a hook *basename* at different paths each register. The builtins `base` and `swe` are the latter case: separate `pre-commit-check.sh` / `hollow-test-check.sh`, two distinct `PreToolUse/Bash` entries. Never dedup on filename alone (it would let one rulebook's hook mask another's). `status`/`uninstall` compare the same resolved-path identity |
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
(for the builtin `swe` rulebook that is `operating-rules` → `BOOTSTRAP.md`,
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

## `[identity]` — presentation fields (optional, kerby v9.4)

How a rulebook *presents itself* to the engine's user-facing flows. The whole
table and every field in it are optional — an existing manifest without it is
untouched, which is why this lands at contract 2 (same precedent as v9.1: new
behavior, no shape break for existing manifests).

**Consumption timeline.** kerby v9.4 ships the field *definitions* and their
validation (E15/E11) only — the loader validates `[identity]` but does not yet
read it, so declaring the table changes nothing this release. The engine begins
consuming it in v9.5, when SKILL.md's `load` / `reload` / `status` flows switch
from their hardcoded builtin branches to the fields below. The semantics stated
here are that **target** behavior; until v9.5 they are declared-but-inert.

- **`signature_phrases`** — distinctive substrings of the rulebook's own prose
  (root body / floor rules) that the engine's `status` will scan recent context
  for to answer "are this rulebook's rules loaded?". **Scan-only for every
  origin**: the status verdict names the rulebook id, never the matched text,
  so the field cannot smuggle content into output. Absent → `status` falls
  back to scanning for the root body's own text (or the base floor's when
  there is no root body). Keep the phrases exact substrings of the shipped
  prose — a reworded rule that orphans its phrase silently degrades detection.
- **`load_confirmation` / `reload_confirmation`** — the confirmation line the
  loader prints after reading this rulebook's eager prose. **Rendered verbatim
  only when the rulebook is an install-resolved builtin** (the strict
  re-derivation in Origins and trust — never the id string alone). Any other
  origin — including a `local` fork that names itself after a builtin — always
  gets the engine's generic template (`kerby loaded <id>@<version> …`), so an
  external manifest string is never rendered by this field. E11 lints all
  three fields anyway, so they cannot become a dormant channel when the engine
  starts rendering them (v9.5) or if a future engine widens rendering.

## Error catalog (E01–E15)

Messages are fix-forward and literal (VOICE.md zoning: error strings carry no
persona). E09-gap, E11, E12-non-builtin, and E15-unknown-key emit as warnings
(exit 0); everything else is an error (exit 1). E02-unknown-event also warns.

| Code | Invariant |
|---|---|
| E01 | manifest parses as TOML |
| E02 | required fields present, types correct (`id`, `version`, `contract`, `accepts`; per check: `id`, `kind`, `enforcement`, `severity`) |
| E03 | `contract` supported by this engine (currently: 2) |
| E04 | declared paths exist and are readable; non-builtin paths resolve inside the rulebook root (no `..` / absolute / symlink escape); no symlinks or `.git/` anywhere under the folder; the manifest `id` is a strict slug (it becomes a path component at `.kerby/rulebooks/<id>`, so `..` / slashes / absolute are rejected before any move or pin) |
| E05 | no base check removed or shadowed; `override_of` never targets `floor = true` |
| E06 | `[gate]` + config only tighten; never below the floor |
| E07 | `id` unique across the merged set |
| E08 | kind/field coherence (see table above) |
| E09 | `enforcement ∈ {hard, partial, behavioral}`; `hard`/`partial` require `enforcer`; `partial` without `gap` → warning |
| E10 | `accepts` non-empty; every `needs` entry known and satisfiable (see View vocabulary) |
| E11 | prose-injection lint, non-builtin origins, **warn-only**: flags `ignore previous`, `you must now`, `disregard the above` in **every prose/text file the trust hash covers** — declared check + command bodies (**regardless of file extension** — a body like `commands/review` with no `.md`/`.txt` suffix is still dispatched as instructions, so it is linted too) *and* undeclared `references/`/`workflows/` markdown a body can read — **and in the free-text manifest fields the loader displays or scans** (the rulebook `description`, each `[[command]].description`, each `[[check]].gap`, and the three `[identity]` fields `signature_phrases` / `load_confirmation` / `reload_confirmation` — the confirmations are never rendered for a non-builtin and the phrases are scan-only, but linting them keeps the fields from becoming a dormant channel), so the payload can't be hidden by moving it out of a declared body or into a string shown at the trust prompt |
| E12 | `[detect]` shape: `markers` = non-empty array of strings (error if malformed); accepted for builtins (the loader matches them as root-relative globs among builtins, v9.1); declared by a non-builtin rulebook → warning (ignored at load, D19) |
| E13 | no `[[command]]` name collides with a reserved engine command, a builtin rulebook id, or another command in the same rulebook |
| E14 | `[[command]]` shape: `name` a slug, `body` a folder-confined path string, `description` non-empty |
| E15 | `[identity]` shape: a table; `signature_phrases` = non-empty array of non-empty strings; `load_confirmation`/`reload_confirmation` = non-empty strings (error if malformed); unknown keys inside the table → warning (ignored) |

**Fail-closed:** a validator crash or an unreadable declared file is an
invalid result, never a pass. Anything gated while the loader is failed is
**HELD** (D11) — "the gate couldn't run" escalates to a human; it is not
DENIED and it is never PASS.

## Lockfile (`.kerby/rulebooks.lock`)

JSON, under the consuming project's `.kerby/` state dir. Written by the
first successful load; read by every later load.

```json
{
  "selected": ["swe"],
  "rulebooks": [
    { "id": "swe", "version": "2.0.0", "origin": "builtin",
      "path_or_url": "<resolved path>", "sha256": null }
  ]
}
```

- Location: `.kerby/rulebooks.lock` — the only location the loader reads.
- `selected` is the D17 pin: which rulebooks this project loads. The **first
  successful load writes it** — whether the selection came from an explicit
  arg, marker detection (`source: detected`), or the user's answer to the
  ask-fallback (`source: chosen`) — so detection/ask happens once per project
  and every later load reads the pin. Changing rulebooks is an explicit act,
  never drift: `load <x>` **adds** to `selected` (or leaves the pin untouched
  when `<x>` is already a member — sameness is resolved identity,
  install-resolved builtin or `path_or_url`, never the id string; a bare id
  resolves to the active incumbent first, and with no incumbent to the
  install builtin before any pinned-but-unselected external of that id) and
  `unload <x>` **removes**;
  replacing a gate is unload-then-load, two explicit acts, and `load +<x>` is
  a back-compat alias of `load <x>`. An external (`local`/`remote`) rulebook
  is appended and pinned only after validation + TOFU approval clear — a
  declined prompt writes nothing. **Ids are unique within `selected`** —
  since it keys on `id` and every user-facing op dispatches by id, `load`
  refuses a rulebook whose id already names a *different* active selection
  (e.g. the builtin `swe` plus a local fork also named `swe`); the user
  unloads the incumbent first. Loading the *same* already-selected rulebook
  is an idempotent pin no-op (in-context refresh).
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

## Intent manifest (`.kerby/rulebooks.toml`) — committed, optional

The lockfile above is machine-local *resolution* — absolute paths, per-checkout
state, never committed. The intent manifest is its committed inverse: a
path-free, trust-inert TOML file naming which rulebooks the project *intends*
to use, so a teammate's fresh checkout can reproduce the selection without
inheriting anyone's machine state.

```toml
# kerby intent manifest — committed. Names which rulebooks this repo uses.
# Trust-inert: grants no approval; externals still TOFU on every machine.
[[rulebook]]
id = "swe"                # builtin — resolves against the local install
version = "3.1.0"         # exact pin: a drift detector, not a resolver

[[rulebook]]
id = "team-standards"
version = "1.2.0"
source = "https://github.com/org/team-standards"  # remote only — never a local path
```

Fields per `[[rulebook]]` entry — nothing else is honored:

- `id` — slug, same rules as a manifest id (E04 doctrine: an id becomes a path
  component).
- `version` — the exact version expected. **A drift detector, not a
  resolver:** kerby has no registry and cannot fetch historical versions —
  builtins load whatever the install ships; remotes fetch HEAD of `source`. A
  mismatch is announced, never silently absorbed.
- `source` — optional; a remote URL (the same forms `load <source>` accepts).
  Never a local filesystem path: a local external has no shareable source, so
  its entry carries `id` + `version` only and each machine supplies its own
  copy.

**Trust: the manifest grants nothing.** It is committed workspace content —
exactly as untrusted as a committed lockfile (previous section). It never
pre-approves: a `source` URL only *names* a rulebook; loading it runs the full
remote flow — clone, validate, TOFU prompt — on every machine. The schema has
no `origin`, `sha256`, or `local_path` fields; an entry carrying one is
malformed, never a trust assertion.

**Lifecycle (opt-in by existence):** created by `kerby install`'s offer or by
hand. While it exists, every pin mutation (`load`/`unload`) and builtin
version-reconcile mirrors into it, always announced. When absent, nothing
reads or writes it. **Malformed → announced and ignored** — TOML parse
failure, an unknown field, a non-slug `id`, or a `source` that is not a remote
URL makes the loader announce `intent manifest unreadable (<reason>) —
ignoring; falling through` and continue down the selection order; never a
HELD. It grants no trust, so skipping is safe; silence is not.

## Engine independence — the zoning rule

This contract's opening promise — the engine loads, weighs, and enforces
*without knowing the domain* — is enforceable in review with one rule:

**Engine surfaces** (`skills/kerby/SKILL.md`, `skills/kerby/resources/**`, and
the kerby repo's root `scripts/`) **may name a builtin rulebook only as (a) a
worked example illustrating a generic mechanism, or (b) bundle contents**
("what ships in the box"). They must never *key behavior* on a builtin's id,
filenames, marker list, or prose text: every behavior-bearing branch consumes
contract fields (`[detect]`, `[identity]`, `[[check]]`, `[[command]]`,
`[tooling]`), so deleting any builtin folder leaves the engine mechanically
intact. That deletion test — the **delete-swe drill** — is a release-checklist
item (from v9.5, once the engine consumes the fields below): temporarily move
`rulebooks/swe/` aside; `load` must fall to detection-among-remaining/ask,
`status` must scan the remaining builtins' `signature_phrases`, `install` must
derive only the remaining enforcers, and no engine text may point at a file
that is gone. Restore afterwards.

Two deliberate non-exceptions:

- The **install-resolved builtin-identity doctrine** (Origins and trust) is
  behavior about the *origin class* — builtin-vs-external trust — not about
  any particular builtin. It stays, and it is what gates verbatim rendering
  of `[identity]` confirmations.
- **Migration residue** (the v9.0 `code` → `swe` rename shims) lives only in
  SKILL.md's marked migration section with a sunset note, exempt until
  removed.

Corollary for contract evolution: a new manifest field that the loader
*displays* joins E11's lint coverage in the same PR that ships it; a field the
loader merely *scans for* or treats as a slug/filename is preferred over free
text wherever it does the job.
