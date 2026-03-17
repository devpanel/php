#!/usr/bin/env python3
"""
Shared baseline-comparison helper.

Usage: compare-baseline.py <baseline-json> <current-json>

Both JSON files must be objects whose keys are "path:RULE_CODE" and whose
values are occurrence counts.  Exits non-zero and prints every violation
whose count *increased* or whose rule/file combination is *new*.

If the violation count for any key has *decreased* (or a key has been fully
resolved), the baseline is considered stale and the script also exits
non-zero, asking the developer to re-run with --update-baseline.

A missing baseline file is treated as an empty baseline ({}).
"""

import json
import os
import sys


def load(path):
    if not os.path.exists(path):
        return {}
    with open(path) as fh:
        return json.load(fh)


def compare(baseline, current):
    new_violations = []
    stale_entries = []

    for key, count in sorted(current.items()):
        base_count = baseline.get(key, 0)
        if count > base_count:
            file_part, rule = key.rsplit(":", 1)
            delta = count - base_count
            new_violations.append(
                f"  {file_part}: {rule} +{delta} new"
                f" (baseline {base_count}, current {count})"
            )

    for key, base_count in sorted(baseline.items()):
        curr_count = current.get(key, 0)
        if curr_count < base_count:
            file_part, rule = key.rsplit(":", 1)
            delta = base_count - curr_count
            stale_entries.append(
                f"  {file_part}: {rule} -{delta} resolved"
                f" (baseline {base_count}, current {curr_count})"
            )

    return new_violations, stale_entries


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <baseline.json> <current.json>",
              file=sys.stderr)
        sys.exit(2)

    baseline = load(sys.argv[1])
    current = load(sys.argv[2])
    new_violations, stale_entries = compare(baseline, current)

    if new_violations:
        print("New lint violations detected (exceeding baseline):")
        for v in new_violations:
            print(v)

    if stale_entries:
        print("Baseline is stale (violations resolved) — run with --update-baseline to regenerate:")
        for v in stale_entries:
            print(v)

    if new_violations or stale_entries:
        sys.exit(1)

    print("No new violations above baseline.")
    sys.exit(0)


if __name__ == "__main__":
    main()
