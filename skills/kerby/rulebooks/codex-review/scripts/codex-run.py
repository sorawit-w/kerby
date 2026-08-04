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
  130 — HUP/INT/TERM delivered to this wrapper. The kill ladder runs whenever
        a live child was reachable at the point the signal was handled — not
        an unconditional guarantee; see the residual-gaps discussion below
        for the specific, narrow windows where a child can exist without the
        ladder running (nothing spawned yet is the common, unremarkable case).

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
microsecond SIGALRM).

A related but MORE TRACTABLE class of gap is the entry into a protected
region rather than a stdlib internal: a signal landing between "we decided to
call kill_ladder()" (say, just entering `except subprocess.TimeoutExpired:`,
or the few statements right after `spawn()` returns in main()) and that
branch's own `block_signals()` line actually running escapes the branch
entirely — Python does not let a sibling `except` catch an exception raised
inside another except clause of the same try. Unlike the returncode race,
THIS shape is closable without touching Popen's internals: main()'s
outermost `except Interrupted:` checks `proc.returncode is None` (`proc` is
a local variable of main(), `None` until `spawn()` succeeds — NOT
module-scoped, an earlier version of this paragraph said so incorrectly) and
runs `kill_ladder()` itself — checking ITS return value too, mirroring the
inner handlers, so a genuine survivor reached this way still gets its
tombstone and exit 6 rather than a bare 130 that would release the lock
beside it (a review caught this specific omission). This narrows the exposed
window from "seconds, at the ceiling or during the grace sleep" down to
individual CPython bytecode instructions, but does NOT make it exactly zero:
`spawn()`'s own body has statements of the same shape (`proc = Popen(...)`,
then `os.close(fd)`, then `return proc`) where a signal landing between
Popen() returning and the NEXT bytecode instruction completing is caught by
spawn()'s own `except BaseException:` cleanup instead of main()'s witness ever
being set — a review reproduced this too. Blocking BEFORE calling `spawn()`
would close it, but that is the exact mask-inheritance mistake documented two
paragraphs up. This sub-gap is therefore folded into the SAME accepted-
residual family as the `Popen._wait()` gap below, not claimed as closed:
pthread_sigmask closes gaps between statements we choose to guard; it cannot
retroactively guard a statement inside a stdlib call, or the assignment that
immediately follows one, without either wrapping literally every statement in
the file (impractical and its own source of bugs) or reintroducing the
mask-inheritance hazard by blocking before the call that needs protecting.

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
    """Short HEAD sha for the attempts log, or the literal '-'.

    Accepted, low-impact residual (flagged by review): this can be called
    while our own mask has HUP/INT/TERM blocked (the survivor path calls it
    from inside a still-blocked region), and fork() copies that mask into
    THIS git subprocess too — the same mask-inheritance mechanism spawn()
    works around for the monitored runtime. Not fixed here: `git rev-parse`
    is a fast, well-behaved command, and once `subprocess.run(timeout=)`
    starts counting, its own enforcement uses the unmaskable SIGKILL — so a
    masked git that got as far as actually running either finishes quickly or
    gets killed on schedule regardless of its mask. NOT airtight: a review
    correctly pointed out that `timeout=` only starts counting AFTER `Popen`
    construction returns — the same fork/exec-handshake-can-hang residual
    this file already documents for the monitored runtime applies here too,
    unbounded by GIT_TIMEOUT, however unlikely on a fast local `git`. Fixing
    the mask issue would mean unblocking/reblocking around every such call
    inside an otherwise-atomic region, which is exactly the kind of extra
    surface that produced the mask-inheritance bug documented in the module
    docstring the first time.
    """
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
            # Unblock unconditionally here, NOT save/restore like release()
            # does — deliberately asymmetric, not an oversight. acquire() has
            # exactly one call site in this file (main()'s very first
            # protected statement), reached before ANY block_signals() call
            # has ever run, so the ambient mask at entry is always fully
            # unblocked — there is no caller state to preserve. release(), by
            # contrast, runs from main()'s outermost finally, which can be
            # reached from paths that already blocked signals (mid-ladder
            # cleanup); THAT is what makes save/restore load-bearing there
            # and merely extra ceremony here. If a second call site is ever
            # added, revisit this.
            unblock_signals()

    def disown(self):
        """Leave the lock directory in place on purpose (the survivor path)."""
        self.held = False

    def release(self):
        # Same discipline as acquire(): a review found `held = False` running
        # BEFORE `os.rmdir()` left a window where a signal could abort the
        # removal with the flag already cleared, stranding the directory —
        # fail-closed and manually recoverable (the collision message already
        # says to remove it), but a real, avoidable gap. block_signals() here
        # carries none of spawn()'s mask-inheritance risk: rmdir() forks
        # nothing.
        #
        # SAVE and RESTORE the caller's exact prior mask — do NOT call the
        # unconditional unblock_signals() acquire() uses. release() runs from
        # main()'s outermost finally, which fires AFTER a clean return value
        # (0/4/5) is already decided — some paths reach it with signals
        # already blocked by the caller (e.g. mid-kill_ladder cleanup). A
        # review found that blindly unblocking there DELIVERS whatever signal
        # was pending, raising Interrupted from INSIDE this finally — which
        # propagates out and REPLACES the already-decided return value with a
        # bare 130, discarding a correct result. pthread_sigmask's own return
        # value is the previous mask; restoring exactly that (SIG_SETMASK)
        # rather than force-unblocking preserves whatever policy the caller
        # was already running, verified directly for both cases (caller
        # blocked stays blocked, caller unblocked's pending signal fires only
        # after this returns — never stolen, never force-suppressed).
        #
        # Accepted, undisclosed-no-longer residual: a signal in the sliver
        # between ENTERING this method and the block_signals() line below
        # actually running is not blocked yet, so it can still raise
        # Interrupted before self.held is ever touched — leaving both
        # held=True and the directory present. Same class of gap as
        # spawn()'s own entry, kill_ladder()'s callers entering their except
        # clauses, and the module docstring's returncode-race discussion:
        # narrowed to individual bytecode instructions by this fix, not
        # eliminated, and not engineered further here for the same reason
        # given in each of those places — there is no handle/state to
        # protect before the function's first statement has actually run.
        saved_mask = block_signals()
        try:
            if not self.held:
                return              # idempotent AND ownership-checked
            self.held = False       # cleared BEFORE the rmdir: no double-release
            try:
                os.rmdir(self.path)
            except OSError:
                pass
        finally:
            restore_signals(saved_mask)


CAUGHT_SIGNALS = (signal.SIGHUP, signal.SIGINT, signal.SIGTERM)


def install_signal_handlers():
    """Turn HUP/INT/TERM into Interrupted so a single try/finally can clean up.

    Called as the FIRST statement in main(), before the lock is even
    acquired: Python's default SIGINT disposition raises KeyboardInterrupt
    (not an Exception subclass, so main()'s `except Interrupted:` clauses
    cannot catch it), which — before this call replaces the disposition —
    would propagate all the way to __main__'s belt-and-suspenders
    `except KeyboardInterrupt:` backstop and skip every bit of cleanup this
    file does (lock release, kill_ladder) along the way. That backstop exists
    for the sliver of time BEFORE this function runs, not as a substitute for
    running it — installing our own handler here replaces Python's default
    for the rest of the process's lifetime, which is what makes cleanup
    possible at all from this point on.

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
    once. This makes kill_ladder()'s OWN body atomic with respect to these
    three signals, and NARROWS (does not fully close — see spawn()'s
    docstring and the module docstring) the gap right after spawn() returns.

    It does NOT close the transitions of entering those regions: a signal
    can still land between "we decided to call kill_ladder()" (e.g. just
    entered `except subprocess.TimeoutExpired:`) and the very next line
    actually running block_signals(). That gap is closed differently —
    main()'s outer `except Interrupted:` checks `proc.returncode is None`
    and runs kill_ladder() itself if the exception reaches it that way, so a
    signal escaping one of these entry gaps still ends up killing the child
    rather than orphaning it. One residual remains even so: the internal gap
    INSIDE Popen._wait() between its own os.waitpid() reaping the child and
    assigning self.returncode, which no handler placement can close — see
    the module docstring.

    Returns the mask that was in effect BEFORE this call (pthread_sigmask's
    own return value) — most callers discard it and use unblock_signals()
    afterward, which is correct for regions that always want signals fully
    live again. Lock.release() is the one caller that uses it, via
    restore_signals(), because it can be entered with signals already
    blocked by ITS caller (see release()'s own docstring for why blindly
    unblocking there is a real bug, not a style choice).
    """
    return signal.pthread_sigmask(signal.SIG_BLOCK, CAUGHT_SIGNALS)


def unblock_signals():
    signal.pthread_sigmask(signal.SIG_UNBLOCK, CAUGHT_SIGNALS)


def restore_signals(mask):
    """Set the mask to EXACTLY `mask` — not "unblock", "set to precisely
    this". Verified directly: if the saved mask had these signals blocked,
    restoring keeps them blocked (no premature delivery of anything pending
    from the caller's own perspective); if unblocked, a pending signal fires
    only after this call, not before — same as if the intervening
    block_signals() had never run at all from the caller's point of view.
    """
    signal.pthread_sigmask(signal.SIG_SETMASK, mask)


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
    function must not touch that path at all. A Popen() failure AFTER a
    successful open() unlinks safely, because only then did we create the
    inode we're removing — NOT the only other case that reaches this cleanup,
    though: `except BaseException` also catches Interrupted, so a signal
    landing between Popen() returning (child alive) and this function's own
    `proc = subprocess.Popen(...)` assignment completing runs this SAME
    cleanup path — unlinking a log a live child may still be writing to, then
    re-raising with the caller's `proc = spawn(...)` never completing, so
    that reference is lost. This is the sub-statement gap the module
    docstring's residual discussion names; not engineered around further
    here for the same reason given there.
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
    # `proc` is the outer Interrupted handler's witness for "does a child
    # exist that might need killing". A review found that handler assumed
    # "no child exists yet" unconditionally — false for real gaps: the
    # instant right after spawn() returns but before the caller's own
    # block_signals() runs, and entering `except subprocess.TimeoutExpired:`
    # before ITS block_signals() runs. Both let Interrupted escape every
    # inner handler and reach here with a live, unmanaged child, and the
    # outer handler below now checks for that.
    #
    # `None` here is NOT an unambiguous "not spawned yet" signal, and a later
    # review round showed why: spawn() can create the child and then itself
    # be interrupted before returning it (see spawn()'s own docstring) — in
    # that specific sub-case a real child exists, orphaned, while `proc`
    # here never leaves `None` at all, because the assignment below never
    # completes. This is the same class of gap as the module docstring's
    # returncode-race residual, not a defect unique to this line — accepted,
    # not claimed away.
    proc = None
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
        # NOW block, immediately after spawn() ITSELF returns (not merely
        # after its internal Popen() call — spawn() has its own post-Popen()
        # assignment/close/return sequence, with the identical gap shape,
        # documented in spawn()'s own docstring and NOT covered by this
        # block_signals() call). The child already forked with a normal
        # mask, so this protects only OUR OWN bookkeeping for the trivial
        # gap between spawn() returning and the next line, without touching
        # the child at all. (A signal landing INSIDE spawn() — before we
        # have `proc` in hand here — is an accepted residual: there is no
        # handle to act on yet regardless of blocking, the same shape as the
        # Popen()-can-hang residual in this file's module docstring.)
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
            # landing here (child ALREADY reaped, rc already has a real
            # value, but still inside the reporting code that follows:
            # elapsed/head/note/emit) escapes to the outermost catch-all.
            # That catch-all now checks proc.returncode before deciding
            # whether to kill anything (fixed in a later round) — and here
            # it's already set, so it correctly does NOT call kill_ladder —
            # but it STILL unconditionally returns a bare 130, discarding
            # the completed, valid result it never looks at. Blocking here
            # is what prevents THAT specific loss; it is not protecting
            # against a misdirected kill on this path (nothing here would
            # trigger one either way).
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
        # Reachable from lock acquisition, the stale-log removal, OR — this
        # is the fix — the two adjacency gaps named above `proc = None`,
        # where a child DOES exist but no inner handler was positioned to
        # catch this exception. `proc.returncode is None` is the same
        # best-available (not airtight — see the module docstring's
        # returncode-race discussion) signal used elsewhere in this file;
        # block first so the kill itself is not interrupted mid-ladder.
        if proc is not None and proc.returncode is None:
            block_signals()
            if not kill_ladder(proc):
                # A review found this branch DISCARDED kill_ladder()'s return
                # value: on a genuine survivor, it still fell through to
                # `return 130` below and the `finally` released the lock —
                # misreporting a proven-unkillable process as a plain
                # interrupt and permitting a retry to start beside it, the
                # exact hazard the survivor path exists to prevent. Mirrors
                # the main survivor branch: disown BEFORE anything else that
                # could fail, then os._exit — never the ordinary return path,
                # so `finally` (which would release the lock) never runs.
                lock.disown()
                emit("SURVIVOR — pid %d outlived SIGKILL while handling an "
                     "interrupt (ceiling %ss); it is stuck in an "
                     "uninterruptible wait. Do NOT retry: a second attempt "
                     "would run beside it. The lock at %s is left in place "
                     "on purpose so it cannot. Investigate that pid, then "
                     "remove the lock once it is gone. Transcript at %s."
                     % (proc.pid, ceiling, lock.path, log))
                sys.stdout.flush()
                sys.stderr.flush()
                os._exit(6)
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
        # Genuinely reachable, not merely defensive: main()'s preflight
        # (parse_args/validate_ceiling/git_dir/which/logdir checks) runs
        # AFTER install_signal_handlers() but BEFORE main()'s own try begins,
        # so a signal there raises Interrupted with no main()-internal
        # handler positioned to catch it — it lands here. Harmless on that
        # specific path: nothing has been acquired or spawned yet, so there
        # is nothing to clean up and exiting 130 immediately is correct. This
        # clause is also the true backstop for any future gap that reopens
        # elsewhere; either way it exits the same way main() itself would.
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
