#!/usr/bin/env python3
"""Exercise the updater's embedded Bash script without GitHub or GitLab writes."""

import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import textwrap
import unittest


ROOT = Path(__file__).resolve().parents[1]
WORKFLOW = ROOT / ".github/workflows/update-devpanel-cli.yml"
STEP = WORKFLOW.read_text().split("      - name: Commit binaries\n", 1)[1]
SCRIPT = textwrap.dedent(
    STEP.split("        run: |\n", 1)[1].split("\n      - name:", 1)[0]
)
REAL_GIT = shutil.which("git")
MOCK = """#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import sys

tool = Path(sys.argv[0]).name
args = sys.argv[1:]
with open(os.environ["CALL_LOG"], "a") as log:
    log.write(json.dumps([tool, args, os.environ.get("GH_TOKEN")]) + "\\n")
if tool == "git":
    if "push" not in args:
        sys.exit(subprocess.call([os.environ["REAL_GIT"], *args]))
    if args[-1].endswith(":refs/heads/main") and os.environ["PROTECTED"] == "1":
        print("GH006: protected branch update failed", file=sys.stderr)
        sys.exit(1)
elif tool == "gh":
    if args[:2] == ["run", "list"]:
        if args[args.index("--limit") + 1] == "1":
            print("100")
        elif os.environ.get("NO_RUN") != "1":
            print("101")
    elif args[:2] == ["pr", "list"]:
        state = os.environ.get("PR_STATE", "")
        print(json.dumps([{
            "number": 42, "state": state,
            "headRefName": os.environ["UPDATE_BRANCH"],
            "headRepositoryOwner": {"login": "devpanel"}
        }] if state else []))
    elif args[:2] == ["run", "watch"]:
        sys.exit(int(os.environ.get("TEST_STATUS", "0")))
    elif args[:2] == ["pr", "merge"]:
        sys.exit(int(os.environ.get("MERGE_STATUS", "0")))
elif tool == "timeout":
    sys.exit(subprocess.call(args[1:]))
"""


class UpdaterTest(unittest.TestCase):
    def run_updater(self, *, protected=True, state="", changed=True,
                    test_status=0, no_run=False, token="pat", merge_status=0):
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            subprocess.run([REAL_GIT, "init", "-q", str(work)], check=True)
            for name in ("devpanel-amd64", "devpanel-arm64"):
                destination = work / "base/bin" / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_text("old")
                destination.chmod(0o755)
                artifact = work / "dist" / name.split("-")[1] / name
                artifact.parent.mkdir(parents=True, exist_ok=True)
                artifact.write_text("new" if changed else "old")
            subprocess.run([REAL_GIT, "-C", str(work), "add", "base"], check=True)
            subprocess.run(
                [REAL_GIT, "-C", str(work), "-c", "user.name=Test",
                 "-c", "user.email=test@example.com", "commit", "-qm", "Initial"],
                check=True,
            )
            tools = work / "tools"
            tools.mkdir()
            for name in ("git", "gh", "timeout", "sleep"):
                executable = tools / name
                executable.write_text(MOCK)
                executable.chmod(0o755)
            branch = "devpanel-cli-update-" + hashlib.sha256(b"main").hexdigest()
            branch += "-" + "a" * 12
            output = work / "output"
            output.touch()
            log = work / "calls"
            env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}",
                       REAL_GIT=REAL_GIT, CALL_LOG=str(log),
                       GITHUB_OUTPUT=str(output), GH_TOKEN="workflow-token",
                       TEST_TOKEN=token,
                       TARGET_BRANCH="main", REPOSITORY_OWNER="devpanel",
                       UPSTREAM_SHA="a" * 40, UPDATE_BRANCH=branch,
                       PROTECTED=str(int(protected)), PR_STATE=state,
                       TEST_STATUS=str(test_status), NO_RUN=str(int(no_run)),
                       MERGE_STATUS=str(merge_status))
            result = subprocess.run(
                ["bash", "-euo", "pipefail", "-c", SCRIPT], cwd=work, env=env,
                capture_output=True, text=True, timeout=30,
            )
            calls = [json.loads(line) for line in log.read_text().splitlines()]
            return result, calls, output.read_text()

    def test_protected_pr_lifecycle(self):
        for state, operation in (("", "create"), ("OPEN", "edit"),
                                 ("CLOSED", "reopen"), ("MERGED", "create")):
            with self.subTest(state=state):
                result, calls, output = self.run_updater(state=state)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(output, "cacheable=false\n")
                gh = [(args, token) for tool, args, token in calls if tool == "gh"]
                dispatches = [(i, args, token) for i, (args, token) in enumerate(gh)
                              if args[:2] == ["workflow", "run"]]
                self.assertEqual(len(dispatches), 1)
                dispatch_index, dispatch_args, dispatch_token = dispatches[0]
                self.assertEqual(dispatch_token, "pat")
                self.assertEqual(dispatch_args[-1], next(
                    args[-1].split(":refs/heads/")[1] for tool, args, _ in calls
                    if tool == "git" and "push" in args and "--force" in args
                ))
                pr_index = next(i for i, (args, _) in enumerate(gh)
                                if args[:2] == ["pr", operation])
                wait_index = next(i for i, (args, _) in enumerate(gh)
                                  if args[:2] == ["run", "watch"])
                self.assertLess(pr_index, dispatch_index)
                self.assertLess(dispatch_index, wait_index)
                merges = [(i, args) for i, (args, _) in enumerate(gh)
                          if args[:2] == ["pr", "merge"]]
                self.assertEqual(len(merges), 1)
                merge_index, merge_args = merges[0]
                self.assertLess(wait_index, merge_index)
                self.assertEqual(merge_args[2], dispatch_args[-1])
                self.assertIn("--rebase", merge_args)
                self.assertIn("--auto", merge_args)
                self.assertNotIn("--admin", merge_args)
                self.assertTrue(all(token == "workflow-token" for args, token in gh
                                    if args[0] == "pr"))
                run_args = next(args for args, _ in gh
                                if args[:2] == ["run", "list"] and "--event" in args)
                self.assertEqual(run_args[run_args.index("--event") + 1], "workflow_dispatch")
                query = run_args[run_args.index("--jq") + 1]
                self.assertIn(".headSha ==", query)
                self.assertIn(".databaseId > 100", query)
                self.assertEqual(
                    merge_args[merge_args.index("--match-head-commit") + 1],
                    query.split('.headSha == "')[1].split('"')[0],
                )
                pushes = [(args, token) for tool, args, token in calls
                          if tool == "git" and "push" in args]
                self.assertEqual(len(pushes), 2)
                self.assertTrue(all(token == "workflow-token" for _, token in pushes))
                self.assertTrue(all("-c" not in args for args, _ in pushes))
                self.assertTrue(all(token == "workflow-token"
                                    for args, token in gh if args[0] != "workflow"))

    def test_direct_push_does_not_dispatch_test(self):
        result, calls, output = self.run_updater(protected=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output, "")
        self.assertFalse(any(tool == "gh" for tool, _, _ in calls))

    def test_unchanged_binaries_do_not_push_or_test(self):
        result, calls, output = self.run_updater(changed=False)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output, "")
        self.assertFalse(any(tool == "gh" or "push" in args for tool, args, _ in calls))

    def test_failed_tests_fail_the_step(self):
        result, calls, _ = self.run_updater(test_status=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(tool == "gh" and args[:2] == ["pr", "merge"]
                             for tool, args, _ in calls))

    def test_merge_failure_fails_without_caching(self):
        result, _, output = self.run_updater(merge_status=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(output, "cacheable=false\n")

    def test_direct_push_succeeds_without_test_even_if_tests_would_fail(self):
        result, calls, output = self.run_updater(protected=False, test_status=1)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(output, "")
        self.assertFalse(any(tool == "gh" for tool, _, _ in calls))

    def test_missing_test_token_fails_explicitly(self):
        result, calls, _ = self.run_updater(token="")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("GHCR_TOKEN with repo scope", result.stdout)
        self.assertFalse(any(tool == "gh" and args[0] == "pr"
                             for tool, args, _ in calls))

    def test_missing_test_run_times_out(self):
        result, calls, output = self.run_updater(no_run=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Timed out waiting", result.stdout)
        self.assertEqual(output, "cacheable=false\n")
        self.assertFalse(any(tool == "gh" and args[:2] == ["pr", "merge"]
                             for tool, args, _ in calls))


if __name__ == "__main__":
    unittest.main()
