# v7-baseline — status verdict + rulebook panel (v6.0.0 @ b161c32)

Permitted v7 delta ONLY: + `Loaded rulebooks:` header line.

## `status`

Check whether the rules are currently loaded.

1. **Determine which rulebook to check for first** — read the `selected` pin in `rulebooks.lock` (if present) and resolve its root body. The verdict must scan for *that* rulebook's markers, not BOOTSTRAP unconditionally: a session that loaded `./my-rulebook` never read BOOTSTRAP, so a BOOTSTRAP-only scan would falsely report "not loaded" and tell the user to reload rules already in context.
   - **Pinned to the builtin `code`** (origin `builtin` + id `code`) **or no pin** (`code` is the default): scan recent context for BOOTSTRAP signatures — distinctive phrases like "Prime Directive", "Clarity over cleverness. Safety over speed.", "implement → check → commit → log → repeat", or BOOTSTRAP.md section headers (`<prime_directive>`, `<hard_rules>`, `<reference_index>`).
   - **Pinned to any other rulebook** (including a `local` rulebook named `code`): scan for distinctive phrases/headers from *that* rulebook's root body instead (plus the shared base-floor rule text, which loads for every rulebook). If the rulebook declares **no root body** (all-mechanical), there is no rulebook-specific prose to detect — scan for the base-floor rule text alone, which loads for every rulebook, and report loaded on that basis.
2. If the selected rulebook's markers are found, report (name the rulebook when it isn't the builtin `code`):

   > **kerby: loaded.** Detected `<id>` markers in current context.

3. If not found, report:

   > **kerby: not loaded.** Invoke `kerby` with `args: load` to load them.

4. **Rulebook panel.** After the loaded/not-loaded verdict, report the rulebook state so degrade is visible, never assumed:

   - Read `rulebooks.lock` (if present) and each selected rulebook's manifest, **merging in `base` first exactly like `load` does** — `selected` deliberately omits `base` (it's implicit per merge rule 1), so reading only the selected manifests would silently drop the floor's own checks (`secrets-staged`, `no-print-secret`, …) from the panel. Header line: the same literal announcement format as `load`, with `source: pinned` (or "no pin — next load selects per the default order").
   - Per check, one row: `<id> — <kind> — declared: <enforcement> — effective: <enforcement>` plus the `gap` text for `partial` checks. **Effective enforcement**: for `hard`/`partial` checks, the declared level holds only if the check's enforcer is actually registered — detect it exactly like `install` Phase 2 does (a hook entry whose command ends in the enforcer's filename AND whose path contains `/skills/kerby/resources/hooks/`, in any of the three settings files). Unregistered → effective is `behavioral` (degraded); mark it `degraded — run install to bind`. `behavioral` checks show `behavioral (by design)`.
   - A check whose `needs` the current subject type cannot satisfy is listed as `skipped (needs: <views>)` — visible, never silent.
   - If the last load failed (invalid manifest, declined trust prompt), say which rulebook and why, and that gated work in the meantime is **HELD**.

---
