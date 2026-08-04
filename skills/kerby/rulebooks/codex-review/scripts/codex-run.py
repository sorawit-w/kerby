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

A live review round then found the same bug class again, one level up: a
signal can still land in the GAP between "the child's fate is decided" and
"we finished acting on it" — after a successful wait() but before we've
finished reporting, or literally mid-kill_ladder(). Reacting to a signal in
that gap by re-running kill_ladder() on a pid that may already be reaped is
exactly the misdirected-signal hazard this file exists to prevent, just
reached through timing instead of a bad `ps` read. Two structural answers
were tried, not another guard:
  - `proc.returncode is None`, checked before every kill_ladder() call reached
    from a signal handler.
  - `signal.pthread_sigmask` to BLOCK HUP/INT/TERM (deferring, not dropping,
    them) around every region that must run as one atomic unit: the trivial
    gap right after spawn() returns, and the kill ladder itself. Left
    UNBLOCKED around the main ceiling wait on purpose, so a long wait stays
    Ctrl-C-interruptible.

Building the blocking half surfaced a THIRD instance of the same bug class,
self-inflicted: an early draft blocked signals BEFORE calling spawn(), on the
theory that it would also close the fork/exec handshake window. It does — by
corrupting something else instead. fork() gives the CHILD a copy of the
CALLER's signal mask; a child forked while we're blocked inherits HUP/INT/TERM
as blocked for its ENTIRE LIFETIME, and nothing of ours ever unblocks it.
Verified directly: with block_signals() active across spawn(), a later
`os.killpg(pid, SIGTERM)` reached the child, raised no exception, and had NO
EFFECT — only the unmaskable SIGKILL still worked, silently defeating "TERM
first, so the runtime can flush a partial transcript" everywhere. Fixed by
blocking AFTER spawn() returns instead.

A SECOND review round then found that `proc.returncode is None` is NOT the
race-free check the paragraph above claimed. It is a fact about CPython's
implementation, not a design choice: `subprocess.Popen._wait()` calls
`os.waitpid()` — which reaps the child; the pid may now be reused by the OS —
and only SEVERAL BYTECODE INSTRUCTIONS LATER assigns `self.returncode`. A
signal delivered to Python in that gap runs its handler with `returncode`
still `None`, even though the kernel has already reaped the process.
Reproduced on the FIRST attempt of a scripted adversarial probe (a 10-
microsecond SIGALRM). The same irreducible bytecode-level granularity also
means the trivial gaps this file blocks around — right after spawn() returns,
entering `except TimeoutExpired:` — are each themselves one instruction
narrower than fully closed, not fully atomic. Pthread_sigmask closes gaps
between STATEMENTS; it cannot close a gap INSIDE a single stdlib call whose
internals we do not control.

This is now accepted as a residual, not engineered further around: closing it
for real means bypassing `subprocess.Popen.wait()`'s pure-Python polling loop
entirely for a hand-rolled `os.waitpid()` call under our own atomicity
control — a materially larger redesign than this file attempts. What is NOT
accepted: a courtesy signal sent on SPECULATION rather than as a reaction to a
proven-live child. An earlier draft added `nudge_stragglers()` — an
unconditional post-reap `killpg()` aimed at a possible leftover descendant —
to close a DIFFERENT (lower-severity) finding. It was removed: the same
review round pointed out that a process-group id is borrowed from the pid
namespace and freed the instant the group is empty, so a courtesy signal fired
after the group may already be empty risks hitting an unrelated, later
process group. That is a WORSE instance of the exact hazard this file exists
to eliminate, introduced while trying to close a milder one. A leader-exits-
cleanly-while-a-descendant-survives is therefore back to being an accepted,
undetected gap (see README's known-ceilings list) rather than a guessed-at fix.

Known residual, not fixed by any of this: `subprocess.Popen()` itself
performs a blocking read of the fork/exec handshake pipe. If the forked
child stalls between fork() and exec() — a hung NFS/FUSE mount resolving the
executable, in practice — Popen() does not return and the ceiling has not
started yet. This is accepted, not engineered around: a thread-based bound
around Popen() would trade one unbounded wait for "how do you forcibly stop
a thread stuck in a blocking syscall", which is the same problem in a new
costume.

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
        # block_signals() around the syscall AND the flag update makes
        # acquisition genuinely atomic — a review found that setting `held`
        # optimistically BEFORE mkdir() (the previous approach) has its own
        # gap: a signal landing between "held = True" and "mkdir() actually
        # runs" leaves held=True with nothing on disk yet; if a DIFFERENT
        # process then creates that same lock path before we unwind, our own
        # cleanup deletes THEIRS. Unlike spawn(), mkdir() forks nothing — a
        # child inheriting our mask is not a risk here, so blocking around the
        # whole operation is free of the hazard that ruled it out for spawn().
        # `held` is only ever set True AFTER mkdir() has actually succeeded,
        # so neither except branch needs to touch it — it is already False.
        block_signals()
        try:
            os.mkdir(self.path)
            self.held = True
        except FileExistsError:
            raise Usage(
                "another attempt already owns %s (lock: %s) — wait for it to "
                "finish, or pass --log to a separate path. If nothing is "
                "running, remove that directory." % (self.log_path, self.path))
        except OSError as exc:
            raise Usage("cannot create the lock at %s: %s — pass --log to a "
                        "writable path" % (self.path, exc))
        finally:
            # Unblock unconditionally, success or failure: acquire() is the
            # only atomic region before spawn() re-blocks on its own, and a
            # Usage() raised here must not leave the process's signal mask
            # blocked while it propagates all the way out to report an error.
            unblock_signals()

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


CAUGHT_SIGNALS = (signal.SIGHUP, signal.SIGINT, signal.SIGTERM)


def install_signal_handlers():
    """Turn HUP/INT/TERM into Interrupted so a single try/finally can clean up.

    Called as the FIRST statement in main(), before the lock is even
    acquired: Python's default SIGINT disposition raises KeyboardInterrupt,
    which is not caught anywhere in this file (it is not an Exception
    subclass) and would otherwise skip cleanup entirely if it arrived during
    lock acquisition. Installing our own handler first replaces that default
    for the whole lifetime of the process.

    A second signal must not re-enter cleanup and skip the release, so the
    handler disarms itself first.
    """
    def handler(signum, _frame):
        for sig in CAUGHT_SIGNALS:
            signal.signal(sig, signal.SIG_IGN)
        raise Interrupted(signum)

    for sig in CAUGHT_SIGNALS:
        signal.signal(sig, handler)


def block_signals():
    """Defer (not drop) HUP/INT/TERM for the duration of an atomic region.

    A blocked signal does not invoke the handler and does not raise
    Interrupted — it is held pending by the kernel and delivered the moment
    it is unblocked. Verified before use: a signal sent while blocked
    produces zero handler invocations until unblock, then fires exactly
    once. This is what makes spawn() and kill_ladder() atomic with respect
    to these three signals without disabling Ctrl-C everywhere else.
    """
    signal.pthread_sigmask(signal.SIG_BLOCK, CAUGHT_SIGNALS)


def unblock_signals():
    signal.pthread_sigmask(signal.SIG_UNBLOCK, CAUGHT_SIGNALS)


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

    Cleanup ownership is scoped precisely: if os.open() itself raises (a
    narrow TOCTOU — something now occupies log_path between the caller's
    stale-log removal and this call), NO file was created by us and this
    function must not touch that path at all. Only a Popen() failure AFTER
    a successful open() unlinks — because only then did we create the inode
    we're removing.
    """
    fd = os.open(log_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o666)
    try:
        proc = subprocess.Popen(cmd,
                                stdin=subprocess.DEVNULL,
                                stdout=fd,
                                stderr=subprocess.STDOUT,
                                start_new_session=True,
                                close_fds=True)
    except BaseException:
        os.close(fd)
        try:
            os.unlink(log_path)     # safe: we created this exact inode above
        except OSError:
            pass
        raise
    os.close(fd)
    return proc


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

    Runs under block_signals(): a review found that a signal arriving MID-
    LADDER (say, during the grace sleep) raised Interrupted from inside the
    caller's `except subprocess.TimeoutExpired:` clause, where it was NOT
    caught by the sibling `except Interrupted:` — it escaped the whole
    construct, leaving the child half-killed and the lock released. Blocking
    the three caught signals for the ladder's duration makes it atomic: a
    signal arriving here is deferred, not lost, until the caller unblocks.
    In practice the caller never does — the process returns/exits shortly
    after the ladder completes, and a deferred signal is simply discarded at
    exit rather than mishandled. The caller (main()) owns the block/unblock
    pairing; this function never calls either, so it composes correctly
    regardless of caller state.

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
    # Handlers are main()'s FIRST statement, before argument parsing, before
    # anything is resolved, acquired, or created — a review found that the
    # comment here once claimed this but the code did not: install ran after
    # parse_args()/validate_ceiling()/git_dir(), leaving all of that under
    # Python's default SIGINT disposition (raise KeyboardInterrupt, which
    # nothing in this file catches inside main()).
    install_signal_handlers()

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
    try:
        # Lock.acquire() blocks signals around its own mkdir() + flag update
        # now, so this call is internally atomic — see its docstring. This
        # try/finally's job is just to guarantee release() runs regardless.
        lock.acquire()

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

        # Signals are DELIBERATELY NOT blocked across this call. fork() gives
        # the CHILD a copy of the CALLER's current signal mask — if we were
        # blocked here, the spawned process (and everything it backgrounds)
        # would inherit HUP/INT/TERM as blocked for its entire lifetime, with
        # no code of ours ever unblocking it, since only WE control our own
        # mask. Verified directly: with block_signals() active across spawn(),
        # a later `os.killpg(..., SIGTERM)` reached the child but produced NO
        # effect, because the child itself could never see the signal it just
        # received — only the unmaskable SIGKILL still worked. That would have
        # silently defeated "TERM first, so the runtime can flush a partial
        # transcript" everywhere, not just here.
        try:
            proc = spawn(cmd, log)
        except OSError as exc:
            # which() passed but exec did not: the binary vanished or lost +x
            # between the two, or the fork/exec handshake itself failed.
            # spawn() has already cleaned up the inode it created (never one
            # it didn't — see spawn()'s docstring); nothing is running.
            raise Usage("cannot start '%s': %s — check it is executable, then "
                        "re-run" % (cmd[0], exc))
        # NOW block, immediately after Popen() has returned control — the
        # child already forked with a normal mask, so this protects only OUR
        # OWN bookkeeping for the trivial gap before the next line, without
        # touching the child at all. (A signal landing INSIDE Popen()'s own
        # fork/exec handshake, before we have `proc` in hand, is an accepted
        # residual — there is no handle to act on yet regardless of blocking,
        # the same shape as the Popen()-can-hang residual in this file's
        # module docstring.)
        block_signals()

        started = time.monotonic()   # monotonic: an NTP step cannot move the bound
        rc = None
        klass = "ok"
        try:
            # Unblock ONLY for the main wait: a long ceiling should still be
            # Ctrl-C-interruptible, and the except Interrupted: handler right
            # below checks proc.returncode before acting — not airtight (see
            # the module docstring's returncode-race discussion), but the best
            # available signal on this path. This does not touch the CHILD's
            # mask — only ours, and the child is long since forked by now.
            unblock_signals()
            rc = proc.wait(timeout=ceiling)   # ONE call. No poll loop, no probe.
            # Re-block THE MOMENT this returns, on the SUCCESS path too — not
            # just in the except branches below. Without this line, a signal
            # landing here (child reaped, but still inside the reporting code
            # that follows: elapsed/head/note/emit) escaped to the outermost
            # catch-all, which returns a bare 130 and discards a completed,
            # valid result it never even looks at. It doesn't kill anything
            # there (no misdirected signal — the outer catch never calls
            # kill_ladder), but it does throw away real information for no
            # reason. Blocking here removes that window.
            block_signals()
        except subprocess.TimeoutExpired:
            block_signals()      # re-atomic: the ladder must run as one unit
            klass = "stall" if kill_ladder(proc) else "survivor"
        except Interrupted:
            block_signals()
            if proc.returncode is not None:
                # Reaped by the time we checked — report the real result
                # instead of discarding a completed, valid transcript as an
                # interrupt. NOT airtight: `returncode` is set a few bytecode
                # instructions AFTER waitpid() itself reaps (see the module
                # docstring's returncode-race discussion), so this is the best
                # available signal, not a proof. klass stays "ok"; falls
                # through to normal reporting below.
                rc = proc.returncode
            else:
                # Still alive by this same imperfect signal: the kill is ours
                # to attempt. A successful kill here is a USER-initiated stop,
                # not a ceiling-initiated stall — report 130, not 4, so the
                # caller isn't told "the ceiling elapsed" when it didn't. A
                # survivor still needs its tombstone written below, which 130
                # alone wouldn't carry.
                klass = "stall" if kill_ladder(proc) else "survivor"
                if klass != "survivor":
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
            #
            # disown() runs FIRST, still under block_signals(), immediately
            # adjacent to the kill_ladder() call that proved survival — not
            # after git_short_head()/note()/emit(). A signal or a failure in
            # any of those must not be able to release the lock before the
            # tombstone is in place; disown() itself cannot fail.
            lock.disown()
            note(attempts, "survivor", elapsed, ceiling, None, head)
            emit("SURVIVOR — pid %d outlived SIGKILL after %ss (ceiling %ss); "
                 "it is stuck in an uninterruptible wait. Do NOT retry: a "
                 "second attempt would run beside it. The lock at %s is left "
                 "in place on purpose so it cannot. Investigate that pid, then "
                 "remove the lock once it is gone. Transcript at %s."
                 % (proc.pid, elapsed, ceiling, lock.path, log))
            # os._exit because an unreaped Popen can emit an UNPREFIXED
            # ResourceWarning from __del__ at interpreter shutdown, which
            # would break the stderr contract on the one path that matters
            # most. It also skips the finally, which is the point — disown()
            # already made that a no-op.
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

        # klass == "ok": the leader is reaped, but that only proves the LEADER
        # exited — waitpid cannot reap a grandchild (it isn't our child), so a
        # backgrounded descendant could still be running. An earlier draft
        # sent a courtesy SIGTERM to the group here; removed — by this point
        # the group may already be EMPTY, and a pgid is borrowed from the pid
        # namespace, freed the instant nothing holds it. Signalling a possibly
        # already-recycled pgid is a worse instance of the exact hazard this
        # file exists to eliminate than the straggler it was trying to catch.
        # Accepted, undetected residual — see README's known-ceilings list.

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
    except Interrupted:
        # Reachable only before spawn() (lock acquisition, or the stale-log
        # removal) or after a Usage()-raising branch already unblocked — no
        # child exists yet on this path, so there is nothing to kill.
        return 130
    finally:
        lock.release()


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv[1:]))
    except Usage as err:
        emit(str(err))
        sys.exit(1)
    except Interrupted:
        # Defensive only — main() now catches Interrupted internally on every
        # path once install_signal_handlers() (its first statement) has run,
        # so this should be unreachable. Kept as a backstop in case a future
        # change reopens a gap; still exits the same way main() would.
        sys.exit(130)
    except KeyboardInterrupt:
        # Belt-and-suspenders for the sliver of time before main()'s first
        # statement installs our own SIGINT handler, where Python's built-in
        # default (raise KeyboardInterrupt) still applies.
        sys.exit(130)
    except Exception as err:        # never let a traceback onto fd 2 unprefixed
        emit("internal error (%s: %s) — this is a bug in codex-run.py"
             % (type(err).__name__, err))
        sys.exit(1)
