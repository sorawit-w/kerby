# DESIGN.md — Design-Token Authority

The agent's contract for repos that contain a project-level `DESIGN.md`.

**"The spec" means the file [Location](#location) selects**: a root `DESIGN.md`, or a file elsewhere that the developer confirmed, whatever its folder or name. Every rule below that says `DESIGN.md` — Authority, Design skills, Editing Safety, Conflict Resolution — applies to that file, and every command takes its path. So do the rules that point here.

---

## When This Rule Fires

- The repo has a file named exactly `DESIGN.md` (uppercase) at its root — or, failing that, a spec found per [Location](#location) — AND
- The current task touches UI, styling, theming, or anything that references design tokens (colors, typography, spacing, radius, motion).

**HTML document export counts.** Producing a self-contained HTML version of a document (see `references/html-export.md`) is a styling task — its stylesheet references design tokens — so `DESIGN.md` governs the export's colors and typography.

If both conditions hold, this rule overrides any local guess about design tokens. If `DESIGN.md` is absent, see [Absence](#absence) below.

---

## Location

`DESIGN.md` lives at the repo root. If the root has none, look for the spec elsewhere before inventing tokens: a `DESIGN.md` in another folder, or a Markdown file in DESIGN.md format under another name — YAML design tokens such as `colors:` and `typography:`, often `docs/*design*.md`.

- **Any spec found outside the root, even just one** → name each one and ask which, if any, governs the UI you are changing. Do not decide from its folder or name; only the developer knows what a file covers. The file they confirm is the spec for this task.
- **Then suggest a home:** a spec that covers the whole repo belongs at the root as `DESIGN.md`, so the next task does not need to ask. A package's own spec stays in its package, because a root file would govern every package.
- **Nothing found** → see [Absence](#absence).

A spec in a `brand-workshop` output folder is a draft the founder has not adopted yet — say so when you ask.

---

## Authority

When `DESIGN.md` exists at repo root — or a spec was found per [Location](#location) — its YAML front matter IS the canonical design contract. Treat its tokens — colors (hex, sRGB only), typography, spacing, rounded values, components — as authoritative.

- **DO NOT** invent alternative tokens, palettes, or scales when generating UI.
- **DO NOT** silently override a token because the surrounding code uses a different value — flag the drift instead (see [Conflict Resolution](#conflict-resolution)).
- The markdown body explains *why* the tokens are what they are. Read it before generating UI; cite it when explaining design choices to the developer.

---

## Design skills

When design skills work on a UI task, split the work by job. Only one skill changes a given surface.

| Job | Current default | Rule |
|---|---|---|
| Make the change | `impeccable` (`document` writes the spec from existing code; then `critique` → `polish`) | The only skill that edits this surface |
| Check direction | `taste-skill`, read-only (`inspect.mjs --app`, `lint.mjs`) | Measures and reports; does not edit the surface |
| Check signal colors | the `dataviz` skill's palette validator, read-only; without it, any color-blind simulation that reports a color difference (ΔE) | Only when the work touches colors. Check the status and accent colors as one set (for example accent, ok, warn, bad, new) in light and dark. A pair a color-blind reader cannot tell apart goes back to the author as a finding, even when icons and words also carry the meaning |
| Verify the render | `screenwright`'s read-only **mode V** (verify-only): axe in light and dark, screenshots at desktop and phone width, the 320px reflow pass, print | After the last edit; a read-only check may follow. Mode V never edits — findings go back to the author. Its other modes paint and fix, so they are not the verifier. 0 axe violations is necessary, not sufficient |

- Give the skill the spec's path explicitly. Most design skills look only for a root `DESIGN.md`.
- When a skill's house rule conflicts with the developer's explicit ask, the developer wins. A token change goes into the spec in the same commit as the code.
- The table names jobs; the skill names are today's picks. If a default is not installed, use what is, and keep the same split.

*Source: job-scout design-skill comparison, 2026-10-20 — four skills on one brief; none found a spec that was not a root `DESIGN.md`, and axe passed every variant. The `dataviz` validator then caught a warn/bad pair at ΔE 0.6 for deutan readers that every other check had passed.*

---

## Editing Safety

When asked to edit `DESIGN.md`:

- **Never strip the YAML front matter.** It is the cross-plugin contract — downstream skills (e.g., `validation-canvas`, `riskiest-assumption-test`, `pitch-deck`) parse it directly.
- Edit prose freely. The markdown body explains the *why* and tolerates iteration.
- For token changes, surface a diff and confirm with the developer before writing.
- Preserve the canonical section order: Overview → Colors → Typography → Layout → Shapes → Do's and Don'ts → Voice. Custom sections are allowed and appear after Voice (preserved by spec-compliant consumers under the spec's "unknown section" rule).
- If a spec linter is available, run it after the edit:
  ```bash
  npx @google/design.md lint <spec path>   # e.g. DESIGN.md or docs/report-design.md
  ```

This file is in the same category as `references/guardrails.md` → "Overwrite guideline/spec files" — read-only for unrelated tasks; edits require explicit instruction and a confirmed diff.

---

## Conflict Resolution

If the project also has downstream theme configs, `DESIGN.md` is the single source of truth. Common downstream targets:

- `tailwind.config.{ts,js}` — Tailwind theme tokens
- `components.json` + `app/globals.css` — shadcn/ui tokens
- `theme.ts` / `tokens.ts` / CSS-in-JS theme files (Stitches, Emotion, vanilla-extract, Panda) — or similar

Behavior on drift:

1. Detect drift between `DESIGN.md` tokens and downstream files.
2. Flag the divergence — name which token diverges where.
3. Offer to regenerate the downstream from `DESIGN.md`. The spec ships an `export` command; prefer it over hand-rewriting:
   ```bash
   npx @google/design.md export <spec path> --format tailwind > tailwind.theme.js
   npx @google/design.md export <spec path> --format dtcg > tokens.json
   ```
4. Do not rewrite downstream files silently. The developer chooses whether to regenerate.

---

## Absence

If no spec exists — none at the repo root and none found per [Location](#location) — fall back to existing project conventions in this order:

1. Tailwind config (`tailwind.config.{ts,js}`)
2. CSS-in-JS theme or a `design-system/` / `tokens/` directory
3. shadcn `components.json` + `globals.css`
4. Figma exports referenced in the README

**Do not synthesize design tokens** unless the developer explicitly asks. If they want a spec, use the first tool that is installed:

- **A new UI with nothing to keep** → `brand-workshop` (a starter `DESIGN.md`) → `impeccable document` (seed mode) → neither installed: ask the developer, and suggest installing `impeccable`.
- **An existing UI** → `impeccable document` (scan mode records the tokens already in the code) → not installed: ask the developer, and suggest installing it. Not `brand-workshop`: it declines to document a brand that already exists.

If your platform has its own built-in way to write a `DESIGN.md`, you may suggest it alongside.

---

## Spec Version

The DESIGN.md spec is at `alpha` (current as of 2026-05). Schema may break before a non-alpha tag. Re-check the [spec repo](https://github.com/google-labs-code/design.md) when:

- The agent encounters a `DESIGN.md` whose front matter contains keys this rule doesn't recognize, or
- The spec repo tags a non-alpha version.

---

## See Also

- [DESIGN.md spec — google-labs-code](https://github.com/google-labs-code/design.md) — canonical schema and `export` command.
- [Stitch — design-md docs](https://stitch.withgoogle.com/docs/design-md/overview) — Google's reference implementation context.
- `references/external-resources.md` → `awesome-design-md` — 59 curated brand specs (Stripe, Linear, Notion, BMW…) usable as reference corpus or starting templates.
- `references/external-resources.md` → `impeccable`, `taste-skill`, `screenwright` — the current defaults in § Design skills.
- `agent-skills:brand-workshop` (upstream producer) — emits a starter `DESIGN.md` as part of a brand-identity package; the founder moves it to repo root when adopting.
- `references/html-export.md` — opt-in self-contained HTML document export; consumes `DESIGN.md` tokens for its stylesheet when present.
