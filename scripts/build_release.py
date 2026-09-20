#!/usr/bin/env python3
"""Build a clean release ZIP and verify its TOC/XML load dependencies."""

import posixpath
import shutil
import sys
import tempfile
import xml.etree.ElementTree as ET
from pathlib import Path
from zipfile import BadZipFile, ZipFile


def validate_archive(path):
    with ZipFile(path) as archive:
        files = {entry.filename for entry in archive.infolist() if not entry.is_dir()}
        visited = set()

        def visit(name, source):
            if name not in files:
                raise ValueError(f"Missing archive file: {name} (referenced by {source})")
            if name in visited:
                return
            visited.add(name)
            if name.lower().endswith(".toc"):
                references = [
                    line.strip()
                    for line in archive.read(name).decode("utf-8-sig").splitlines()
                    if line.strip() and not line.lstrip().startswith("#")
                ]
            elif name.lower().endswith(".xml"):
                references = [
                    element.attrib["file"]
                    for element in ET.fromstring(archive.read(name)).iter()
                    if element.tag.rsplit("}", 1)[-1] in ("Script", "Include")
                    and "file" in element.attrib
                ]
            else:
                return
            for reference in references:
                target = posixpath.normpath(
                    posixpath.join(posixpath.dirname(name), reference.replace("\\", "/"))
                )
                visit(target, name)

        visit("RLHelper/RLHelper.toc", "release entry point")


def build_release(root):
    # Keep staging beside the output so the validated ZIP can be replaced atomically.
    with tempfile.TemporaryDirectory(prefix=".rlhelper-release-", dir=root) as temporary:
        staging = Path(temporary)
        addon = staging / "RLHelper"
        addon.mkdir()
        for name in ("RLHelper.toc", "RLHelper.xml", "Core.lua"):
            shutil.copy2(root / name, addon / name)
        for name in ("modules", "lib", "Libs", "data"):
            shutil.copytree(root / name, addon / name)
        archive = Path(shutil.make_archive(str(staging / "RLHelper"), "zip", staging, "RLHelper"))
        validate_archive(archive)
        output = root / "RLHelper.zip"
        archive.replace(output)
    print(f"Built and validated {output}")


if __name__ == "__main__":
    try:
        build_release(Path(__file__).resolve().parents[1])
    except (OSError, ValueError, ET.ParseError, BadZipFile) as error:
        print(f"Release failed: {error}", file=sys.stderr)
        sys.exit(1)
