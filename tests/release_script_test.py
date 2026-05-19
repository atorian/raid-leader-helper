#!/usr/bin/env python3

import importlib.util
import unittest
from contextlib import redirect_stdout
from io import StringIO
from pathlib import Path


RELEASE_SCRIPT = Path(__file__).resolve().parents[1] / ".opencode" / "skills" / "rlhelper-release" / "scripts" / "release.py"
spec = importlib.util.spec_from_file_location("release", RELEASE_SCRIPT)
release = importlib.util.module_from_spec(spec)
spec.loader.exec_module(release)


class ReleaseScriptTest(unittest.TestCase):
    def setUp(self):
        self.original_current_branch = release.current_branch
        self.original_require_clean_worktree = release.require_clean_worktree
        self.original_origin_url = release.origin_url
        self.original_toc_version = release.toc_version
        self.original_semver_tags = release.semver_tags
        self.original_git = release.git
        self.original_replace_toc_version = release.replace_toc_version
        self.original_collect_result = release.collect_result

        release.current_branch = lambda: "master"
        release.require_clean_worktree = lambda: []
        release.origin_url = lambda: "git@example.invalid:repo.git"
        release.semver_tags = lambda: [((0, 3, 22), "v0.3.22")]

    def tearDown(self):
        release.current_branch = self.original_current_branch
        release.require_clean_worktree = self.original_require_clean_worktree
        release.origin_url = self.original_origin_url
        release.toc_version = self.original_toc_version
        release.semver_tags = self.original_semver_tags
        release.git = self.original_git
        release.replace_toc_version = self.original_replace_toc_version
        release.collect_result = self.original_collect_result

    def test_prepare_still_rejects_toc_version_that_does_not_match_latest_tag(self):
        release.toc_version = lambda: "0.4.0"

        with self.assertRaisesRegex(release.ReleaseError, "latest tag is v0.3.22"):
            release.collect_prepare_data()

    def test_custom_prepare_data_allows_user_approved_custom_tag(self):
        release.toc_version = lambda: "0.4.0"
        release.git = lambda *args: "" if args[0] in {"log", "diff"} else self.fail(args)

        data = release.collect_prepare_data("v0.4.0")

        self.assertEqual("0.4.0", data["next_version"])
        self.assertEqual("v0.4.0", data["next_tag"])
        self.assertEqual("v0.3.22", data["latest_tag"])

    def test_custom_apply_uses_user_approved_custom_tag(self):
        replaced_versions = []
        git_calls = []
        release.toc_version = lambda: "0.4.0"
        release.git = lambda *args: git_calls.append(args) or ""
        release.replace_toc_version = lambda version: replaced_versions.append(version)
        release.collect_result = lambda tag: {"tag": tag}

        with redirect_stdout(StringIO()):
            result = release.apply("v0.4.0", allow_custom_version=True)

        self.assertEqual(0, result)
        self.assertEqual(["0.4.0"], replaced_versions)
        self.assertIn(("tag", "v0.4.0"), git_calls)


if __name__ == "__main__":
    unittest.main()
