<p align="center">
  <img src="assets/cerby-hero.png" alt="cerby — the gate guardian for agentic coding" width="280"/>
</p>

<h1 align="center">cerby</h1>

<p align="center"><em>The gate guardian for agentic coding — nothing unproven passes.</em></p>

---

`cerby` is a loadable **rule-corpus + opt-in guardrail hooks** that govern how an AI
coding agent works. It encodes one operating posture — *clarity over cleverness, safety
over speed, never leave the repo broken* — and stands at the gate: **GATE → WEIGH →
VERDICT**. A change arrives, cerby weighs it against the evidence, and nothing unproven
gets through (no claim without fresh tests, no commit on a protected branch, no secret in
the diff).

It is a **meta-system**: it shapes how ordinary coding tasks are done rather than doing a
task itself. Load it at the start of a session, install per-project hooks for mechanical
enforcement, prepare an existing repo, or audit a repo's conformance to the rules.

> Formerly shipped as `coding-rules` in
> [`sorawit-w/agent-skills`](https://github.com/sorawit-w/agent-skills); extracted here
> with full history. **Invoke `cerby`, not `coding-rules`.**

## Install

```
/plugin marketplace add sorawit-w/cerby
/plugin install cerby@cerby
```

Or via the cross-platform CLI:

```
npx skills add sorawit-w/cerby
```

## Quick start

```
/cerby             # default: load the rules into the session
/cerby reload      # re-load after a context compaction
/cerby status      # check whether the rules are still active
/cerby install     # persistent per-project setup (guardrail hooks)
/cerby uninstall    # mirror — removes the managed hooks
/cerby prepare     # onboard an existing repo (populate .ai/ context)
/cerby audit       # conformance audit → HTML report
```

## Documentation

- **[`skills/cerby/README.md`](skills/cerby/README.md)** — full user guide: what it does,
  when to use it, the loader behavior, and the per-project install.
- **[`skills/cerby/SKILL.md`](skills/cerby/SKILL.md)** — the skill body (sub-command routing,
  install/uninstall mechanics).
- **[`skills/cerby/resources/BOOTSTRAP.md`](skills/cerby/resources/BOOTSTRAP.md)** — the
  rules themselves.
- **[`CLAUDE.md`](CLAUDE.md)** — the harness-engineering vocabulary cerby implements.

## Status

Current release: `4.21.0` — first release under the `cerby` name (extracted and renamed
from `coding-rules`; see [CHANGELOG.md](CHANGELOG.md)).

**Opinionated — read first.** These are one author's rules. Read
`skills/cerby/resources/BOOTSTRAP.md` end-to-end before adopting, and fork-and-edit rather
than file feature requests on rule content.

## License

MIT — see [LICENSE](LICENSE). Third-party attributions in [NOTICE](NOTICE).
