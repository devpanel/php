#!/usr/bin/env bash
# tests/lint-yaml.sh — Run yamllint on all GitHub Actions YAML files
# (workflows and composite actions) and fail on any violation.
# Zero violations are strictly enforced: any yamllint error or warning
# that matches the configured rules causes an immediate CI failure.
#
# Options:
#   --files <f1> [f2 ...]   Lint specific files instead of all YAML files.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
YAMLLINT_CONFIG="${REPO_ROOT}/.yamllint.yml"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
FILES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --update-baseline)
      echo "ERROR: tests/lint-yaml.sh does not support --update-baseline." >&2
      echo "       yamllint violations must be fixed; they cannot be baselined." >&2
      exit 1
      ;;
    --files) shift; while [[ $# -gt 0 && "$1" != --* ]]; do FILES+=("$1"); shift; done ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ ${#FILES[@]} -eq 0 ]]; then
  # macOS ships Bash 3.2, which does not provide mapfile.
  while IFS= read -r file; do
    FILES+=("$file")
  done < <(find "$REPO_ROOT/.github" -type f \( -name "*.yml" -o -name "*.yaml" \) 2>/dev/null | sort)
fi

# ---------------------------------------------------------------------------
# Run yamllint and fail on any violation
# ---------------------------------------------------------------------------
echo "Running yamllint on ${#FILES[@]} file(s)…"

python3 - "$YAMLLINT_CONFIG" "${FILES[@]}" << 'PYEOF'
import subprocess, sys, re

config_path = sys.argv[1]
files       = sys.argv[2:]

PATTERN = re.compile(r"^.+?:\d+:\d+: \[(?:warning|error)\] .+\((.+?)\)\s*$")

total_violations = 0
any_failed = False
for f in files:
    result = subprocess.run(
        ["yamllint", "--format", "parsable", "-c", config_path, f],
        capture_output=True, text=True
    )
    # yamllint exit codes: 0 = no issues, 1 = issues found, 2+ = config/fatal error
    if result.returncode not in (0, 1):
        sys.stderr.write("yamllint failed on {} with exit code {}\n".format(f, result.returncode))
        if result.stderr:
            sys.stderr.write(result.stderr)
        sys.exit(result.returncode)
    if result.returncode == 1:
        any_failed = True
        matched = 0
        for line in result.stdout.splitlines():
            if PATTERN.match(line):
                matched += 1
                total_violations += 1
                print("  {}".format(line))
        # If nothing matched the expected pattern, print raw output so nothing is hidden
        if matched == 0 and result.stdout.strip():
            sys.stderr.write("yamllint reported issues in {} (raw output):\n".format(f))
            sys.stderr.write(result.stdout)

if any_failed or total_violations > 0:
    sys.stderr.write("yamllint: {} violation(s) found. Fix all violations before committing.\n".format(total_violations))
    sys.exit(1)
PYEOF

echo "yamllint: no violations found."
