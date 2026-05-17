#!/usr/bin/env python3
"""Strict RLHelper release helper."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
TOC = ROOT / "RLHelper.toc"
TRUNK_BRANCH = "master"
VERSION_RE = re.compile(r"^(## Version:\s*)(\d+\.\d+\.\d+)\s*$")
TAG_RE = re.compile(r"^v(\d+)\.(\d+)\.(\d+)$")


class ReleaseError(RuntimeError):
    pass


def git(*args: str) -> str:
    result = subprocess.run(
        ["git", *args],
        cwd=ROOT,
        check=False,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip()
        raise ReleaseError(f"git {' '.join(args)} failed: {detail}")
    return result.stdout.strip()


def require_clean_worktree() -> list[str]:
    status = git("status", "--short").splitlines()
    if status:
        raise ReleaseError(
            "worktree is not clean; ask the user whether to commit, stash, or discard changes first:\n"
            + "\n".join(status)
        )
    return status


def current_branch() -> str:
    branch = git("branch", "--show-current")
    if branch != TRUNK_BRANCH:
        raise ReleaseError(
            f"current branch is {branch!r}, expected {TRUNK_BRANCH!r}; ask the user before proceeding"
        )
    return branch


def origin_url() -> str:
    url = git("remote", "get-url", "origin")
    if not url:
        raise ReleaseError("origin remote is missing; ask the user which remote to use")
    return url


def toc_version() -> str:
    versions: list[str] = []
    for line in TOC.read_text(encoding="utf-8").splitlines():
        match = VERSION_RE.match(line)
        if match:
            versions.append(match.group(2))
    if len(versions) != 1:
        raise ReleaseError(f"expected exactly one '## Version:' line in {TOC.name}; found {len(versions)}")
    return versions[0]


def semver_tags() -> list[tuple[tuple[int, int, int], str]]:
    tags: list[tuple[tuple[int, int, int], str]] = []
    for tag in git("tag", "--list", "v*").splitlines():
        match = TAG_RE.match(tag)
        if match:
            tags.append(((int(match.group(1)), int(match.group(2)), int(match.group(3))), tag))
    if not tags:
        raise ReleaseError("no vX.Y.Z tags found; ask the user for the initial release tag")
    return sorted(tags)


def bump_patch(version: tuple[int, int, int]) -> tuple[int, int, int]:
    major, minor, patch = version
    return major, minor, patch + 1


def format_version(version: tuple[int, int, int]) -> str:
    return ".".join(str(part) for part in version)


def replace_toc_version(next_version: str) -> None:
    lines = TOC.read_text(encoding="utf-8").splitlines(keepends=True)
    changed = False
    output: list[str] = []
    for line in lines:
        match = VERSION_RE.match(line.rstrip("\r\n"))
        if match:
            newline = "\r\n" if line.endswith("\r\n") else "\n" if line.endswith("\n") else ""
            output.append(f"{match.group(1)}{next_version}{newline}")
            changed = True
        else:
            output.append(line)
    if not changed:
        raise ReleaseError(f"could not update {TOC.name}; version line was not found")
    TOC.write_text("".join(output), encoding="utf-8")


def collect_prepare_data() -> dict[str, object]:
    branch = current_branch()
    require_clean_worktree()
    remote = origin_url()
    version = toc_version()
    tags = semver_tags()
    latest_version, latest_tag = tags[-1]
    latest_version_text = format_version(latest_version)
    if version != latest_version_text:
        raise ReleaseError(
            f"{TOC.name} version is {version}, latest tag is {latest_tag}; ask the user which version to release"
        )

    next_version_tuple = bump_patch(latest_version)
    next_version = format_version(next_version_tuple)
    next_tag = f"v{next_version}"
    if next_tag in {tag for _, tag in tags}:
        raise ReleaseError(f"next tag {next_tag} already exists; ask the user for the intended version")

    commits = git("log", "--reverse", "--format=%h %s", f"{latest_tag}..HEAD").splitlines()
    files = git("diff", "--name-status", f"{latest_tag}..HEAD").splitlines()
    return {
        "branch": branch,
        "origin": remote,
        "toc_version": version,
        "latest_tag": latest_tag,
        "next_version": next_version,
        "next_tag": next_tag,
        "commits_since_latest_tag": commits,
        "files_changed_since_latest_tag": files,
    }


def prepare() -> int:
    print(json.dumps(collect_prepare_data(), ensure_ascii=False, indent=2))
    return 0


def apply(tag: str) -> int:
    data = collect_prepare_data()
    expected_tag = str(data["next_tag"])
    if tag != expected_tag:
        raise ReleaseError(f"approved tag {tag} does not match computed next tag {expected_tag}; ask the user")

    next_version = str(data["next_version"])
    replace_toc_version(next_version)
    git("add", "RLHelper.toc")
    git("commit", "-m", f"chore: release {tag}")
    git("tag", tag)
    git("push", "origin", TRUNK_BRANCH)
    git("push", "origin", tag)
    print(json.dumps(collect_result(tag), ensure_ascii=False, indent=2))
    return 0


def collect_result(tag: str) -> dict[str, str]:
    return {
        "tag": tag,
        "head": git("rev-parse", "HEAD"),
        "toc_version": toc_version(),
        "tag_target": git("rev-list", "-n", "1", tag),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description="Prepare or apply a strict RLHelper release.")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("prepare")
    apply_parser = subparsers.add_parser("apply")
    apply_parser.add_argument("--tag", required=True)
    args = parser.parse_args()

    try:
        if args.command == "prepare":
            return prepare()
        if args.command == "apply":
            return apply(args.tag)
    except ReleaseError as exc:
        print(f"release.py: {exc}", file=sys.stderr)
        return 1
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
