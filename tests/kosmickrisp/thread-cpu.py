#!/usr/bin/env python3
"""How busy each thread of a running game is, by name – for a game under Wine and Rosetta:

    python3 -I tests/kosmickrisp/thread-cpu.py <pid> [seconds] [sample.txt]

Reads each thread's CPU time from the kernel (proc_pidinfo, no root needed for one's own
processes) twice, `seconds` apart (default 5), and prints the busiest threads with their names:
DXVK names its own (dxvk-cs records and replays the game's draws, dxvk-submit hands them to the
driver); the game's threads have none. With the output of `sample <pid> 10 -file sample.txt`, the
busiest threads also show which modules their stacks are in: libvulkan_kosmickrisp.dylib is
KosmicKrisp (Vulkan → Metal and its shader translation, x86_64 under Rosetta), winevulkan.so and
win32u.so are Wine's Vulkan thunks, AGXMetal… is Apple's GPU driver, "<unknown binary>" is Windows
code as Rosetta runs it (the game, DXVK).
"""

import ctypes
import re
import sys
import time
from collections import Counter

PROC_PIDLISTTHREADS = 6
PROC_PIDTHREADINFO = 5


class ThreadInfo(ctypes.Structure):
    _fields_ = [("user", ctypes.c_uint64), ("system", ctypes.c_uint64), ("cpu_usage", ctypes.c_int32),
                ("policy", ctypes.c_int32), ("run_state", ctypes.c_int32), ("flags", ctypes.c_int32),
                ("sleep_time", ctypes.c_int32), ("curpri", ctypes.c_int32), ("priority", ctypes.c_int32),
                ("maxpriority", ctypes.c_int32), ("name", ctypes.c_char * 64)]


libproc = ctypes.CDLL("/usr/lib/libproc.dylib")


def threads(pid):
    """Thread handle → (name, CPU time in ns)."""
    handles = (ctypes.c_uint64 * 4096)()
    size = libproc.proc_pidinfo(pid, PROC_PIDLISTTHREADS, 0, handles, ctypes.sizeof(handles))
    if size <= 0:
        sys.exit(f"no process {pid} (or not yours)")
    result = {}
    for handle in handles[: size // 8]:
        info = ThreadInfo()
        if libproc.proc_pidinfo(pid, PROC_PIDTHREADINFO, ctypes.c_uint64(handle), ctypes.byref(info),
                                ctypes.sizeof(info)) == ctypes.sizeof(info):
            result[handle] = (info.name.decode(errors="replace") or "(no name)", info.user + info.system)
    return result


def modules(sample_path):
    """Thread name → modules its stacks end in, from `sample` output (the leaves of each thread's tree)."""
    by_thread, name, nodes = {}, None, []
    thread = re.compile(r"^\s+\d+\s+Thread_\S+?(?::\s*(.*))?$")
    node = re.compile(r"^([\s+!:|]*?)(\d+)\s+(.*)$")
    lines = open(sample_path, errors="replace").read().splitlines() + ["    0 Thread_end"]
    for line in lines:
        if line.startswith("Total number in stack"):
            line = "    0 Thread_end"
        match = thread.match(line)
        if match:
            if name is not None:
                counts = by_thread.setdefault(name, Counter())
                for i, (depth, count, text) in enumerate(nodes):
                    if i + 1 < len(nodes) and nodes[i + 1][0] > depth:
                        continue
                    module = re.search(r"\(in ([^)]+)\)", text)
                    counts[module.group(1) if module else "?"] += count
            name, nodes = (match.group(1) or "(no name)"), []
            if line.strip() == "0 Thread_end":
                break
            continue
        found = node.match(line)
        if name is not None and found and "+" in found.group(1):
            nodes.append((len(found.group(1)), int(found.group(2)), found.group(3)))
    return by_thread


def main():
    pid = int(sys.argv[1])
    seconds = float(sys.argv[2]) if len(sys.argv) > 2 else 5
    before = threads(pid)
    time.sleep(seconds)
    after = threads(pid)
    rows = sorted(((after[h][1] - before[h][1]) / (seconds * 1e9) * 100, after[h][0]) for h in after if h in before)
    stacks = modules(sys.argv[3]) if len(sys.argv) > 3 else {}
    print(f"{sum(cpu for cpu, _ in rows):.0f} % in all, {len(after)} threads")
    for cpu, name in reversed(rows[-10:]):
        where = stacks.get(name)
        detail = ""
        if where and name != "(no name)":
            total = sum(where.values())
            detail = "  " + ", ".join(f"{m} {c * 100 // total} %" for m, c in where.most_common(4))
        print(f"{cpu:5.0f} %  {name}{detail}")


if __name__ == "__main__":
    main()
