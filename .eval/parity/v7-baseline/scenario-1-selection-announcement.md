# v7-baseline — selection order, pin, announcement (v6.0.0 @ b161c32)

Verbatim from SKILL.md § Rulebooks, selection, and trust. Byte-match required
except whitelisted deltas (ENGINE-MAP-v2 § Expected parity deltas).

**Selection order (first hit wins), resolved at `load`:**

1. **Explicit arg** — `args: load <id>` or `args: load <path>` (a path = a `local` rulebook).
2. **Pinned selection** — the `selected` array in `rulebooks.lock` at the project root.
3. **Detection** — reserved; at contract v1 the detection step always returns *undetermined*.
4. **Default** — `code`.

The first successful load **writes the pin** to `rulebooks.lock` (JSON: `selected` + per-rulebook `{id, version, origin, path_or_url, sha256}`; builtin entries carry `sha256: null` — they are repo-versioned). **`selected` records only what was explicitly chosen or defaulted to** — for a default `code` load that is `["code"]`, never `["base", "code"]`: `base` is always composed in per merge rule 1 (`docs/rulebook-contract.md`), so it is never itself a member of `selected`. Every later load reads the pin. Changing rulebooks is an explicit act (`args: load <id>` re-pins); it never drifts with workspace content. Auto-selection is builtin-only: an external rulebook loads by explicit invocation *only*, regardless of any `[detect]` table it declares.

**The lockfile's `origin` field is untrusted — builtin-ness is *re-derived from the install*, never read from the pin.** `rulebooks.lock` is workspace content; a cloned repo can set any entry's `origin` to `"builtin"` with a `path_or_url` inside the workspace. If the loader believed that field it would skip the approval prompt and validate the workspace rulebook with `--origin builtin` (which grants repo-relative path resolution with no confinement) — loading untrusted prose as trusted builtin content. So the loader **determines origin by resolution, not by the pin's claim**: a rulebook is `builtin` **iff** its `id` names a directory that actually ships in this install at `<install-root>/resources/rulebooks/<id>`. Builtins are always loaded and validated from that install path — a builtin pin's `path_or_url` is ignored. A pin whose `origin` is `"builtin"` but whose `id` is not an installed builtin (or whose `path_or_url` points into the workspace) is invalid: do not load it as a builtin and do not silently fall back — treat it as the fail-closed **HELD** case (§ below), since the workspace is asserting trusted status for content the install does not vouch for.

**"The builtin `code`" always means the rulebook resolves to the installed `<install-root>/resources/rulebooks/code`, never the id alone.** A `local` rulebook may legitimately declare `id = "code"` (the id is untrusted manifest data for a non-builtin origin), so every branch that gives `code` its BOOTSTRAP-specific treatment — the verbatim load/reload confirmation, the `status` BOOTSTRAP-marker scan — must key on that install-resolved builtin identity (origin re-derived as above), not on the id and not on the lockfile's `origin` field. A local rulebook named `code` is treated like any other local rulebook (its own root body, its own markers, the approval prompt), not as the builtin.

**Every load announces the decision in one literal line:**

```
rulebook: <id>@<version> (<origin>) — source: explicit | pinned | detected | default
```

On a first-time default, append the hint: `(detection inconclusive; 'kerby load <id>' to override)`.

**Hash-changed re-approval gets its own source value, never a bare `pinned`.** If a previously-pinned `local` rulebook's hash no longer matches (§ below), its announcement line must say so plainly — `source: pinned (content changed — reapproval required)` — never the unqualified `pinned`, which would read as a clean success sitting directly above a trust prompt asking the user to approve it again. The two must not contradict each other.
