#!/usr/bin/env python3
"""
Shared baseline-comparison helper.

Usage: compare-baseline.py <baseline-json> <current-json> [--repo-root PATH --files PATH...]

Both JSON files must be objects whose keys are "path:RULE_CODE" and whose
values are occurrence counts. Exits non-zero and prints every violation whose
count *increased* or whose rule/file combination is *new*.

If the violation count for any key has *decreased* (or a key has been fully
resolved), the baseline is considered stale and the script also exits
non-zero, asking the developer to re-run with --update-baseline.

A missing baseline file is treated as an empty baseline ({}).
A missing current file is an error (it means the linter did not run).

When --files is provided, baseline comparison is scoped to only those files.
This is used by the local pre-push hook, which lints only changed files.
"""

import argparse
import json
import os
import sys


def load(path, missing_ok=False):
    if not os.path.exists(path):
        if missing_ok:
            return {}
        print(f"Error: file not found: {path}", file=sys.stderr)
        sys.exit(1)
    with open(path) as fh:
        return json.load(fh)


def normalize_scope_path(path, repo_root):
    try:
        rel_path = os.path.relpath(path, repo_root)
    except ValueError:
        rel_path = path
    return "./" + rel_path.lstrip("/")


def filter_counts(counts, scope_files):
    if scope_files is None:
        return counts

    filtered = {}
    for key, count in counts.items():
        file_part, _rule = key.rsplit(":", 1)
        if file_part in scope_files:
            filtered[key] = count
    return filtered


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


def parse_args(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline_json")
    parser.add_argument("current_json")
    parser.add_argument("--repo-root")
    parser.add_argument("--files", nargs="+")
    args = parser.parse_args(argv)

    if args.files and not args.repo_root:
        parser.error("--repo-root is required when --files is provided")

    return args


def main():
    args = parse_args(sys.argv[1:])

    baseline = load(args.baseline_json, missing_ok=True)
    current = load(args.current_json)

    scope_files = None
    if args.files:
        scope_files = {
            normalize_scope_path(path, args.repo_root)
            for path in args.files
        }

    baseline = filter_counts(baseline, scope_files)
    current = filter_counts(current, scope_files)
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

    print("Violation counts match baseline exactly.")
    sys.exit(0)


if __name__ == "__main__":
    main()
