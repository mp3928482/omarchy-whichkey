#!/usr/bin/env python3
"""Collapse digit-key runs (workspace 1..0 style) in index.json into one row.

Reads index.json on stdin, writes the collapsed version to stdout. Keeps the
HUD short: 20 near-identical "Switch to workspace N" rows become one.
"""
import json
import re
import sys

DIGIT = re.compile(r"^[0-9]$")
TRAIL = re.compile(r"^(.*?)\s*\d+$")


def collapse(items):
    digits = [it for it in items if DIGIT.match(it["k"])]
    if len(digits) < 3:
        return items

    prefixes = {TRAIL.match(it["d"]).group(1) for it in digits if TRAIL.match(it["d"])}
    if len(prefixes) != 1:
        return items
    prefix = next(iter(prefixes))

    keys = sorted((it["k"] for it in digits), key=lambda k: (k == "0", k))
    merged = {"k": f"{keys[0]}–{keys[-1]}", "d": f"{prefix} N"}

    out, placed = [], False
    for it in items:
        if DIGIT.match(it["k"]):
            if not placed:
                out.append(merged)
                placed = True
        else:
            out.append(it)
    return out


data = json.load(sys.stdin)
json.dump({mask: collapse(items) for mask, items in data.items()},
          sys.stdout, ensure_ascii=False)
sys.stdout.write("\n")
