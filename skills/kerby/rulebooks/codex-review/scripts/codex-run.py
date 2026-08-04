#!/usr/bin/env python3
"""codex-run.py — run ONE headless Codex attempt under a wall-clock bound.

The mechanical form of references/delegation.md § Bounded delegation. This
script bounds ONE attempt and reports how it ended. It does not own the
2-attempt delegation budget, does not decide whether to retry, and never parses
a verdict — that is codex-mark.sh's grammar and must not fork.

Usage (normally reached through the codex-run.sh shim, which is what the
rulebook prose names):
    codex-run.sh [--ceiling <seconds>] [--log <path>] -- <command> [args...]
      --ceiling  whole seconds, 1..86400; default = 2x the observed-good median
      --log      transcript path; default $GIT_DIR/codex-review.log
      --         everything after it is an argv vector, executed verbatim
Then run codex-mark.sh to parse the verdict it left behind.

The command is an argv VECTOR, never a pipeline and never a shell string. That
is load-bearing: with `codex ... | tee log &` a shell's $! is TEE's pid, so a
timeout built on it kills tee and leaves codex running forever. That is the
failure this script exists to end.

Exit codes (0/1/2 are codex-mark's PASS/DENIED/HELD and must never be read
across the two scripts; 2 and 3 are therefore never emitted here):
    0 — exited on its own, status 0, inside the ceiling. Run codex-mark next.
    1 — usage or precondition error; nothing spawned, no transcript created.
    4 — STALL: alive at the ceiling; the group was killed AND reaped.
        At most one blind retry, then pr-workflow.md's step-4 fallback.
    5 — the runtime exited on its own, non-zero. Read the log, fix, retry once.
    6 — SURVIVOR: the group did not die within the grace+reap window after
        SIGKILL. Do NOT retry — a second attempt would run beside it. The lock
        is deliberately left behind so the next attempt refuses. Escalate.
  130 — HUP/INT/TERM delivered to this wrapper; the kill ladder ran.

WHY PYTHON. Five review rounds of the bash predecessor produced seven defects,
every one the same shape: the shell's process-inspection primitives (ps,
kill -0, kill, wait) each have a THIRD answer besides yes and no — "the query
failed" — and each guard that folded it into one of the other two produced
either an unbounded wait or a signal aimed at a process the wrapper never
started. proc.wait(timeout=...) on our own child has exactly two outcomes, an
integer status or TimeoutExpired, both bounded by construction. There is no
third answer here to misfold. That property, not brevity, is the entire case
for this file: it is not shorter than the shell version.

Consequently this script asks the operating system NOTHING about the child
except through waitpid. No ps, no kill -0, no getpgid. See kill_ladder().

Fail-closed: a usage error, an unresolvable runtime, an unusable log path, or a
lock held by another attempt exits 1 WITHOUT spawning anything — a half-started
attempt would leave a zero-byte transcript that codex-mark would then stat as
evidence.

Stdlib only; Python >= 3.6. Deliberately below validate-rulebook.py's 3.11
floor: nothing here needs tomllib, and this file runs on whatever machine the
user is on (docs/ENGINE-MAP.md: existing scripts stay version-agnostic).
"""

import datetime
import os
import re
import shutil
import signal
import subprocess
import sys
import time

PREFIX = "codex-run: "
GRACE_SECONDS = 5        # TERM -> KILL. Owed to the GROUP, not just its leader.
REAP_SECONDS = 10        # KILL -> waitpid. Exceeding this PROVES survival.
GIT_TIMEOUT = 10         # the shell version's $(git ...) was itself unbounded
DEFAULT_CEILING = 900    # delegation.md's 15 min cold start
CEILING_FLOOR = 300
CEILING_CAP = 3600
CEILING_MAX = 86400
MAX_CEILING_DIGITS = 6
MIN_SAMPLES = 3          # fewer than three numbers is not a median
DUR_RE = re.compile(rb"dur=([0-9]+)s")

USAGE = ("usage: codex-run.sh [--ceiling <seconds>] [--log <path>] "
         "-- <command> [args...]")


def say(msg):
    """The only writer of stdout. Every line carries the prefix."""
    sys.stdout.write(PREFIX + msg + "\n")


def emit(msg):
    """The only writer of stderr. Every line carries the prefix.

    The shell version needed a stderr-muffled brace group here, because bash
    asynchronously printed its own unprefixed job-control notice ("Killed: 9")
    when it reaped a killed job. Nothing but this function can write to fd 2
    now; the top-level guard in __main__ closes the last hole (a traceback).
    """
    sys.stderr.write(PREFIX + msg + "\n")


class Usage(Exception):
    """A precondition failure. Nothing has been spawned; exit 1."""


class Interrupted(Exception):
    """HUP/INT/TERM reached the wrapper. Deliberately an Exception, not a
    BaseException: it is caught explicitly and BEFORE the generic guard, and
    ordering handlers is a local reviewable fact where class-hierarchy games
    are not."""


def parse_args(argv):
    """Return (ceiling_text or None, log or None, command_list).

    Deliberately not argparse, for three reasons that are contract, not taste:
    argparse installs -h/--help (which must hit the unknown-option error here),
    it exits 2 on a parse failure (a RESERVED code), and it prints an
    unprefixed "usage:" block to stderr. Working around all three leaves a
    liability wearing a library's clothes.

    Flags may repeat; last wins. '--' is the only terminator. --ceiling and
    --log consume the next token verbatim whatever it is, so `--ceiling --`
    yields the value '--' and is then rejected as non-numeric — exactly as the
    shell version behaved.
    """
    ceiling = None
    log = None
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--ceiling":
            i += 1
            if i >= len(argv):
                raise Usage("--ceiling needs a value in whole seconds, "
                            "e.g. --ceiling 900")
            ceiling = argv[i]
        elif arg == "--log":
            i += 1
            if i >= len(argv):
                raise Usage("--log needs a path")
            log = argv[i]
        elif arg == "--":
            return ceiling, log, argv[i + 1:]
        else:
            raise Usage("unknown option '%s' — %s" % (arg, USAGE))
        i += 1
    return ceiling, log, []


def validate_ceiling(text):
    """Validate an explicit --ceiling BEFORE anything is spawned.

    re.fullmatch, never str.isdigit(): '\\u0663'.isdigit() is True and
    int('\\u0663') is 3, so a non-ASCII digit would sail through a naive port of
    the shell's *[!0-9]* guard.

    The digit-count check is retained from the shell version, where it was
    load-bearing (an overflowed value made the ceiling comparison fail as a
    non-integer inside a muffled block, spinning the loop with the watchdog
    silently off). Python ints do not overflow, so here it only preserves the
    message contract — cheap, and the two errors say different things.
    """
    if not re.fullmatch(r"[0-9]+", text):
        raise Usage("--ceiling takes whole seconds — pass a positive number "
                    "like --ceiling 900")
    if len(text) > MAX_CEILING_DIGITS:
        raise Usage("--ceiling out of range (max %d seconds) — pass a smaller "
                    "number like --ceiling 900" % CEILING_MAX)
    value = int(text, 10)   # base 10 explicitly, so '00' resolves to 0
    if not 1 <= value <= CEILING_MAX:
        raise Usage("--ceiling must be between 1 and %d seconds — pass a value "
                    "like --ceiling 900" % CEILING_MAX)
    return value


def compute_ceiling(audit_path):
    """2x the observed-good median from codex-mark's audit log.

    dur= appears only on codex-mark PASS lines, so the sample set is already
    "observed-good". `dur=?s` contains no digit and so is skipped by the regex
    with no special case — that is delegation.md's "ignoring ?" rule, for free.

    MEDIAN, not mean: this repo's own audit log carries one 85344s entry (a
    23.7-hour attempt) that drags a mean to 4.8 hours and the median not at all.
    Upper median (1-based n/2+1) so an even sample count needs no averaging,
    and erring generous is the safe direction for a threshold that kills things.
    """
    samples = []
    try:
        with open(audit_path, "rb") as fh:
            for line in fh:
                found = DUR_RE.search(line)
                if found:
                    samples.append(int(found.group(1)))
    except OSError:
        pass                        # no audit log yet is a cold start, not an error

    if len(samples) >= MIN_SAMPLES:
        samples.sort()
        ceiling = samples[len(samples) // 2] * 2
    else:
        ceiling = DEFAULT_CEILING

    # Floor: one 20s fluke would set a 40s ceiling that kills every real review.
    # Cap: a log that accumulates several hangs would compute a 47-hour
    # "ceiling" and the watchdog would quietly stop being one. Both bracket the
    # cold-start default. Applied ONLY here — an explicit --ceiling is never
    # clamped, because the operator asked for a specific number.
    return max(CEILING_FLOOR, min(CEILING_CAP, ceiling))


def git_dir():
    """Absolute $GIT_DIR, or raise Usage."""
    try:
        done = subprocess.run(["git", "rev-parse", "--git-dir"],
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                              timeout=GIT_TIMEOUT)
    except (OSError, subprocess.SubprocessError):
        raise Usage("not inside a git repo — run this from the repo whose "
                    "branch is under review")
    if done.returncode != 0:
        raise Usage("not inside a git repo — run this from the repo whose "
                    "branch is under review")
    return os.path.abspath(done.stdout.decode("utf-8", "replace").strip())


def git_short_head():
    """Short HEAD sha for the attempts log, or the literal '-'."""
    try:
        done = subprocess.run(["git", "rev-parse", "--short", "HEAD"],
                              stdout=subprocess.PIPE, stderr=subprocess.DEVNULL,
                              timeout=GIT_TIMEOUT)
        if done.returncode == 0:
            return done.stdout.decode("utf-8", "replace").strip() or "-"
    except (OSError, subprocess.SubprocessError):
        pass
    return "-"


class Lock:
    """Atomic mkdir claim on <log>.lock, released from exactly one place.

    Two overlapping attempts on the shared default transcript silently destroy
    each other's evidence: the second unlinks the first's inode, the first
    keeps writing to a file with no name, and the survivor holds half the
    story — while both report success. mkdir is the portable atomic
    test-and-set (no flock on macOS).
    """

    def __init__(self, log_path):
        self.log_path = log_path
        self.path = log_path + ".lock"
        self.held = False

    def acquire(self):
        # Optimistic: ownership is assumed BEFORE the syscall, so a signal
        # landing between mkdir returning and the flag being set cannot strand
        # the directory. The shell version set its flag after mkdir and had
        # exactly that window.
        self.held = True
        try:
            os.mkdir(self.path)
        except FileExistsError:
            self.held = False       # someone else's lock — never touch it
            raise Usage(
                "another attempt already owns %s (lock: %s) — wait for it to "
                "finish, or pass --log to a separate path. If nothing is "
                "running, remove that directory." % (self.log_path, self.path))
        except OSError as exc:
            self.held = False
            raise Usage("cannot create the lock at %s: %s — pass --log to a "
                        "writable path" % (self.path, exc))

    def disown(self):
        """Leave the lock directory in place on purpose (the survivor path)."""
        self.held = False

    def release(self):
        if not self.held:
            return                  # idempotent AND ownership-checked
        self.held = False           # cleared BEFORE the rmdir: no double-release
        try:
            os.rmdir(self.path)
        except OSError:
            pass


def install_signal_handlers():
    """Turn HUP/INT/TERM into Interrupted so the single try/finally cleans up.

    A second signal must not re-enter cleanup and skip the release, so the
    handler disarms itself first.
    """
    def handler(signum, _frame):
        for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
            signal.signal(sig, signal.SIG_IGN)
        raise Interrupted(signum)

    for sig in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
        signal.signal(sig, handler)


def spawn(cmd, log_path):
    """Create the transcript inode and exec the vector into its own session.

    O_EXCL, not truncation: codex-mark derives the audit dur= field from this
    file's filesystem BIRTH time, and truncating an existing file does NOT
    reset birth — so a never-marked leftover would make the next attempt's dur=
    span since the FIRST one. That is how a 23.7-hour dur= landed in an audit
    log full of two-minute reviews. The shell version removed the file and then
    re-checked; O_EXCL makes it a kernel guarantee instead of a two-step check.

    The parent closes its copy of the fd immediately and never write()s to that
    path on any path, so the transcript's mtime is the child's last write —
    which is what codex-mark compares against the HEAD commit time.

    start_new_session=True, NOT preexec_fn=os.setsid: preexec_fn runs Python
    bytecode between fork and exec and can deadlock on a lock held across the
    fork. Same setsid(2), on the async-signal-safe C path. It also guarantees
    pgid == pid, which is why os.getpgid() — itself a third-answer query — is
    never called anywhere in this file.

    stdin=DEVNULL is the documented deadlock, closed structurally: an open
    empty stdin makes the runtime wait forever on "Reading additional input
    from stdin...".
    """
    fd = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o666)
    try:
        return subprocess.Popen(cmd,
                                stdin=subprocess.DEVNULL,
                                stdout=fd,
                                stderr=subprocess.STDOUT,
                                start_new_session=True,
                                close_fds=True)
    finally:
        os.close(fd)


def signal_group(proc, sig):
    """Signal the child's process GROUP.

    Every exception is swallowed and NONE of them feeds a branch in the caller.
    That is the whole discipline of this file: killpg is a request, never an
    oracle. ProcessLookupError means the group is already empty; PermissionError
    means it exists and we may not signal it. Neither is a fact we are allowed
    to act on — only waitpid gets to conclude anything.
    """
    try:
        os.killpg(proc.pid, sig)    # pgid == pid, guaranteed by start_new_session
    except OSError:
        pass


def kill_ladder(proc):
    """TERM -> bounded grace -> KILL -> bounded reap.

    Returns True if the child was reaped, False if it survived SIGKILL. Total
    wall-clock cost is at most GRACE_SECONDS + REAP_SECONDS, unconditionally.

    The grace is time.sleep, not proc.wait(timeout=GRACE), on purpose: grace is
    owed to the GROUP, and wait() returns the instant the LEADER exits, which
    would cut short a descendant still flushing a partial transcript. waitpid
    cannot wait on a grandchild — it is not our child — so there is nothing to
    wait on, and a fixed sleep is the honest expression of "give the group five
    seconds". The stall path is already >= 300s by definition, so the cost is
    noise.

    A False return is PROOF, not a guess: waitpid on our own unreaped child is
    the kernel's own answer. Its predecessor asked `ps` and got a third answer.
    """
    signal_group(proc, signal.SIGTERM)
    time.sleep(GRACE_SECONDS)
    signal_group(proc, signal.SIGKILL)
    try:
        proc.wait(timeout=REAP_SECONDS)
        return True
    except subprocess.TimeoutExpired:
        return False


def shell_rc(rc):
    """Normalise Popen's status to the shell convention used by existing
    attempts-log history: Popen returns -N for a signal death, shells use
    128+N."""
    return rc if rc >= 0 else 128 - rc


def note(attempts_path, klass, elapsed, ceiling, rc, head):
    """Append one line to the attempts log.

    Killed and failed attempts only — never successes, and deliberately NOT the
    audit log, so these can never enter the dur= median that sets the ceiling.
    Without this file a run that hangs and never marks leaves no trace at all
    (the 23.7-hour entry is visible only because it happened to end in PASS).

    rc is None whenever no status was collected, and renders as '-'. It is
    never initialised to 0: a stall that logged rc=0 was reporting a status it
    had never obtained.
    """
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime(
        "%Y-%m-%dT%H:%M:%SZ")
    line = "%s %s class=%s elapsed=%ss ceiling=%ss rc=%s\n" % (
        stamp, head, klass, elapsed, ceiling,
        "-" if rc is None else shell_rc(rc))
    try:
        with open(attempts_path, "a", encoding="utf-8") as fh:
            fh.write(line)
    except OSError:
        pass                        # a missing trace must not mask the verdict


def main(argv):
    ceiling_text, log, cmd = parse_args(argv)

    if not cmd:
        raise Usage('no command after \'--\' — pass the runtime to run, '
                    'e.g. -- codex exec "<review brief>"')

    ceiling = validate_ceiling(ceiling_text) if ceiling_text is not None else None

    gitdir = git_dir()
    if log is None:
        log = os.path.join(gitdir, "codex-review.log")
    audit = os.path.join(gitdir, "codex-review-audit.log")
    attempts = os.path.join(gitdir, "codex-run-attempts.log")

    if shutil.which(cmd[0]) is None:
        raise Usage("runtime '%s' not found on PATH — resolve the Codex "
                    "runtime first (references/stance.md § Preflight, or run "
                    "'kerby pr-check')" % cmd[0])

    logdir = os.path.dirname(log) or "."
    if not (os.path.isdir(logdir) and os.access(logdir, os.W_OK)):
        raise Usage("cannot write the log directory %s — pass --log to a "
                    "writable path" % logdir)

    lock = Lock(log)
    lock.acquire()
    try:
        install_signal_handlers()

        try:
            os.unlink(log)
        except FileNotFoundError:
            pass
        except OSError:
            raise Usage("cannot remove the stale log at %s — remove it by "
                        "hand, then re-run" % log)
        if os.path.exists(log):
            raise Usage("%s still exists after removal (a directory?) — clear "
                        "that path, then re-run" % log)

        if ceiling is None:
            ceiling = compute_ceiling(audit)

        try:
            proc = spawn(cmd, log)
        except OSError as exc:
            # which() passed but exec did not: the binary vanished or lost +x
            # between the two. Nothing is running, so the contract requires
            # exit 1 with NO transcript — and this is the one place the wrapper
            # unlinks a file it created (safe: we hold the lock and made that
            # exact inode microseconds ago).
            try:
                os.unlink(log)
            except OSError:
                pass
            raise Usage("cannot start '%s': %s — check it is executable, then "
                        "re-run" % (cmd[0], exc))

        started = time.monotonic()   # monotonic: an NTP step cannot move the bound
        rc = None
        try:
            rc = proc.wait(timeout=ceiling)   # ONE call. No poll loop, no probe.
            klass = "ok"
        except subprocess.TimeoutExpired:
            klass = "stall" if kill_ladder(proc) else "survivor"
        except Interrupted:
            kill_ladder(proc)
            return 130
        elapsed = int(time.monotonic() - started)
        head = git_short_head()

        if klass == "survivor":
            # Proven alive after SIGKILL: uninterruptible I/O, a hung NFS/FUSE
            # mount, or a stopped-and-traced process. NOT exit 4 — that code's
            # contract is "at most one blind retry", and a retry beside an
            # unkillable process is two Codex runs on one repo, interleaved git
            # operations, and a transcript being appended to by something
            # nobody can see.
            note(attempts, "survivor", elapsed, ceiling, None, head)
            emit("SURVIVOR — pid %d outlived SIGKILL after %ss (ceiling %ss); "
                 "it is stuck in an uninterruptible wait. Do NOT retry: a "
                 "second attempt would run beside it. The lock at %s is left "
                 "in place on purpose so it cannot. Investigate that pid, then "
                 "remove the lock once it is gone. Transcript at %s."
                 % (proc.pid, elapsed, ceiling, lock.path, log))
            # The lock stays as a tombstone; the next attempt's collision
            # message already ends "If nothing is running, remove that
            # directory." os._exit because an unreaped Popen can emit an
            # UNPREFIXED ResourceWarning from __del__ at interpreter shutdown,
            # which would break the stderr contract on the one path that
            # matters most. It also skips the finally, which is the point.
            lock.disown()
            sys.stdout.flush()
            sys.stderr.flush()
            os._exit(6)

        if klass == "stall":
            note(attempts, "stall", elapsed, ceiling, None, head)
            emit("STALL — still running at the %ss ceiling, killed "
                 "(ceiling %ss). Transcript kept at %s. At most one blind "
                 "retry, then take the step-4 fallback in "
                 "references/pr-workflow.md." % (ceiling, ceiling, log))
            return 4

        if rc != 0:
            note(attempts, "exit-%d" % shell_rc(rc), elapsed, ceiling, rc, head)
            emit("runtime exited %d after %ss (ceiling %ss). Read %s for the "
                 "cause, fix it, then retry once."
                 % (shell_rc(rc), elapsed, ceiling, log))
            return 5

        say("OK — %ss (ceiling %ss). Transcript at %s. NEXT: run "
            "scripts/codex-mark.sh now — it is the only thing that parses the "
            "verdict AND advances the 3-round cap. Reading the verdict by eye "
            "instead leaves the counter at zero and the cap never fires."
            % (elapsed, ceiling, log))
        return 0
    finally:
        lock.release()


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Usage as err:
        emit(str(err))
        sys.exit(1)
    except Interrupted:
        # Reached only before a child exists; the in-flight case is handled in
        # main() so the group is killed first.
        sys.exit(130)
    except Exception as err:        # never let a traceback onto fd 2 unprefixed
        emit("internal error (%s: %s) — this is a bug in codex-run.py"
             % (type(err).__name__, err))
        sys.exit(1)
