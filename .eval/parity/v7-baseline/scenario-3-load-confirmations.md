# v7-baseline — load flow + confirmations + nudge (v6.0.0 @ b161c32)

The builtin-code confirmation and reload wording are PARITY-CRITICAL (verbatim).

## `load` (default)

Load the kerby into the current session.

1. Locate the install per the section above, then **select rulebooks** per the selection order (explicit arg → `rulebooks.lock` pin → detection stub → default `code`) and emit the one-line announcement. If this is the first successful load in this project, write the pin to `rulebooks.lock` and say so in one short line.
2. Resolve each selected rulebook's `rulebook.toml` and validate per the trust section (hash-keyed; trust prompt for first-load/changed local rulebooks; fail-closed → HELD). Merge `base` first.
3. Read the merged rulebook's **eager prose in full using the `Read` tool**: the selected rulebook's root body (its first-declared prose check) — for `code` that is `operating-rules` → `BOOTSTRAP.md` — plus every prose body that is **`floor = true` OR `token_cost = "low"`**. **All `floor = true` prose loads eagerly regardless of `token_cost`** — a floor is the non-negotiable, always-on baseline (prompt-injection defense, the Iron Law, secret-handling), so a floor rule that isn't in context isn't a floor; `token_cost` governs progressive disclosure only for *non-floor* prose. **A rulebook may legitimately declare no prose at all** (an all-mechanical rulebook of only `data`/`code` checks) — it then has **no root body**, and eager load is just the base floor prose; do not invent one. **Do not paraphrase or summarize** — the full content must enter context as a tool result. Summarizing into your response does not load the rules the same way. Heavier *non-floor* bodies (`references/*.md`) stay on demand, exactly as BOOTSTRAP's reference index directs.
4. Confirm to the user. The confirmation is **rulebook-aware** — name what actually loaded, never a rulebook that wasn't selected:

   - **The builtin `code`** (origin `builtin` + id `code` — the common path, whether by default, pin, or explicit `load code`; keep this wording verbatim for parity with pre-v6 behavior):

     > **kerby loaded.** BOOTSTRAP is in context for this session — I will follow its rules until the session ends or context is compacted. If rules seem to stop applying mid-session, invoke `kerby` with `args: reload`.

   - **Any other selected rulebook** (a `local` rulebook, or any rulebook that isn't the builtin `code` — including a local rulebook that happens to be named `code`): name the rulebook and its root body instead of BOOTSTRAP — do not claim BOOTSTRAP is in context when the builtin `code` wasn't the one loaded. If the rulebook declares no prose (no root body), name its checks and the base floor instead of a root body:

     > **kerby loaded `<id>@<version>`.** Its rules (`<root-body>` + the base floor) are in context for this session — I will follow them until the session ends or context is compacted. If rules seem to stop applying mid-session, invoke `kerby` with `args: reload`.

     (No-root-body variant: `**kerby loaded `<id>@<version>`.** Its checks (`<data/code check ids>`) and the base floor are active for this session — …`)

5. The rules are now active. Apply the loaded rulebook's rules (for `code`, that is BOOTSTRAP) plus the base floor rules for all subsequent work in this session.

6. **Readiness nudge (read-only).** After confirming, check whether this repo is already prepared for kerby, and suggest `prepare` if not. This adds **no writes** — detection only.

   - **Has real code?** True if any project manifest exists (`package.json`, `deno.json`, `pyproject.toml`, `go.mod`, `Cargo.toml`) or there is a populated source tree.
   - **Already prepared?** True if `agent-context.yaml` exists with a non-empty `project.name` (the template ships `""`) **AND** (`CONTEXT.md` has ≥1 glossary entry **OR** `.ai/knowledge/` has ≥1 entry file beyond `KNOWLEDGE.md`).
   - **If has-real-code AND NOT already-prepared**, append this one line after the confirmation:

     > This repo has code but no populated kerby context (CONTEXT.md / `.ai/knowledge/` / agent-context.yaml look empty or missing). Run `kerby` with `args: prepare` to onboard it — I'll populate those from your code and git history, with a diff-and-confirm on every write.

   - **Otherwise stay silent** — already prepared, or no real code (a greenfield repo belongs to `workflows/new-project.md`, not `prepare`). The nudge is a suggestion only; never auto-run `prepare`.

---

## `reload`

Re-load the rules. Useful after Claude Code compacts the conversation and may have stripped earlier context.

Same procedure as `load` — the pin in `rulebooks.lock` is read, never re-resolved (announcement source: `pinned`) — but the confirmation message is **rulebook-aware**, mirroring step 4 of `load` (name what was actually refreshed, never BOOTSTRAP for a non-`code` rulebook):

- **Pinned to the builtin `code`** (origin `builtin` + id `code`) (verbatim, for parity):

  > **kerby reloaded.** BOOTSTRAP refreshed in context.

- **Pinned to any other rulebook** (including a `local` rulebook named `code`):

  > **kerby reloaded `<id>@<version>`.** Its rules (`<root-body>` + the base floor) refreshed in context.

---
