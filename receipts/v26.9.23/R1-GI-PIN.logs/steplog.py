#!/usr/bin/env python3
"""Summarize step logs written by step.sh: exit, timestamps, sha256, key summary line."""
import hashlib
import json
import re
import sys


def summarize(path):
    data = open(path, "rb").read()
    text = data.decode("utf-8", "replace")
    head = re.search(r"^# cwd=(\S+) head=([0-9a-f]{40}) started=(\S+)", text, re.M)
    cmd = re.search(r"^# cmd=(.*)$", text, re.M)
    end = re.search(r"^# ended=(\S+) exit=(\d+)", text, re.M)
    keys = []
    for pat in (
        r"^Elixir \d.*$",
        r"^Finished in .*$",
        r"^\d+ doctests?.*$|^\d+ tests?,.*$|^\d+ properties.*$",
        r".*mods/funs.*$",
        r"^Generated ggen_igniter app$",
        r"^\*\* \(.*$",
        r"^The following files are not formatted.*$",
    ):
        for m in re.finditer(pat, text, re.M):
            keys.append(m.group(0).strip())
    return {
        "log": path,
        "cwd": head.group(1) if head else None,
        "head": head.group(2) if head else None,
        "started_at": head.group(3) if head else None,
        "cmd": cmd.group(1) if cmd else None,
        "ended_at": end.group(1) if end else None,
        "exit": int(end.group(2)) if end else None,
        "output_sha256": hashlib.sha256(data).hexdigest(),
        "key_lines": keys,
    }


if __name__ == "__main__":
    print(json.dumps([summarize(p) for p in sys.argv[1:]], indent=1))
