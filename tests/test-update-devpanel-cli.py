#!/usr/bin/env python3
"""Exercise CLI update and merged-revision scripts without remote writes."""

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
CACHE_WORKFLOW = ROOT / ".github/workflows/cache-devpanel-cli.yml"
CACHE_SCRIPT = textwrap.dedent(
    CACHE_WORKFLOW.read_text().split("        run: |\n", 1)[1]
    .split("\n      - name:", 1)[0]
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
    if args[0] == "api":
        if args[-1].endswith("/approve"):
            sys.exit(int(os.environ.get("APPROVAL_STATUS", "0")))
        elif "/actions/workflows/test.yml/runs" in args[3]:
            runs = [] if os.environ.get("NO_RUN") == "1" else [
                {"id": 101, "conclusion": os.environ["RUN_CONCLUSION"],
                 "pull_requests": [{"number": 42}]},
                {"id": 102, "conclusion": "action_required",
                 "pull_requests": [{"number": 99}]},
            ]
            sys.exit(subprocess.run(
                ["jq", "-r", args[args.index("--jq") + 1]],
                input=json.dumps({"workflow_runs": runs}), text=True,
            ).returncode)
        elif "/commits/" in args[1]:
            print(os.environ["COMMIT_SUBJECT"])
        else:
            print(os.environ["AUTO_MERGE"])
    elif args[:2] == ["pr", "view"]:
        print("42")
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
                    test_status=0, no_run=False, token="pat", merge_status=0,
                    auto_merge=False, run_conclusion="action_required",
                    approval_status=0):
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
                       GITHUB_REPOSITORY="devpanel/php",
                       TEST_TOKEN=token,
                       TARGET_BRANCH="main", REPOSITORY_OWNER="devpanel",
                       UPSTREAM_SHA="a" * 40, UPDATE_BRANCH=branch,
                       PROTECTED=str(int(protected)), PR_STATE=state,
                       TEST_STATUS=str(test_status), NO_RUN=str(int(no_run)),
                       MERGE_STATUS=str(merge_status),
                       RUN_CONCLUSION=run_conclusion,
                       APPROVAL_STATUS=str(approval_status),
                       AUTO_MERGE=str(auto_merge).lower())
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
                approvals = [(i, args, token) for i, (args, token) in enumerate(gh)
                             if args[-1].endswith("/approve")]
                self.assertEqual(len(approvals), 1)
                approval_index, approval_args, approval_token = approvals[0]
                self.assertEqual(approval_token, "pat")
                self.assertEqual(approval_args, [
                    "api", "--method", "POST",
                    "repos/devpanel/php/actions/runs/101/approve",
                ])
                self.assertFalse(any(args[:2] == ["workflow", "run"]
                                     for args, _ in gh))
                pr_index = next(i for i, (args, _) in enumerate(gh)
                                if args[:2] == ["pr", operation])
                wait_index = next(i for i, (args, _) in enumerate(gh)
                                  if args[:2] == ["run", "watch"])
                self.assertLess(pr_index, approval_index)
                if state == "CLOSED":
                    reopen_index = next(
                        i for i, (tool, args, _) in enumerate(calls)
                        if tool == "gh" and args[:2] == ["pr", "reopen"]
                    )
                    force_push_index = next(
                        i for i, (tool, args, _) in enumerate(calls)
                        if tool == "git" and "push" in args and "--force" in args
                    )
                    self.assertLess(reopen_index, force_push_index)
                self.assertLess(approval_index, wait_index)
                merges = [(i, args) for i, (args, _) in enumerate(gh)
                          if args[:2] == ["pr", "merge"]]
                self.assertEqual(len(merges), 1)
                merge_index, merge_args = merges[0]
                self.assertLess(wait_index, merge_index)
                self.assertIn("--rebase", merge_args)
                self.assertNotIn("--auto", merge_args)
                self.assertNotIn("--admin", merge_args)
                self.assertTrue(all(token == "workflow-token" for args, token in gh
                                    if args[0] == "pr"))
                run_args = next(args for args, _ in gh if "event=pull_request" in args)
                self.assertIn(f"branch={merge_args[2]}", run_args)
                merge_sha = merge_args[merge_args.index("--match-head-commit") + 1]
                self.assertIn(f"head_sha={merge_sha}", run_args)
                self.assertEqual(next(args for args, _ in gh
                                      if args[:2] == ["run", "watch"])[2], "101")
                pushes = [(args, token) for tool, args, token in calls
                          if tool == "git" and "push" in args]
                self.assertEqual(len(pushes), 2)
                self.assertTrue(all(token == "workflow-token" for _, token in pushes))
                self.assertTrue(all("-c" not in args for args, _ in pushes))
                self.assertTrue(all(token == "workflow-token"
                                    for args, token in gh
                                    if not args[-1].endswith("/approve")))

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
        for auto_merge in (False, True):
            with self.subTest(auto_merge=auto_merge):
                result, _, output = self.run_updater(
                    merge_status=1, auto_merge=auto_merge,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(output, "cacheable=false\n")

    def test_auto_merge_approves_without_waiting_for_test_completion(self):
        for state in ("", "OPEN", "CLOSED"):
            with self.subTest(state=state):
                result, calls, output = self.run_updater(
                    state=state, auto_merge=True, test_status=1,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(output, "cacheable=false\n")
                self.assertFalse(any(tool in ("sleep", "timeout")
                                     or (tool == "gh" and args[0] == "run")
                                     for tool, args, _ in calls))
                gh = [(args, token) for tool, args, token in calls if tool == "gh"]
                approvals = [(i, args, token) for i, (args, token) in enumerate(gh)
                             if args[-1].endswith("/approve")]
                self.assertEqual(len(approvals), 1)
                approval_index, _, approval_token = approvals[0]
                self.assertEqual(approval_token, "pat")
                self.assertFalse(any(args[:2] == ["workflow", "run"]
                                     for args, _ in gh))
                merges = [(i, args, token) for i, (args, token) in enumerate(gh)
                          if args[:2] == ["pr", "merge"]]
                self.assertEqual(len(merges), 1)
                merge_index, merge_args, merge_token = merges[0]
                self.assertLess(approval_index, merge_index)
                self.assertEqual(merge_token, "workflow-token")
                self.assertIn("--rebase", merge_args)
                self.assertIn("--auto", merge_args)
                self.assertNotIn("--admin", merge_args)
                pushed_sha = next(
                    args[-1].split(":")[0] for tool, args, _ in calls
                    if tool == "git" and "push" in args
                )
                self.assertEqual(
                    merge_args[merge_args.index("--match-head-commit") + 1],
                    pushed_sha,
                )
                self.assertTrue(all(token == "workflow-token" for args, token in gh
                                    if not args[-1].endswith("/approve")))

    def test_already_running_or_finished_test_is_not_approved_again(self):
        for conclusion in ("null", "success", "failure"):
            with self.subTest(conclusion=conclusion):
                test_status = int(conclusion == "failure")
                result, calls, _ = self.run_updater(
                    run_conclusion=conclusion, test_status=test_status,
                )
                self.assertEqual(result.returncode, test_status, result.stderr)
                self.assertFalse(any(args[-1].endswith("/approve")
                                     for tool, args, _ in calls if tool == "gh"))
                self.assertTrue(any(tool == "gh" and args[:2] == ["run", "watch"]
                                    for tool, args, _ in calls))
                if test_status:
                    self.assertFalse(any(tool == "gh" and args[:2] == ["pr", "merge"]
                                         for tool, args, _ in calls))

    def test_failed_approval_fails_without_merging_or_caching(self):
        result, calls, output = self.run_updater(approval_status=1)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(output, "cacheable=false\n")
        self.assertFalse(any(tool == "gh" and args[:2] == ["pr", "merge"]
                             for tool, args, _ in calls))

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
        for auto_merge in (False, True):
            with self.subTest(auto_merge=auto_merge):
                result, calls, output = self.run_updater(no_run=True, auto_merge=auto_merge)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("Timed out waiting", result.stdout)
                self.assertEqual(output, "cacheable=false\n")
                self.assertFalse(any(tool == "gh" and args[:2] == ["pr", "merge"]
                                     for tool, args, _ in calls))


class MergedRevisionTest(unittest.TestCase):
    def run_cache(self, *, target="main", subject=None, branch=None):
        sha = "a" * 40
        if subject is None:
            subject = f"Update devpanel CLI from GitLab devpanel-vn/cli@{sha}"
        if branch is None:
            branch = "devpanel-cli-update-" + hashlib.sha256(target.encode()).hexdigest()
            branch += "-" + sha[:12]
        with tempfile.TemporaryDirectory() as directory:
            work = Path(directory)
            tools = work / "tools"
            tools.mkdir()
            executable = tools / "gh"
            executable.write_text(MOCK)
            executable.chmod(0o755)
            output = work / "output"
            output.touch()
            env = dict(os.environ, PATH=f"{tools}:{os.environ['PATH']}",
                       GH_TOKEN="workflow-token", CALL_LOG=str(work / "calls"),
                       GITHUB_REPOSITORY="devpanel/php", GITHUB_OUTPUT=str(output),
                       RUNNER_TEMP=str(work), HEAD_SHA="b" * 40,
                       HEAD_BRANCH=branch, TARGET_BRANCH=target,
                       COMMIT_SUBJECT=subject)
            result = subprocess.run(
                ["bash", "-euo", "pipefail", "-c", CACHE_SCRIPT], env=env,
                capture_output=True, text=True, timeout=10,
            )
            revision = work / "devpanel-cli-revision/sha"
            return result, output.read_text(), (
                revision.read_text() if revision.exists() else None
            )

    def test_merged_revision_is_recorded_for_destination_branch(self):
        for target in ("main", "release/cli"):
            with self.subTest(target=target):
                result, output, revision = self.run_cache(target=target)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(output, "sha=" + "a" * 40 + "\n")
                self.assertEqual(revision, "a" * 40 + "\n")

    def test_invalid_revision_is_not_cached(self):
        for subject in ("Unrelated update", "Update devpanel CLI from GitLab devpanel-vn/cli@bad"):
            with self.subTest(subject=subject):
                result, output, revision = self.run_cache(subject=subject)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("no valid upstream revision", result.stdout)
                self.assertEqual(output, "")
                self.assertIsNone(revision)

    def test_mismatched_target_or_revision_is_not_cached(self):
        for branch in (
            "devpanel-cli-update-" + hashlib.sha256(b"develop").hexdigest() + "-" + "a" * 12,
            "devpanel-cli-update-" + hashlib.sha256(b"main").hexdigest() + "-" + "c" * 12,
        ):
            with self.subTest(branch=branch):
                result, output, revision = self.run_cache(branch=branch)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("does not match", result.stdout)
                self.assertEqual(output, "")
                self.assertIsNone(revision)


if __name__ == "__main__":
    unittest.main()
