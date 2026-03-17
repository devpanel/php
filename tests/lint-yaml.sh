#!/usr/bin/env bash
# tests/lint-yaml.sh — Run yamllint on all GitHub Actions YAML files
# (workflows and composite actions) and compare against the stored baseline.
# Only *new* violations cause failure; a stale (over-counted) baseline also
# causes failure to enforce regeneration.
#
# Options:
#   --files <f1> [f2 ...]   Lint specific files instead of all YAML files.
#   --update-baseline       Overwrite the baseline with the current results.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASELINE="${REPO_ROOT}/tests/baselines/yamllint-baseline.json"
YAMLLINT_CONFIG="${REPO_ROOT}/.yamllint.yml"
TMP_CURRENT="$(mktemp "${TMPDIR:-/tmp}/yamllint-current-XXXXXX")"
trap 'rm -f "$TMP_CURRENT"' EXIT

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
UPDATE_BASELINE=false
FILES=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --update-baseline) UPDATE_BASELINE=true; shift ;;
    --files) shift; while [[ $# -gt 0 && "$1" != --* ]]; do FILES+=("$1"); shift; done ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ ${#FILES[@]} -eq 0 ]]; then
  mapfile -t FILES < <(find "$REPO_ROOT/.github" -type f \( -name "*.yml" -o -name "*.yaml" \) 2>/dev/null | sort)
fi

# ---------------------------------------------------------------------------
# Run yamllint and collect counts per file:rule
# ---------------------------------------------------------------------------
echo "Running yamllint on ${#FILES[@]} file(s)…"

python3 - "$REPO_ROOT" "$YAMLLINT_CONFIG" "$BASELINE" "$TMP_CURRENT" "${FILES[@]}" << 'PYEOF'
import subprocess, json, sys, re, os

repo_root      = sys.argv[1]
config_path    = sys.argv[2]
baseline_path  = sys.argv[3]
current_path   = sys.argv[4]
files          = sys.argv[5:]

def rel(path):
    try:
        r = os.path.relpath(path, repo_root)
    except ValueError:
        r = path
    # os.path.relpath never returns a leading "./" for subdirectory paths,
    # so we only need to strip a leading "/" (shouldn't happen on POSIX but
    # be safe), and must NOT strip leading dots (e.g. ".github/workflows/…").
    return "./" + r.lstrip("/")

counts = {}
# parsable format: path:line:col: [level] message (rule)
# The rule name appears in parentheses at the end of each line.
PATTERN = re.compile(r"^.+?:\d+:\d+: \[(?:warning|error)\] .+\((.+?)\)\s*$")

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
    for line in result.stdout.splitlines():
        m = PATTERN.match(line)
        if m:
            rule = m.group(1)
            key = "{}:{}".format(rel(f), rule)
            counts[key] = counts.get(key, 0) + 1
            print("  {}".format(line))

with open(current_path, "w") as fh:
    json.dump(counts, fh, indent=2, sort_keys=True)
    fh.write("\n")
PYEOF

# ---------------------------------------------------------------------------
# Update baseline if requested
# ---------------------------------------------------------------------------
if [[ "$UPDATE_BASELINE" == true ]]; then
  count=$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))))" "$TMP_CURRENT")
  cp "$TMP_CURRENT" "$BASELINE"
  if [[ "$count" == "0" ]]; then
    echo "All violations resolved. Baseline written as empty: $BASELINE"
    echo "TODO: All violations for this linter are now fixed."
    echo "  Remove the baseline comparison for this linter entirely:"
    echo "  1. Delete the baseline file: $BASELINE"
    echo "  2. Remove the baseline comparison logic from tests/lint-yaml.sh."
    echo "  After that, any new violation will be an immediate CI failure with no exceptions."
  else
    echo "Baseline updated: $BASELINE"
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Compare against baseline
# ---------------------------------------------------------------------------
python3 "${REPO_ROOT}/tests/compare-baseline.py" "$BASELINE" "$TMP_CURRENT"
