#!/usr/bin/env python3
"""Decompile every contract of a list with the CLI, several at a time: the
timings, the failures, the timeouts.

    tools/corpus.py [INPUT...] [--cli PATH] [-j N] [--threads T]
                    [--sigdb PATH] [--abi-dump PATH] [--env NAME=VALUE]...
                    [--kill-after S] [--limit N] [--out DIR] [--json FILE]
                    [--quiet] [--train] [-- CLI ARGUMENTS...]

INPUT: a list of .hex paths (one per line; '#' comments; relative to the
list), a directory (its *.hex) or .hex files; by default the 1121 runtime
bytecodes of DEFAULT_LIST. Each contract runs `CLI decompile FILE
--no-color [-j T] [CLI ARGUMENTS]` (T: the decompiler's own threads, its
default when not given), N contracts at a time (-j, 2 by default: the
machine has 2 CPUs shared by every worker), with
  PANORAMIX_TIMEOUT=0       no time limit inside the decompiler: the same
                            work at any speed (comparable timings)
  PANORAMIX_SIGDB=--sigdb   the signature database (default: SIGDB of the
                            environment, or cxx/$B/sigdb2.bin when it exists)
  PANORAMIX_LOG=error
and --kill-after S (600 by default, 0: never) kills a run taking longer: a
timeout. A run is ok (exit 0), failed (exit != 0), crashed (a signal) or a
timeout. Each finished run prints a line (unless --quiet); then the
summary: the counts, the CPU time (user + system) in total and per contract
(median, percentiles, max), the peak memory (max RSS), the slowest, the
failures with the last line of their stderr. --out DIR keeps every
NAME.txt (stdout) and NAME.err; --json FILE every measure.

--train: the PGO training run (`make pgo`): quiet, one summary line, and
the exit status is 0 whatever the contracts did. Otherwise the exit status
is 1 when a run failed, crashed or timed out.
"""
import argparse
import concurrent.futures
import dataclasses
import glob
import json
import math
import os
import signal
import subprocess
import sys
import tempfile
import threading
import time

DEFAULT_LIST = ("/tmp/claude-0/-home-claude/0fe601fa-3d3d-56af-9a22-c5068d00d0e0"
                "/scratchpad/prof/all_hex.txt")
CXX_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


@dataclasses.dataclass
class Result:
    path: str
    name: str
    status: str      # "ok", "failed", "crashed", "timeout"
    rc: int          # the exit code, or -SIGNAL
    user: float      # seconds
    sys: float
    wall: float
    rss_kib: int     # the peak resident set size
    err: str         # the last line of stderr

    @property
    def cpu(self):
        return self.user + self.sys


def read_inputs(inputs):
    """the .hex files of the arguments, in order, each once"""
    files = []
    for x in inputs:
        if os.path.isdir(x):
            files += sorted(glob.glob(os.path.join(x, "*.hex")))
        elif x.endswith(".hex"):
            files.append(x)
        else:
            base = os.path.dirname(os.path.abspath(x))
            with open(x) as fh:
                for line in fh:
                    line = line.strip()
                    if line and not line.startswith("#"):
                        files.append(os.path.join(base, line))
    seen = set()
    return [f for f in files if not (f in seen or seen.add(f))]


def unique_names(files):
    """a name per file: its basename without .hex, numbered on a collision"""
    names, count = [], {}
    for f in files:
        n = os.path.basename(f)[:-4] if f.endswith(".hex") else os.path.basename(f)
        count[n] = count.get(n, 0) + 1
        names.append(n if count[n] == 1 else "%s~%d" % (n, count[n]))
    return names


def last_line(path):
    try:
        with open(path, "rb") as fh:
            fh.seek(0, os.SEEK_END)
            fh.seek(max(0, fh.tell() - 4096))
            lines = fh.read().decode("utf-8", "replace").strip().splitlines()
            return lines[-1] if lines else ""
    except OSError:
        return ""


def run_one(cli, path, name, args, env, kill_after=600.0, out_dir=None):
    """`cli decompile path --no-color args`, measured (os.wait4's rusage)"""
    if out_dir:
        out_path = os.path.join(out_dir, name + ".txt")
        err_path = os.path.join(out_dir, name + ".err")
    else:
        out_path = os.devnull
        fd, err_path = tempfile.mkstemp(prefix="corpus-", suffix=".err")
        os.close(fd)
    try:
        with open(out_path, "wb") as out, open(err_path, "wb") as err:
            t0 = time.monotonic()
            p = subprocess.Popen([cli, "decompile", path, "--no-color", *args],
                                 stdin=subprocess.DEVNULL, stdout=out, stderr=err,
                                 env=env, start_new_session=True)
        lock, state = threading.Lock(), {"exited": False, "killed": False}

        def kill():
            with lock:
                if not state["exited"]:
                    state["killed"] = True
                    os.killpg(p.pid, signal.SIGKILL)

        timer = threading.Timer(kill_after, kill) if kill_after > 0 else None
        if timer:
            timer.daemon = True
            timer.start()
        # exited but not reaped: until wait4, the pid (and its process group)
        # cannot be another process's, so the timer cannot kill a stranger
        os.waitid(os.P_PID, p.pid, os.WEXITED | os.WNOWAIT)
        with lock:
            state["exited"] = True
        if timer:
            timer.cancel()
        _, status, ru = os.wait4(p.pid, 0)
        wall = time.monotonic() - t0
        rc = os.waitstatus_to_exitcode(status)
        p.returncode = rc
        if state["killed"]:
            kind = "timeout"
        elif rc < 0:
            kind = "crashed"
        else:
            kind = "ok" if rc == 0 else "failed"
        return Result(path, name, kind, rc, ru.ru_utime, ru.ru_stime, wall, ru.ru_maxrss,
                      "" if kind == "ok" else last_line(err_path))
    finally:
        if not out_dir:
            os.unlink(err_path)


def percentile(xs, p):
    """the nearest-rank percentile of the sorted list xs"""
    return xs[max(0, math.ceil(p / 100 * len(xs)) - 1)] if xs else 0.0


def environment(sigdb=None, abi_dump=None, extra=()):
    env = dict(os.environ, PANORAMIX_TIMEOUT="0", PANORAMIX_LOG="error")
    if sigdb:
        env["PANORAMIX_SIGDB"] = os.path.abspath(sigdb)
    if abi_dump:
        env["PANORAMIX_ABI_DUMP"] = os.path.abspath(abi_dump)
    for kv in extra:
        k, _, v = kv.partition("=")
        env[k] = v
    return env


def default_sigdb():
    if os.environ.get("SIGDB"):
        return os.environ["SIGDB"]
    path = os.path.join(CXX_DIR, os.environ.get("B", "build"), "sigdb2.bin")
    return path if os.path.exists(path) else None


def fmt_status(r):
    if r.status == "ok":
        return "ok"
    if r.status == "crashed":
        return "CRASH " + (signal.Signals(-r.rc).name if -r.rc in signal.valid_signals() else str(r.rc))
    return "TIMEOUT" if r.status == "timeout" else "FAIL rc=%d" % r.rc


def summary(results, wall, jobs, kill_after):
    """the summary's lines"""
    by = {k: [r for r in results if r.status == k] for k in ("ok", "failed", "crashed", "timeout")}
    cpu = sorted(r.cpu for r in results)
    lines = ["%d contracts, -j %d: %d ok, %d failed, %d crashed, %d timeouts%s"
             % (len(results), jobs, len(by["ok"]), len(by["failed"]), len(by["crashed"]),
                len(by["timeout"]), " (killed after %g s)" % kill_after if by["timeout"] else "")]
    if not results:
        return lines
    slowest = max(results, key=lambda r: r.cpu)
    fattest = max(results, key=lambda r: r.rss_kib)
    lines.append("CPU %.2f s (user %.2f, sys %.2f), elapsed %.2f s"
                 % (sum(cpu), sum(r.user for r in results), sum(r.sys for r in results), wall))
    lines.append("per contract: median %.3f s, p90 %.3f, p99 %.3f, max %.3f (%s)"
                 % (percentile(cpu, 50), percentile(cpu, 90), percentile(cpu, 99), slowest.cpu,
                    slowest.name))
    lines.append("peak RSS: max %d MiB (%s), median %d MiB"
                 % (fattest.rss_kib >> 10, fattest.name,
                    percentile(sorted(r.rss_kib for r in results), 50) >> 10))
    return lines


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("inputs", nargs="*", help="lists of .hex paths, directories, .hex files")
    ap.add_argument("--cli", default=os.path.join(CXX_DIR, os.environ.get("B", "build"), "pancxx"))
    ap.add_argument("-j", "--jobs", type=int, default=2, help="contracts at a time (2)")
    ap.add_argument("--threads", type=int, help="the CLI's -j (its default when not given)")
    ap.add_argument("--sigdb", default=default_sigdb(), help="PANORAMIX_SIGDB")
    ap.add_argument("--abi-dump", help="PANORAMIX_ABI_DUMP (the CLI rebuilds a stale --sigdb)")
    ap.add_argument("--env", action="append", default=[], metavar="NAME=VALUE")
    ap.add_argument("--kill-after", type=float, default=600.0, metavar="S")
    ap.add_argument("--limit", type=int, help="only the first N contracts")
    ap.add_argument("--out", metavar="DIR", help="keep the outputs: DIR/NAME.txt, DIR/NAME.err")
    ap.add_argument("--json", metavar="FILE", help="every measure")
    ap.add_argument("--slowest", type=int, default=10, help="how many of the slowest to list (10)")
    ap.add_argument("-q", "--quiet", action="store_true", help="no line per contract")
    ap.add_argument("--train", action="store_true", help="the PGO training run: quiet, exit 0")
    argv = sys.argv[1:]
    extra = []
    if "--" in argv:
        i = argv.index("--")
        argv, extra = argv[:i], argv[i + 1:]
    a = ap.parse_args(argv)

    files = read_inputs(a.inputs or [DEFAULT_LIST])
    if a.limit:
        files = files[:a.limit]
    if not files:
        sys.exit("corpus.py: no contracts")
    if not os.access(a.cli, os.X_OK):
        sys.exit("corpus.py: no CLI at %s (make all?)" % a.cli)
    if a.sigdb and not os.path.exists(a.sigdb) and not a.abi_dump:
        print("corpus.py: warning: no signature database %s (make sigdb?)" % a.sigdb, file=sys.stderr)
    if a.out:
        os.makedirs(a.out, exist_ok=True)
    quiet = a.quiet or a.train
    args = (["-j", str(a.threads)] if a.threads else []) + extra
    env = environment(a.sigdb, a.abi_dump, a.env)
    names = unique_names(files)

    results, n = [], len(files)
    t0 = time.monotonic()
    with concurrent.futures.ThreadPoolExecutor(max_workers=max(1, a.jobs)) as pool:
        futures = [pool.submit(run_one, a.cli, f, nm, args, env, a.kill_after, a.out)
                   for f, nm in zip(files, names)]
        for fut in concurrent.futures.as_completed(futures):
            r = fut.result()
            results.append(r)
            if not quiet:
                print("[%*d/%d] %-10s %8.3f s %6d MiB  %s%s"
                      % (len(str(n)), len(results), n, fmt_status(r), r.cpu, r.rss_kib >> 10, r.name,
                         "  " + r.err if r.err else ""), flush=True)
    wall = time.monotonic() - t0
    order = {nm: i for i, nm in enumerate(names)}
    results.sort(key=lambda r: order[r.name])

    lines = summary(results, wall, a.jobs, a.kill_after)
    if a.train:
        print("training: " + lines[0] + ("; " + lines[1] if len(lines) > 1 else ""))
    else:
        print("\n".join(lines))
        if a.slowest:
            print("slowest:")
            for r in sorted(results, key=lambda r: -r.cpu)[:a.slowest]:
                print("  %8.3f s %6d MiB  %s" % (r.cpu, r.rss_kib >> 10, r.name))
        bad = [r for r in results if r.status != "ok"]
        if bad:
            print("not ok:")
            for r in bad:
                print("  %-10s %s  %s" % (fmt_status(r), r.name, r.err))
    if a.json:
        with open(a.json, "w") as fh:
            json.dump({"cli": a.cli, "jobs": a.jobs, "args": args, "sigdb": a.sigdb, "wall": wall,
                       "results": [dataclasses.asdict(r) for r in results]}, fh, indent=1)
    if not a.train and any(r.status != "ok" for r in results):
        sys.exit(1)


if __name__ == "__main__":
    main()
