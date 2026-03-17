#!/usr/bin/env bash
# tests/lint-shell.sh — Run shellcheck (style+) on all shell scripts and
# compare against the stored baseline.  Only *new* violations cause failure.
#
# Options:
#   --files <f1> [f2 ...]   Lint specific files instead of all scripts.
#   --update-baseline       Overwrite the baseline with the current results.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BASELINE="${REPO_ROOT}/tests/baselines/shellcheck-baseline.json"
TMP_CURRENT="$(mktemp "${TMPDIR:-/tmp}/shellcheck-current-XXXXXX")"
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
  mapfile -t FILES < <(
    {
      find "$REPO_ROOT" -name "*.sh" -not -path "*/.git/*"
      find "$REPO_ROOT/.githooks" -type f -not -path "*/.git/*" 2>/dev/null || true
    } | sort -u
  )
fi

# ---------------------------------------------------------------------------
# Run shellcheck and collect counts per file:rule
# ---------------------------------------------------------------------------
echo "Running shellcheck on ${#FILES[@]} file(s)…"

python3 - "$REPO_ROOT" "$BASELINE" "$TMP_CURRENT" "${FILES[@]}" << 'PYEOF'
import subprocess, json, sys, os

repo_root     = sys.argv[1]
baseline_path = sys.argv[2]
current_path  = sys.argv[3]
files         = sys.argv[4:]

def rel(path):
    """Return path relative to repo_root, prefixed with './'."""
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
    result = subprocess.run(
        ["shellcheck", "--format=json1", "--severity=style", f],
        capture_output=True, text=True
    )
    # shellcheck exit codes: 0 = no issues, 1 = issues found, 2+ = fatal/internal error
    if result.returncode > 1:
        sys.stderr.write("shellcheck fatal error on {} (exit code {}): {}\n".format(
            f, result.returncode, result.stderr))
        sys.exit(result.returncode)
    try:
        data = json.loads(result.stdout)
        comments = data.get("comments", []) if isinstance(data, dict) else []
        for issue in comments:
            code = "SC{}".format(issue["code"])
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
        sys.stderr.write("  shellcheck parse error for {}: {}\n".format(f, e))
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
  count=$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))))" "$TMP_CURRENT")
  if [[ "$count" == "0" ]]; then
    rm -f "$BASELINE"
    echo "No violations found; baseline file removed: $BASELINE"
  else
    cp "$TMP_CURRENT" "$BASELINE"
    echo "Baseline updated: $BASELINE"
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Compare against baseline
# ---------------------------------------------------------------------------
python3 "${REPO_ROOT}/tests/compare-baseline.py" "$BASELINE" "$TMP_CURRENT"
