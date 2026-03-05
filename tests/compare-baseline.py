#!/usr/bin/env python3
"""
Shared baseline-comparison helper.

Usage: compare_baseline.py <baseline-json> <current-json>

Both JSON files must be objects whose keys are "path:RULE_CODE" and whose
values are occurrence counts.  Exits non-zero and prints every violation
whose count *increased* or whose rule/file combination is *new*.
Decreases (improvements) are silently accepted.
"""

import json
import sys


def load(path):
    with open(path) as fh:
        return json.load(fh)


def compare(baseline, current):
    new_violations = []
    for key, count in sorted(current.items()):
        base_count = baseline.get(key, 0)
        if count > base_count:
            file_part, rule = key.rsplit(":", 1)
            delta = count - base_count
            new_violations.append(
                f"  {file_part}: {rule} +{delta} new"
                f" (baseline {base_count}, current {count})"
            )
    return new_violations


def main():
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <baseline.json> <current.json>",
              file=sys.stderr)
        sys.exit(2)

    baseline = load(sys.argv[1])
    current = load(sys.argv[2])
    new_violations = compare(baseline, current)

    if new_violations:
        print("New lint violations detected (exceeding baseline):")
        for v in new_violations:
            print(v)
        sys.exit(1)

    print("No new violations above baseline.")
    sys.exit(0)


if __name__ == "__main__":
    main()
