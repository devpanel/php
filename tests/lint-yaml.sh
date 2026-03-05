#!/usr/bin/env bash
# tests/lint-yaml.sh — Run yamllint on all GitHub Actions workflow files and
# compare against the stored baseline.  Only *new* violations cause failure.
#
# Options:
#   --files <f1> [f2 ...]   Lint specific files instead of all YAML files.
#   --update-baseline       Overwrite the baseline with the current results.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASELINE="${REPO_ROOT}/tests/baselines/yamllint-baseline.json"
YAMLLINT_CONFIG="${REPO_ROOT}/.yamllint.yml"
TMP_CURRENT="$(mktemp /tmp/yamllint-current-XXXXXX.json)"
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
  mapfile -t FILES < <(find "$REPO_ROOT/.github/workflows" -name "*.yml" -o -name "*.yaml" 2>/dev/null | sort)
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
    return "./" + r.lstrip("./")

counts = {}
# parsable format: path:line:col: [level] (rule) message
# Only the rule name (last capture group) is needed for counting.
PATTERN = re.compile(r"^.+?:\d+:\d+: \[(?:warning|error)\] .+ \((.+)\)$")

for f in files:
    result = subprocess.run(
        ["yamllint", "--format", "parsable", "-c", config_path, f],
        capture_output=True, text=True
    )
    for line in result.stdout.splitlines():
        m = PATTERN.match(line)
        if m:
            rule = m.group(1)
            key = "{}:{}".format(rel(f), rule)
            counts[key] = counts.get(key, 0) + 1
            print("  {}".format(line))

with open(current_path, "w") as fh:
    json.dump(counts, fh, indent=2, sort_keys=True)
PYEOF

# ---------------------------------------------------------------------------
# Update baseline if requested
# ---------------------------------------------------------------------------
if [[ "$UPDATE_BASELINE" == true ]]; then
  cp "$TMP_CURRENT" "$BASELINE"
  echo "Baseline updated: $BASELINE"
  exit 0
fi

# ---------------------------------------------------------------------------
# Compare against baseline
# ---------------------------------------------------------------------------
python3 "${REPO_ROOT}/tests/compare-baseline.py" "$BASELINE" "$TMP_CURRENT"
