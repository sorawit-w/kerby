#!/usr/bin/env python3
"""Validate a kerby rulebook against manifest contract v1.

Ships inside the skill bundle (resources/scripts/) so the load flow can
invoke it wherever the skill is installed — the repo-level scripts/ dir
does not travel with the plugin.

Usage:
    python3 <install-root>/resources/scripts/validate-rulebook.py <rulebook-dir> [options]

Options:
    --origin {builtin,local}   Trust origin (default: local)
    --builtin-root PATH        Directory holding builtin rulebooks, for
                               resolving `extends` (default: the repo's
                               skills/kerby/resources/rulebooks)
    --resources-root PATH      Root builtin declared paths may resolve
                               against (default: parent of --builtin-root)
    --config PATH              Optional user-config TOML ([gate] table) to
                               check against the floor (E06)
    --hash                     Print the sha256 over manifest + declared
                               files and exit (no validation output)

Exit codes: 0 = valid (warnings allowed), 1 = invalid.
Fail-closed: a crash or an unreadable declared file is invalid, never a pass.

Stdlib only (tomllib requires Python >= 3.11). Two modes, one logic: run
standalone this is advisory; invoked by the `load` flow it is authoritative —
an advisory pass is never a trust grant.

Error catalog E01-E12: docs/rulebook-contract.md. Messages are literal and
fix-forward (VOICE.md zoning).
"""

import argparse
import hashlib
import re
import sys
import tomllib
from pathlib import Path

CONTRACT_SUPPORTED = (1,)
# A rulebook id is a bare slug — never a path. This is the gate that keeps an
# `extends` entry from resolving outside builtin_root (e.g. "/tmp/evil", "../x").
RULEBOOK_ID_RE = re.compile(r"^[a-z0-9]+(-[a-z0-9]+)*$")
KINDS = {"data", "code", "prose"}
ENFORCEMENTS = {"hard", "partial", "behavioral"}
SEVERITIES = {"block", "warn", "info"}
RUNNERS = {"gitleaks", "semgrep", "regex-floor"}  # built-in data-runner ids (docs/rulebook-contract.md)
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


def default_builtin_root() -> Path:
    # this script lives at <resources>/scripts/; builtins at <resources>/rulebooks/
    return Path(__file__).resolve().parent.parent / "rulebooks"


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


def check_fields(check: dict, idx: int, res: Result) -> str:
    cid = check.get("id", f"<check #{idx + 1}>")
    if "id" in check and not isinstance(check["id"], str):
        res.error("E02", f"check #{idx + 1}: 'id' must be a string, got {type(check['id']).__name__}")
        cid = f"<check #{idx + 1}>"  # don't propagate a non-string id into later id-uniqueness/status logic
    for field in CHECK_REQUIRED:
        if field not in check:
            res.error("E02", f"check '{cid}': missing required field '{field}'")
    kind = check.get("kind")
    if kind is not None and kind not in KINDS:
        res.error("E02", f"check '{cid}': kind '{kind}' is not one of data, code, prose")
    sev = check.get("severity")
    if sev is not None and sev not in SEVERITIES:
        res.error("E02", f"check '{cid}': severity '{sev}' is not one of block, warn, info")
    tc = check.get("token_cost")
    if tc is not None and tc not in TOKEN_COSTS:
        res.error("E02", f"check '{cid}': token_cost '{tc}' is not one of low, medium, high")

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
    if enf is not None and enf not in ENFORCEMENTS:
        res.error("E09", f"check '{cid}': enforcement '{enf}' is not one of hard, partial, behavioral")
    if enf in ("hard", "partial") and "enforcer" not in check:
        res.error("E09", f"check '{cid}': enforcement '{enf}' requires an enforcer")
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


def resolve_declared(path_str: str, root: Path, origin: str, resources_root: Path | None, cid: str, res: Result) -> Path | None:
    p = Path(path_str)
    if origin != "builtin":
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
        candidates = [resolved]
    else:
        candidates = [(root / p).resolve()]
        if resources_root is not None:
            candidates.append((resources_root / p).resolve())
    for c in candidates:
        if c.is_file():
            try:
                with open(c, "rb"):
                    pass
            except OSError:
                res.error("E04", f"check '{cid}': declared path '{path_str}' exists but is unreadable — fix its permissions")
                return None
            return c
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


def merge_and_check(data: dict, root: Path, origin: str, builtin_root: Path, resources_root: Path, config_gate: dict | None, res: Result) -> list[Path]:
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
        for c in pack_data.get("check", []):
            if isinstance(c, dict) and "id" in c:
                prior = merged_src.get(c["id"])
                if prior is not None and prior != pack_id:
                    res.error("E07", f"check id '{c['id']}' declared by two extended packs ('{prior}', '{pack_id}'); a pack cannot silently overwrite another pack's check")
                    continue
                merged[c["id"]] = c
                merged_src[c["id"]] = pack_id

    accepts = data.get("accepts", ["*"])
    if not isinstance(accepts, list):
        accepts = ["*"]
    declared_files: list[Path] = []
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
        if cid in merged and override_of != cid:
            res.error("E07", f"duplicate check id '{cid}' (also in an extended pack); use override_of or rename")
        if override_of is not None:
            target = merged.get(override_of)
            if target is None:
                res.error("E05", f"check '{cid}': override_of targets unknown check '{override_of}'")
            elif target.get("floor") is True:
                res.error("E05", f"check '{cid}': cannot override a floor check ('{override_of}')")

        for field in ("config", "entry", "body", "enforcer"):
            if field in check:
                if not isinstance(check[field], str):
                    res.error("E02", f"check '{cid}': '{field}' must be a path string")
                    continue
                resolved = resolve_declared(check[field], root, origin, resources_root, cid, res)
                if resolved is not None:
                    declared_files.append(resolved)
                    if field == "body" and origin != "builtin":
                        lint_prose(resolved, cid, res)
        merged[cid] = check

    # E06 — gate floors: every floor check's severity must stay blocking
    for gate_name, gate in (("[gate]", data.get("gate")), ("config", config_gate)):
        if gate is None:
            continue
        block_on = gate.get("block_on")
        if block_on is None:
            continue
        if not isinstance(block_on, list):
            res.error("E02", f"{gate_name}: 'block_on' must be an array of severities")
            continue
        for c in merged.values():
            if c.get("floor") is True and c.get("severity") == "block" and "block" not in block_on:
                res.error("E06", f"{gate_name} lowers '{c.get('id')}' below the base floor; floors are non-overridable")
    return declared_files


def lint_prose(path: Path, cid: str, res: Result):
    try:
        text = path.read_text(encoding="utf-8", errors="replace").lower()
    except OSError:
        res.error("E04", f"check '{cid}': prose body '{path.name}' is unreadable — fix its permissions")
        return
    for pattern in INJECTION_PATTERNS:
        if pattern in text:
            res.warn("E11", f"check '{cid}': prose body contains instruction-override pattern ('{pattern}'); review before trusting")


def compute_hash(root: Path, declared: list[Path]) -> str:
    """sha256 over the manifest plus every declared file, in declared-path
    order — a manifest-only hash would let a declared body mutate silently."""
    h = hashlib.sha256()
    for f in [root / "rulebook.toml"] + sorted(set(declared)):
        h.update(f.read_bytes())
    return h.hexdigest()


def validate(root: Path, origin: str, builtin_root: Path, resources_root: Path, config_path: Path | None) -> tuple[Result, list[Path]]:
    res = Result()
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
    declared = merge_and_check(data, root, origin, builtin_root, resources_root, config_gate, res)
    return res, declared


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("rulebook_dir", type=Path)
    ap.add_argument("--origin", choices=("builtin", "local"), default="local")
    ap.add_argument("--builtin-root", type=Path, default=None)
    ap.add_argument("--resources-root", type=Path, default=None)
    ap.add_argument("--config", type=Path, default=None)
    ap.add_argument("--hash", action="store_true")
    args = ap.parse_args()

    root = args.rulebook_dir
    builtin_root = args.builtin_root or default_builtin_root()
    resources_root = args.resources_root or builtin_root.parent

    res, declared = validate(root, args.origin, builtin_root, resources_root, args.config)

    if args.hash:
        if res.errors:
            for e in res.errors:
                print(e, file=sys.stderr)
            print("invalid: refusing to hash an invalid rulebook (fail-closed)", file=sys.stderr)
            return 1
        print(compute_hash(root, declared))
        return 0

    for w in res.warnings:
        print(w)
    if res.errors:
        for e in res.errors:
            print(e)
        print(f"invalid: {root} — {len(res.errors)} error(s), {len(res.warnings)} warning(s)")
        return 1
    print(f"ok: {root} — contract 1, {len(res.warnings)} warning(s)")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:  # fail-closed: a validator crash is never a pass (D11)
        print(f"invalid: validator error (fail-closed): {type(e).__name__}: {e}", file=sys.stderr)
        sys.exit(1)
