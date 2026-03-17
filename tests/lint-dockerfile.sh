#!/usr/bin/env bash
# tests/lint-dockerfile.sh — Run hadolint (all severities) on every Dockerfile
# and compare against the stored baseline.  Only *new* violations cause failure.
#
# Requires: Docker (hadolint/hadolint:v2.12.0 is pulled automatically; override via HADOLINT_IMAGE env var)
#
# Options:
#   --files <f1> [f2 ...]   Lint specific files instead of all Dockerfiles.
#   --update-baseline       Overwrite the baseline with the current results.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASELINE="${REPO_ROOT}/tests/baselines/hadolint-baseline.json"
TMP_CURRENT="$(mktemp "${TMPDIR:-/tmp}/hadolint-current-XXXXXX")"
trap 'rm -f "$TMP_CURRENT"' EXIT
HADOLINT_IMAGE="${HADOLINT_IMAGE:-hadolint/hadolint:v2.12.0}"

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
  mapfile -t FILES < <(find "$REPO_ROOT" -name "Dockerfile" -not -path "*/.git/*" | sort)
fi

# ---------------------------------------------------------------------------
# Ensure hadolint is available
# ---------------------------------------------------------------------------
if command -v hadolint &>/dev/null; then
  RUN_HADOLINT="hadolint --format json"
elif command -v docker &>/dev/null; then
  docker pull --quiet "$HADOLINT_IMAGE" >/dev/null
  RUN_HADOLINT="docker run --rm -i $HADOLINT_IMAGE hadolint --format json"
else
  echo "ERROR: Neither 'hadolint' nor 'docker' found. Install one to run Dockerfile linting." >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Run hadolint and collect counts per file:rule
# ---------------------------------------------------------------------------
echo "Running hadolint on ${#FILES[@]} Dockerfile(s)…"

python3 - "$REPO_ROOT" "$BASELINE" "$TMP_CURRENT" "$RUN_HADOLINT" "${FILES[@]}" << 'PYEOF'
import subprocess, json, sys, shlex, os

repo_root     = sys.argv[1]
baseline_path = sys.argv[2]
current_path  = sys.argv[3]
cmd_str       = sys.argv[4]
files         = sys.argv[5:]

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
parse_error = False

for f in files:
    cmd = shlex.split(cmd_str) + ["-"]
    with open(f, "rb") as fh:
        content = fh.read()
    result = subprocess.run(cmd, input=content, capture_output=True)
    # hadolint exit codes: 0 = no issues, 1 = issues found, 2+ = config/fatal error
    if result.returncode > 1:
        sys.stderr.write("hadolint fatal error on {} (exit code {}): {}\n".format(
            f, result.returncode, result.stderr.decode(errors="replace")))
        sys.exit(result.returncode)
    try:
        issues = json.loads(result.stdout)
        for issue in issues:
            code = issue.get("code", "unknown")
            line = issue.get("line", "?")
            key  = "{}:{}".format(rel(f), code)
            counts[key] = counts.get(key, 0) + 1
            print("  {}:{}: [{}] {} — {}".format(
                rel(f), line,
                issue.get("level", ""),
                code,
                issue.get("message", ""),
            ))
    except Exception as e:
        sys.stderr.write("  hadolint parse error for {}: {}\n".format(f, e))
        parse_error = True

with open(current_path, "w") as fh:
    json.dump(counts, fh, indent=2, sort_keys=True)
    fh.write("\n")

if parse_error:
    sys.exit(1)
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
