#!/usr/bin/env python3
"""Validate a kerby rulebook against manifest contract v2.

Ships inside the skill bundle (resources/scripts/) so the load flow can
invoke it wherever the skill is installed — the repo-level scripts/ dir
does not travel with the plugin.

Usage:
    python3 <install-root>/resources/scripts/validate-rulebook.py <rulebook-dir> [options]

Options:
    --origin {builtin,local}   Trust origin (default: local)
    --builtin-root PATH        Directory holding builtin rulebooks, for
                               resolving `extends` (default: the repo's
                               skills/kerby/rulebooks)
    --config PATH              Optional user-config TOML ([gate] table) to
                               check against the floor (E06)
    --hash                     Print the sha256 over manifest + declared
                               files and exit (no validation output)

Exit codes: 0 = valid (warnings allowed), 1 = invalid.
Fail-closed: a crash or an unreadable declared file is invalid, never a pass.

Stdlib only (tomllib requires Python >= 3.11). Two modes, one logic: run
standalone this is advisory; invoked by the `load` flow it is authoritative —
an advisory pass is never a trust grant.

Error catalog E01-E14: docs/rulebook-contract.md. Messages are literal and
fix-forward (VOICE.md zoning).
"""

import argparse
import hashlib
import re
import sys
import tomllib
from pathlib import Path

CONTRACT_SUPPORTED = (2,)
# A rulebook id is a bare slug — never a path. This is the gate that keeps an
# `extends` entry from resolving outside builtin_root (e.g. "/tmp/evil", "../x").
RULEBOOK_ID_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
KINDS = {"data", "code", "prose"}
ENFORCEMENTS = {"hard", "partial", "behavioral"}
SEVERITIES = {"block", "warn", "info"}
RUNNERS = {"gitleaks", "semgrep", "regex-floor"}  # built-in data-runner ids (docs/rulebook-contract.md)
DEFAULT_BLOCK_ON = ["block"]  # contract default when a manifest omits [gate].block_on
TOKEN_COSTS = {"low", "medium", "high"}
VIEWS_BY_SUBJECT = {
    "git_change": {
        "changed_files", "changed_content", "staged_content", "added_lines",
        "commit", "branch", "install_state", "repo_tree",
    },
}
ALL_VIEWS = set().union(*VIEWS_BY_SUBJECT.values())
INJECTION_PATTERNS = ("ignore previous", "you must now", "disregard the above")
CHECK_REQUIRED = ("id", "kind", "enforcement", "severity")
TOP_REQUIRED = ("id", "version", "contract", "accepts")
# Engine command names a rulebook may never declare or shadow (V16). Includes
# grammar tokens (`list`, `create`) and `help` (reserved-only at v7).
RESERVED_COMMANDS = {"load", "unload", "reload", "status", "install", "uninstall",
                     "rulebooks", "list", "create", "help"}
# Claude Code lifecycle events install can register hooks for. Unknown events
# warn rather than fail — the harness may add events faster than this list.
KNOWN_EVENTS = {"PreToolUse", "PostToolUse", "SessionStart", "SessionEnd", "Stop",
                "UserPromptSubmit", "Notification", "SubagentStop", "PreCompact"}


def default_builtin_root() -> Path:
    # this script lives at <install-root>/resources/scripts/; builtins at
    # <install-root>/rulebooks/ (v7 self-contained layout)
    return Path(__file__).resolve().parent.parent.parent / "rulebooks"


class Result:
    def __init__(self):
        self.errors: list[str] = []
        self.warnings: list[str] = []

    def error(self, code: str, msg: str):
        self.errors.append(f"{code}: {msg}")

    def warn(self, code: str, msg: str):
        self.warnings.append(f"warning {code}: {msg}")


def load_manifest(root: Path, res: Result) -> dict | None:
    manifest = root / "rulebook.toml"
    if not manifest.is_file():
        res.error("E01", f"rulebook.toml: not found in {root}")
        return None
    try:
        with open(manifest, "rb") as f:
            return tomllib.load(f)
    except tomllib.TOMLDecodeError as e:
        res.error("E01", f"rulebook.toml: parse error: {e}")
    except OSError as e:
        res.error("E01", f"rulebook.toml: unreadable: {e}")
    return None


def check_top_level(data: dict, res: Result):
    for field in TOP_REQUIRED:
        if field not in data:
            res.error("E02", f"manifest: missing required field '{field}'")
    if not isinstance(data.get("id", ""), str):
        res.error("E02", "manifest: 'id' must be a string")
    if not isinstance(data.get("version", ""), str):
        res.error("E02", "manifest: 'version' must be a string")
    contract = data.get("contract")
    if contract is not None and not isinstance(contract, int):
        res.error("E02", "manifest: 'contract' must be an integer")
    elif isinstance(contract, int) and contract not in CONTRACT_SUPPORTED:
        supported = ", ".join(str(c) for c in CONTRACT_SUPPORTED)
        res.error("E03", f"manifest targets contract {contract}; this engine supports {supported} — upgrade kerby or lower the manifest contract")
    accepts = data.get("accepts")
    if accepts is not None:
        if not isinstance(accepts, list) or not accepts or not all(isinstance(a, str) for a in accepts):
            res.error("E10", "manifest: 'accepts' must be a non-empty array of subject-type strings")
    desc = data.get("description")
    if desc is not None and not isinstance(desc, str):
        res.error("E02", "manifest: 'description' must be a string")


def check_commands(data: dict, root: Path, builtin_root: Path, res: Result, declared_files: list[Path]) -> None:
    """[[command]] — user-invocable rulebook commands (contract 2, V2/V16).
    E13 = name collisions (reserved engine names, builtin rulebook ids,
    duplicates within this rulebook); E14 = command shape. Bodies are declared
    files: they resolve folder-confined (E04) and enter the trust hash. Their
    E11 prose-injection lint is handled by the whole-folder pass
    (`lint_tree_prose`), so a command body — read as agent instructions at
    dispatch while the trust prompt shows only name/description — is linted like
    every other prose file, with no per-field special case to slip past."""
    commands = data.get("command")
    if commands is None:
        return
    if not isinstance(commands, list):
        res.error("E14", "manifest: [[command]] entries must be an array of tables")
        return
    builtin_ids = {p.name for p in builtin_root.iterdir() if p.is_dir()} if builtin_root.is_dir() else set()
    seen: set[str] = set()
    for idx, cmd in enumerate(commands):
        label = f"command #{idx + 1}"
        if not isinstance(cmd, dict):
            res.error("E14", f"{label}: must be a table")
            continue
        name = cmd.get("name")
        if not isinstance(name, str) or not RULEBOOK_ID_RE.match(name):
            res.error("E14", f"{label}: 'name' must be a lowercase slug string (a dispatch token)")
            continue
        label = f"command '{name}'"
        if name in RESERVED_COMMANDS:
            res.error("E13", f"{label}: collides with a reserved engine command — rulebooks may never declare or shadow {sorted(RESERVED_COMMANDS)}")
        if name in builtin_ids:
            res.error("E13", f"{label}: collides with the builtin rulebook id '{name}' — rulebook ids shadow command names in dispatch")
        if name in seen:
            res.error("E13", f"duplicate command name '{name}' within this rulebook; rename one")
        seen.add(name)
        body = cmd.get("body")
        if not isinstance(body, str):
            res.error("E14", f"{label}: 'body' must be a path string (the instruction file read at invocation)")
        else:
            resolved = resolve_declared(body, root, label, res)
            if resolved is not None:
                declared_files.append(resolved)
        cdesc = cmd.get("description")
        if not isinstance(cdesc, str) or not cdesc.strip():
            res.error("E14", f"{label}: 'description' must be a non-empty string (shown in dispatch listings and the trust prompt)")


def check_fields(check: dict, idx: int, res: Result) -> str:
    cid = check.get("id", f"<check #{idx + 1}>")
    if "id" in check and not isinstance(check["id"], str):
        res.error("E02", f"check #{idx + 1}: 'id' must be a string, got {type(check['id']).__name__}")
        cid = f"<check #{idx + 1}>"  # don't propagate a non-string id into later id-uniqueness/status logic
    for field in CHECK_REQUIRED:
        if field not in check:
            res.error("E02", f"check '{cid}': missing required field '{field}'")
    # Enum fields: guard with isinstance BEFORE the set-membership test. A TOML
    # array/table value is an unhashable list/dict, so a bare `x not in SET`
    # raises TypeError and — because load treats a validator crash as HELD —
    # turns an author typo into a generic fail-closed crash instead of the
    # actionable E02 message. `not isinstance(x, str)` short-circuits the `or`,
    # so the membership test never sees a non-string.
    kind = check.get("kind")
    if kind is not None and (not isinstance(kind, str) or kind not in KINDS):
        res.error("E02", f"check '{cid}': kind '{kind}' is not one of data, code, prose")
    sev = check.get("severity")
    if sev is not None and (not isinstance(sev, str) or sev not in SEVERITIES):
        res.error("E02", f"check '{cid}': severity '{sev}' is not one of block, warn, info")
    tc = check.get("token_cost")
    if tc is not None and (not isinstance(tc, str) or tc not in TOKEN_COSTS):
        res.error("E02", f"check '{cid}': token_cost '{tc}' is not one of low, medium, high")

    # 'floor' must be a real TOML boolean. Everything downstream tests
    # `floor is True`, so a mistyped `floor = "true"` (string) or `floor = 1`
    # would silently read as non-floor — E05 (no override), E06 (must block)
    # and eager floor-loading would all stop protecting it, quietly making a
    # non-overridable base/code rule overridable. Reject the bad type here.
    if "floor" in check and not isinstance(check["floor"], bool):
        res.error("E02", f"check '{cid}': 'floor' must be a boolean (true/false), not {type(check['floor']).__name__}")

    # E08 kind/field coherence
    if kind == "data":
        runner = check.get("runner")
        if runner is None:
            res.error("E08", f"check '{cid}': kind 'data' requires a 'runner'")
        elif not isinstance(runner, str):
            res.error("E08", f"check '{cid}': 'runner' must be a string built-in runner id, one of {sorted(RUNNERS)}")
        elif runner not in RUNNERS:
            res.error("E08", f"check '{cid}': unknown runner '{runner}'; must be one of {sorted(RUNNERS)}")
    if kind == "code" and not ("entry" in check or "enforcer" in check):
        res.error("E08", f"check '{cid}': kind 'code' requires 'entry' or 'enforcer'")
    if kind == "prose":
        if "body" not in check:
            res.error("E08", f"check '{cid}': kind 'prose' requires a 'body'")
        if "needs" in check:
            res.error("E08", f"check '{cid}': kind 'prose' does not take 'needs' — prose loads as context rules, not executions")

    # E09 enforcement coherence
    enf = check.get("enforcement")
    if enf is not None and (not isinstance(enf, str) or enf not in ENFORCEMENTS):
        res.error("E09", f"check '{cid}': enforcement '{enf}' is not one of hard, partial, behavioral")
    if enf in ("hard", "partial") and "enforcer" not in check:
        res.error("E09", f"check '{cid}': enforcement '{enf}' requires an enforcer")
    # event/matcher: how install derives the hook registration for this
    # check's enforcer (Phase C derivation). Optional; required only to be
    # well-shaped when present, and an enforcer without them cannot be
    # auto-registered (E09 warns so authors find out at validate time).
    ev, ma = check.get("event"), check.get("matcher")
    if ev is not None and (not isinstance(ev, str) or not ev.strip()):
        res.error("E02", f"check '{cid}': 'event' must be a non-empty string (a Claude Code lifecycle event)")
    elif isinstance(ev, str) and ev not in KNOWN_EVENTS:
        res.warn("E02", f"check '{cid}': event '{ev}' is not a known lifecycle event ({', '.join(sorted(KNOWN_EVENTS))}) — registered as declared")
    if ma is not None and not isinstance(ma, str):
        res.error("E02", f"check '{cid}': 'matcher' must be a string (tool-name pattern; empty = all)")
    if "enforcer" in check and ev is None:
        res.warn("E09", f"check '{cid}': enforcer declared without 'event' — install cannot auto-register this hook until the manifest declares its trigger")
    if enf == "partial" and "gap" not in check:
        res.warn("E09", f"check '{cid}': enforcement 'partial' should name its 'gap'")
    return cid


def check_needs(check: dict, accepts: list, res: Result):
    cid = check.get("id", "?")
    needs = check.get("needs")
    if needs is None:
        return
    if not isinstance(needs, list) or not all(isinstance(n, str) for n in needs):
        res.error("E02", f"check '{cid}': 'needs' must be an array of view-name strings")
        return
    for n in needs:
        if n not in ALL_VIEWS:
            res.error("E10", f"check '{cid}' needs unknown view '{n}'; known views: {', '.join(sorted(ALL_VIEWS))}")
    if "*" in accepts:
        return  # any known view is declarable; unsatisfiable needs skip at runtime
    concrete = [a for a in accepts if a in VIEWS_BY_SUBJECT]
    satisfiable = any(set(needs) <= VIEWS_BY_SUBJECT[a] for a in concrete)
    if needs and not satisfiable:
        res.error("E10", f"check '{cid}' needs views {needs} but rulebook accepts only {accepts}")


def resolve_declared(path_str: str, root: Path, cid: str, res: Result) -> Path | None:
    """Uniform folder confinement (contract 2): every rulebook's declared paths
    resolve inside its own folder, regardless of origin. The v6 builtin
    resources-root exemption is gone — self-contained rulebooks made it
    unnecessary, and it was the special case the trust model had to defend."""
    p = Path(path_str)
    if p.is_absolute() or ".." in p.parts:
        res.error("E04", f"check '{cid}': declared path '{path_str}' escapes the rulebook root; move the file inside the folder")
        return None
    resolved = (root / p).resolve()
    try:
        inside = resolved.is_relative_to(root.resolve())
    except AttributeError:  # < py3.9, unreachable given tomllib gate
        inside = str(resolved).startswith(str(root.resolve()))
    if not inside:  # symlink escape
        res.error("E04", f"check '{cid}': declared path '{path_str}' escapes the rulebook root via a symlink; move the file inside the folder")
        return None
    if resolved.is_file():
        try:
            with open(resolved, "rb"):
                pass
        except OSError:
            res.error("E04", f"check '{cid}': declared path '{path_str}' exists but is unreadable — fix its permissions")
            return None
        return resolved
    res.error("E04", f"check '{cid}': declared path '{path_str}' does not exist")
    return None


def check_detect(data: dict, origin: str, res: Result):
    detect = data.get("detect")
    if detect is None:
        return
    markers = detect.get("markers")
    if not isinstance(markers, list) or not markers or not all(isinstance(m, str) for m in markers):
        res.error("E12", "[detect]: 'markers' must be a non-empty array of string globs")
        return
    if origin != "builtin":
        res.warn("E12", f"[detect]: declared by a {origin} rulebook — ignored; auto-selection is builtin-only")


def resolve_check_files(check: dict, cid: str, root: Path, res: Result, out: list[Path]) -> None:
    """Resolve a check's declared files (config/entry/body/enforcer), append each
    resolved path to `out` (so it enters the hash and E04 covers its existence /
    readability). Shared by a rulebook's own checks and the checks it composes
    from an extended pack — the composed floor must be file-validated too, or a
    damaged install could pass through a selected rulebook that merely extends
    it. Prose-injection (E11) linting is a separate whole-folder pass
    (`lint_tree_prose`), not per-declared-body — so it can't be dodged by moving
    a payload into a declared non-body file or an undeclared reference."""
    for field in ("config", "entry", "body", "enforcer"):
        if field in check:
            if not isinstance(check[field], str):
                res.error("E02", f"check '{cid}': '{field}' must be a path string")
                continue
            resolved = resolve_declared(check[field], root, cid, res)
            if resolved is not None:
                out.append(resolved)


def merge_and_check(data: dict, root: Path, origin: str, builtin_root: Path, config_gate: dict | None, res: Result) -> list[Path]:
    """Merge with extended packs (base implicit), run E04-E07, E10, E11.

    Returns the list of resolved declared files (for hashing)."""
    rid = data.get("id", "?")
    extends = data.get("extends", [])
    if not isinstance(extends, list) or not all(isinstance(e, str) for e in extends):
        res.error("E02", "manifest: 'extends' must be an array of rulebook ids")
        extends = []
    # merge rule 1: base is implicit-mandatory. Only the real builtin base
    # rulebook is exempt from merging itself — `id` is untrusted manifest
    # data for any non-builtin origin, so a local/remote rulebook claiming
    # id="base" must not skip the floor merge (that would let it bypass
    # every non-overridable check by simply naming itself "base").
    is_real_base = origin == "builtin" and rid == "base"
    if not is_real_base and "base" not in extends:
        extends = ["base"] + extends

    merged: dict[str, dict] = {}  # id -> check (extended packs first)
    merged_src: dict[str, str] = {}  # check id -> pack it came from
    declared_files: list[Path] = []
    builtin_root_resolved = builtin_root.resolve()
    for pack_id in extends:
        # An `extends` entry must be a bare builtin id, never a path. Without
        # this gate `builtin_root / pack_id` resolves outside the trusted root
        # for an absolute ("/tmp/evil" — pathlib drops the left side) or `..`
        # entry, letting an untrusted local rulebook pull in an attacker pack
        # that redeclares a floor check (e.g. secrets-staged, floor=false) and
        # silently strips the non-overridable base floor before E05/E07 run.
        if not RULEBOOK_ID_RE.match(pack_id):
            res.error("E04", f"extends '{pack_id}': not a valid rulebook id — 'extends' takes bare builtin ids, not paths")
            continue
        pack_root = (builtin_root / pack_id).resolve()
        try:
            inside = pack_root.is_relative_to(builtin_root_resolved)
        except AttributeError:  # < py3.9, unreachable given tomllib gate
            inside = str(pack_root).startswith(str(builtin_root_resolved))
        if not inside:  # symlink escape
            res.error("E04", f"extends '{pack_id}': resolves outside the builtin rulebook root — only builtin packs may be extended")
            continue
        pack_res = Result()
        pack_data = load_manifest(pack_root, pack_res)
        if pack_data is None:
            res.error("E04", f"extends '{pack_id}': cannot load {pack_root / 'rulebook.toml'} — fail-closed")
            continue
        for pidx, c in enumerate(pack_data.get("check", [])):
            if isinstance(c, dict) and "id" in c:
                prior = merged_src.get(c["id"])
                if prior is not None and prior != pack_id:
                    res.error("E07", f"check id '{c['id']}' declared by two extended packs ('{prior}', '{pack_id}'); a pack cannot silently overwrite another pack's check")
                    continue
                # Validate the composed pack check and resolve its files too. For
                # a default `code` pin the implicit `base` is only ever validated
                # through this merge, so a damaged install — a missing or
                # unreadable base floor body — must fail here (E04), not pass as
                # a valid `code`. Packs are builtins (repo-relative resolution).
                pcid = check_fields(c, pidx, res)
                resolve_check_files(c, pcid, pack_root, res, declared_files)
                merged[c["id"]] = c
                merged_src[c["id"]] = pack_id

    accepts = data.get("accepts", ["*"])
    if not isinstance(accepts, list):
        accepts = ["*"]
    own_ids: set[str] = set()
    checks = data.get("check", [])
    if not isinstance(checks, list):
        res.error("E02", "manifest: [[check]] entries must be an array of tables")
        checks = []

    for idx, check in enumerate(checks):
        if not isinstance(check, dict):
            res.error("E02", f"check #{idx + 1}: must be a table")
            continue
        cid = check_fields(check, idx, res)
        check_needs(check, accepts, res)

        if cid in own_ids:
            res.error("E07", f"duplicate check id '{cid}' within this manifest; rename one")
        own_ids.add(cid)

        override_of = check.get("override_of")
        if override_of is not None and not isinstance(override_of, str):
            # override_of is matched against check ids (all strings) and used as
            # a dict key. A non-string fails closed (never matches → E05), but
            # flag the type explicitly rather than emit a confusing
            # "targets unknown check" for what is really an author type error.
            res.error("E02", f"check '{cid}': 'override_of' must be a check-id string, not {type(override_of).__name__}")
            override_of = None
        if cid in merged and override_of != cid:
            res.error("E07", f"duplicate check id '{cid}' (also in an extended pack); use override_of or rename")
        if override_of is not None:
            # override_of is how a same-id redeclaration is blessed (merge rule
            # 2): it must name THIS check's own id. If it names a different id,
            # the target is never removed — the new check is stored under its
            # own id and BOTH survive, so an author who typo'd the new id
            # (id="replacement", override_of="tunable-rule") silently keeps the
            # rule they meant to replace. Reject the mismatch.
            if override_of != cid:
                res.error("E05", f"check '{cid}': override_of '{override_of}' must equal this check's own id — override_of blesses a same-id replacement, it cannot rename or remove a different check")
            target = merged.get(override_of)
            if target is None:
                res.error("E05", f"check '{cid}': override_of targets unknown check '{override_of}'")
            elif target.get("floor") is True:
                res.error("E05", f"check '{cid}': cannot override a floor check ('{override_of}')")

        resolve_check_files(check, cid, root, res, declared_files)
        merged[cid] = check

    # Gate value types: in every gate source, block_on and hold_on must each be
    # an array of valid severity strings. hold_on drives the warn→HELD mapping;
    # the contract requires a severity array, but an unvalidated hold_on = "warn"
    # (string) or hold_on = [1] would be accepted and pinned, then misapplied by
    # gate/status consumers. block_on is additionally relied on by the E06
    # computation below.
    for src_name, src in (("[gate]", data.get("gate")), ("config", config_gate)):
        if src is None:
            continue
        for key in ("block_on", "hold_on"):
            vals = src.get(key)
            if vals is None:
                continue
            if not isinstance(vals, list) or not all(isinstance(v, str) for v in vals):
                res.error("E02", f"{src_name}: '{key}' must be an array of severity strings")
                continue
            bad = [v for v in vals if v not in SEVERITIES]
            if bad:
                res.error("E02", f"{src_name}: '{key}' has unknown severities {bad}; must be from block, warn, info")

    # E06 — gate floors: every floor check's severity must stay blocking under
    # the EFFECTIVE gate. Precedence: user config overrides the rulebook [gate]
    # overrides the contract default block_on = ["block"]. A missing [gate] or a
    # missing block_on key does NOT skip this check — the default still applies,
    # so a floor='warn' check with no [gate] must still fail (it would otherwise
    # validate yet map to HELD, not DENIED — a floor that doesn't block isn't a
    # floor). The old code both special-cased severity=='block' and skipped when
    # the key was absent.
    eff_block_on = None
    eff_src = "default gate (block_on = ['block'])"
    for src_name, src in (("config", config_gate), ("[gate]", data.get("gate"))):
        if src is None:
            continue
        bo = src.get("block_on")
        if bo is None:
            continue
        if not isinstance(bo, list):
            continue  # already reported by the gate-value validation above
        eff_block_on = bo
        eff_src = src_name
        break
    if eff_block_on is None:
        eff_block_on = DEFAULT_BLOCK_ON
    for c in merged.values():
        if c.get("floor") is True and c.get("severity") not in eff_block_on:
            res.error("E06", f"floor check '{c.get('id')}' has severity '{c.get('severity')}' not in the effective block_on {eff_block_on} ({eff_src}); floors must stay blocking and are non-overridable")
    return declared_files


def lint_prose(path: Path, label: str, res: Result):
    try:
        text = path.read_text(encoding="utf-8", errors="replace").lower()
    except OSError:
        res.error("E04", f"{label}: prose file '{path.name}' is unreadable — fix its permissions")
        return
    for pattern in INJECTION_PATTERNS:
        if pattern in text:
            res.warn("E11", f"{label}: prose contains an instruction-override pattern ('{pattern}'); review before trusting")


def lint_tree_prose(root: Path, origin: str, res: Result) -> None:
    """E11-lint EVERY markdown/text file under a non-builtin rulebook folder.

    The trust hash covers the whole folder, so the injection lint must span the
    same set — one whole-folder pass, not per-declared-body. A per-body lint is
    dodgeable by relocating an `ignore previous instructions` payload out of a
    declared prose body: into a command body, a declared *non-body* file (a data
    check's `config = "references/payload.md"`), or an undeclared reference a
    root/command body reads. All are files an approved rulebook can cause the
    agent to read as instructions, all are covered by the hash — so all are
    linted here, with no per-field or declared/undeclared distinction to slip
    through. Builtins are repo-trusted, so this is skipped there. The tree is
    already confined (no symlinks / `.git`) when this runs."""
    if origin == "builtin":
        return
    root_r = root.resolve()
    for f in root_r.rglob("*"):
        if (f.is_file() and not f.is_symlink()
                and f.suffix.lower() in (".md", ".markdown", ".txt")):
            lint_prose(f, f"file '{f.relative_to(root_r).as_posix()}'", res)


def compute_hash(root: Path) -> str:
    """sha256 over **every file in the rulebook folder**, each **framed** by its
    root-relative path and byte length, ordered by that path.

    Not just manifest-*declared* files. A rulebook's instructions dispatch to
    files the manifest never declares: BOOTSTRAP's reference index reads every
    `references/*.md`, command bodies read their `references/`/`workflows/`
    targets, workflows drive multi-step edits to user files. If the trust hash
    covered only declared files, those undeclared-but-behavior-bearing files
    would be a mutable-after-approval instruction channel — edit only
    `references/audit.md` (or a workflow) after the user approved a local/remote
    rulebook and the stored SHA still matches, so a later load skips the trust
    prompt while the command follows new, unapproved instructions (indirect
    prompt injection). Covering the whole folder closes that channel and removes
    any "is this file behavior-bearing?" classification an attacker could hide
    instructions behind. The cost: editing *any* file (a README included)
    re-triggers approval for a local/remote rulebook — the safe direction for
    untrusted content. Builtins are repo-versioned (`sha256: null`) and are
    never trust-gated by this hash, so their READMEs cost nothing.

    A bare byte-concatenation is ambiguous: an edit can move bytes across a file
    boundary while keeping the concatenated stream, and thus the hash,
    identical. Length-prefixing each file (and binding its path) commits the
    boundaries so any cross-file move changes the digest. Keys are root-relative
    (POSIX) so the hash is stable regardless of where the rulebook sits on disk.
    Symlinks and `.git/` are skipped here only defensively: `validate()` already
    **rejects** any rulebook that contains either (E04, `check_tree_confinement`)
    and `--hash` is fail-closed on validation errors, so a valid rulebook
    reaching this point has neither. The skips just stop the walk from following
    a symlinked directory or hashing stray VCS metadata if the hash is ever
    computed outside the validated path — they are not the security boundary
    (rejection is); a body-readable file under a *skipped* path would otherwise
    be a hash-blind channel, which is exactly why the skip must be paired with
    rejection, never left standing alone."""
    root_r = root.resolve()
    entries: list[tuple[str, Path]] = []
    for f in root_r.rglob("*"):
        if f.is_symlink() or not f.is_file():
            continue
        rel = f.relative_to(root_r)
        if ".git" in rel.parts:
            continue
        entries.append((rel.as_posix(), f))
    h = hashlib.sha256()
    for key, fr in sorted(entries):
        data = fr.read_bytes()
        h.update(f"{key}\0{len(data)}\0".encode("utf-8"))
        h.update(data)
    return h.hexdigest()


def check_tree_confinement(root: Path, res: Result) -> None:
    """Reject symlinks and `.git/` anywhere under the rulebook folder (E04).

    A rulebook must be self-contained plain files, and every file under it must
    be covered by the trust hash. Two things break that if allowed:

    - **Symlinks.** A symlink either escapes (its target lives outside the
      folder — uncontrolled and mutable *without touching anything the hash
      frames*, so a body / BOOTSTRAP that reads it becomes a
      mutable-after-approval instruction channel) or is a redundant internal
      alias. Hashing it can't help: an outside target changes with the folder's
      bytes unchanged, and framing outside-root bytes would break confinement.

    - **`.git/`.** VCS metadata is not rulebook content, and `compute_hash`
      skips it — so a declared *or* body-referenced path under `.git/` (which
      `resolve_declared` otherwise accepts as in-folder) would be agent-readable
      yet dropped from the digest: edit `.git/rule.md` after approval and the
      SHA is unchanged. Remote clones already strip `.git/` at fetch; a local
      rulebook must be a clean content dir, not a live repo working tree.

    Rejecting both (rather than trying to hash them) is the only way to keep the
    hash's whole-folder guarantee honest. Builtins ship neither, so this is
    uniform across origins. Cheap top-level `.git` check first, so a large
    working-tree `.git` isn't walked before we reject it."""
    root_r = root.resolve()
    top_git = root_r / ".git"
    if top_git.exists() or top_git.is_symlink():
        res.error("E04", "'.git' present under the rulebook root — a rulebook must be a clean content folder, not a git working tree. VCS metadata is skipped by the trust hash, so content under it would be a hash-blind instruction channel. Remote clones strip .git at fetch; for a local rulebook, load a copy without .git.")
        return
    for f in root_r.rglob("*"):
        rel = f.relative_to(root_r)
        if ".git" in rel.parts:
            res.error("E04", f"'.git' path '{rel.as_posix()}' under the rulebook root — VCS metadata is not rulebook content and is hash-blind; remove it.")
            return
        if f.is_symlink():
            res.error("E04", f"symlink '{rel.as_posix()}' under the rulebook root — rulebooks must be self-contained plain files; a symlink escapes confinement or is a mutable-target instruction channel. Replace it with the real file.")


def validate(root: Path, origin: str, builtin_root: Path, config_path: Path | None) -> tuple[Result, list[Path]]:
    res = Result()
    # `origin` is a trust CLAIM, not a fact — in a cloned repo the lockfile that
    # supplies it is untrusted workspace content. `origin = "builtin"` grants
    # repo-relative path resolution (no confinement) and, in the load flow, skips
    # the approval prompt. So a builtin must actually LIVE in the installed
    # builtin root; otherwise an attacker could mark a workspace-local rulebook
    # `origin: "builtin"` and have untrusted prose validated as trusted builtin.
    # Anchor builtin-ness to the install location here as defense-in-depth (the
    # loader must also resolve builtins only from the install, never a lockfile
    # path — see SKILL.md).
    if origin == "builtin":
        try:
            inside = root.resolve().is_relative_to(builtin_root.resolve())
        except AttributeError:  # < py3.9, unreachable given tomllib gate
            inside = str(root.resolve()).startswith(str(builtin_root.resolve()))
        if not inside:
            res.error("E04", f"origin 'builtin' claimed for '{root}', which is not inside the installed builtin root '{builtin_root}' — builtins load only from the install, never a workspace path")
            return res, []
    check_tree_confinement(root, res)
    if res.errors:  # a symlink or `.git/` under the root is fail-closed — never hash/load it
        return res, []
    data = load_manifest(root, res)
    if data is None:
        return res, []
    check_top_level(data, res)
    check_detect(data, origin, res)
    config_gate = None
    if config_path is not None:
        try:
            with open(config_path, "rb") as f:
                config_gate = tomllib.load(f).get("gate")
        except (OSError, tomllib.TOMLDecodeError) as e:
            res.error("E01", f"config {config_path}: unreadable or unparseable: {e}")
    declared = merge_and_check(data, root, origin, builtin_root, config_gate, res)
    check_commands(data, root, builtin_root, res, declared)
    lint_tree_prose(root, origin, res)
    return res, declared


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("rulebook_dir", type=Path)
    ap.add_argument("--origin", choices=("builtin", "local"), default="local")
    ap.add_argument("--builtin-root", type=Path, default=None)
    ap.add_argument("--config", type=Path, default=None)
    ap.add_argument("--hash", action="store_true")
    args = ap.parse_args()

    root = args.rulebook_dir
    builtin_root = args.builtin_root or default_builtin_root()

    res, declared = validate(root, args.origin, builtin_root, args.config)

    if args.hash:
        if res.errors:
            for e in res.errors:
                print(e, file=sys.stderr)
            print("invalid: refusing to hash an invalid rulebook (fail-closed)", file=sys.stderr)
            return 1
        print(compute_hash(root))
        return 0

    for w in res.warnings:
        print(w)
    if res.errors:
        for e in res.errors:
            print(e)
        print(f"invalid: {root} — {len(res.errors)} error(s), {len(res.warnings)} warning(s)")
        return 1
    print(f"ok: {root} — contract {CONTRACT_SUPPORTED[-1]}, {len(res.warnings)} warning(s)")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # fail-closed: a validator crash is never a pass (D11)
        print(f"invalid: validator error (fail-closed): {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(1)
