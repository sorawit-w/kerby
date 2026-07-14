# The Intent Gate on Behavior Changes

**Before any behavior-changing edit, establish what the intended behavior IS —
and write it down as one forced line in this exact shape:**

```
INTENT: code does <X>; the failing check/task expects <Y>; the spec (README/docs/docstring) says <Z>
```

Filling the `<Z>` slot requires actually opening the statement of intended
behavior — README, spec, docstring, comment, or type — not recalling it. If
behavior changed, the INTENT line appears verbatim in the final report; a
report that changed behavior without one skipped the gate.

**If X, Y, and Z do not all agree, do not edit yet — the disagreement is the
real finding.** A failing check has two possible culprits: the code or the
check itself. Surface the contradiction, say which side you trust and why,
and never silently make one side match another. The gate then clears on its
own: once the contradiction is surfaced and the authority order below names a
side you can act on, proceed — ask first only when it names none, or in the
no-spec case below.

**Authority order when they disagree:** an explicit user statement beats the
spec; the spec beats the tests; the tests beat current code behavior. A task
framing like "fix the code" or "make the tests pass" is NOT a statement of
intended behavior — it does not promote the tests above the spec, and it does
not prove the code is the broken part.

**When no spec source exists** (nothing to open for `<Z>`), write the slot as
`no spec found` — never fabricate one. Tests still outrank current code for a
low-stakes change, but with an empty `<Z>` a consequential change (pricing,
money, security, externally visible behavior) is a product decision, not a
mechanical fix: surface both readings and ask one pointed question instead of
editing.

The gate is cheap where it matters least (X, Y, Z visibly agree — one line,
move on) and decisive where it matters most: silently "fixing" correct code
to satisfy a wrong test is the failure this rule exists to prevent. Loop
bounds for the ensuing investigation live in `references/debugging.md`; what
counts as verification evidence lives in `references/validation.md` — this
rule adds the forced artifact, not a new loop.

**Source:** absorbed from `Sahir619/fable-method` (MIT, 2026-07-14) — the
intent-gate forced artifact and its authority order, whose eval measured the
rule as mid-list prose at 1/4 compliance and as a forced artifact at 4/4;
their orchestration loop deliberately NOT adopted (laney's domain).
